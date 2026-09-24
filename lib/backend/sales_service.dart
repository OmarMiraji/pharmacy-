import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';

class SaleCartItem {
  const SaleCartItem({
    required this.medicineId,
    required this.medicineName,
    required this.quantity,
    required this.unitPriceMinor,
  });

  final String medicineId;
  final String medicineName;
  final int quantity;
  final int unitPriceMinor;

  int get totalMinor => quantity * unitPriceMinor;
}

class SalesService {
  SalesService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> voidSale(String saleId) async {
    TenantContext.instance.assertWritable();
    final saleRef = _firestore.collection(FirestoreCollections.sales).doc(saleId);
    final saleDoc = await saleRef.get();
    if (!saleDoc.exists) return;

    final itemSnapshots = await saleRef.collection(FirestoreCollections.saleItems).get();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      for (final item in itemSnapshots.docs) {
        final data = item.data();
        final medicineId = data['medicineId'] as String?;
        final quantity = (data['quantity'] as num?)?.toInt() ?? 0;
        if (medicineId == null || quantity <= 0) {
          continue;
        }

        final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(medicineId);
        final medicineSnapshot = await transaction.get(medicineRef);
        if (medicineSnapshot.exists) {
          final currentStock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
          transaction.update(medicineRef, {
            'quantityOnHand': currentStock + quantity,
            'updatedAt': now,
          });
        }

        transaction.set(_firestore.collection(FirestoreCollections.stockMovements).doc(), TenantContext.instance.withTenant({
          'medicineId': medicineId,
          'type': 'sale_void',
          'quantityChange': quantity,
          'referenceId': saleId,
          'createdAt': now,
          'createdBy': 'system',
        }));

        transaction.delete(item.reference);
      }

      transaction.delete(saleRef);
    });
  }

  Future<String> completeSale({
    required List<SaleCartItem> items,
    required String soldBy,
    required String paymentMethod,
    int discountMinor = 0,
    String? customerId,
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

    final medicineTotals = <String, int>{};
    final itemByMedicine = <String, SaleCartItem>{};
    for (final item in items) {
      if (item.quantity <= 0) throw ArgumentError('Sale quantity must be greater than zero.');
      medicineTotals[item.medicineId] = (medicineTotals[item.medicineId] ?? 0) + item.quantity;
      itemByMedicine[item.medicineId] = item;
    }

    final batchPlans = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (final entry in medicineTotals.entries) {
      final medicine = itemByMedicine[entry.key]!;
      final batches = await TenantContext.instance
          .scoped(_firestore.collection(FirestoreCollections.medicineBatches))
          .where('medicineId', isEqualTo: medicine.medicineId)
          .get();
      final sortedBatches = batches.docs.toList()
        ..sort((left, right) {
          final leftExpiry = (left.data()['expiryDate'] as Timestamp?)?.toDate() ?? DateTime(9999);
          final rightExpiry = (right.data()['expiryDate'] as Timestamp?)?.toDate() ?? DateTime(9999);
          return leftExpiry.compareTo(rightExpiry);
        });
      var remaining = entry.value;
      for (final batch in sortedBatches) {
        if (remaining == 0) break;
        final data = batch.data();
        if (data['isActive'] != true) continue;
        final expiry = (data['expiryDate'] as Timestamp?)?.toDate();
        if (expiry == null || expiry.isBefore(now.subtract(const Duration(days: 1)))) continue;
        final available = (data['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (available <= 0) continue;
        final taken = available < remaining ? available : remaining;
        batchPlans.add({'item': medicine, 'batch': batch, 'quantity': taken});
        remaining -= taken;
      }
      if (remaining > 0) throw StateError('No active batches contain enough stock for ${medicine.medicineName}.');
    }

    await _firestore.runTransaction((transaction) async {
      final serverNow = FieldValue.serverTimestamp();
      final batchSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in medicineTotals.entries) {
        final medicine = itemByMedicine[entry.key]!;
        final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(entry.key);
        final medicineSnapshot = await transaction.get(medicineRef);
        if (!medicineSnapshot.exists) throw StateError('Medicine ${medicine.medicineName} does not exist.');
        final stock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (stock < entry.value) throw StateError('Not enough stock for ${medicine.medicineName}.');
      }
      for (final plan in batchPlans) {
        final batch = plan['batch'] as QueryDocumentSnapshot<Map<String, dynamic>>;
        final batchSnapshot = await transaction.get(batch.reference);
        if (!batchSnapshot.exists) throw StateError('A selected stock batch no longer exists.');
        batchSnapshots[batch.id] = batchSnapshot;
      }
      for (final entry in medicineTotals.entries) {
        final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(entry.key);
        final medicineSnapshot = await transaction.get(medicineRef);
        final stock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        transaction.update(medicineRef, {'quantityOnHand': stock - entry.value, 'updatedAt': serverNow});
      }

      final totalMinor = subtotalMinor - discountMinor;
      transaction.set(saleRef, TenantContext.instance.withTenant({
        'receiptNumber': receiptNumber,
        'customerId': customerId,
        'status': 'completed',
        'paymentMethod': paymentMethod.trim(),
        'subtotalMinor': subtotalMinor,
        'discountMinor': discountMinor,
        'taxMinor': 0,
        'totalMinor': totalMinor,
        'soldBy': soldBy.trim(),
        'createdAt': serverNow,
        'updatedAt': serverNow,
      }));

      for (final item in items) {
        final itemRef = saleItemsCollection.doc();
        transaction.set(itemRef, {
          'medicineId': item.medicineId,
          'medicineName': item.medicineName,
          'quantity': item.quantity,
          'unitPriceMinor': item.unitPriceMinor,
          'totalMinor': item.totalMinor,
          'createdAt': serverNow,
        });
      }
      for (final allocation in batchPlans) {
        final batch = allocation['batch'] as QueryDocumentSnapshot<Map<String, dynamic>>;
        final item = allocation['item'] as SaleCartItem;
        final taken = allocation['quantity'] as int;
        final currentSnapshot = batchSnapshots[batch.id];
        if (currentSnapshot == null) throw StateError('A selected stock batch could not be read.');
        final current = (currentSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (current < taken) throw StateError('Stock changed. Please review the cart and try again.');
        transaction.update(batch.reference, {
          'quantityOnHand': current - taken,
          'updatedAt': serverNow,
          'isActive': current - taken > 0,
        });
        transaction.set(movementCollection.doc(), TenantContext.instance.withTenant({
          'medicineId': item.medicineId,
          'type': 'sale',
          'quantityChange': -taken,
          'referenceId': saleRef.id,
          'createdBy': soldBy.trim(),
          'createdAt': serverNow,
        }));
      }
    });
    return receiptNumber;
  }
}
