import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'stock_ledger.dart';
import 'tenant_context.dart';

class InventoryService {
  InventoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> receiveBatch({
    required String medicineId,
    required String batchNumber,
    required Timestamp expiryDate,
    required int quantity,
    required int unitCostMinor,
    required String createdBy,
    String? supplierId,
    String? purchaseId,
  }) async {
    TenantContext.instance.assertWritable();
    if (medicineId.isEmpty) {
      throw ArgumentError('Medicine is required.');
    }
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be greater than zero.');
    }
    if (unitCostMinor < 0) {
      throw ArgumentError.value(unitCostMinor, 'unitCostMinor', 'Cost cannot be negative.');
    }

    final expiry = expiryDate.toDate();
    final month = expiry.month.toString().padLeft(2, '0');
    final day = expiry.day.toString().padLeft(2, '0');
    final normalizedBatch = batchNumber.trim().isEmpty ? 'STOCK-${expiry.year}$month$day' : batchNumber.trim();
    if (expiry.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      throw ArgumentError('Expiry date cannot be in the past.');
    }

    final existingBatchQuery = await TenantContext.instance
        .scoped(_firestore.collection(FirestoreCollections.medicineBatches))
        .where('medicineId', isEqualTo: medicineId)
        .where('batchNumber', isEqualTo: normalizedBatch)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    final existingBatchRef = existingBatchQuery.docs.isEmpty ? null : existingBatchQuery.docs.first.reference;

    final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(medicineId);
    final batchRef = existingBatchRef ?? _firestore.collection(FirestoreCollections.medicineBatches).doc();
    final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();

    await _firestore.runTransaction((transaction) async {
      final medicineSnapshot = await transaction.get(medicineRef);
      if (!medicineSnapshot.exists) {
        throw StateError('Medicine $medicineId does not exist.');
      }

      final medicineData = medicineSnapshot.data() ?? const <String, dynamic>{};
      final packSize = (medicineData['packSize'] as num?)?.toInt() ?? 1;
      final loose = packSize > 1;
      final stockQty = loose ? quantity * packSize : quantity;
      final currentStock = (medicineData['quantityOnHand'] as num?)?.toInt() ?? 0;
      var batchQty = 0;
      if (existingBatchRef != null) {
        final batchSnap = await transaction.get(existingBatchRef);
        batchQty = (batchSnap.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      }
      final now = FieldValue.serverTimestamp();
      transaction.update(medicineRef, {
        'quantityOnHand': currentStock + stockQty,
        'purchasePriceMinor': unitCostMinor,
        'supplierId': supplierId ?? medicineData['supplierId'],
        'updatedAt': now,
      });
      if (existingBatchRef != null) {
        transaction.update(existingBatchRef, {
          'quantityOnHand': batchQty + stockQty,
          'unitCostMinor': unitCostMinor,
          'expiryDate': expiryDate,
          'isActive': true,
          'updatedAt': now,
        });
      } else {
        transaction.set(batchRef, TenantContext.instance.withTenant({
          'medicineId': medicineId,
          'batchNumber': normalizedBatch,
          'expiryDate': expiryDate,
          'quantityOnHand': stockQty,
          'unitCostMinor': unitCostMinor,
          'supplierId': supplierId,
          'purchaseId': purchaseId,
          'isActive': true,
          'createdAt': now,
          'updatedAt': now,
        }));
      }
      transaction.set(movementRef, StockLedger.movement(
        medicineId: medicineId,
        medicineName: medicineSnapshot.data()?['name'] as String?,
        type: 'purchase',
        quantityChange: stockQty,
        referenceId: purchaseId,
        createdBy: createdBy,
        batchId: batchRef.id,
        batchNumber: normalizedBatch,
        createdAt: now,
      ));
    });
  }
}
