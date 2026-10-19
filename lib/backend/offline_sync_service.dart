import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'medicine_service.dart';
import 'models.dart';
import 'permissions.dart';
import 'sales_service.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class PendingSale {
  const PendingSale({
    required this.id,
    required this.pharmacyId,
    required this.soldBy,
    this.soldByName = '',
    required this.paymentMethod,
    required this.discountMinor,
    required this.items,
    required this.createdAt,
    this.lastError,
    this.actorRole,
  });

  final String id;
  final String pharmacyId;
  final String soldBy;
  final String soldByName;
  final String paymentMethod;
  final int discountMinor;
  final List<SaleCartItem> items;
  final DateTime createdAt;
  final String? lastError;
  final String? actorRole;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pharmacyId': pharmacyId,
        'soldBy': soldBy,
        'soldByName': soldByName,
        'paymentMethod': paymentMethod,
        'discountMinor': discountMinor,
        'createdAt': createdAt.toIso8601String(),
        'lastError': lastError,
        'actorRole': actorRole,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory PendingSale.fromJson(Map<String, dynamic> json) {
    return PendingSale(
      id: json['id'] as String? ?? '',
      pharmacyId: json['pharmacyId'] as String? ?? '',
      soldBy: json['soldBy'] as String? ?? '',
      soldByName: json['soldByName'] as String? ?? '',
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      discountMinor: (json['discountMinor'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastError: json['lastError'] as String?,
      actorRole: json['actorRole'] as String?,
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => SaleCartItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class PendingMedicineWrite {
  const PendingMedicineWrite({
    required this.id,
    required this.pharmacyId,
    required this.editing,
    required this.name,
    required this.sku,
    required this.categoryId,
    required this.unit,
    required this.purchasePriceMinor,
    required this.sellingPriceMinor,
    required this.reorderLevel,
    required this.requiresPrescription,
    required this.packSize,
    required this.stripSize,
    required this.boxSize,
    required this.minSaleQty,
    required this.allowLooseSale,
    required this.allowHalfBlister,
    required this.openingQuantity,
    required this.openingAsTablets,
    required this.previewQuantity,
    required this.createdBy,
    required this.createdAt,
    this.medicineId,
    this.expiryDate,
    this.batchNumber,
    this.onHandQuantity,
    this.lastError,
  });

  final String id;
  final String pharmacyId;
  final bool editing;
  final String? medicineId;
  final String name;
  final String sku;
  final String categoryId;
  final String unit;
  final int purchasePriceMinor;
  final int sellingPriceMinor;
  final int reorderLevel;
  final bool requiresPrescription;
  final int packSize;
  final int stripSize;
  final int boxSize;
  final int minSaleQty;
  final bool allowLooseSale;
  final bool allowHalfBlister;
  final DateTime? expiryDate;
  final int openingQuantity;
  final bool openingAsTablets;
  final String? batchNumber;
  final int? onHandQuantity;
  final int previewQuantity;
  final String createdBy;
  final DateTime createdAt;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pharmacyId': pharmacyId,
        'editing': editing,
        'medicineId': medicineId,
        'name': name,
        'sku': sku,
        'categoryId': categoryId,
        'unit': unit,
        'purchasePriceMinor': purchasePriceMinor,
        'sellingPriceMinor': sellingPriceMinor,
        'reorderLevel': reorderLevel,
        'requiresPrescription': requiresPrescription,
        'packSize': packSize,
        'stripSize': stripSize,
        'boxSize': boxSize,
        'minSaleQty': minSaleQty,
        'allowLooseSale': allowLooseSale,
        'allowHalfBlister': allowHalfBlister,
        'expiryDate': expiryDate?.toIso8601String(),
        'openingQuantity': openingQuantity,
        'openingAsTablets': openingAsTablets,
        'batchNumber': batchNumber,
        'onHandQuantity': onHandQuantity,
        'previewQuantity': previewQuantity,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'lastError': lastError,
      };

  factory PendingMedicineWrite.fromJson(Map<String, dynamic> json) {
    return PendingMedicineWrite(
      id: json['id'] as String? ?? '',
      pharmacyId: json['pharmacyId'] as String? ?? '',
      editing: json['editing'] == true,
      medicineId: json['medicineId'] as String?,
      name: json['name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      unit: json['unit'] as String? ?? 'unit',
      purchasePriceMinor: (json['purchasePriceMinor'] as num?)?.toInt() ?? 0,
      sellingPriceMinor: (json['sellingPriceMinor'] as num?)?.toInt() ?? 0,
      reorderLevel: (json['reorderLevel'] as num?)?.toInt() ?? 0,
      requiresPrescription: json['requiresPrescription'] == true,
      packSize: (json['packSize'] as num?)?.toInt() ?? 1,
      stripSize: (json['stripSize'] as num?)?.toInt() ?? 0,
      boxSize: (json['boxSize'] as num?)?.toInt() ?? 0,
      minSaleQty: (json['minSaleQty'] as num?)?.toInt() ?? 0,
      allowLooseSale: json['allowLooseSale'] == true,
      allowHalfBlister: json['allowHalfBlister'] == true,
      expiryDate: DateTime.tryParse(json['expiryDate'] as String? ?? ''),
      openingQuantity: (json['openingQuantity'] as num?)?.toInt() ?? 0,
      openingAsTablets: json['openingAsTablets'] != false,
      batchNumber: json['batchNumber'] as String?,
      onHandQuantity: (json['onHandQuantity'] as num?)?.toInt(),
      previewQuantity: (json['previewQuantity'] as num?)?.toInt() ?? 0,
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastError: json['lastError'] as String?,
    );
  }

  PendingMedicineWrite copyWithError(String error) {
    return PendingMedicineWrite(
      id: id,
      pharmacyId: pharmacyId,
      editing: editing,
      medicineId: medicineId,
      name: name,
      sku: sku,
      categoryId: categoryId,
      unit: unit,
      purchasePriceMinor: purchasePriceMinor,
      sellingPriceMinor: sellingPriceMinor,
      reorderLevel: reorderLevel,
      requiresPrescription: requiresPrescription,
      packSize: packSize,
      stripSize: stripSize,
      boxSize: boxSize,
      minSaleQty: minSaleQty,
      allowLooseSale: allowLooseSale,
      allowHalfBlister: allowHalfBlister,
      expiryDate: expiryDate,
      openingQuantity: openingQuantity,
      openingAsTablets: openingAsTablets,
      batchNumber: batchNumber,
      onHandQuantity: onHandQuantity,
      previewQuantity: previewQuantity,
      createdBy: createdBy,
      createdAt: createdAt,
      lastError: error,
    );
  }
}

class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  static const _syncChunkSize = 15;

  final SalesService _sales = SalesService();
  final MedicineService _medicines = MedicineService();
  final _OfflineQueueVault _vault = _OfflineQueueVault();
  Timer? _timer;
  bool _online = true;
  bool _syncing = false;
  List<PendingSale> _queue = [];
  List<PendingMedicineWrite> _medicineQueue = [];

  bool get isOnline => _online;
  bool get isSyncing => _syncing;
  int get pendingCount => _queue.length + _medicineQueue.length;

  int get failedMedicinePendingCount => _medicineQueue
      .where((change) => isPermanentSyncErrorMessage(change.lastError))
      .length;

  int get retryableMedicinePendingCount =>
      _medicineQueue.length - failedMedicinePendingCount;

  List<PendingSale> get pendingSales => List.unmodifiable(_queue);

  static bool isPermanentSyncError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied' ||
          error.code == 'unauthenticated';
    }
    return isPermanentSyncErrorMessage('$error');
  }

  static bool isPermanentSyncErrorMessage(String? message) {
    if (message == null || message.trim().isEmpty) return false;
    final lower = message.toLowerCase();
    return lower.contains('permission-denied') ||
        lower.contains('insufficient permissions') ||
        lower.contains('missing or insufficient');
  }

  /// Stops retrying medicine saves that Firestore will never accept on this login.
  Future<int> discardFailedMedicinePending() async {
    final before = _medicineQueue.length;
    _medicineQueue = [
      for (final change in _medicineQueue)
        if (!isPermanentSyncErrorMessage(change.lastError)) change,
    ];
    if (_medicineQueue.length != before) {
      await _save();
      notifyListeners();
    }
    return before - _medicineQueue.length;
  }

  String? get lastError {
    for (final sale in _queue) {
      final error = sale.lastError;
      if (error != null && error.trim().isNotEmpty) return error;
    }
    for (final change in _medicineQueue) {
      final error = change.lastError;
      if (error != null && error.trim().isNotEmpty) return error;
    }
    return null;
  }

  Future<void> start() async {
    await _load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(pingAndSync());
    });
    unawaited(pingAndSync());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> pingAndSync() async {
    final online = await probeNetwork();
    final changed = online != _online;
    _online = online;
    if (changed) notifyListeners();
    if (online && pendingCount > 0) {
      await syncPending();
    }
  }

  void noteDisconnected() {
    if (_online) {
      _online = false;
      notifyListeners();
    }
  }

  void noteConnected() {
    if (!_online) {
      _online = true;
      notifyListeners();
      if (pendingCount > 0) unawaited(syncPending());
    }
  }

  static Future<bool> probeNetwork() async {
    try {
      final ipv4 = await InternetAddress.lookup(
        'firestore.googleapis.com',
        type: InternetAddressType.IPv4,
      );
      if (ipv4.isNotEmpty) {
        final socket = await Socket.connect(ipv4.first, 443, timeout: const Duration(seconds: 3));
        socket.destroy();
        return true;
      }
    } catch (_) {}
    try {
      final socket = await Socket.connect(InternetAddress('1.1.1.1'), 443, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool isNetworkError(Object error) {
    final text = '$error'.toLowerCase();
    return error is SocketException ||
        error is TimeoutException ||
        text.contains('unavailable') ||
        text.contains('network is unreachable') ||
        text.contains('no route to host') ||
        text.contains('connection timed out') ||
        text.contains('failed to connect') ||
        text.contains('wsagetoverlappedresult') ||
        text.contains('10051') ||
        text.contains('10060') ||
        text.contains('10065') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('offline') ||
        text.contains('failed host lookup') ||
        text.contains('client is offline') ||
        text.contains('the client is offline');
  }

  Future<String> completeSale({
    required List<SaleCartItem> items,
    required String soldBy,
    String? soldByName,
    required String paymentMethod,
    int discountMinor = 0,
    String? customerId,
    UserProfile? actor,
  }) async {
    TenantContext.instance.assertWritable();
    if (_online) {
      try {
        return await _sales.completeSale(
          items: items,
          soldBy: soldBy,
          soldByName: (soldByName ?? actor?.displayName ?? '').trim(),
          paymentMethod: paymentMethod,
          discountMinor: discountMinor,
          customerId: customerId,
          actor: actor,
        );
      } catch (error) {
        if (!isNetworkError(error)) rethrow;
        _online = false;
      }
    }

    final pending = PendingSale(
      id: 'L-${DateTime.now().millisecondsSinceEpoch}',
      pharmacyId: TenantContext.instance.requirePharmacyId(),
      soldBy: soldBy,
      soldByName: (soldByName ?? actor?.displayName ?? '').trim(),
      paymentMethod: paymentMethod,
      discountMinor: discountMinor,
      items: items,
      createdAt: DateTime.now(),
      actorRole: actor?.role,
    );
    _queue = [..._queue, pending];
    await _save();
    notifyListeners();
    unawaited(pingAndSync());
    return pending.id;
  }

  Future<String> saveMedicine({
    required bool editing,
    String? medicineId,
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
    int? onHandQuantity,
    required int previewQuantity,
    required String createdBy,
  }) async {
    TenantContext.instance.assertWritable();
    if (name.trim().isEmpty || categoryId.trim().isEmpty) {
      throw ArgumentError('Name and category are required.');
    }
    if (editing && (medicineId ?? '').trim().isEmpty) {
      throw ArgumentError('Medicine is required.');
    }

    Future<String> send() {
      if (editing) {
        return _sendMedicineUpdate(
          medicineId: medicineId!.trim(),
          name: name,
          sku: sku,
          categoryId: categoryId,
          unit: unit,
          purchasePriceMinor: purchasePriceMinor,
          sellingPriceMinor: sellingPriceMinor,
          reorderLevel: reorderLevel,
          requiresPrescription: requiresPrescription,
          packSize: packSize,
          stripSize: stripSize,
          boxSize: boxSize,
          minSaleQty: minSaleQty,
          allowLooseSale: allowLooseSale,
          allowHalfBlister: allowHalfBlister,
          expiryDate: expiryDate,
          onHandQuantity: onHandQuantity,
          batchNumber: batchNumber,
          createdBy: createdBy,
        );
      }
      return _medicines.createMedicine(
        name: name,
        sku: sku,
        categoryId: categoryId,
        unit: unit,
        purchasePriceMinor: purchasePriceMinor,
        sellingPriceMinor: sellingPriceMinor,
        reorderLevel: reorderLevel,
        requiresPrescription: requiresPrescription,
        packSize: packSize,
        stripSize: stripSize,
        boxSize: boxSize,
        minSaleQty: minSaleQty,
        allowLooseSale: allowLooseSale,
        allowHalfBlister: allowHalfBlister,
        expiryDate: expiryDate,
        openingQuantity: openingQuantity,
        openingAsTablets: openingAsTablets,
        batchNumber: batchNumber,
        createdBy: createdBy,
      );
    }

    if (_online) {
      try {
        return await send();
      } catch (error) {
        if (!isNetworkError(error)) rethrow;
        _online = false;
      }
    }

    final pending = PendingMedicineWrite(
      id: 'M-${DateTime.now().millisecondsSinceEpoch}',
      pharmacyId: TenantContext.instance.requirePharmacyId(),
      editing: editing,
      medicineId: medicineId,
      name: name.trim(),
      sku: sku.trim(),
      categoryId: categoryId.trim(),
      unit: unit,
      purchasePriceMinor: purchasePriceMinor,
      sellingPriceMinor: sellingPriceMinor,
      reorderLevel: reorderLevel,
      requiresPrescription: requiresPrescription,
      packSize: packSize,
      stripSize: stripSize,
      boxSize: boxSize,
      minSaleQty: minSaleQty,
      allowLooseSale: allowLooseSale,
      allowHalfBlister: allowHalfBlister,
      expiryDate: expiryDate,
      openingQuantity: openingQuantity,
      openingAsTablets: openingAsTablets,
      batchNumber: batchNumber,
      onHandQuantity: onHandQuantity,
      previewQuantity: previewQuantity,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    _medicineQueue = [..._medicineQueue, pending];
    await _save();
    notifyListeners();
    unawaited(pingAndSync());
    return pending.id;
  }

  Future<String> _sendMedicineUpdate({
    required String medicineId,
    required String name,
    required String sku,
    required String categoryId,
    required String unit,
    required int purchasePriceMinor,
    required int sellingPriceMinor,
    required int reorderLevel,
    required bool requiresPrescription,
    required int packSize,
    required int stripSize,
    required int boxSize,
    required int minSaleQty,
    required bool allowLooseSale,
    required bool allowHalfBlister,
    required DateTime? expiryDate,
    required int? onHandQuantity,
    required String? batchNumber,
    required String createdBy,
  }) async {
    await _medicines.updateMedicine(
      medicineId: medicineId,
      name: name,
      sku: sku,
      categoryId: categoryId,
      unit: unit,
      purchasePriceMinor: purchasePriceMinor,
      sellingPriceMinor: sellingPriceMinor,
      reorderLevel: reorderLevel,
      requiresPrescription: requiresPrescription,
      packSize: packSize,
      stripSize: stripSize,
      boxSize: boxSize,
      minSaleQty: minSaleQty,
      allowLooseSale: allowLooseSale,
      allowHalfBlister: allowHalfBlister,
      expiryDate: expiryDate,
    );
    if (onHandQuantity != null) {
      await _medicines.setOnHandQuantity(
        medicineId: medicineId,
        quantity: onHandQuantity,
        createdBy: createdBy,
        expiryDate: expiryDate,
        batchNumber: batchNumber,
      );
    }
    return medicineId;
  }

  Future<void> syncPending() async {
    if (_syncing) return;
    final pharmacyId = TenantContext.instance.pharmacyId;
    if (pharmacyId == null || pharmacyId.isEmpty) return;
    if (_queue.isEmpty && _medicineQueue.isEmpty) return;

    _syncing = true;
    notifyListeners();
    try {
      final remaining = <PendingSale>[];
      var paused = false;
      var processed = 0;
      for (final sale in _queue) {
        if (paused) {
          remaining.add(sale);
          continue;
        }
        if (sale.pharmacyId != pharmacyId) {
          remaining.add(sale);
          continue;
        }
        if (processed >= _syncChunkSize) {
          remaining.add(sale);
          continue;
        }
        try {
          await _sales.completeSale(
            items: sale.items,
            soldBy: sale.soldBy,
            soldByName: sale.soldByName,
            paymentMethod: sale.paymentMethod,
            discountMinor: sale.discountMinor,
            actor: UserProfile(
              id: sale.soldBy,
              employeeCode: '',
              displayName: sale.soldByName,
              email: '',
              role: sale.actorRole ?? 'cashier',
              permissions: AppPermissions.resolvedPermissions(sale.actorRole ?? 'cashier'),
              isActive: true,
            ),
          );
          processed++;
        } catch (error) {
          if (isNetworkError(error)) {
            remaining.add(sale);
            paused = true;
            continue;
          }
          remaining.add(
            PendingSale(
              id: sale.id,
              pharmacyId: sale.pharmacyId,
              soldBy: sale.soldBy,
              soldByName: sale.soldByName,
              paymentMethod: sale.paymentMethod,
              discountMinor: sale.discountMinor,
              items: sale.items,
              createdAt: sale.createdAt,
              lastError: error.toString().replaceFirst('Bad state: ', ''),
              actorRole: sale.actorRole,
            ),
          );
          processed++;
        }
      }
      _queue = remaining;
      final medicineRemaining = <PendingMedicineWrite>[];
      if (paused) {
        medicineRemaining.addAll(_medicineQueue);
      } else {
        for (final change in _medicineQueue) {
          if (paused) {
            medicineRemaining.add(change);
            continue;
          }
          if (change.pharmacyId != pharmacyId) {
            medicineRemaining.add(change);
            continue;
          }
          if (isPermanentSyncErrorMessage(change.lastError)) {
            medicineRemaining.add(change);
            continue;
          }
          if (processed >= _syncChunkSize) {
            medicineRemaining.add(change);
            continue;
          }
          try {
            await _replayMedicine(change);
            processed++;
          } catch (error) {
            if (isNetworkError(error)) {
              medicineRemaining.add(change);
              paused = true;
              continue;
            }
            medicineRemaining.add(
              change.copyWithError(
                error.toString().replaceFirst('Bad state: ', ''),
              ),
            );
            processed++;
            if (isPermanentSyncError(error)) {
              continue;
            }
          }
        }
      }
      _medicineQueue = medicineRemaining;
      await _save();
      final salesLeft = remaining.any((sale) => sale.pharmacyId == pharmacyId && (sale.lastError ?? '').isEmpty);
      final medicinesLeft = medicineRemaining.any((change) => change.pharmacyId == pharmacyId && (change.lastError ?? '').isEmpty);
      if (!paused && (salesLeft || medicinesLeft)) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50), syncPending));
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Map<String, int> reservedQuantities() {
    final pharmacyId = TenantContext.instance.pharmacyId ?? '';
    final reserved = <String, int>{};
    for (final sale in _queue) {
      if (sale.pharmacyId != pharmacyId) continue;
      for (final item in sale.items) {
        reserved[item.medicineId] = (reserved[item.medicineId] ?? 0) + item.baseQuantity;
      }
    }
    return reserved;
  }

  List<Medicine> applyLocalStock(List<Medicine> medicines) {
    final overlaid = _overlayMedicines(medicines);
    final reserved = reservedQuantities();
    if (reserved.isEmpty) return overlaid;
    return overlaid
        .map((medicine) {
          final hold = reserved[medicine.id] ?? 0;
          if (hold == 0) return medicine;
          final remaining = medicine.quantityOnHand - hold;
          return medicine.copyWith(quantityOnHand: remaining < 0 ? 0 : remaining);
        })
        .toList();
  }

  Future<void> _replayMedicine(PendingMedicineWrite change) async {
    if (change.editing) {
      await _sendMedicineUpdate(
        medicineId: (change.medicineId ?? '').trim(),
        name: change.name,
        sku: change.sku,
        categoryId: change.categoryId,
        unit: change.unit,
        purchasePriceMinor: change.purchasePriceMinor,
        sellingPriceMinor: change.sellingPriceMinor,
        reorderLevel: change.reorderLevel,
        requiresPrescription: change.requiresPrescription,
        packSize: change.packSize,
        stripSize: change.stripSize,
        boxSize: change.boxSize,
        minSaleQty: change.minSaleQty,
        allowLooseSale: change.allowLooseSale,
        allowHalfBlister: change.allowHalfBlister,
        expiryDate: change.expiryDate,
        onHandQuantity: change.onHandQuantity,
        batchNumber: change.batchNumber,
        createdBy: change.createdBy,
      );
      return;
    }
    await _medicines.createMedicine(
      name: change.name,
      sku: change.sku,
      categoryId: change.categoryId,
      unit: change.unit,
      purchasePriceMinor: change.purchasePriceMinor,
      sellingPriceMinor: change.sellingPriceMinor,
      reorderLevel: change.reorderLevel,
      requiresPrescription: change.requiresPrescription,
      packSize: change.packSize,
      stripSize: change.stripSize,
      boxSize: change.boxSize,
      minSaleQty: change.minSaleQty,
      allowLooseSale: change.allowLooseSale,
      allowHalfBlister: change.allowHalfBlister,
      expiryDate: change.expiryDate,
      openingQuantity: change.openingQuantity,
      openingAsTablets: change.openingAsTablets,
      batchNumber: change.batchNumber,
      createdBy: change.createdBy,
    );
  }

  List<Medicine> _overlayMedicines(List<Medicine> medicines) {
    final pharmacyId = TenantContext.instance.pharmacyId ?? '';
    final list = [...medicines];
    for (final change in _medicineQueue) {
      if (change.pharmacyId != pharmacyId) continue;
      if (change.editing) {
        final index = list.indexWhere((item) => item.id == change.medicineId);
        if (index < 0) continue;
        list[index] = _previewFrom(list[index], change);
        continue;
      }
      final named = change.name.trim().toLowerCase();
      if (list.any((item) => item.name.trim().toLowerCase() == named)) continue;
      list.add(_previewNew(change));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Medicine _previewFrom(Medicine base, PendingMedicineWrite change) {
    return Medicine(
      id: base.id,
      name: change.name,
      sku: change.sku.trim().isEmpty ? '' : change.sku.trim().toUpperCase(),
      categoryId: change.categoryId,
      unit: change.unit,
      purchasePriceMinor: change.purchasePriceMinor,
      sellingPriceMinor: change.sellingPriceMinor,
      quantityOnHand: change.onHandQuantity ?? base.quantityOnHand,
      reorderLevel: change.reorderLevel,
      requiresPrescription: change.requiresPrescription,
      isActive: true,
      expiryDate: change.expiryDate == null ? base.expiryDate : Timestamp.fromDate(change.expiryDate!),
      packSize: change.packSize < 1 ? 1 : change.packSize,
      stripSize: change.stripSize,
      boxSize: change.boxSize,
      allowLooseSale: change.allowLooseSale,
      allowHalfBlister: change.allowHalfBlister,
      minSaleQty: change.minSaleQty,
    );
  }

  Medicine _previewNew(PendingMedicineWrite change) {
    return Medicine(
      id: change.id,
      name: change.name,
      sku: change.sku.trim().isEmpty ? '' : change.sku.trim().toUpperCase(),
      categoryId: change.categoryId,
      unit: change.unit,
      purchasePriceMinor: change.purchasePriceMinor,
      sellingPriceMinor: change.sellingPriceMinor,
      quantityOnHand: change.previewQuantity < 0 ? 0 : change.previewQuantity,
      reorderLevel: change.reorderLevel,
      requiresPrescription: change.requiresPrescription,
      isActive: true,
      expiryDate: change.expiryDate == null ? null : Timestamp.fromDate(change.expiryDate!),
      packSize: change.packSize < 1 ? 1 : change.packSize,
      stripSize: change.stripSize,
      boxSize: change.boxSize,
      allowLooseSale: change.allowLooseSale,
      allowHalfBlister: change.allowHalfBlister,
      minSaleQty: change.minSaleQty,
    );
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/phyimacy_offline_sales.enc');
  }

  Future<File> _legacyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/phyimacy_offline_sales.json');
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      final legacy = await _legacyFile();
      String? raw;
      if (await file.exists()) {
        raw = await _vault.decrypt(await file.readAsString());
      } else if (await legacy.exists()) {
        raw = await legacy.readAsString();
      }
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = await compute(_decodeQueueJson, raw);
        _queue = decoded.map(PendingSale.fromJson).toList();
        if (await legacy.exists()) {
          await _saveSales();
          await legacy.delete();
        }
      }
      await _loadMedicines();
      notifyListeners();
    } catch (_) {}
  }

  Future<File> _medicineFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/phyimacy_offline_medicines.enc');
  }

  Future<void> _loadMedicines() async {
    final file = await _medicineFile();
    if (!await file.exists()) return;
    final raw = await _vault.decrypt(await file.readAsString());
    if (raw.trim().isEmpty) return;
    final decoded = await compute(_decodeQueueJson, raw);
    _medicineQueue = decoded.map(PendingMedicineWrite.fromJson).toList();
  }

  Future<void> _save() async {
    await _saveSales();
    await _saveMedicines();
  }

  Future<void> _saveSales() async {
    final file = await _file();
    final payload = await compute(_encodeQueueJson, [for (final sale in _queue) sale.toJson()]);
    await file.writeAsString(await _vault.encrypt(payload), flush: true);
  }

  Future<void> _saveMedicines() async {
    final file = await _medicineFile();
    final payload = await compute(_encodeQueueJson, [for (final change in _medicineQueue) change.toJson()]);
    await file.writeAsString(await _vault.encrypt(payload), flush: true);
  }
}

List<Map<String, dynamic>> _decodeQueueJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return [
    for (final row in decoded)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

String _encodeQueueJson(List<Map<String, dynamic>> rows) => jsonEncode(rows);

class _AesJob {
  const _AesJob({required this.keyB64, required this.payload, required this.seal});

  final String keyB64;
  final String payload;
  final bool seal;
}

String _runAesJob(_AesJob job) {
  final keyBytes = base64Url.decode(job.keyB64);
  final padded = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    padded[i] = i < keyBytes.length ? keyBytes[i] : 0;
  }
  final key = enc.Key(padded);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  if (job.seal) {
    final iv = enc.IV.fromSecureRandom(16);
    final sealed = encrypter.encrypt(job.payload, iv: iv);
    return '${iv.base64}.${sealed.base64}';
  }
  final trimmed = job.payload.trim();
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) return trimmed;
  final parts = trimmed.split('.');
  if (parts.length != 2) throw const FormatException('Invalid offline queue payload.');
  final iv = enc.IV.fromBase64(parts[0]);
  return encrypter.decrypt64(parts[1], iv: iv);
}

class _OfflineQueueVault {
  static const _storageKey = 'phyimacy_offline_aes_v1';
  static const _storage = FlutterSecureStorage();
  String? _cachedKey;

  Future<String> _keyB64() async {
    if (_cachedKey != null && _cachedKey!.isNotEmpty) return _cachedKey!;
    var stored = await _storage.read(key: _storageKey);
    if (stored == null || stored.isEmpty) {
      final raw = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      stored = base64UrlEncode(raw);
      await _storage.write(key: _storageKey, value: stored);
    }
    _cachedKey = stored;
    return stored;
  }

  Future<String> encrypt(String plaintext) async {
    final key = await _keyB64();
    final job = _AesJob(keyB64: key, payload: plaintext, seal: true);
    try {
      return await compute(_runAesJob, job);
    } catch (_) {
      return _runAesJob(job);
    }
  }

  Future<String> decrypt(String payload) async {
    final trimmed = payload.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) return trimmed;
    final key = await _keyB64();
    final job = _AesJob(keyB64: key, payload: trimmed, seal: false);
    try {
      return await compute(_runAesJob, job);
    } catch (_) {
      return _runAesJob(job);
    }
  }
}
