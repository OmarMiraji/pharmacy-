import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'stock_ledger.dart';
import 'tenant_context.dart';

class SupplierOption {
  const SupplierOption({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;
}

class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.supplierId,
    required this.status,
    required this.totalMinor,
    this.invoiceNumber,
    this.supplierName,
    this.medicineName,
    this.quantity,
  });

  final String id;
  final String supplierId;
  final String status;
  final int totalMinor;
  final String? invoiceNumber;
  final String? supplierName;
  final String? medicineName;
  final int? quantity;
}

class PurchaseService {
  PurchaseService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _suppliers => _firestore.collection(FirestoreCollections.suppliers);
  CollectionReference<Map<String, dynamic>> get _purchases => _firestore.collection(FirestoreCollections.purchases);

  Stream<List<SupplierOption>> watchSuppliers() => TenantContext.instance.scoped(_suppliers).snapshots().map((snapshot) => snapshot.docs.map((doc) => SupplierOption(id: doc.id, name: doc.data()['name'] as String? ?? '', phone: doc.data()['phone'] as String?)).where((supplier) => supplier.name.isNotEmpty).toList()..sort((a, b) => a.name.compareTo(b.name)));

  Stream<List<PurchaseRecord>> watchPurchases() => TenantContext.instance.scoped(_purchases).snapshots().map((snapshot) => snapshot.docs.map((doc) {
        final data = doc.data();
        return PurchaseRecord(
          id: doc.id,
          supplierId: data['supplierId'] as String? ?? '',
          status: data['status'] as String? ?? 'draft',
          totalMinor: (data['totalMinor'] as num?)?.toInt() ?? 0,
          invoiceNumber: data['invoiceNumber'] as String?,
          supplierName: data['supplierName'] as String?,
          medicineName: data['medicineName'] as String?,
          quantity: (data['quantityReceived'] as num?)?.toInt(),
        );
      }).toList());

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

    String? supplierName;
    try {
      final supplierSnap = await _suppliers.doc(supplierId).get();
      supplierName = supplierSnap.data()?['name'] as String?;
    } catch (_) {}

    final existingBatchQuery = await TenantContext.instance
        .scoped(_firestore.collection(FirestoreCollections.medicineBatches))
        .where('medicineId', isEqualTo: medicineId)
        .where('batchNumber', isEqualTo: normalizedBatch)
        .where('isActive', isEqualTo: true)
        .limit(5)
        .get();
    DocumentReference<Map<String, dynamic>>? existingBatchRef;
    for (final doc in existingBatchQuery.docs) {
      final existingExpiry = (doc.data()['expiryDate'] as Timestamp?)?.toDate();
      if (existingExpiry == null) continue;
      if (existingExpiry.year == expiryDate.year && existingExpiry.month == expiryDate.month && existingExpiry.day == expiryDate.day) {
        existingBatchRef = doc.reference;
        break;
      }
    }

    final purchaseRef = _purchases.doc();
    final itemRef = purchaseRef.collection(FirestoreCollections.purchaseItems).doc();
    final medicineRef = _firestore.collection(FirestoreCollections.medicines).doc(medicineId);
    final batchRef = existingBatchRef ?? _firestore.collection(FirestoreCollections.medicineBatches).doc();
    final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();
    final total = quantity * unitCostMinor;
    var medicineName = '';
    var stockQty = quantity;
    await _firestore.runTransaction((transaction) async {
      final medicineSnapshot = await transaction.get(medicineRef);
      if (!medicineSnapshot.exists) throw StateError('Medicine does not exist.');
      final medicineData = medicineSnapshot.data() ?? const <String, dynamic>{};
      final packSize = (medicineData['packSize'] as num?)?.toInt() ?? 1;
      final loose = packSize > 1;
      stockQty = loose ? quantity * packSize : quantity;
      final currentStock = (medicineData['quantityOnHand'] as num?)?.toInt() ?? 0;
      var batchQty = 0;
      if (existingBatchRef != null) {
        final batchSnap = await transaction.get(existingBatchRef);
        batchQty = (batchSnap.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      }
      final now = FieldValue.serverTimestamp();
      medicineName = (medicineData['name'] as String?) ?? '';
      transaction.set(purchaseRef, TenantContext.instance.withTenant({
        'supplierId': supplierId,
        'supplierName': supplierName,
        'invoiceNumber': invoiceNumber?.trim(),
        'status': 'received',
        'subtotalMinor': total,
        'taxMinor': 0,
        'totalMinor': total,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'quantityReceived': stockQty,
        'receivedAt': now,
        'createdBy': createdBy,
        'createdAt': now,
        'updatedAt': now,
      }));
      transaction.set(itemRef, TenantContext.instance.withTenant({
        'medicineId': medicineId,
        'medicineName': medicineName,
        'quantity': quantity,
        'unitCostMinor': unitCostMinor,
        'totalMinor': total,
        'batchNumber': normalizedBatch,
        'expiryDate': Timestamp.fromDate(expiryDate),
      }));
      transaction.update(medicineRef, {
        'quantityOnHand': currentStock + stockQty,
        'purchasePriceMinor': unitCostMinor,
        'supplierId': supplierId,
        'updatedAt': now,
      });
      if (existingBatchRef != null) {
        transaction.update(existingBatchRef, {
          'quantityOnHand': batchQty + stockQty,
          'unitCostMinor': unitCostMinor,
          'expiryDate': Timestamp.fromDate(expiryDate),
          'isActive': true,
          'updatedAt': now,
        });
      } else {
        transaction.set(batchRef, TenantContext.instance.withTenant({
          'medicineId': medicineId,
          'batchNumber': normalizedBatch,
          'expiryDate': Timestamp.fromDate(expiryDate),
          'quantityOnHand': stockQty,
          'unitCostMinor': unitCostMinor,
          'supplierId': supplierId,
          'purchaseId': purchaseRef.id,
          'isActive': true,
          'createdAt': now,
          'updatedAt': now,
        }));
      }
    });
    try {
      await movementRef.set(StockLedger.movement(
        medicineId: medicineId,
        medicineName: medicineName,
        type: 'purchase',
        quantityChange: stockQty,
        referenceId: purchaseRef.id,
        createdBy: createdBy,
        batchId: batchRef.id,
        batchNumber: normalizedBatch,
      ));
    } catch (_) {}
    return purchaseRef.id;
  }
}
