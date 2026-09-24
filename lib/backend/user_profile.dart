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
    return AppPermissions.roleDefaults[role]?[permission] == true || permissions[permission] == true;
  }

  List<String> missingPharmacyPermissions() {
    const required = [
      'medicines.view',
      'medicines.create',
      'medicines.update',
      'inventory.view',
      'inventory.adjust',
      'sales.view',
      'sales.create',
      'purchases.view',
      'purchases.create',
      'purchases.receive',
      'reports.view',
    ];
    return required.where((permission) => !can(permission)).toList();
  }

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawPermissions = data['permissions'] as Map<String, dynamic>? ?? {};
    final permissions = <String, bool>{};
    _flattenPermissions(rawPermissions, permissions);
    final role = (data['role'] as String? ?? 'cashier').trim().toLowerCase();
    return UserProfile(
      id: doc.id,
      employeeCode: data['employeeCode'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: role,
      permissions: AppPermissions.resolvedPermissions(role, permissions),
      isActive: data['isActive'] != false,
      phone: data['phone'] as String?,
      pharmacyId: () {
        final raw = data['pharmacyId'];
        if (raw is String && raw.trim().isNotEmpty) return raw.trim();
        return null;
      }(),
    );
  }

  static void _flattenPermissions(
    Map<String, dynamic> source,
    Map<String, bool> target, {
    String prefix = '',
  }) {
    for (final entry in source.entries) {
      final key = entry.key.trim();
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      if (entry.value is Map<String, dynamic>) {
        _flattenPermissions(entry.value as Map<String, dynamic>, target, prefix: fullKey);
      } else {
        target[fullKey] = entry.value == true;
      }
    }
  }
}
