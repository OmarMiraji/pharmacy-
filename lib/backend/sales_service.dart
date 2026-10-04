import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'expiry_priority.dart';
import 'permissions.dart';
import 'stock_ledger.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class SaleCartItem {
  const SaleCartItem({
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.unitPriceMinor,
    this.unitName = 'unit',
    this.toBase = 1,
    this.sellUnitId = 'base',
    this.baseLabel = 'unit',
  });

  final String medicineId;
  final String medicineName;
  /// Quantity of the selected sell unit (e.g. 5 tablets or 1 pack).
  final int quantity;
  /// Price of one selected sell unit.
  final int unitPriceMinor;
  final String unitName;
  /// How many base/stock units one sell unit equals.
  final int toBase;
  final String sellUnitId;
  final String baseLabel;

  String get lineKey => '$medicineId:$sellUnitId';

  int get baseQuantity => quantity * (toBase < 1 ? 1 : toBase);

  int get totalMinor => quantity * unitPriceMinor;

  String get receiptCaption {
    if (sellUnitId == 'lot' && toBase > 1) {
      final tablets = quantity * toBase;
      return '$tablets $baseLabel${tablets == 1 ? '' : 's'} ($quantity × $toBase)';
    }
    final unitWord = quantity == 1 ? unitName : (unitName.toLowerCase() == 'box' ? 'Boxes' : '${unitName}s');
    if (sellUnitId == 'base' || toBase <= 1) return '$quantity $unitWord';
    return '$quantity $unitWord ($toBase $baseLabel${toBase == 1 ? '' : 's'})';
  }

  Map<String, dynamic> toJson() => {
        'medicineId': medicineId,
        'medicineName': medicineName,
        'quantity': quantity,
        'unitPriceMinor': unitPriceMinor,
        'unitName': unitName,
        'toBase': toBase,
        'sellUnitId': sellUnitId,
        'baseLabel': baseLabel,
        'baseQuantity': baseQuantity,
      };

  factory SaleCartItem.fromJson(Map<String, dynamic> json) {
    final toBase = (json['toBase'] as num?)?.toInt() ?? 1;
    return SaleCartItem(
      medicineId: json['medicineId'] as String? ?? '',
      medicineName: json['medicineName'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPriceMinor: (json['unitPriceMinor'] as num?)?.toInt() ?? 0,
      unitName: json['unitName'] as String? ?? 'unit',
      toBase: toBase < 1 ? 1 : toBase,
      sellUnitId: json['sellUnitId'] as String? ?? 'base',
      baseLabel: json['baseLabel'] as String? ?? 'unit',
    );
  }
}

class SalesService {
  SalesService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const staffDiscountCapPercent = 20;

  static void assertSaleDiscount({
    required int discountMinor,
    required int subtotalMinor,
    UserProfile? actor,
  }) {
    if (discountMinor < 0) throw ArgumentError('Discount cannot be negative.');
    if (discountMinor == 0) return;
    if (actor == null || !actor.can(AppPermissions.salesDiscount)) {
      throw ArgumentError('This login cannot apply a discount.');
    }
    if (discountMinor > subtotalMinor) throw ArgumentError('Discount cannot exceed subtotal.');
    if (actor.isSuperAdmin || actor.role == 'admin') return;
    if (discountMinor * 100 > subtotalMinor * staffDiscountCapPercent) {
      throw ArgumentError('Discount cannot exceed $staffDiscountCapPercent%.');
    }
  }

