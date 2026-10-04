import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'models.dart';
import 'stock_ledger.dart';
import 'tenant_context.dart';

class StockMovementEntry {
  const StockMovementEntry({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.type,
    required this.direction,
    required this.quantityChange,
    required this.units,
    this.batchNumber,
    this.referenceId,
    this.createdAt,
  });

  final String id;
  final String medicineId;
  final String medicineName;
  final String type;
  final String direction;
  final int quantityChange;
  final int units;
  final String? batchNumber;
  final String? referenceId;
  final DateTime? createdAt;

  bool get isOut => quantityChange < 0 || direction == 'out';
}

class MedicineDayTrack {
  const MedicineDayTrack({
    required this.medicine,
    required this.unitsIn,
    required this.unitsOut,
    required this.saleLedgerUnits,
    required this.expiryUnits,
    required this.saleReceiptUnits,
  });

  final Medicine medicine;
  final int unitsIn;
  final int unitsOut;
  final int saleLedgerUnits;
  final int expiryUnits;
  final int saleReceiptUnits;

  int get net => unitsIn - unitsOut;
  bool get ledgerMatchesSales => saleLedgerUnits == saleReceiptUnits;
}

class DailyInventoryTrack {
  const DailyInventoryTrack({
    required this.day,
    required this.unitsIn,
    required this.unitsOut,
    required this.saleLedgerUnits,
    required this.expiryUnits,
    required this.saleReceiptUnits,
    required this.stockUnits,
    required this.lowStockCount,
    required this.rows,
    required this.movements,
  });

  final DateTime day;
  final int unitsIn;
  final int unitsOut;
  final int saleLedgerUnits;
  final int expiryUnits;
  final int saleReceiptUnits;
  final int stockUnits;
  final int lowStockCount;
  final List<MedicineDayTrack> rows;
  final List<StockMovementEntry> movements;

  int get net => unitsIn - unitsOut;
  bool get salesMatchLedger => saleLedgerUnits == saleReceiptUnits;
}

class InventoryTrackingService {
  InventoryTrackingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<DailyInventoryTrack> watchDay({
    required DateTime day,
    required List<Medicine> medicines,
  }) {
    final start = StockLedger.startOfDay(day);
    final end = StockLedger.endOfDay(day);
    return TenantContext.instance
        .scoped(_firestore.collection(FirestoreCollections.stockMovements))
        .snapshots()
        .asyncMap((snapshot) async {
      final docs = snapshot.docs.where((doc) {
        final createdAt = _readDate(doc.data()['createdAt']);
        return createdAt != null && !createdAt.isBefore(start) && !createdAt.isAfter(end);
      }).toList();
      final saleUnits = await _saleUnitsByMedicine(start, end);
      return _build(day, medicines, docs, saleUnits);
    });
  }

  Future<DailyInventoryTrack> loadDay({
    required DateTime day,
    required List<Medicine> medicines,
  }) async {
    final start = StockLedger.startOfDay(day);
    final end = StockLedger.endOfDay(day);
    final docs = await _fallbackMovements(start, end);
    final saleUnits = await _saleUnitsByMedicine(start, end);
    return _build(day, medicines, docs, saleUnits);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fallbackMovements(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final snapshot = await TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.stockMovements)).get();
      return snapshot.docs.where((doc) {
        final createdAt = _readDate(doc.data()['createdAt']);
        return createdAt != null && !createdAt.isBefore(start) && !createdAt.isAfter(end);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, int>> _saleUnitsByMedicine(DateTime start, DateTime end) async {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> salesDocs;
    try {
      final snapshot = await TenantContext.instance
          .scoped(_firestore.collection(FirestoreCollections.sales))
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      salesDocs = snapshot.docs.where((doc) => (doc.data()['status'] as String? ?? 'completed') != 'voided').toList();
    } catch (_) {
      final snapshot = await TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.sales)).get();
      salesDocs = snapshot.docs.where((doc) {
        final createdAt = _readDate(doc.data()['createdAt']);
        final status = doc.data()['status'] as String? ?? 'completed';
        return status != 'voided' && createdAt != null && !createdAt.isBefore(start) && !createdAt.isAfter(end);
      }).toList();
    }

    final totals = <String, int>{};
    const chunkSize = 15;
    for (var i = 0; i < salesDocs.length; i += chunkSize) {
      final chunk = salesDocs.sublist(i, i + chunkSize > salesDocs.length ? salesDocs.length : i + chunkSize);
      final itemSnaps = await Future.wait(chunk.map((doc) => doc.reference.collection(FirestoreCollections.saleItems).get()));
      for (final items in itemSnaps) {
        for (final item in items.docs) {
          final medicineId = (item.data()['medicineId'] as String?) ?? '';
          final quantity = (item.data()['quantity'] as num?)?.toInt() ?? 0;
          if (medicineId.isEmpty || quantity <= 0) continue;
          totals[medicineId] = (totals[medicineId] ?? 0) + quantity;
        }
      }
    }
    return totals;
  }

