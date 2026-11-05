import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'activity_log_service.dart';

class SystemControl {
  const SystemControl({
    this.maintenance = false,
    this.message = '',
    this.minBuild = 0,
    this.minVersion = '',
    this.updatedBy = '',
    this.updatedAt,
  });

  factory SystemControl.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return SystemControl(
      maintenance: map['maintenance'] == true,
      message: (map['maintenanceMessage'] as String? ?? '').trim(),
      minBuild: (map['minBuild'] as num?)?.toInt() ?? 0,
      minVersion: (map['minVersion'] as String? ?? '').trim(),
      updatedBy: (map['updatedBy'] as String? ?? '').trim(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final bool maintenance;
  final String message;
  final int minBuild;
  final String minVersion;
  final String updatedBy;
  final DateTime? updatedAt;
}

/// One shared listener per app on `system_control/config`: Firestore only bills a read when it changes.
class SystemControlService {
  SystemControlService._();
  static final instance = SystemControlService._();

  final config = ValueNotifier<SystemControl>(const SystemControl());
  final installedBuild = ValueNotifier<int?>(null);
  var installedVersion = '';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  var _users = 0;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('system_control').doc('config');

  void start() {
    if (installedBuild.value == null) {
      PackageInfo.fromPlatform().then((info) {
        installedVersion = info.version;
        installedBuild.value = int.tryParse(info.buildNumber) ?? 0;
      }).catchError((_) {
        installedBuild.value = 0;
      });
    }
    _users++;
    _sub ??= _ref.snapshots().listen(
      (snap) => config.value = SystemControl.fromMap(snap.data()),
      onError: (_) => _sub = null,
    );
  }

  void stop() {
    if (_users > 0) _users--;
    if (_users > 0) return;
    _sub?.cancel();
    _sub = null;
    config.value = const SystemControl();
  }

  bool needsUpdate(SystemControl control) {
    final build = installedBuild.value;
    return build != null && build > 0 && control.minBuild > 0 && build < control.minBuild;
  }

  String get _actor => FirebaseAuth.instance.currentUser?.email ?? '';

  Future<void> setMaintenance({required bool on, required String message}) async {
    await _ref.set({
      'maintenance': on,
      'maintenanceMessage': message.trim(),
      'updatedBy': _actor,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    ActivityLogService.record(on ? ActivityAction.maintenanceOn : ActivityAction.maintenanceOff,
        level: ActivityLevel.security, target: 'System', detail: message.trim());
  }

  Future<void> setMinimumBuild({required int build, required String version}) async {
    await _ref.set({
      'minBuild': build < 0 ? 0 : build,
      'minVersion': build <= 0 ? '' : version.trim(),
      'updatedBy': _actor,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    ActivityLogService.record(ActivityAction.minimumVersionSet,
        level: ActivityLevel.security,
        target: 'System',
        detail: build <= 0 ? 'Requirement removed' : 'Minimum $version (build $build)');
  }
}
