import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';

class ReportDateRange {
  const ReportDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class MedicinePerformanceRow {
  const MedicinePerformanceRow({
    required this.medicineId,
    required this.medicineName,
    required this.unitsSold,
    required this.revenueMinor,
    required this.costMinor,
    required this.grossProfitMinor,
  });

  final String medicineId;
  final String medicineName;
  final int unitsSold;
  final int revenueMinor;
  final int costMinor;
  final int grossProfitMinor;
}

class DetailedReport {
  const DetailedReport({
    required this.range,
    required this.salesCount,
    required this.salesTotalMinor,
    required this.purchasesCount,
    required this.purchasesTotalMinor,
    required this.grossProfitMinor,
    required this.medicineCount,
    required this.lowStockCount,
    required this.stockUnits,
    required this.medicinePerformance,
  });

  final ReportDateRange range;
  final int salesCount;
  final int salesTotalMinor;
  final int purchasesCount;
  final int purchasesTotalMinor;
  final int grossProfitMinor;
  final int medicineCount;
  final int lowStockCount;
  final int stockUnits;
  final List<MedicinePerformanceRow> medicinePerformance;
}

class ReportSummary {
  const ReportSummary({
    required this.salesCount,
    required this.salesTotalMinor,
    required this.purchasesCount,
    required this.purchasesTotalMinor,
    required this.medicineCount,
    required this.lowStockCount,
    required this.stockUnits,
  });

  final int salesCount;
  final int salesTotalMinor;
  final int purchasesCount;
  final int purchasesTotalMinor;
  final int medicineCount;
  final int lowStockCount;
  final int stockUnits;
}

class ReportService {
  ReportService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static ReportDateRange buildDateRange({DateTime? from, DateTime? to}) {
    final now = DateTime.now();
    final resolvedFrom = (from ?? DateTime(now.year, now.month, 1));
    final resolvedTo = (to ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999));

    return ReportDateRange(
      start: DateTime(resolvedFrom.year, resolvedFrom.month, resolvedFrom.day),
      end: DateTime(resolvedTo.year, resolvedTo.month, resolvedTo.day, 23, 59, 59, 999),
    );
  }

