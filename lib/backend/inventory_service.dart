import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
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
    if (medicineId.isEmpty || batchNumber.trim().isEmpty) {
      throw ArgumentError('Medicine and batch number are required.');
    }
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be greater than zero.');
    }
    if (unitCostMinor < 0) {
      throw ArgumentError.value(unitCostMinor, 'unitCostMinor', 'Cost cannot be negative.');
    }

    final normalizedBatch = batchNumber.trim();
    final expiry = expiryDate.toDate();
    if (expiry.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      throw ArgumentError('Expiry date cannot be in the past.');
    }

    final duplicateBatches = await TenantContext.instance
        .scoped(_firestore.collection(FirestoreCollections.medicineBatches))
        .where('medicineId', isEqualTo: medicineId)
        .where('batchNumber', isEqualTo: normalizedBatch)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (duplicateBatches.docs.isNotEmpty) {
      throw StateError('This medicine already has an active batch with the same number.');
    }

    final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(medicineId);
    final batchRef = _firestore.collection(FirestoreCollections.medicineBatches).doc();
    final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();

    await _firestore.runTransaction((transaction) async {
      final medicineSnapshot = await transaction.get(medicineRef);
      if (!medicineSnapshot.exists) {
        throw StateError('Medicine $medicineId does not exist.');
      }

      final currentStock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      final now = FieldValue.serverTimestamp();
      transaction.update(medicineRef, {
        'quantityOnHand': currentStock + quantity,
        'purchasePriceMinor': unitCostMinor,
        'supplierId': supplierId ?? medicineSnapshot.data()?['supplierId'],
        'updatedAt': now,
      });
      transaction.set(batchRef, TenantContext.instance.withTenant({
        'medicineId': medicineId,
        'batchNumber': normalizedBatch,
        'expiryDate': expiryDate,
        'quantityOnHand': quantity,
        'unitCostMinor': unitCostMinor,
        'supplierId': supplierId,
        'purchaseId': purchaseId,
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
      }));
      transaction.set(movementRef, TenantContext.instance.withTenant({
        'medicineId': medicineId,
        'type': 'purchase',
        'quantityChange': quantity,
        'referenceId': purchaseId,
        'createdBy': createdBy,
        'createdAt': now,
      }));
    });
  }
}
