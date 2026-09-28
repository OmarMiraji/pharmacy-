import 'package:cloud_firestore/cloud_firestore.dart';

import 'permissions.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.employeeCode,
    required this.displayName,
    required this.email,
    required this.role,
    required this.permissions,
    required this.isActive,
    this.phone,
    this.pharmacyId,
  });

  final String id;
  final String employeeCode;
  final String displayName;
  final String email;
  final String role;
  final Map<String, bool> permissions;
  final bool isActive;
  final String? phone;
  final String? pharmacyId;

  bool get isSuperAdmin => role == 'super_admin';

  bool get canSeeSalesTotals => isSuperAdmin || role == 'admin';

  bool visibleTo(UserProfile? viewer) {
    if (viewer == null) return !isSuperAdmin;
    if (viewer.isSuperAdmin || id == viewer.id) return true;
    return !isSuperAdmin;
  }

  bool can(String permission) {
    if (isSuperAdmin) return true;
    if (AppPermissions.superAdminOnlyPermissions.contains(permission)) return false;
    if (role == 'admin') {
      return AppPermissions.pharmacyPermissions.contains(permission);
    }
    return permissions[permission] == true;
  }

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawPermissions = data['permissions'];
    final permissions = <String, bool>{};
    if (rawPermissions is Map) {
      _flattenPermissions(Map<String, dynamic>.from(rawPermissions), permissions);
    }
    final role = _asString(data['role']).trim().toLowerCase();
    final safeRole = role.isEmpty ? 'cashier' : role;
    return UserProfile(
      id: doc.id,
      employeeCode: _asString(data['employeeCode']),
      displayName: _asString(data['displayName']),
      email: _asString(data['email']),
      role: safeRole,
      permissions: AppPermissions.resolvedPermissions(safeRole, permissions),
      isActive: data['isActive'] != false,
      phone: _asString(data['phone']).trim().isEmpty ? null : _asString(data['phone']),
      pharmacyId: () {
        final raw = data['pharmacyId'];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
        return null;
      }(),
    );
  }

  static String _asString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  static void _flattenPermissions(
    Map<String, dynamic> source,
    Map<String, bool> target, {
    String prefix = '',
  }) {
    for (final entry in source.entries) {
      final key = entry.key.trim();
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      if (entry.value is Map) {
        _flattenPermissions(Map<String, dynamic>.from(entry.value as Map), target, prefix: fullKey);
      } else {
        target[fullKey] = entry.value == true;
      }
    }
  }
}
