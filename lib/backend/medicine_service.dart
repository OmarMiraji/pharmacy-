import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'firestore_collections.dart';
import 'models.dart';
import 'offline_sync_service.dart';
import 'expiry_priority.dart';
import 'expiry_stock.dart';
import 'medicine_match.dart';
import 'stock_ledger.dart';
import 'selling_units.dart';
import 'tenant_context.dart';

class MedicineImportReport {
  const MedicineImportReport({
    required this.imported,
    required this.skippedExisting,
    required this.failed,
    this.errors = const [],
  });

  final int imported;
  final int skippedExisting;
  final int failed;
  final List<String> errors;

  int get total => imported + skippedExisting + failed;
}

class MedicineService {
  MedicineService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String? _sharedShop;
  static List<Medicine>? _lastMedicines;
  static List<MedicineBatch>? _lastBatches;
  static List<CategoryOption>? _lastCategories;
  static StreamController<List<Medicine>>? _medicineEvents;
  static StreamController<List<MedicineBatch>>? _batchEvents;
  static StreamController<List<CategoryOption>>? _categoryEvents;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _medicineSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _categorySub;
  static VoidCallback? _offlineListener;

  CollectionReference<Map<String, dynamic>> get _medicines =>
      _firestore.collection(FirestoreCollections.medicines);

  CollectionReference<Map<String, dynamic>> get _categories =>
      _firestore.collection(FirestoreCollections.categories);

  CollectionReference<Map<String, dynamic>> get _batches =>
      _firestore.collection(FirestoreCollections.medicineBatches);

  TenantContext get _tenant => TenantContext.instance;

  static void dropSharedListeners() {
    _medicineSub?.cancel();
    _batchSub?.cancel();
    _categorySub?.cancel();
    _medicineSub = null;
    _batchSub = null;
    _categorySub = null;
    if (_offlineListener != null) {
      OfflineSyncService.instance.removeListener(_offlineListener!);
      _offlineListener = null;
    }
    _medicineEvents?.close();
    _batchEvents?.close();
    _categoryEvents?.close();
    _medicineEvents = null;
    _batchEvents = null;
    _categoryEvents = null;
    _lastMedicines = null;
    _lastBatches = null;
    _lastCategories = null;
    _sharedShop = null;
  }

