import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import '../platform/file_saver.dart';
import 'activity_log_service.dart';
import 'firestore_collections.dart';
import 'tenant_context.dart';

class PharmacyDataService {
  PharmacyDataService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const backupVersion = 1;

  static const _dataCollections = [
    FirestoreCollections.medicines,
    FirestoreCollections.medicineBatches,
    FirestoreCollections.categories,
    FirestoreCollections.suppliers,
    FirestoreCollections.purchases,
    FirestoreCollections.sales,
    FirestoreCollections.stockMovements,
    FirestoreCollections.customers,
    FirestoreCollections.expenses,
    FirestoreCollections.settings,
  ];

  static const _nestedItemParents = {
    FirestoreCollections.purchases: FirestoreCollections.purchaseItems,
    FirestoreCollections.sales: FirestoreCollections.saleItems,
  };

  /// Returns where the backup was saved (a path, or a file name in the browser's downloads).
  Future<String> backupToFile() async {
    TenantContext.instance.assertWritable();
    final pharmacyId = TenantContext.instance.requirePharmacyId();
    final payload = <String, dynamic>{
      'version': backupVersion,
      'pharmacyId': pharmacyId,
      'pharmacyName': TenantContext.instance.pharmacyName,
      'exportedAt': DateTime.now().toIso8601String(),
      'collections': <String, dynamic>{},
    };

    final collections = payload['collections'] as Map<String, dynamic>;
    for (final name in _dataCollections) {
      final snapshot = await TenantContext.instance.scoped(_firestore.collection(name)).get();
      final docs = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final record = <String, dynamic>{
          'id': doc.id,
          'data': _encodeData(doc.data()),
        };
        final nested = _nestedItemParents[name];
        if (nested != null) {
          final items = await doc.reference.collection(nested).get();
          record['items'] = [
            for (final item in items.docs) {'id': item.id, 'data': _encodeData(item.data())},
          ];
        }
        docs.add(record);
      }
      collections[name] = docs;
    }

    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final suggested = 'phyimacy-backup-$pharmacyId.json';
    final savedPath = await FileSaver.saveAs(
      dialogTitle: 'Save pharmacy backup',
      fileName: suggested,
      extension: 'json',
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    );
    if (savedPath == null) {
      throw StateError('Backup cancelled.');
    }
    return savedPath;
  }

  Future<int> restoreFromPickedFile() async {
    TenantContext.instance.assertWritable();
    final pharmacyId = TenantContext.instance.requirePharmacyId();
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Restore pharmacy backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) throw StateError('Restore cancelled.');
    final bytes = await FileSaver.readPicked(file);
    if (bytes == null) throw StateError('Restore cancelled.');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid backup file.');
    }
    if (decoded['version'] != backupVersion) {
      throw StateError('Unsupported backup version.');
    }
    final backupPharmacyId = (decoded['pharmacyId'] as String? ?? '').trim();
    if (backupPharmacyId.isNotEmpty && backupPharmacyId != pharmacyId) {
      throw StateError('This backup belongs to another pharmacy.');
    }
    final collections = decoded['collections'];
    if (collections is! Map<String, dynamic>) {
      throw StateError('Backup file is missing collections.');
    }

    var restored = 0;
    for (final name in _dataCollections) {
      final records = collections[name];
      if (records is! List) continue;
      for (final record in records) {
        if (record is! Map) continue;
        final id = (record['id'] as String? ?? '').trim();
        final data = record['data'];
        if (id.isEmpty || data is! Map) continue;
        final payload = _decodeData(Map<String, dynamic>.from(data));
        payload['pharmacyId'] = pharmacyId;
        await _firestore.collection(name).doc(id).set(payload);
        restored++;
        final nested = _nestedItemParents[name];
        final items = record['items'];
        if (nested != null && items is List) {
          for (final item in items) {
            if (item is! Map) continue;
            final itemId = (item['id'] as String? ?? '').trim();
            final itemData = item['data'];
            if (itemId.isEmpty || itemData is! Map) continue;
            await _firestore.collection(name).doc(id).collection(nested).doc(itemId).set(
                  _decodeData(Map<String, dynamic>.from(itemData)),
                );
            restored++;
          }
        }
      }
    }
    ActivityLogService.record(ActivityAction.dataRestored,
        level: ActivityLevel.security, target: file.name, detail: '$restored records', pharmacyId: pharmacyId);
    return restored;
  }

  static const collectionLabels = <String, String>{
    FirestoreCollections.medicines: 'Medicines',
    FirestoreCollections.medicineBatches: 'Stock batches',
    FirestoreCollections.categories: 'Categories',
    FirestoreCollections.suppliers: 'Suppliers',
    FirestoreCollections.purchases: 'Purchases',
    FirestoreCollections.sales: 'Sales',
    FirestoreCollections.stockMovements: 'Stock movements',
    FirestoreCollections.customers: 'Customers',
    FirestoreCollections.expenses: 'Expenses',
    FirestoreCollections.settings: 'Shop settings',
  };

  String _requirePharmacyId(String? pharmacyId) {
    if (TenantContext.instance.isSuperAdmin && (pharmacyId ?? '').trim().isNotEmpty) {
      return pharmacyId!.trim();
    }
    if (!TenantContext.instance.isSuperAdmin) {
      TenantContext.instance.assertWritable();
    }
    return TenantContext.instance.requirePharmacyId();
  }

  Future<int> clearOperationalData({String? pharmacyId}) async {
    var deleted = 0;
    for (final name in _dataCollections) {
      deleted += await clearCollection(name, pharmacyId: pharmacyId, log: false);
    }
    ActivityLogService.record(ActivityAction.dataCleared,
        level: ActivityLevel.security, target: 'All shop data', detail: '$deleted records', pharmacyId: _requirePharmacyId(pharmacyId));
    return deleted;
  }

  Future<int> clearCollection(String collectionName, {String? pharmacyId, bool log = true}) async {
    if (!_dataCollections.contains(collectionName)) {
      throw ArgumentError('Unknown data group: $collectionName');
    }
    final id = _requirePharmacyId(pharmacyId);
    var deleted = 0;
    final snapshot = await _firestore.collection(collectionName).where('pharmacyId', isEqualTo: id).get();
    for (final doc in snapshot.docs) {
      final nested = _nestedItemParents[collectionName];
      if (nested != null) {
        final items = await doc.reference.collection(nested).get();
        for (final item in items.docs) {
          await item.reference.delete();
          deleted++;
        }
      }
      await doc.reference.delete();
      deleted++;
    }
    if (log) {
      ActivityLogService.record(ActivityAction.dataCleared,
          level: ActivityLevel.security, target: collectionLabels[collectionName] ?? collectionName, detail: '$deleted records', pharmacyId: id);
    }
    return deleted;
  }

  Map<String, dynamic> _encodeData(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _encodeValue(value)));
  }

  Map<String, dynamic> _decodeData(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _decodeValue(value)));
  }

  dynamic _encodeValue(dynamic value) {
    if (value is Timestamp) {
      return {'__ts': value.millisecondsSinceEpoch};
    }
    if (value is DateTime) {
      return {'__ts': value.millisecondsSinceEpoch};
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _encodeValue(item)));
    }
    if (value is List) {
      return value.map(_encodeValue).toList();
    }
    return value;
  }

  dynamic _decodeValue(dynamic value) {
    if (value is Map && value.length == 1 && value.containsKey('__ts')) {
      return Timestamp.fromMillisecondsSinceEpoch((value['__ts'] as num).toInt());
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _decodeValue(item)));
    }
    if (value is List) {
      return value.map(_decodeValue).toList();
    }
    return value;
  }
}
