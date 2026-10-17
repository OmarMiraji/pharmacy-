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
  PurchaseService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _suppliers =>
      _firestore.collection(FirestoreCollections.suppliers);
  CollectionReference<Map<String, dynamic>> get _purchases =>
      _firestore.collection(FirestoreCollections.purchases);

  Stream<List<SupplierOption>> watchSuppliers() => TenantContext.instance
      .scoped(_suppliers)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs
                .map(
                  (doc) => SupplierOption(
                    id: doc.id,
                    name: doc.data()['name'] as String? ?? '',
                    phone: doc.data()['phone'] as String?,
                  ),
                )
                .where((supplier) => supplier.name.isNotEmpty)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Stream<List<PurchaseRecord>> watchPurchases() => TenantContext.instance
      .scoped(_purchases)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
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
        }).toList(),
      );

  Future<void> adjustReceivedQuantity({
    required String purchaseId,
    required int quantity,
    required String updatedBy,
  }) async {
    TenantContext.instance.assertWritable();
    if (quantity <= 0) {
      throw ArgumentError('Received quantity must be greater than zero.');
    }

    final purchaseRef = _purchases.doc(purchaseId);
    final itemCollection = purchaseRef.collection(
      FirestoreCollections.purchaseItems,
    );
    final loaded = await Future.wait<Object>([
      purchaseRef.get(),
      itemCollection.get(),
      TenantContext.instance
          .scoped(_firestore.collection(FirestoreCollections.stockMovements))
          .where('referenceId', isEqualTo: purchaseId)
          .get(),
    ]);
    final purchaseSnapshot =
        loaded[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!purchaseSnapshot.exists) {
      throw StateError('The received record was not found.');
    }
    final purchaseData = purchaseSnapshot.data() ?? const <String, dynamic>{};
    if ((purchaseData['status'] as String?) != 'received') {
      throw StateError('Only received stock can be corrected.');
    }
    final itemSnapshot = loaded[1] as QuerySnapshot<Map<String, dynamic>>;
    if (itemSnapshot.docs.length != 1) {
      throw StateError(
        'This received record cannot be corrected because its item details are incomplete.',
      );
    }
    final movementSnapshot = loaded[2] as QuerySnapshot<Map<String, dynamic>>;
    final purchaseMovements = movementSnapshot.docs
        .where((doc) => doc.data()['type'] == 'purchase')
        .toList();
    if (purchaseMovements.length != 1) {
      throw StateError(
        'This received record has no unique stock batch history and cannot be corrected.',
      );
    }

    final itemRef = itemSnapshot.docs.single.reference;
    final itemData = itemSnapshot.docs.single.data();
    final oldReceived =
        (purchaseData['quantityReceived'] as num?)?.toInt() ?? 0;
    final oldPurchaseQuantity = (itemData['quantity'] as num?)?.toInt() ?? 0;
    if (oldReceived <= 0 ||
        oldPurchaseQuantity <= 0 ||
        oldReceived % oldPurchaseQuantity != 0) {
      throw StateError(
        'This received record has an invalid quantity conversion and cannot be corrected.',
      );
    }
    final stockUnitsPerItem = oldReceived ~/ oldPurchaseQuantity;
    if (quantity % stockUnitsPerItem != 0) {
      throw ArgumentError(
        'Quantity must be a multiple of $stockUnitsPerItem stock units.',
      );
    }
    final newPurchaseQuantity = quantity ~/ stockUnitsPerItem;
    final unitCost = (itemData['unitCostMinor'] as num?)?.toInt() ?? 0;
    final newTotal = newPurchaseQuantity * unitCost;
    final delta = quantity - oldReceived;
    if (delta == 0) return;

    final itemMedicineId = (itemData['medicineId'] as String?)?.trim() ?? '';
    final medicineId = itemMedicineId.isNotEmpty
        ? itemMedicineId
        : (purchaseData['medicineId'] as String? ?? '').trim();
    final batchId =
        (purchaseMovements.single.data()['batchId'] as String?)?.trim() ?? '';
    if (medicineId.isEmpty || batchId.isEmpty) {
      throw StateError(
        'This received record is missing its medicine batch reference.',
      );
    }

    final medicineRef = _firestore
        .collection(FirestoreCollections.medicines)
        .doc(medicineId);
    final batchRef = _firestore
        .collection(FirestoreCollections.medicineBatches)
        .doc(batchId);
    final originalMovementRef = purchaseMovements.single.reference;
    final correctionMovementRef = _firestore
        .collection(FirestoreCollections.stockMovements)
        .doc();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(purchaseRef),
        transaction.get(itemRef),
        transaction.get(medicineRef),
        transaction.get(batchRef),
        transaction.get(originalMovementRef),
      ]);
      final currentPurchase = snapshots[0];
      final currentItem = snapshots[1];
      final medicine = snapshots[2];
      final batch = snapshots[3];
      final originalMovement = snapshots[4];
      if (!currentPurchase.exists ||
          !currentItem.exists ||
          !medicine.exists ||
          !batch.exists ||
          !originalMovement.exists) {
        throw StateError(
          'This received stock changed or its batch is no longer available.',
        );
      }
      final currentReceived =
          (currentPurchase.data()?['quantityReceived'] as num?)?.toInt() ?? 0;
      if (currentReceived != oldReceived) {
        throw StateError(
          'This received record changed. Reload the page and try again.',
        );
      }
      final currentMedicineStock =
          (medicine.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      final currentBatchStock =
          (batch.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      if (currentMedicineStock + delta < 0 || currentBatchStock + delta < 0) {
        throw StateError(
          'Some of this batch has already been sold or removed. The received quantity cannot be reduced that far.',
        );
      }

      transaction.update(purchaseRef, {
        'quantityReceived': quantity,
        'subtotalMinor': newTotal,
        'totalMinor': newTotal,
        'updatedAt': now,
      });
      transaction.update(itemRef, {
        'quantity': newPurchaseQuantity,
        'totalMinor': newTotal,
        'updatedAt': now,
      });
      transaction.update(medicineRef, {
        'quantityOnHand': currentMedicineStock + delta,
        'updatedAt': now,
      });
      transaction.update(batchRef, {
        'quantityOnHand': currentBatchStock + delta,
        'isActive': currentBatchStock + delta > 0,
        'updatedAt': now,
      });
      transaction.update(originalMovementRef, {
        'quantityChange': quantity,
        'units': quantity,
        'direction': 'in',
        'updatedAt': now,
      });
      transaction.set(correctionMovementRef, {
        ...StockLedger.movement(
          medicineId: medicineId,
          medicineName:
              (itemData['medicineName'] as String?) ??
              (purchaseData['medicineName'] as String?),
          type: 'purchase_correction',
          quantityChange: delta,
          referenceId: purchaseId,
          batchId: batchId,
          batchNumber:
              (purchaseMovements.single.data()['batchNumber'] as String?) ?? '',
          createdBy: updatedBy,
          createdAt: now,
        ),
        'correctsMovementId': originalMovementRef.id,
      });
    });
  }

  Future<void> createSupplier({
    required String name,
    String? phone,
    String? email,
  }) async {
    TenantContext.instance.assertWritable();
    if (name.trim().isEmpty) throw ArgumentError('Supplier name is required.');
    await _suppliers.add(
      TenantContext.instance.withTenant({
        'name': name.trim(),
        'phone': phone?.trim(),
        'email': email?.trim(),
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  Future<String> receivePurchase({
    required String supplierId,
    required String medicineId,
    required String batchNumber,
    required DateTime expiryDate,
    required int quantity,
    required int unitCostMinor,
    required String createdBy,
    String? invoiceNumber,
  }) async {
    TenantContext.instance.assertWritable();
    final shopSupplier = supplierId.trim();
    if (medicineId.isEmpty || quantity <= 0 || unitCostMinor < 0) {
      throw ArgumentError('Medicine, quantity, and cost are required.');
    }
    final month = expiryDate.month.toString().padLeft(2, '0');
    final day = expiryDate.day.toString().padLeft(2, '0');
    final normalizedBatch = batchNumber.trim().isEmpty
        ? 'STOCK-${expiryDate.year}$month$day'
        : batchNumber.trim();
    final invoice = invoiceNumber?.trim() ?? '';
    if (expiryDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      throw ArgumentError('Expiry date cannot be in the past.');
    }

    String? supplierName;
    if (shopSupplier.isNotEmpty) {
      try {
        final supplierSnap = await _suppliers.doc(shopSupplier).get();
        supplierName = supplierSnap.data()?['name'] as String?;
      } catch (_) {}
    }

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
      if (existingExpiry.year == expiryDate.year &&
          existingExpiry.month == expiryDate.month &&
          existingExpiry.day == expiryDate.day) {
        existingBatchRef = doc.reference;
        break;
      }
    }

    final purchaseRef = _purchases.doc();
    final itemRef = purchaseRef
        .collection(FirestoreCollections.purchaseItems)
        .doc();
    final medicineRef = _firestore
        .collection(FirestoreCollections.medicines)
        .doc(medicineId);
    final batchRef =
        existingBatchRef ??
        _firestore.collection(FirestoreCollections.medicineBatches).doc();
    final movementRef = _firestore
        .collection(FirestoreCollections.stockMovements)
        .doc();
    final total = quantity * unitCostMinor;
    var medicineName = '';
    var stockQty = quantity;
    await _firestore.runTransaction((transaction) async {
      final medicineSnapshot = await transaction.get(medicineRef);
      if (!medicineSnapshot.exists)
        throw StateError('Medicine does not exist.');
      final medicineData = medicineSnapshot.data() ?? const <String, dynamic>{};
      final packSize = (medicineData['packSize'] as num?)?.toInt() ?? 1;
      final loose = packSize > 1;
      stockQty = loose ? quantity * packSize : quantity;
      final currentStock =
          (medicineData['quantityOnHand'] as num?)?.toInt() ?? 0;
      var batchQty = 0;
      if (existingBatchRef != null) {
        final batchSnap = await transaction.get(existingBatchRef);
        batchQty = (batchSnap.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      }
      final now = FieldValue.serverTimestamp();
      medicineName = (medicineData['name'] as String?) ?? '';
      final medicinePatch = <String, dynamic>{
        'quantityOnHand': currentStock + stockQty,
        'purchasePriceMinor': unitCostMinor,
        'updatedAt': now,
      };
      if (shopSupplier.isNotEmpty) medicinePatch['supplierId'] = shopSupplier;
      transaction.set(
        purchaseRef,
        TenantContext.instance.withTenant({
          'supplierId': shopSupplier.isEmpty ? null : shopSupplier,
          'supplierName': supplierName,
          'invoiceNumber': invoice.isEmpty ? null : invoice,
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
        }),
      );
      transaction.set(
        itemRef,
        TenantContext.instance.withTenant({
          'medicineId': medicineId,
          'medicineName': medicineName,
          'quantity': quantity,
          'unitCostMinor': unitCostMinor,
          'totalMinor': total,
          'batchNumber': normalizedBatch,
          'expiryDate': Timestamp.fromDate(expiryDate),
        }),
      );
      transaction.update(medicineRef, medicinePatch);
      if (existingBatchRef != null) {
        transaction.update(existingBatchRef, {
          'quantityOnHand': batchQty + stockQty,
          'unitCostMinor': unitCostMinor,
          'expiryDate': Timestamp.fromDate(expiryDate),
          'isActive': true,
          'updatedAt': now,
        });
      } else {
        transaction.set(
          batchRef,
          TenantContext.instance.withTenant({
            'medicineId': medicineId,
            'batchNumber': normalizedBatch,
            'expiryDate': Timestamp.fromDate(expiryDate),
            'quantityOnHand': stockQty,
            'unitCostMinor': unitCostMinor,
            'supplierId': shopSupplier.isEmpty ? null : shopSupplier,
            'purchaseId': purchaseRef.id,
            'isActive': true,
            'createdAt': now,
            'updatedAt': now,
          }),
        );
      }
    });
    try {
      await movementRef.set(
        StockLedger.movement(
          medicineId: medicineId,
          medicineName: medicineName,
          type: 'purchase',
          quantityChange: stockQty,
          referenceId: purchaseRef.id,
          createdBy: createdBy,
          batchId: batchRef.id,
          batchNumber: normalizedBatch,
        ),
      );
    } catch (_) {}
    return purchaseRef.id;
  }
}