  void _ensureSharedShop() {
    final shop = _tenant.pharmacyId ?? '';
    if (_sharedShop == shop && _medicineEvents != null) return;
    dropSharedListeners();
    _sharedShop = shop;
    _medicineEvents = StreamController<List<Medicine>>.broadcast();
    _batchEvents = StreamController<List<MedicineBatch>>.broadcast();
    _categoryEvents = StreamController<List<CategoryOption>>.broadcast();

    void emitMedicines() {
      final latest = _lastMedicines;
      if (latest == null) return;
      _medicineEvents?.add(OfflineSyncService.instance.applyLocalStock(latest));
    }

    _medicineSub = _tenant
        .scoped(_medicines)
        .where('isActive', isEqualTo: true)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (!snapshot.metadata.isFromCache) OfflineSyncService.instance.noteConnected();
      final latest = snapshot.docs.map(Medicine.fromFirestore).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _lastMedicines = latest;
      emitMedicines();
    }, onError: (Object error, StackTrace stack) {
      if (OfflineSyncService.isNetworkError(error)) {
        OfflineSyncService.instance.noteDisconnected();
        emitMedicines();
        return;
      }
      _medicineEvents?.addError(error, stack);
    });

    _offlineListener = emitMedicines;
    OfflineSyncService.instance.addListener(_offlineListener!);

    _batchSub = _tenant.scoped(_batches).snapshots(includeMetadataChanges: true).listen((snapshot) {
      if (!snapshot.metadata.isFromCache) OfflineSyncService.instance.noteConnected();
      final batches = snapshot.docs.map(MedicineBatch.fromFirestore).toList()
        ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      _lastBatches = batches;
      _batchEvents?.add(batches);
    }, onError: (Object error, StackTrace stack) {
      if (OfflineSyncService.isNetworkError(error) && _lastBatches != null) {
        OfflineSyncService.instance.noteDisconnected();
        _batchEvents?.add(_lastBatches!);
        return;
      }
      _batchEvents?.addError(error, stack);
    });

    _categorySub = _tenant
        .scoped(_categories)
        .where('isActive', isEqualTo: true)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (!snapshot.metadata.isFromCache) OfflineSyncService.instance.noteConnected();
      final categories = snapshot.docs
          .map((doc) => CategoryOption(id: doc.id, name: doc.data()['name'] as String? ?? ''))
          .where((category) => category.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _lastCategories = categories;
      _categoryEvents?.add(categories);
    }, onError: (Object error, StackTrace stack) {
      if (OfflineSyncService.isNetworkError(error) && _lastCategories != null) {
        OfflineSyncService.instance.noteDisconnected();
        _categoryEvents?.add(_lastCategories!);
        return;
      }
      _categoryEvents?.addError(error, stack);
    });
  }

  Stream<List<T>> _replay<T>(List<T>? last, StreamController<List<T>>? events) {
    final source = events;
    if (source == null) {
      return last == null ? const Stream.empty() : Stream<List<T>>.value(last);
    }
    if (last == null) return source.stream;
    return Stream<List<T>>.multi((listener) {
      listener.add(last);
      final sub = source.stream.listen(listener.add, onError: listener.addError, onDone: listener.close);
      listener.onCancel = sub.cancel;
    });
  }

  Stream<List<Medicine>> watchMedicines() {
    _ensureSharedShop();
    final cached = _lastMedicines == null ? null : OfflineSyncService.instance.applyLocalStock(_lastMedicines!);
    return _replay(cached, _medicineEvents);
  }

  Stream<List<CategoryOption>> watchCategories() {
    _ensureSharedShop();
    return _replay(_lastCategories, _categoryEvents);
  }

  Stream<List<MedicineBatch>> watchBatches(String medicineId) {
    return watchAllBatches().map((batches) => batches.where((batch) => batch.medicineId == medicineId).toList());
  }

  Stream<List<MedicineBatch>> watchAllBatches() {
    _ensureSharedShop();
    return _replay(_lastBatches, _batchEvents);
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

  Future<void> updateCategory({required String categoryId, required String name}) async {
    _tenant.assertWritable();
    final trimmedName = name.trim();
    if (categoryId.trim().isEmpty || trimmedName.isEmpty) {
      throw ArgumentError('Category name is required.');
    }
    await _categories.doc(categoryId.trim()).update({
      'name': trimmedName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCategory(String categoryId) async {
    _tenant.assertWritable();
    final id = categoryId.trim();
    if (id.isEmpty) throw ArgumentError('Category is required.');
    final used = await _tenant
        .scoped(_medicines)
        .where('categoryId', isEqualTo: id)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (used.docs.isNotEmpty) {
      throw StateError('This category still has medicines. Move those products first, then delete it.');
    }
    await _categories.doc(id).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Future<MedicineImportReport> importMedicines(
    List<dynamic> rows, {
    void Function(int done, int total)? onProgress,
  }) async {
    _tenant.assertWritable();
    if (rows.isEmpty) {
      return const MedicineImportReport(imported: 0, skippedExisting: 0, failed: 0);
    }

    var imported = 0;
    var skippedExisting = 0;
    var failed = 0;
    final errors = <String>[];
    final total = rows.length;
    final existingSkuSnap = await _tenant.scoped(_medicines).get();
    final existingSkus = {
      for (final doc in existingSkuSnap.docs)
        ((doc.data()['sku'] as String?) ?? '').trim().toUpperCase(),
    }..removeWhere((sku) => sku.isEmpty);
    final categoryIds = <String, String>{};

    for (var i = 0; i < rows.length; i++) {
      onProgress?.call(i, total);
      final row = rows[i];
      if (row is! Map<String, dynamic>) {
        failed++;
        continue;
      }

      try {
        final sku = (row['sku'] as String? ?? '').trim().toUpperCase();
        if (sku.isEmpty) {
          failed++;
          errors.add('Row ${i + 1}: missing SKU');
          continue;
        }

        if (existingSkus.contains(sku)) {
          skippedExisting++;
          continue;
        }

        final categoryName = (row['category'] as String? ?? '').trim();
        if (categoryName.isEmpty) {
          failed++;
          errors.add('$sku: missing category');
          continue;
        }

        final categoryId = categoryIds[categoryName.toLowerCase()] ?? await findOrCreateCategoryId(categoryName);
        categoryIds[categoryName.toLowerCase()] = categoryId;
        final packSize = int.tryParse('${row['pack_size'] ?? '1'}'.trim()) ?? 1;
        final openingQty = int.tryParse('${row['opening_quantity'] ?? row['quantity_on_hand'] ?? '0'}'.trim()) ?? 0;
        final unitCost = int.tryParse('${row['buying_price'] ?? row['buying_price_minor'] ?? '0'}'.trim()) ?? 0;
        final selling = int.tryParse('${row['selling_price'] ?? row['selling_price_minor'] ?? '0'}'.trim()) ?? 0;
        final expiryDateText = '${row['expiry_date'] ?? ''}'.trim();
        final expiry = ExpiryPriority.parse(expiryDateText);
        final rx = '${row['requires_prescription'] ?? ''}'.trim().toLowerCase();
        await createMedicine(
          name: (row['medicine_name'] as String? ?? '').trim(),
          sku: sku,
          categoryId: categoryId,
          unit: BaseUnits.normalize('${row['unit'] ?? 'Tablet'}'),
          purchasePriceMinor: unitCost,
          sellingPriceMinor: selling,
          reorderLevel: int.tryParse('${row['reorder_level'] ?? '0'}'.trim()) ?? 0,
          requiresPrescription: rx == '1' || rx == 'yes' || rx == 'true',
          packSize: packSize < 1 ? 1 : packSize,
          stripSize: int.tryParse('${row['strip_size'] ?? '0'}'.trim()) ?? 0,
          boxSize: int.tryParse('${row['box_size'] ?? '0'}'.trim()) ?? 0,
          minSaleQty: int.tryParse('${row['min_sale_qty'] ?? '0'}'.trim()) ?? 0,
          allowLooseSale: BaseUnits.sellsByPiece('${row['unit'] ?? 'Tablet'}'),
          allowHalfBlister: () {
            final half = '${row['allow_half_blister'] ?? ''}'.trim().toLowerCase();
            return half == '1' || half == 'yes' || half == 'true';
          }(),
          expiryDate: expiry,
          openingQuantity: openingQty,
          openingAsTablets: () {
            final stockAs = '${row['stock_as'] ?? ''}'.trim().toLowerCase();
            final packed = stockAs == 'packs' || stockAs == 'pack' || stockAs == 'blisters' || stockAs == 'blister' || stockAs == 'blista';
            return BaseUnits.sellsByPiece('${row['unit'] ?? 'Tablet'}') && !packed;
          }(),
          batchNumber: '${row['batch_number'] ?? ''}',
          createdBy: 'import',
        );
        imported++;
        existingSkus.add(sku);
      } catch (error) {
        failed++;
        errors.add('Row ${i + 1}: $error');
      }
    }

    onProgress?.call(total, total);
    return MedicineImportReport(
      imported: imported,
      skippedExisting: skippedExisting,
      failed: failed,
      errors: errors.take(8).toList(),
    );
  }

  Future<int> writeOffExpiredLine({required ExpiredStockLine line, required String createdBy}) async {
    _tenant.assertWritable();
    if (line.quantity <= 0) return 0;
    if (!ExpiryPriority.isExpired(line.expiry)) {
      throw StateError('Only expired stock can be removed from this list.');
    }

    final medicineRef = _medicines.doc(line.medicineId);
    final batchRef = line.batchId == null || line.batchId!.isEmpty ? null : _batches.doc(line.batchId);
    final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();

    return _firestore.runTransaction((transaction) async {
      final medicineSnapshot = await transaction.get(medicineRef);
      if (!medicineSnapshot.exists) throw StateError('The medicine was not found.');
      DocumentSnapshot<Map<String, dynamic>>? batchSnapshot;
      if (batchRef != null) {
        batchSnapshot = await transaction.get(batchRef);
      }
      var take = line.quantity;
      if (batchSnapshot != null && batchSnapshot.exists) {
        final batchQty = (batchSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (batchQty > 0 && batchQty < take) take = batchQty;
      }
      final currentStock = (medicineSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
      if (take > currentStock) take = currentStock;
      if (take <= 0) return 0;
      final now = FieldValue.serverTimestamp();
      transaction.update(medicineRef, {
        'quantityOnHand': currentStock - take,
        'updatedAt': now,
      });
      if (batchRef != null && batchSnapshot != null && batchSnapshot.exists) {
        final batchQty = (batchSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        final left = batchQty - take;
        transaction.update(batchRef, {
          'quantityOnHand': left < 0 ? 0 : left,
          'isActive': false,
          'writtenOffReason': 'expiry',
          'writtenOffAt': now,
          'updatedAt': now,
        });
      }
      transaction.set(
        movementRef,
        StockLedger.movement(
          medicineId: line.medicineId,
          medicineName: medicineSnapshot.data()?['name'] as String?,
          type: 'expiry',
          quantityChange: -take,
          createdBy: createdBy,
          batchId: line.batchId,
          batchNumber: line.batchNumber,
          createdAt: now,
        ),
      );
      return take;
    });
  }

  Future<int> writeOffExpiredLines({required List<ExpiredStockLine> lines, required String createdBy}) async {
    _tenant.assertWritable();
    var total = 0;
    const chunkSize = 40;
    for (var offset = 0; offset < lines.length; offset += chunkSize) {
      final chunk = lines.sublist(offset, math.min(offset + chunkSize, lines.length));
      total += await _writeOffExpiredChunk(chunk, createdBy);
    }
    return total;
  }

  Future<int> _writeOffExpiredChunk(List<ExpiredStockLine> lines, String createdBy) async {
    if (lines.isEmpty) return 0;
    return _firestore.runTransaction((transaction) async {
      final medicineRefs = <String, DocumentReference<Map<String, dynamic>>>{
        for (final line in lines) line.medicineId: _medicines.doc(line.medicineId),
      };
      final batchRefs = <String, DocumentReference<Map<String, dynamic>>>{
        for (final line in lines)
          if (line.batchId != null && line.batchId!.isNotEmpty) line.batchId!: _batches.doc(line.batchId),
      };
      final medicineSnaps = await Future.wait(medicineRefs.values.map(transaction.get));
      final batchSnaps = await Future.wait(batchRefs.values.map(transaction.get));
      final medicines = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      var i = 0;
      for (final id in medicineRefs.keys) {
        medicines[id] = medicineSnaps[i++];
      }
      final batches = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      i = 0;
      for (final id in batchRefs.keys) {
        batches[id] = batchSnaps[i++];
      }

      var takenTotal = 0;
      final now = FieldValue.serverTimestamp();
      final stockLeft = <String, int>{
        for (final entry in medicines.entries)
          if (entry.value.exists) entry.key: (entry.value.data()?['quantityOnHand'] as num?)?.toInt() ?? 0,
      };
      final medicineDelta = <String, int>{};
      for (final line in lines) {
        if (line.quantity <= 0 || !ExpiryPriority.isExpired(line.expiry)) continue;
        final medicineSnapshot = medicines[line.medicineId];
        if (medicineSnapshot == null || !medicineSnapshot.exists) continue;
        var take = line.quantity;
        final batchId = line.batchId;
        if (batchId != null && batchId.isNotEmpty) {
          final batchSnapshot = batches[batchId];
          if (batchSnapshot != null && batchSnapshot.exists) {
            final batchQty = (batchSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
            if (batchQty > 0 && batchQty < take) take = batchQty;
          }
        }
        final currentStock = stockLeft[line.medicineId] ?? 0;
        if (take > currentStock) take = currentStock;
        if (take <= 0) continue;
        stockLeft[line.medicineId] = currentStock - take;
        medicineDelta[line.medicineId] = (medicineDelta[line.medicineId] ?? 0) + take;
        takenTotal += take;
        if (batchId != null && batchId.isNotEmpty) {
          final batchSnapshot = batches[batchId];
          final batchRef = batchRefs[batchId];
          if (batchSnapshot != null && batchSnapshot.exists && batchRef != null) {
            final batchQty = (batchSnapshot.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
            final left = batchQty - take;
            transaction.update(batchRef, {
              'quantityOnHand': left < 0 ? 0 : left,
              'isActive': false,
              'writtenOffReason': 'expiry',
              'writtenOffAt': now,
              'updatedAt': now,
            });
          }
        }
        transaction.set(
          _firestore.collection(FirestoreCollections.stockMovements).doc(),
          StockLedger.movement(
            medicineId: line.medicineId,
            medicineName: medicineSnapshot.data()?['name'] as String?,
            type: 'expiry',
            quantityChange: -take,
            createdBy: createdBy,
            batchId: line.batchId,
            batchNumber: line.batchNumber,
            createdAt: now,
          ),
        );
      }
      for (final entry in medicineDelta.entries) {
        final original = (medicines[entry.key]?.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
        transaction.update(medicineRefs[entry.key]!, {
          'quantityOnHand': original - entry.value,
          'updatedAt': now,
        });
      }
      return takenTotal;
    });
  }

  Future<String> createMedicine({
    required String name,
    required String sku,
    required String categoryId,
    required String unit,
    required int purchasePriceMinor,
    required int sellingPriceMinor,
    required int reorderLevel,
    required bool requiresPrescription,
    int packSize = 1,
    int stripSize = 0,
    int boxSize = 0,
    int minSaleQty = 0,
    bool allowLooseSale = false,
    bool allowHalfBlister = false,
    DateTime? expiryDate,
    int openingQuantity = 0,
    bool openingAsTablets = true,
    String? batchNumber,
    required String createdBy,
  }) async {
    _tenant.assertWritable();
    final existing = await findExistingByName(name);
    if (existing != null) return existing.id;
    if (name.trim().isEmpty || sku.trim().isEmpty || categoryId.trim().isEmpty) {
      throw ArgumentError('Name, SKU, and category are required.');
    }
    if (purchasePriceMinor < 0 || sellingPriceMinor < 0 || reorderLevel < 0) {
      throw ArgumentError('Prices and reorder level cannot be negative.');
    }
    if (openingQuantity < 0) {
      throw ArgumentError('Opening quantity cannot be negative.');
    }
    if (openingQuantity > 0 && expiryDate == null) {
      throw ArgumentError('Expiry date is required when adding opening stock.');
    }
    final ref = _medicines.doc();
    final size = packSize < 1 ? 1 : packSize;
    final loose = BaseUnits.sellsByPiece(unit) || allowLooseSale;
    final piece = BaseUnits.sellsByPiece(unit);
    final blisterStock = piece && stripSize > 1 && size <= 1 && !openingAsTablets;
    final packStock = piece && size > 1 && !openingAsTablets;
    final stockQty = blisterStock
        ? openingQuantity * stripSize
        : packStock
            ? openingQuantity * size
            : openingQuantity;
    if (openingQuantity > 0 && expiryDate != null) {
      final code = (batchNumber ?? '').trim();
      final batchRef = _batches.doc();
      final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();
      await _firestore.runTransaction((transaction) async {
        final now = FieldValue.serverTimestamp();
        transaction.set(ref, _tenant.withTenant({
          'name': name.trim(),
          'sku': sku.trim().toUpperCase(),
          'categoryId': categoryId.trim(),
          'unit': unit.trim().isEmpty ? 'unit' : unit.trim(),
          'purchasePriceMinor': purchasePriceMinor,
          'sellingPriceMinor': sellingPriceMinor,
          'quantityOnHand': stockQty,
          'reorderLevel': reorderLevel,
          'requiresPrescription': requiresPrescription,
          'isActive': true,
          'packSize': packSize < 1 ? 1 : packSize,
          'stripSize': stripSize < 0 ? 0 : stripSize,
          'boxSize': boxSize < 0 ? 0 : boxSize,
          'minSaleQty': minSaleQty < 0 ? 0 : minSaleQty,
          'allowLooseSale': loose,
          'allowHalfBlister': allowHalfBlister && stripSize > 1,
          'expiryDate': Timestamp.fromDate(expiryDate),
          'createdAt': now,
          'updatedAt': now,
        }));
        transaction.set(batchRef, _tenant.withTenant({
          'medicineId': ref.id,
          'batchNumber': code.isEmpty ? 'OPEN-${sku.trim().toUpperCase()}' : code,
          'expiryDate': Timestamp.fromDate(expiryDate),
          'quantityOnHand': stockQty,
          'unitCostMinor': BaseUnits.costPerStockUnit(
            unit: unit,
            purchasePriceMinor: purchasePriceMinor,
            packSize: size,
            stripSize: stripSize,
            minSaleQty: minSaleQty,
          ),
          'isActive': true,
          'createdAt': now,
          'updatedAt': now,
        }));
        transaction.set(
          movementRef,
          StockLedger.movement(
            medicineId: ref.id,
            medicineName: name.trim(),
            type: 'purchase',
            quantityChange: stockQty,
            createdBy: createdBy,
            batchId: batchRef.id,
            batchNumber: code.isEmpty ? 'OPEN-${sku.trim().toUpperCase()}' : code,
            createdAt: now,
          ),
        );
      });
      return ref.id;
    }
    await ref.set(_tenant.withTenant({
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
      'packSize': packSize < 1 ? 1 : packSize,
      'stripSize': stripSize < 0 ? 0 : stripSize,
      'boxSize': boxSize < 0 ? 0 : boxSize,
      'minSaleQty': minSaleQty < 0 ? 0 : minSaleQty,
      'allowLooseSale': BaseUnits.sellsByPiece(unit) || allowLooseSale,
      'allowHalfBlister': allowHalfBlister && stripSize > 1,
      if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
    return ref.id;
  }

  Future<Medicine?> findExistingByName(String name) async {
    final cached = _lastMedicines;
    final local = MedicineMatch.findIn(cached ?? const [], name);
    if (local != null) return local;
    try {
      final snapshot = await _tenant.scoped(_medicines).where('isActive', isEqualTo: true).get();
      return MedicineMatch.findIn(snapshot.docs.map(Medicine.fromFirestore), name);
    } catch (_) {
      return null;
    }
  }

  static var _didConsolidate = false;

  Future<void> consolidateDuplicateMedicinesOnce() async {
    if (_didConsolidate) return;
    _didConsolidate = true;
    try {
      await _consolidateDuplicateMedicines();
    } catch (_) {
      _didConsolidate = false;
    }
  }

  Future<void> _consolidateDuplicateMedicines() async {
    _tenant.assertWritable();
    final snapshot = await _tenant.scoped(_medicines).where('isActive', isEqualTo: true).get();
    final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in snapshot.docs) {
      final name = doc.data()['name'] as String? ?? '';
      final id = MedicineMatch.key(name);
      if (id.isEmpty) continue;
      groups.putIfAbsent(id, () => []).add(doc);
    }
    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) {
        final qtyA = (a.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
        final qtyB = (b.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (qtyA != qtyB) return qtyB.compareTo(qtyA);
        return a.id.compareTo(b.id);
      });
      final primary = group.first;
      var extraQty = 0;
      for (final extra in group.skip(1)) {
        extraQty += (extra.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
        final batches = await _tenant.scoped(_batches).where('medicineId', isEqualTo: extra.id).get();
        for (final batch in batches.docs) {
          await batch.reference.update({
            'medicineId': primary.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await extra.reference.update({
          'isActive': false,
          'quantityOnHand': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (extraQty > 0) {
        final current = (primary.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
        await primary.reference.update({
          'quantityOnHand': current + extraQty,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<String> createQuickMedicine({
    required String name,
    required int sellingPriceMinor,
    required String createdBy,
  }) async {
    final existing = await findExistingByName(name);
    if (existing != null) return existing.id;
    List<CategoryOption> categories = _lastCategories ?? const [];
    if (categories.isEmpty) {
      try {
        categories = await watchCategories().first.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (categories.isEmpty) {
      await createCategory('General');
      try {
        categories = await watchCategories().first.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (categories.isEmpty) {
      throw StateError('Could not create a medicine category.');
    }
    final sku = 'MED-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    return createMedicine(
      name: name,
      sku: sku,
      categoryId: categories.first.id,
      unit: 'unit',
      purchasePriceMinor: 0,
      sellingPriceMinor: sellingPriceMinor,
      reorderLevel: 0,
      requiresPrescription: false,
      createdBy: createdBy,
    );
  }

  Future<void> updateMedicine({
    required String medicineId,
    required String name,
    required String sku,
    required String categoryId,
    required String unit,
    required int purchasePriceMinor,
    required int sellingPriceMinor,
    required int reorderLevel,
    required bool requiresPrescription,
    int packSize = 1,
    int stripSize = 0,
    int boxSize = 0,
    int minSaleQty = 0,
    bool allowLooseSale = false,
    bool allowHalfBlister = false,
    DateTime? expiryDate,
  }) async {
    _tenant.assertWritable();
    if (medicineId.trim().isEmpty || name.trim().isEmpty || sku.trim().isEmpty || categoryId.trim().isEmpty) {
      throw ArgumentError('Name, SKU, and category are required.');
    }
    if (purchasePriceMinor < 0 || sellingPriceMinor < 0 || reorderLevel < 0) {
      throw ArgumentError('Prices and reorder level cannot be negative.');
    }
    final size = packSize < 1 ? 1 : packSize;
    final loose = BaseUnits.sellsByPiece(unit) || allowLooseSale;
    final current = await _medicines.doc(medicineId).get();
    final previous = current.data() ?? const <String, dynamic>{};
    final oldPack = (previous['packSize'] as num?)?.toInt() ?? 1;
    await _medicines.doc(medicineId).update({
      'name': name.trim(),
      'sku': sku.trim().toUpperCase(),
      'categoryId': categoryId.trim(),
      'unit': unit.trim().isEmpty ? 'unit' : unit.trim(),
      'purchasePriceMinor': purchasePriceMinor,
      'sellingPriceMinor': sellingPriceMinor,
      'reorderLevel': reorderLevel,
      'requiresPrescription': requiresPrescription,
      'packSize': size,
      'stripSize': stripSize < 0 ? 0 : stripSize,
      'boxSize': boxSize < 0 ? 0 : boxSize,
      'minSaleQty': minSaleQty < 0 ? 0 : minSaleQty,
      'allowLooseSale': loose,
      'allowHalfBlister': allowHalfBlister && stripSize > 1,
      if (expiryDate != null) 'expiryDate': Timestamp.fromDate(expiryDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (oldPack <= 1 && size > 1) {
      try {
        await _convertPackStockToTablets(medicineId, size);
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
      }
    }
    if (expiryDate == null) return;
    try {
      final batches = await _tenant
          .scoped(_batches)
          .where('medicineId', isEqualTo: medicineId)
          .where('isActive', isEqualTo: true)
          .get();
      final live = batches.docs.where((doc) {
        final qty = (doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
        return qty > 0;
      }).toList();
      if (live.length == 1) {
        await live.first.reference.update({
          'expiryDate': Timestamp.fromDate(expiryDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
  }

  Future<void> setOnHandQuantity({
    required String medicineId,
    required int quantity,
    required String createdBy,
    DateTime? expiryDate,
    String? batchNumber,
  }) async {
    _tenant.assertWritable();
    if (medicineId.trim().isEmpty) throw ArgumentError('Medicine is required.');
    if (quantity < 0) throw ArgumentError('Stock cannot be negative.');

    final medicineRef = _medicines.doc(medicineId);
    final medicineSnap = await medicineRef.get();
    if (!medicineSnap.exists) throw StateError('The medicine was not found.');
    final medicineData = medicineSnap.data() ?? const <String, dynamic>{};
    final current = (medicineData['quantityOnHand'] as num?)?.toInt() ?? 0;
    if (current == quantity) return;

    final batches = await _tenant.scoped(_batches).where('medicineId', isEqualTo: medicineId).get();
    final live = batches.docs.where((doc) {
      final qty = (doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
      return doc.data()['isActive'] != false && qty > 0;
    }).toList()
      ..sort((a, b) {
        final left = ExpiryPriority.parseAny(a.data()['expiryDate']) ?? DateTime(9999);
        final right = ExpiryPriority.parseAny(b.data()['expiryDate']) ?? DateTime(9999);
        return left.compareTo(right);
      });

    final delta = quantity - current;
    final movementRef = _firestore.collection(FirestoreCollections.stockMovements).doc();
    final now = FieldValue.serverTimestamp();
    final sku = (medicineData['sku'] as String? ?? 'STOCK').trim().toUpperCase();
    final name = (medicineData['name'] as String? ?? '').trim();
    final expiry = expiryDate ?? ExpiryPriority.parseAny(medicineData['expiryDate']);

    await _firestore.runTransaction((transaction) async {
      transaction.update(medicineRef, {
        'quantityOnHand': quantity,
        if (expiry != null) 'expiryDate': Timestamp.fromDate(expiry),
        'updatedAt': now,
      });

      var leftover = delta;
      String? usedBatchId;
      String? usedBatchNumber;
      if (live.isEmpty && quantity > 0) {
        final batchRef = _batches.doc();
        final code = (batchNumber ?? '').trim();
        usedBatchId = batchRef.id;
        usedBatchNumber = code.isEmpty ? 'STOCK-$sku' : code;
        transaction.set(batchRef, _tenant.withTenant({
          'medicineId': medicineId,
          'batchNumber': usedBatchNumber,
          'expiryDate': Timestamp.fromDate(expiry ?? DateTime.now().add(const Duration(days: 365))),
          'quantityOnHand': quantity,
          'unitCostMinor': BaseUnits.costPerStockUnit(
            unit: medicineData['unit'] as String? ?? 'Tablet',
            purchasePriceMinor: (medicineData['purchasePriceMinor'] as num?)?.toInt() ?? 0,
            packSize: (medicineData['packSize'] as num?)?.toInt() ?? 1,
            stripSize: (medicineData['stripSize'] as num?)?.toInt() ?? 0,
            minSaleQty: (medicineData['minSaleQty'] as num?)?.toInt() ?? 0,
          ),
          'isActive': true,
          'createdAt': now,
          'updatedAt': now,
        }));
      } else if (live.length == 1) {
        final doc = live.first;
        usedBatchId = doc.id;
        usedBatchNumber = (doc.data()['batchNumber'] as String?) ?? '';
        transaction.update(doc.reference, {
          'quantityOnHand': quantity,
          if (expiry != null) 'expiryDate': Timestamp.fromDate(expiry),
          'isActive': quantity > 0,
          'updatedAt': now,
        });
        leftover = 0;
      } else {
        for (final doc in live) {
          if (leftover == 0) break;
          final qty = (doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
          usedBatchId ??= doc.id;
          usedBatchNumber ??= (doc.data()['batchNumber'] as String?) ?? '';
          if (leftover > 0) {
            transaction.update(doc.reference, {
              'quantityOnHand': qty + leftover,
              if (expiry != null) 'expiryDate': Timestamp.fromDate(expiry),
              'updatedAt': now,
            });
            leftover = 0;
          } else {
            final take = qty < -leftover ? qty : -leftover;
            transaction.update(doc.reference, {
              'quantityOnHand': qty - take,
              'isActive': qty - take > 0,
              'updatedAt': now,
            });
            leftover += take;
          }
        }
        if (leftover > 0) {
          final batchRef = _batches.doc();
          final code = (batchNumber ?? '').trim();
          usedBatchId = batchRef.id;
          usedBatchNumber = code.isEmpty ? 'STOCK-$sku' : code;
          transaction.set(batchRef, _tenant.withTenant({
            'medicineId': medicineId,
            'batchNumber': usedBatchNumber,
            'expiryDate': Timestamp.fromDate(expiry ?? DateTime.now().add(const Duration(days: 365))),
            'quantityOnHand': leftover,
            'unitCostMinor': BaseUnits.costPerStockUnit(
            unit: medicineData['unit'] as String? ?? 'Tablet',
            purchasePriceMinor: (medicineData['purchasePriceMinor'] as num?)?.toInt() ?? 0,
            packSize: (medicineData['packSize'] as num?)?.toInt() ?? 1,
            stripSize: (medicineData['stripSize'] as num?)?.toInt() ?? 0,
            minSaleQty: (medicineData['minSaleQty'] as num?)?.toInt() ?? 0,
          ),
            'isActive': true,
            'createdAt': now,
            'updatedAt': now,
          }));
        }
      }

      transaction.set(
        movementRef,
        StockLedger.movement(
          medicineId: medicineId,
          medicineName: name,
          type: 'adjustment',
          quantityChange: delta,
          createdBy: createdBy,
          batchId: usedBatchId,
          batchNumber: usedBatchNumber,
          createdAt: now,
        ),
      );
    });
  }

  Future<void> _convertPackStockToTablets(String medicineId, int packSize) async {
    if (packSize <= 1) return;
    final medicineRef = _medicines.doc(medicineId);
    final results = await Future.wait([
      medicineRef.get(),
      _tenant.scoped(_batches).where('medicineId', isEqualTo: medicineId).get(),
    ]);
    final medicineSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final batches = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final current = (medicineSnap.data()?['quantityOnHand'] as num?)?.toInt() ?? 0;
    final batch = _firestore.batch();
    batch.update(medicineRef, {
      'quantityOnHand': current * packSize,
      'reorderLevel': ((medicineSnap.data()?['reorderLevel'] as num?)?.toInt() ?? 0) * packSize,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final doc in batches.docs) {
      final qty = (doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0;
      batch.update(doc.reference, {
        'quantityOnHand': qty * packSize,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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