  DailyInventoryTrack _build(
    DateTime day,
    List<Medicine> medicines,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, int> saleUnits,
  ) {
    final names = {for (final medicine in medicines) medicine.id: medicine.name};
    final inBy = <String, int>{};
    final outBy = <String, int>{};
    final saleBy = <String, int>{};
    final expiryBy = <String, int>{};
    final movements = <StockMovementEntry>[];

    for (final doc in docs) {
      final data = doc.data();
      final change = (data['quantityChange'] as num?)?.toInt() ?? 0;
      final type = (data['type'] as String?) ?? '';
      final medicineId = (data['medicineId'] as String?) ?? '';
      final direction = (data['direction'] as String?) ?? (change < 0 ? 'out' : 'in');
      final units = (data['units'] as num?)?.toInt() ?? change.abs();
      final name = (data['medicineName'] as String?)?.trim();
      if (type == 'sale' || (type.isEmpty && change < 0)) {
        outBy[medicineId] = (outBy[medicineId] ?? 0) + units;
        saleBy[medicineId] = (saleBy[medicineId] ?? 0) + units;
      } else if (type == 'expiry') {
        outBy[medicineId] = (outBy[medicineId] ?? 0) + units;
        expiryBy[medicineId] = (expiryBy[medicineId] ?? 0) + units;
      } else if (type == 'sale_void') {
        outBy[medicineId] = ((outBy[medicineId] ?? 0) - units).clamp(0, 1 << 30);
        saleBy[medicineId] = ((saleBy[medicineId] ?? 0) - units).clamp(0, 1 << 30);
      } else if (type == 'adjustment') {
        if (change < 0 || direction == 'out') {
          outBy[medicineId] = (outBy[medicineId] ?? 0) + units;
        } else {
          inBy[medicineId] = (inBy[medicineId] ?? 0) + units;
        }
      } else {
        inBy[medicineId] = (inBy[medicineId] ?? 0) + (change.abs() > 0 ? change.abs() : units);
      }
      movements.add(
        StockMovementEntry(
          id: doc.id,
          medicineId: medicineId,
          medicineName: (name != null && name.isNotEmpty) ? name : (names[medicineId] ?? 'Medicine'),
          type: type,
          direction: direction,
          quantityChange: change,
          units: units,
          batchNumber: data['batchNumber'] as String?,
          referenceId: data['referenceId'] as String?,
          createdAt: _readDate(data['createdAt']),
        ),
      );
    }

    movements.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    final rows = medicines.map((medicine) {
      return MedicineDayTrack(
        medicine: medicine,
        unitsIn: inBy[medicine.id] ?? 0,
        unitsOut: outBy[medicine.id] ?? 0,
        saleLedgerUnits: saleBy[medicine.id] ?? 0,
        expiryUnits: expiryBy[medicine.id] ?? 0,
        saleReceiptUnits: saleUnits[medicine.id] ?? 0,
      );
    }).toList()
      ..sort((a, b) {
        final activity = (b.unitsOut + b.unitsIn).compareTo(a.unitsOut + a.unitsIn);
        if (activity != 0) return activity;
        return a.medicine.name.compareTo(b.medicine.name);
      });

    final unitsIn = inBy.values.fold<int>(0, (total, value) => total + value);
    final unitsOut = outBy.values.fold<int>(0, (total, value) => total + value);
    final saleLedgerUnits = saleBy.values.fold<int>(0, (total, value) => total + value);
    final expiryUnits = expiryBy.values.fold<int>(0, (total, value) => total + value);
    final receiptUnits = saleUnits.values.fold<int>(0, (total, value) => total + value);
    final stockUnits = medicines.fold<int>(0, (total, medicine) => total + medicine.quantityOnHand);
    final lowStock = medicines.where((medicine) => medicine.quantityOnHand <= medicine.reorderLevel).length;

    return DailyInventoryTrack(
      day: day,
      unitsIn: unitsIn,
      unitsOut: unitsOut,
      saleLedgerUnits: saleLedgerUnits,
      expiryUnits: expiryUnits,
      saleReceiptUnits: receiptUnits,
      stockUnits: stockUnits,
      lowStockCount: lowStock,
      rows: rows,
      movements: movements,
    );
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
