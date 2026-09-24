import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'models.dart';
import 'tenant_context.dart';

class MedicineService {
  MedicineService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _medicines =>
      _firestore.collection(FirestoreCollections.medicines);

  CollectionReference<Map<String, dynamic>> get _categories =>
      _firestore.collection(FirestoreCollections.categories);

  CollectionReference<Map<String, dynamic>> get _batches =>
      _firestore.collection(FirestoreCollections.medicineBatches);

  TenantContext get _tenant => TenantContext.instance;

  Stream<List<Medicine>> watchMedicines() {
    return _tenant
        .scoped(_medicines)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final medicines = snapshot.docs.map(Medicine.fromFirestore).toList();
      medicines.sort((a, b) => a.name.compareTo(b.name));
      return medicines;
    });
  }

  Stream<List<CategoryOption>> watchCategories() {
    return _tenant
        .scoped(_categories)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final categories = snapshot.docs
          .map((doc) => CategoryOption(
                id: doc.id,
                name: doc.data()['name'] as String? ?? '',
              ))
          .where((category) => category.name.isNotEmpty)
          .toList();
      categories.sort((a, b) => a.name.compareTo(b.name));
      return categories;
    });
  }

  Stream<List<MedicineBatch>> watchBatches(String medicineId) {
    return _tenant
        .scoped(_batches)
        .where('medicineId', isEqualTo: medicineId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final batches = snapshot.docs.map(MedicineBatch.fromFirestore).toList();
      batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      return batches;
    });
  }

  Stream<List<MedicineBatch>> watchAllBatches() {
    return _tenant.scoped(_batches).where('isActive', isEqualTo: true).snapshots().map((snapshot) {
      final batches = snapshot.docs.map(MedicineBatch.fromFirestore).toList();
      batches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      return batches;
    });
  }

  Future<void> createCategory(String name) async {
    _tenant.assertWritable();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Category name is required.');
    await _categories.add(_tenant.withTenant({
      'name': trimmedName,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
  }

  Future<String> findOrCreateCategoryId(String name) async {
    _tenant.assertWritable();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Category name is required.');

    final existing = await _tenant
        .scoped(_categories)
        .where('name', isEqualTo: trimmedName)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;

    final docRef = await _categories.add(_tenant.withTenant({
      'name': trimmedName,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
    return docRef.id;
  }

  Future<String> findOrCreateSupplierId(String name) async {
    _tenant.assertWritable();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Supplier name is required.');

    final existing = await _tenant
        .scoped(_firestore.collection(FirestoreCollections.suppliers))
        .where('name', isEqualTo: trimmedName)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;

    final docRef = await _firestore.collection(FirestoreCollections.suppliers).add(_tenant.withTenant({
      'name': trimmedName,
      'phone': '',
      'email': '',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
    return docRef.id;
  }

  Future<void> importMedicines(List<dynamic> rows) async {
    _tenant.assertWritable();
    if (rows.isEmpty) return;

    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        continue;
      }

      final sku = (row['sku'] as String? ?? '').trim();
      if (sku.isEmpty) continue;

      final existingSku = await _tenant.scoped(_medicines).where('sku', isEqualTo: sku).limit(1).get();
      if (existingSku.docs.isNotEmpty) {
        continue;
      }

      final categoryId = await findOrCreateCategoryId((row['category'] as String? ?? '').trim());
      final supplierId = await findOrCreateSupplierId((row['supplier_name'] as String? ?? '').trim());

      final medicineRef = await _medicines.add(_tenant.withTenant({
        'name': (row['medicine_name'] as String? ?? '').trim(),
        'sku': sku,
        'categoryId': categoryId,
        'unit': (row['unit'] as String? ?? 'unit').trim().isEmpty ? 'unit' : (row['unit'] as String? ?? 'unit').trim(),
        'purchasePriceMinor': int.tryParse((row['buying_price_minor'] as String? ?? '0').trim()) ?? 0,
        'sellingPriceMinor': int.tryParse((row['selling_price_minor'] as String? ?? '0').trim()) ?? 0,
        'quantityOnHand': int.tryParse((row['quantity_on_hand'] as String? ?? '0').trim()) ?? 0,
        'reorderLevel': int.tryParse((row['reorder_level'] as String? ?? '0').trim()) ?? 0,
        'requiresPrescription': false,
        'isActive': true,
        'supplierId': supplierId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }));

      final expiryDateText = (row['expiry_date'] as String? ?? '').trim();
      final batchNumber = (row['batch_number'] as String? ?? '').trim();
      if (expiryDateText.isNotEmpty && batchNumber.isNotEmpty) {
        await _batches.add(_tenant.withTenant({
          'medicineId': medicineRef.id,
          'batchNumber': batchNumber,
          'expiryDate': Timestamp.fromDate(DateTime.parse(expiryDateText)),
          'quantityOnHand': int.tryParse((row['quantity_on_hand'] as String? ?? '0').trim()) ?? 0,
          'unitCostMinor': int.tryParse((row['buying_price_minor'] as String? ?? '0').trim()) ?? 0,
          'supplierId': supplierId,
          'purchaseId': null,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }
    }
  }

  Future<void> createMedicine({
    required String name,
    required String sku,
    required String categoryId,
    required String unit,
    required int purchasePriceMinor,
    required int sellingPriceMinor,
    required int reorderLevel,
    required bool requiresPrescription,
  }) async {
    _tenant.assertWritable();
    if (name.trim().isEmpty || sku.trim().isEmpty || categoryId.trim().isEmpty) {
      throw ArgumentError('Name, SKU, and category are required.');
    }
    if (purchasePriceMinor < 0 || sellingPriceMinor < 0 || reorderLevel < 0) {
      throw ArgumentError('Prices and reorder level cannot be negative.');
    }
    await _medicines.add(_tenant.withTenant({
      'name': name.trim(),
      'sku': sku.trim().toUpperCase(),
      'categoryId': categoryId.trim(),
      'unit': unit.trim().isEmpty ? 'unit' : unit.trim(),
      'purchasePriceMinor': purchasePriceMinor,
      'sellingPriceMinor': sellingPriceMinor,
      'quantityOnHand': 0,
      'reorderLevel': reorderLevel,
      'requiresPrescription': requiresPrescription,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
  }

  Future<void> createBatch({
    required String medicineId,
    required String batchNumber,
    required DateTime expiryDate,
    required int quantity,
    required int unitCostMinor,
    String? supplierId,
    String? purchaseId,
  }) async {
    _tenant.assertWritable();
    if (batchNumber.trim().isEmpty || quantity <= 0 || unitCostMinor < 0) {
      throw ArgumentError('Batch number, positive quantity, and valid cost are required.');
    }
    await _batches.add(_tenant.withTenant({
      'medicineId': medicineId,
      'batchNumber': batchNumber.trim(),
      'expiryDate': Timestamp.fromDate(expiryDate),
      'quantityOnHand': quantity,
      'unitCostMinor': unitCostMinor,
      'supplierId': supplierId,
      'purchaseId': purchaseId,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
  }

  Future<void> archiveMedicine(String medicineId) {
    _tenant.assertWritable();
    return _medicines.doc(medicineId).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class CategoryOption {
  const CategoryOption({required this.id, required this.name});

  final String id;
  final String name;
}
