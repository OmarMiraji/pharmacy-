import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';

class SupplierOption {
  const SupplierOption({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;
}

class PurchaseRecord {
  const PurchaseRecord({required this.id, required this.supplierId, required this.status, required this.totalMinor, this.invoiceNumber});

  final String id;
  final String supplierId;
  final String status;
  final int totalMinor;
  final String? invoiceNumber;
}

class PurchaseService {
  PurchaseService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _suppliers => _firestore.collection(FirestoreCollections.suppliers);
  CollectionReference<Map<String, dynamic>> get _purchases => _firestore.collection(FirestoreCollections.purchases);

  Stream<List<SupplierOption>> watchSuppliers() => TenantContext.instance.scoped(_suppliers).snapshots().map((snapshot) => snapshot.docs.map((doc) => SupplierOption(id: doc.id, name: doc.data()['name'] as String? ?? '', phone: doc.data()['phone'] as String?)).where((supplier) => supplier.name.isNotEmpty).toList()..sort((a, b) => a.name.compareTo(b.name)));

  Stream<List<PurchaseRecord>> watchPurchases() => TenantContext.instance.scoped(_purchases).snapshots().map((snapshot) => snapshot.docs.map((doc) { final data = doc.data(); return PurchaseRecord(id: doc.id, supplierId: data['supplierId'] as String? ?? '', status: data['status'] as String? ?? 'draft', totalMinor: (data['totalMinor'] as num?)?.toInt() ?? 0, invoiceNumber: data['invoiceNumber'] as String?); }).toList());

  Future<void> createSupplier({required String name, String? phone, String? email}) async {
    TenantContext.instance.assertWritable();
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required.');
    await _suppliers.add(TenantContext.instance.withTenant({'name': name.trim(), 'phone': phone?.trim(), 'email': email?.trim(), 'isActive': true, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()}));
  }

  Future<String> receivePurchase({required String supplierId, required String medicineId, required String batchNumber, required DateTime expiryDate, required int quantity, required int unitCostMinor, required String createdBy, String? invoiceNumber}) async {
    TenantContext.instance.assertWritable();
    if (supplierId.isEmpty || medicineId.isEmpty || batchNumber.trim().isEmpty || quantity <= 0 || unitCostMinor < 0) {
      throw ArgumentError('Supplier, medicine, batch, quantity, and cost are required.');
    }
    final normalizedBatch = batchNumber.trim();
    if (expiryDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
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
      throw StateError('This medicine already has an active batch with the same batch number.');
    }

    final purchaseRef = _purchases.doc();
    final itemRef = purchaseRef.collection(FirestoreCollections.purchaseItems).doc();
    final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(medicineId);
    final batchRef = _firestore.collection(FirestoreCollections.medicineBatches).doc();
    final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();
    final total = quantity * unitCostMinor;
    await _firestore.runTransaction((transaction) async {
      final medicineSnapshot = await transaction.get(medicineRef);
      if (!medicineSnapshot.exists) throw StateError('Medicine does not exist.');
      final currentStock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      final now = FieldValue.serverTimestamp();
      transaction.set(purchaseRef, TenantContext.instance.withTenant({
        'supplierId': supplierId,
        'invoiceNumber': invoiceNumber?.trim(),
        'status': 'received',
        'subtotalMinor': total,
        'taxMinor': 0,
        'totalMinor': total,
        'receivedAt': now,
        'createdBy': createdBy,
        'createdAt': now,
        'updatedAt': now,
      }));
      transaction.set(itemRef, {
        'medicineId': medicineId,
        'quantity': quantity,
        'unitCostMinor': unitCostMinor,
        'totalMinor': total,
        'batchNumber': normalizedBatch,
        'expiryDate': Timestamp.fromDate(expiryDate),
      });
      transaction.update(medicineRef, {
        'quantityOnHand': currentStock + quantity,
        'purchasePriceMinor': unitCostMinor,
        'supplierId': supplierId,
        'updatedAt': now,
      });
      transaction.set(batchRef, TenantContext.instance.withTenant({
        'medicineId': medicineId,
        'batchNumber': normalizedBatch,
        'expiryDate': Timestamp.fromDate(expiryDate),
        'quantityOnHand': quantity,
        'unitCostMinor': unitCostMinor,
        'supplierId': supplierId,
        'purchaseId': purchaseRef.id,
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
      }));
      transaction.set(movementRef, TenantContext.instance.withTenant({
        'medicineId': medicineId,
        'type': 'purchase',
        'quantityChange': quantity,
        'referenceId': purchaseRef.id,
        'createdBy': createdBy,
        'createdAt': now,
      }));
    });
    return purchaseRef.id;
  }
}