  Future<void> voidSale(String saleId) async {
    TenantContext.instance.assertWritable();
    final saleRef = _firestore.collection(FirestoreCollections.sales).doc(saleId);
    final itemsQuery = saleRef.collection(FirestoreCollections.saleItems);
    final loaded = await Future.wait<Object>([
      saleRef.get(),
      itemsQuery.get(),
    ]);
    final saleDoc = loaded[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!saleDoc.exists) return;
    final saleData = saleDoc.data() ?? const <String, dynamic>{};
    if ((saleData['status'] as String?) == 'voided') return;

    final itemSnapshots = loaded[1] as QuerySnapshot<Map<String, dynamic>>;
    final restoreByMedicine = <String, int>{};
    final names = <String, String?>{};
    for (final item in itemSnapshots.docs) {
      final data = item.data();
      final medicineId = data['medicineId'] as String?;
      final quantity = (data['quantity'] as num?)?.toInt() ?? 0;
      if (medicineId == null || quantity <= 0) continue;
      restoreByMedicine[medicineId] = (restoreByMedicine[medicineId] ?? 0) + quantity;
      names[medicineId] = data['medicineName'] as String?;
    }

    final now = FieldValue.serverTimestamp();
    await _firestore.runTransaction((transaction) async {
      final medicineRefs = [
        for (final id in restoreByMedicine.keys) _firestore.collection(FirestoreCollections.medicines).doc(id),
      ];
      final medicineSnaps = await Future.wait(medicineRefs.map(transaction.get));
      for (var i = 0; i < medicineRefs.length; i++) {
        final snap = medicineSnaps[i];
        if (!snap.exists) continue;
        final id = medicineRefs[i].id;
        final currentStock = (snap.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        transaction.update(medicineRefs[i], {
          'quantityOnHand': currentStock + restoreByMedicine[id]!,
          'updatedAt': now,
        });
      }
      transaction.update(saleRef, {
        'status': 'voided',
        'voidedAt': now,
        'updatedAt': now,
      });
    });
    try {
      final writes = _firestore.batch();
      for (final entry in restoreByMedicine.entries) {
        writes.set(_firestore.collection(FirestoreCollections.stockMovements).doc(), StockLedger.movement(
          medicineId: entry.key,
          medicineName: names[entry.key],
          type: 'sale_void',
          quantityChange: entry.value,
          referenceId: saleId,
          createdBy: 'system',
        ));
      }
      await writes.commit();
    } catch (_) {}
  }

  Future<String> completeSale({
    required List<SaleCartItem> items,
    required String soldBy,
    required String paymentMethod,
    int discountMinor = 0,
    String? customerId,
    UserProfile? actor,
  }) async {
    TenantContext.instance.assertWritable();
    if (items.isEmpty) throw ArgumentError('Cart cannot be empty.');
    if (soldBy.trim().isEmpty) throw ArgumentError('Seller is required.');
    if (paymentMethod.trim().isEmpty) throw ArgumentError('Payment method is required.');
    if (discountMinor < 0) throw ArgumentError('Discount cannot be negative.');

    final saleRef = _firestore.collection(FirestoreCollections.sales).doc();
    final receiptNumber = 'R-${DateTime.now().millisecondsSinceEpoch}';
    final movementCollection = _firestore.collection(FirestoreCollections.stockMovements);
    final saleItemsCollection = saleRef.collection(FirestoreCollections.saleItems);
    final subtotalMinor = items.fold<int>(0, (total, item) => total + item.totalMinor);
    if (discountMinor > subtotalMinor) throw ArgumentError('Discount cannot exceed subtotal.');
    assertSaleDiscount(discountMinor: discountMinor, subtotalMinor: subtotalMinor, actor: actor);

    final medicineTotals = <String, int>{};
    final itemByMedicine = <String, SaleCartItem>{};
    for (final item in items) {
      if (item.quantity <= 0) throw ArgumentError('Sale quantity must be greater than zero.');
      medicineTotals[item.medicineId] = (medicineTotals[item.medicineId] ?? 0) + item.baseQuantity;
      itemByMedicine[item.medicineId] = item;
    }

    final medicineIds = medicineTotals.keys.toList(growable: false);
    final batchQueries = await Future.wait([
      for (final id in medicineIds)
        TenantContext.instance
            .scoped(_firestore.collection(FirestoreCollections.medicineBatches))
            .where('medicineId', isEqualTo: id)
            .get(),
    ]);
    final batchRefsByMedicine = <String, List<DocumentReference<Map<String, dynamic>>>>{};
    for (var i = 0; i < medicineIds.length; i++) {
      batchRefsByMedicine[medicineIds[i]] = [for (final doc in batchQueries[i].docs) doc.reference];
    }

    var allocations = <_BatchTake>[];
    await _firestore.runTransaction((transaction) async {
      final serverNow = FieldValue.serverTimestamp();
      final medicineRefs = [
        for (final id in medicineIds) _firestore.collection(FirestoreCollections.medicines).doc(id),
      ];
      final allBatchRefs = <DocumentReference<Map<String, dynamic>>>[
        for (final refs in batchRefsByMedicine.values) ...refs,
      ];
      final locked = await Future.wait([
        ...medicineRefs.map(transaction.get),
        ...allBatchRefs.map(transaction.get),
      ]);
      final medicineSnaps = locked.sublist(0, medicineRefs.length);
      final batchSnaps = locked.sublist(medicineRefs.length);

      final batchById = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final snap in batchSnaps) {
        batchById[snap.id] = snap;
      }

      for (var i = 0; i < medicineIds.length; i++) {
        final medicine = itemByMedicine[medicineIds[i]]!;
        final medicineSnapshot = medicineSnaps[i];
        if (!medicineSnapshot.exists) throw StateError('Medicine ${medicine.medicineName} does not exist.');
        final stock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (stock < medicineTotals[medicineIds[i]]!) {
          throw StateError('Not enough stock for ${medicine.medicineName}.');
        }
      }

      allocations = <_BatchTake>[];
      for (final medicineId in medicineIds) {
        final medicine = itemByMedicine[medicineId]!;
        final needed = medicineTotals[medicineId]!;
        final live = <DocumentSnapshot<Map<String, dynamic>>>[
          for (final ref in batchRefsByMedicine[medicineId] ?? const <DocumentReference<Map<String, dynamic>>>[])
            if (batchById[ref.id] != null) batchById[ref.id]!,
        ]..sort((left, right) {
            final leftExpiry = ExpiryPriority.parseAny(left.data()?['expiryDate']) ?? DateTime(9999);
            final rightExpiry = ExpiryPriority.parseAny(right.data()?['expiryDate']) ?? DateTime(9999);
            return leftExpiry.compareTo(rightExpiry);
          });
        var remaining = needed;
        for (final snap in live) {
          if (remaining == 0) break;
          final data = snap.data();
          if (data == null || data['isActive'] != true) continue;
          final expiry = ExpiryPriority.parseAny(data['expiryDate']);
          if (expiry == null || ExpiryPriority.isExpired(expiry)) continue;
          final available = (data['quantityOnHand'] as num?)?.toInt() ?? 0;
          if (available <= 0) continue;
          final taken = available < remaining ? available : remaining;
          allocations.add(_BatchTake(medicine: medicine, snapshot: snap, quantity: taken));
          remaining -= taken;
        }
        if (remaining > 0) {
          throw StateError('No active batches contain enough stock for ${medicine.medicineName}.');
        }
      }

      for (var i = 0; i < medicineIds.length; i++) {
        final stock = (medicineSnaps[i].data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        transaction.update(medicineRefs[i], {
          'quantityOnHand': stock - medicineTotals[medicineIds[i]]!,
          'updatedAt': serverNow,
        });
      }

      transaction.set(saleRef, TenantContext.instance.withTenant({
        'receiptNumber': receiptNumber,
        'customerId': customerId,
        'status': 'completed',
        'paymentMethod': paymentMethod.trim(),
        'subtotalMinor': subtotalMinor,
        'discountMinor': discountMinor,
        'taxMinor': 0,
        'totalMinor': subtotalMinor - discountMinor,
        'soldBy': soldBy.trim(),
        'itemNames': [for (final item in items) item.medicineName],
        'createdAt': serverNow,
        'updatedAt': serverNow,
      }));

      for (final item in items) {
        transaction.set(saleItemsCollection.doc(), TenantContext.instance.withTenant({
          'medicineId': item.medicineId,
          'medicineName': item.medicineName,
          'quantity': item.baseQuantity,
          'soldQty': item.quantity,
          'soldUnit': item.unitName,
          'unitPriceMinor': item.unitPriceMinor,
          'totalMinor': item.totalMinor,
          'createdAt': serverNow,
        }));
      }
      for (final allocation in allocations) {
        final current = (allocation.snapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (current < allocation.quantity) {
          throw StateError('Stock changed. Please review the cart and try again.');
        }
        transaction.update(allocation.snapshot.reference, {
          'quantityOnHand': current - allocation.quantity,
          'updatedAt': serverNow,
          'isActive': current - allocation.quantity > 0,
        });
      }
    });

    try {
      final writes = _firestore.batch();
      for (final allocation in allocations) {
        writes.set(movementCollection.doc(), StockLedger.movement(
          medicineId: allocation.medicine.medicineId,
          medicineName: allocation.medicine.medicineName,
          type: 'sale',
          quantityChange: -allocation.quantity,
          referenceId: saleRef.id,
          createdBy: soldBy.trim(),
          batchId: allocation.snapshot.id,
          batchNumber: allocation.snapshot.data()?['batchNumber'] as String?,
        ));
      }
      await writes.commit();
    } catch (_) {}
    return receiptNumber;
  }
}

class _BatchTake {
  const _BatchTake({
    required this.medicine,
    required this.snapshot,
    required this.quantity,
  });

  final SaleCartItem medicine;
  final DocumentSnapshot<Map<String, dynamic>> snapshot;
  final int quantity;
}
