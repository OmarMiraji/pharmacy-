import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

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

class OfflineSyncService extends ChangeNotifier {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  static const _syncChunkSize = 15;

  final SalesService _sales = SalesService();
  final _OfflineQueueVault _vault = _OfflineQueueVault();
  Timer? _timer;
  bool _online = true;
  bool _syncing = false;
  List<PendingSale> _queue = [];

  bool get isOnline => _online;
  bool get isSyncing => _syncing;
  int get pendingCount => _queue.length;
  List<PendingSale> get pendingSales => List.unmodifiable(_queue);
  String? get lastError {
    for (final sale in _queue) {
      final error = sale.lastError;
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
    if (online && _queue.isNotEmpty) {
      await syncPending();
    }
  }

  static Future<bool> probeNetwork() async {
    try {
      final socket = await Socket.connect('firestore.googleapis.com', 443, timeout: const Duration(milliseconds: 400));
      socket.destroy();
      return true;
    } catch (_) {
      try {
        final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(milliseconds: 250));
        socket.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static bool isNetworkError(Object error) {
    final text = '$error'.toLowerCase();
    return error is SocketException ||
        error is TimeoutException ||
        text.contains('unavailable') ||
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

  Future<void> syncPending() async {
    if (_syncing) return;
    final pharmacyId = TenantContext.instance.pharmacyId;
    if (pharmacyId == null || pharmacyId.isEmpty) return;
    if (_queue.isEmpty) return;

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
            paymentMethod: sale.paymentMethod,
            discountMinor: sale.discountMinor,
            actor: UserProfile(
              id: sale.soldBy,
              employeeCode: '',
              displayName: '',
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
      await _save();
      if (!paused && remaining.any((sale) => sale.pharmacyId == pharmacyId && (sale.lastError ?? '').isEmpty)) {
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
    final reserved = reservedQuantities();
    if (reserved.isEmpty) return medicines;
    return medicines
        .map((medicine) {
          final hold = reserved[medicine.id] ?? 0;
          if (hold == 0) return medicine;
          final remaining = medicine.quantityOnHand - hold;
          return medicine.copyWith(quantityOnHand: remaining < 0 ? 0 : remaining);
        })
        .toList();
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
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = await compute(_decodeQueueJson, raw);
      _queue = decoded.map(PendingSale.fromJson).toList();
      if (await legacy.exists()) {
        await _save();
        await legacy.delete();
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final file = await _file();
    final payload = await compute(_encodeQueueJson, [for (final sale in _queue) sale.toJson()]);
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