  Future<ReportSummary> loadSummary() async {
    final results = await Future.wait([
      TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.sales)).get(),
      TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.purchases)).get(),
      TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.medicines)).where('isActive', isEqualTo: true).get(),
    ]);
    final sales = results[0];
    final purchases = results[1];
    final medicines = results[2];
    final salesTotal = sales.docs.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
    final purchasesTotal = purchases.docs.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
    final lowStock = medicines.docs.where((doc) {
      final data = doc.data();
      final stock = (data['quantityOnHand'] as num?)?.toInt() ?? 0;
      final reorder = (data['reorderLevel'] as num?)?.toInt() ?? 0;
      return stock <= reorder;
    }).length;
    final stockUnits = medicines.docs.fold<int>(0, (total, doc) => total + ((doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0));
    return ReportSummary(
      salesCount: sales.size,
      salesTotalMinor: salesTotal,
      purchasesCount: purchases.size,
      purchasesTotalMinor: purchasesTotal,
      medicineCount: medicines.size,
      lowStockCount: lowStock,
      stockUnits: stockUnits,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _docsInRange({
    required String collection,
    required ReportDateRange range,
  }) async {
    Query<Map<String, dynamic>> query = TenantContext.instance.scoped(_firestore.collection(collection));
    try {
      final snapshot = await query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(range.end))
          .get();
      return snapshot.docs;
    } catch (_) {
      final snapshot = await TenantContext.instance.scoped(_firestore.collection(collection)).get();
      return snapshot.docs.where((doc) {
        final createdAt = _readDate(doc.data()['createdAt']);
        return createdAt != null && !createdAt.isBefore(range.start) && !createdAt.isAfter(range.end);
      }).toList();
    }
  }

  Future<List<QuerySnapshot<Map<String, dynamic>>>> _loadSubcollections(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String subcollection,
  ) async {
    final snapshots = <QuerySnapshot<Map<String, dynamic>>>[];
    const chunkSize = 15;
    for (var i = 0; i < docs.length; i += chunkSize) {
      final chunk = docs.sublist(i, i + chunkSize > docs.length ? docs.length : i + chunkSize);
      snapshots.addAll(
        await Future.wait(
          chunk.map((doc) => doc.reference.collection(subcollection).get()),
        ),
      );
    }
    return snapshots;
  }

  Future<DetailedReport> loadDetailedReport({DateTime? from, DateTime? to}) async {
    final range = buildDateRange(from: from, to: to);
    final results = await Future.wait([
      _docsInRange(collection: FirestoreCollections.sales, range: range),
      _docsInRange(collection: FirestoreCollections.purchases, range: range),
      TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.medicines)).where('isActive', isEqualTo: true).get(),
    ]);
    final salesDocs = results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final purchaseDocs = results[1] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final medicinesSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>;

    int salesTotalMinor = 0;
    int purchasesTotalMinor = 0;
    final medicinePerformance = <String, Map<String, dynamic>>{};

    Map<String, dynamic> entryFor(String medicineId, String medicineName) {
      return medicinePerformance.putIfAbsent(
        medicineId.isEmpty ? medicineName : medicineId,
        () => {
          'medicineId': medicineId,
          'medicineName': medicineName,
          'unitsSold': 0,
          'revenueMinor': 0,
          'costMinor': 0,
          'grossProfitMinor': 0,
        },
      );
    }

    for (final saleDoc in salesDocs) {
      salesTotalMinor += (saleDoc.data()['totalMinor'] as num?)?.toInt() ?? 0;
    }
    for (final purchaseDoc in purchaseDocs) {
      purchasesTotalMinor += (purchaseDoc.data()['totalMinor'] as num?)?.toInt() ?? 0;
    }

    final itemSnapshots = await Future.wait([
      _loadSubcollections(salesDocs, FirestoreCollections.saleItems),
      _loadSubcollections(purchaseDocs, FirestoreCollections.purchaseItems),
    ]);
    final saleItemSnapshots = itemSnapshots[0];
    final purchaseItemSnapshots = itemSnapshots[1];

    for (final items in saleItemSnapshots) {
      for (final itemDoc in items.docs) {
        final item = itemDoc.data();
        final medicineId = (item['medicineId'] as String?) ?? '';
        final medicineName = (item['medicineName'] as String?) ?? 'Unknown medicine';
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final revenue = (item['totalMinor'] as num?)?.toInt() ?? 0;
        final entry = entryFor(medicineId, medicineName);
        entry['unitsSold'] = (entry['unitsSold'] as int) + quantity;
        entry['revenueMinor'] = (entry['revenueMinor'] as int) + revenue;
      }
    }

    for (final items in purchaseItemSnapshots) {
      for (final itemDoc in items.docs) {
        final item = itemDoc.data();
        final medicineId = (item['medicineId'] as String?) ?? '';
        final medicineName = (item['medicineName'] as String?) ?? 'Unknown medicine';
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final unitCost = (item['unitCostMinor'] as num?)?.toInt() ?? 0;
        final entry = entryFor(medicineId, medicineName);
        entry['costMinor'] = (entry['costMinor'] as int) + (quantity * unitCost);
      }
    }

    final rows = medicinePerformance.values.map((entry) {
      final sold = (entry['unitsSold'] as num?)?.toInt() ?? 0;
      final revenue = (entry['revenueMinor'] as num?)?.toInt() ?? 0;
      final cost = (entry['costMinor'] as num?)?.toInt() ?? 0;
      final medicineName = (entry['medicineName'] as String?) ?? 'Unknown medicine';
      return MedicinePerformanceRow(
        medicineId: (entry['medicineId'] as String?) ?? medicineName,
        medicineName: medicineName,
        unitsSold: sold,
        revenueMinor: revenue,
        costMinor: cost,
        grossProfitMinor: revenue - cost,
      );
    }).toList();

    rows.sort((a, b) => b.revenueMinor.compareTo(a.revenueMinor));

    final grossProfitMinor = salesTotalMinor - purchasesTotalMinor;
    final lowStock = medicinesSnapshot.docs.where((doc) {
      final data = doc.data();
      final stock = (data['quantityOnHand'] as num?)?.toInt() ?? 0;
      final reorder = (data['reorderLevel'] as num?)?.toInt() ?? 0;
      return stock <= reorder;
    }).length;
    final stockUnits = medicinesSnapshot.docs.fold<int>(0, (total, doc) => total + ((doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0));

    return DetailedReport(
      range: range,
      salesCount: salesDocs.length,
      salesTotalMinor: salesTotalMinor,
      purchasesCount: purchaseDocs.length,
      purchasesTotalMinor: purchasesTotalMinor,
      grossProfitMinor: grossProfitMinor,
      medicineCount: medicinesSnapshot.size,
      lowStockCount: lowStock,
      stockUnits: stockUnits,
      medicinePerformance: rows,
    );
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
