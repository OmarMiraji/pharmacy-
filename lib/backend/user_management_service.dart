import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'activity_log_service.dart';
import 'auth_account_service.dart';
import 'firestore_collections.dart';
import 'permissions.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class UserManagementService {
  UserManagementService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> isActiveEmail(String email) async {
    final mail = email.trim().toLowerCase();
    if (!mail.contains('@')) return false;
    final users = _firestore.collection(FirestoreCollections.users);
    final lowered = await users.where('email', isEqualTo: mail).limit(5).get();
    final docs = lowered.docs.isNotEmpty
        ? lowered.docs
        : (await users.where('email', isEqualTo: email.trim()).limit(5).get()).docs;
    if (docs.isEmpty) return false;
    return docs.any((doc) => doc.data()['isActive'] != false);
  }

  Stream<List<UserProfile>> watchUsers({String? pharmacyId}) {
    final tenant = TenantContext.instance;
    final filterId = (pharmacyId ?? '').trim();
    final Query<Map<String, dynamic>> query;
    if (tenant.isSuperAdmin) {
      query = filterId.isEmpty
          ? _firestore.collection(FirestoreCollections.users)
          : _firestore.collection(FirestoreCollections.users).where('pharmacyId', isEqualTo: filterId);
    } else {
      query = tenant.scoped(_firestore.collection(FirestoreCollections.users));
    }
    return query.snapshots().map((snapshot) {
      final users = <UserProfile>[];
      for (final doc in snapshot.docs) {
        try {
          final user = UserProfile.fromFirestore(doc);
          if (tenant.isSuperAdmin || user.role != 'super_admin') {
            users.add(user);
          }
        } catch (_) {}
      }
      users.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return users;
    });
  }

  static const protectedSuperAdminMessage =
      'A super admin login is protected. It cannot be deleted, disabled, or given a lower role.';

  static bool isProtectedRole(Object? role) => '$role'.trim().toLowerCase() == 'super_admin';

  Future<void> updateAccess({
    required String userId,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
  }) async {
    TenantContext.instance.assertWritable();
    if (!AppPermissions.roleDefaults.containsKey(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported role.');
    }
    final actorId = FirebaseAuth.instance.currentUser?.uid;
    if (!TenantContext.instance.isSuperAdmin && actorId != null && actorId == userId) {
      throw StateError('You cannot change your own access. Ask your administrator.');
    }
    final ref = _firestore.collection(FirestoreCollections.users).doc(userId);
    final before = (await ref.get()).data() ?? const <String, dynamic>{};
    if (isProtectedRole(before['role'])) throw StateError(protectedSuperAdminMessage);
    final resolved = AppPermissions.resolvedPermissions(role, permissions);
    await ref.update({
      'role': role,
      'permissions': resolved,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logAccessChange(
      before: before,
      name: (before['displayName'] as String? ?? '').trim(),
      email: (before['email'] as String? ?? '').trim(),
      role: role,
      permissions: resolved,
      isActive: isActive,
      pharmacyId: (before['pharmacyId'] as String? ?? '').trim(),
    );
  }

  Future<void> updateProfileDetails({
    required String userId,
    required String displayName,
    required String email,
    String? phone,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
    String? pharmacyId,
    String? employeeCode,
  }) async {
    TenantContext.instance.assertWritable();
    if (!AppPermissions.roleDefaults.containsKey(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported role.');
    }
    final actorId = FirebaseAuth.instance.currentUser?.uid;
    if (!TenantContext.instance.isSuperAdmin && actorId != null && actorId == userId) {
      throw StateError('You cannot change your own access. Ask your administrator.');
    }
    if (displayName.trim().isEmpty || email.trim().isEmpty) {
      throw ArgumentError('Name and email are required.');
    }
    final tenant = TenantContext.instance;
    var tenantId = (pharmacyId ?? tenant.pharmacyId ?? '').trim();
    if (!tenant.isSuperAdmin) {
      tenantId = (tenant.pharmacyId ?? tenantId).trim();
      if (tenantId.isEmpty) {
        throw StateError('Your account is not linked to a pharmacy, so staff cannot be changed.');
      }
    }
    final resolved = AppPermissions.resolvedPermissions(role, permissions);
    final ref = _firestore.collection(FirestoreCollections.users).doc(userId);
    final before = await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.data() ?? const <String, dynamic>{};
      if (isProtectedRole(existing['role']) && (!isProtectedRole(role) || !isActive)) {
        throw StateError(protectedSuperAdminMessage);
      }
      final existingShop = (existing['pharmacyId'] as String?)?.trim() ?? '';
      final shopId = tenant.isSuperAdmin
          ? tenantId
          : (existingShop.isNotEmpty ? existingShop : tenantId);
      if (!tenant.isSuperAdmin && existingShop.isNotEmpty && shopId != tenantId) {
        throw StateError('This login belongs to another pharmacy.');
      }
      tx.set(ref, {
        'displayName': displayName.trim(),
        'email': email.trim(),
        'phone': (phone ?? '').trim(),
        'role': role,
        'permissions': resolved,
        'isActive': isActive,
        if ((employeeCode ?? '').trim().isNotEmpty) 'employeeCode': employeeCode!.trim(),
        if (role != 'super_admin' && shopId.isNotEmpty) 'pharmacyId': shopId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return existing;
    });
    _logAccessChange(
      before: before,
      name: displayName.trim(),
      email: email.trim(),
      role: role,
      permissions: resolved,
      isActive: isActive,
      pharmacyId: (role != 'super_admin' ? (before['pharmacyId'] as String? ?? tenantId) : '').trim(),
    );
  }

  void _logAccessChange({
    required Map<String, dynamic> before,
    required String name,
    required String email,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
    required String pharmacyId,
  }) {
    final target = '$name <$email>';
    final shopId = pharmacyId.isEmpty ? null : pharmacyId;
    final oldRole = (before['role'] as String? ?? '').trim();
    final wasActive = before['isActive'] != false;
    final oldPerms = Map<String, dynamic>.from(before['permissions'] as Map? ?? const {});
    final added = [for (final e in permissions.entries) if (e.value && oldPerms[e.key] != true) e.key];
    final removed = [for (final e in permissions.entries) if (!e.value && oldPerms[e.key] == true) e.key];
    if (wasActive != isActive) {
      ActivityLogService.record(isActive ? ActivityAction.staffEnabled : ActivityAction.staffDisabled,
          level: ActivityLevel.security, target: target, pharmacyId: shopId);
    }
    if (oldRole.isNotEmpty && oldRole != role) {
      ActivityLogService.record(ActivityAction.staffRoleChanged,
          level: ActivityLevel.security, target: target, detail: '$oldRole → $role', pharmacyId: shopId);
    } else if (added.isNotEmpty || removed.isNotEmpty) {
      ActivityLogService.record(ActivityAction.staffUpdated,
          level: ActivityLevel.security,
          target: target,
          detail: [
            if (added.isNotEmpty) '+ ${added.join(', ')}',
            if (removed.isNotEmpty) '- ${removed.join(', ')}',
          ].join('  '),
          pharmacyId: shopId);
    } else if (wasActive == isActive &&
        ((before['displayName'] ?? '') != name || (before['email'] ?? '') != email)) {
      ActivityLogService.record(ActivityAction.staffUpdated, target: target, detail: 'name/email', pharmacyId: shopId);
    }
  }

  Future<String> createLoginAndProfile({
    required String displayName,
    required String email,
    required String password,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
    String? pharmacyId,
    String? phone,
    String? employeeCode,
  }) async {
    TenantContext.instance.assertWritable();
    final shopId = (pharmacyId ?? TenantContext.instance.pharmacyId ?? '').trim();
    if (!TenantContext.instance.isSuperAdmin) {
      if (role == 'admin' || role == 'super_admin') {
        throw StateError('Only Super Admin creates the shop admin. Add pharmacist, cashier, or storekeeper.');
      }
      if (shopId.isEmpty) {
        throw StateError('Your account is not linked to a pharmacy, so staff cannot be added.');
      }
    } else if (role != 'super_admin' && shopId.isEmpty) {
      throw ArgumentError('This login must belong to a pharmacy.');
    }
    final mail = email.trim().toLowerCase();
    final team = TenantContext.instance.isSuperAdmin
        ? await _firestore.collection(FirestoreCollections.users).where('email', isEqualTo: mail).limit(5).get()
        : await TenantContext.instance.scoped(_firestore.collection(FirestoreCollections.users)).get();
    final alreadyOnTeam = team.docs.any((doc) {
      final data = doc.data();
      return (data['email'] as String? ?? '').trim().toLowerCase() == mail;
    });
    if (alreadyOnTeam) {
      throw Exception(
        '$mail is already a staff login for this pharmacy. They can sign in with their existing password.',
      );
    }
    final uid = await AuthAccountService().createAuthUser(email: mail, password: password, role: role);
    await createProfile(
      userId: uid,
      displayName: displayName,
      email: email.trim().toLowerCase(),
      role: role,
      permissions: permissions,
      isActive: isActive,
      pharmacyId: shopId,
      phone: phone,
      employeeCode: employeeCode,
      temporaryPassword: password,
    );
    return uid;
  }

  /// Records that [password] was chosen by an admin, so the owner must replace it at next sign-in.
  /// Best effort: the login already works even if this write is rejected.
  Future<void> markTemporaryPassword({required String userId, required String password}) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    try {
      await _firestore.collection(FirestoreCollections.users).doc(id).set({
        'mustChangePassword': true,
        'tempPassword': password.trim(),
        'tempPasswordSetAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> createProfile({
    required String userId,
    required String displayName,
    required String email,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
    String? pharmacyId,
    String? phone,
    String? employeeCode,
    String? temporaryPassword,
  }) async {
    TenantContext.instance.assertWritable();
    if (userId.trim().isEmpty || displayName.trim().isEmpty || email.trim().isEmpty) {
      throw ArgumentError('Firebase Auth UID, name, and email are required.');
    }
    if (!AppPermissions.roleDefaults.containsKey(role)) {
      throw ArgumentError.value(role, 'role', 'Choose a valid role.');
    }
    final tenantId = (pharmacyId ?? TenantContext.instance.pharmacyId ?? '').trim();
    if (role != 'super_admin' && tenantId.isEmpty) {
      throw ArgumentError('This login must belong to a pharmacy.');
    }
    if (!TenantContext.instance.isSuperAdmin) {
      if (role == 'admin' || role == 'super_admin') {
        throw StateError('Only Super Admin creates the shop admin. You can add pharmacist, cashier, or storekeeper.');
      }
      final shopId = (TenantContext.instance.pharmacyId ?? '').trim();
      if (shopId.isEmpty || shopId != tenantId) {
        throw StateError('Staff can only be added to your pharmacy.');
      }
    }
    await _firestore.collection(FirestoreCollections.users).doc(userId.trim()).set({
      'displayName': displayName.trim(),
      'email': email.trim(),
      'phone': (phone ?? '').trim(),
      'employeeCode': (employeeCode ?? '').trim(),
      'role': role,
      'permissions': AppPermissions.resolvedPermissions(role, permissions),
      'isActive': isActive,
      if (role != 'super_admin') 'pharmacyId': tenantId,
      if ((temporaryPassword ?? '').trim().isNotEmpty) ...{
        'mustChangePassword': true,
        'tempPassword': temporaryPassword!.trim(),
        'tempPasswordSetAt': FieldValue.serverTimestamp(),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    ActivityLogService.record(
      ActivityAction.staffCreated,
      level: ActivityLevel.security,
      target: '${displayName.trim()} <${email.trim()}>',
      detail: role,
      pharmacyId: role == 'super_admin' ? null : tenantId,
    );
    await AuthAccountService().rememberAuthUid(email: email.trim(), uid: userId.trim());
  }

  Future<void> deleteProfile(String userId) async {
    if (!TenantContext.instance.isSuperAdmin) {
      TenantContext.instance.assertWritable();
    }
    final id = userId.trim();
    if (id.isEmpty) return;
    final snap = await _firestore.collection(FirestoreCollections.users).doc(id).get();
    if (isProtectedRole(snap.data()?['role'])) throw StateError(protectedSuperAdminMessage);
    final email = (snap.data()?['email'] as String? ?? '').trim().toLowerCase();
    if (email.isNotEmpty) {
      await AuthAccountService().rememberAuthUid(email: email, uid: id);
    }
    await _firestore.collection(FirestoreCollections.users).doc(id).delete();
    final data = snap.data() ?? const <String, dynamic>{};
    ActivityLogService.record(
      ActivityAction.staffDeleted,
      level: ActivityLevel.security,
      target: '${(data['displayName'] as String? ?? '').trim()} <$email>',
      detail: (data['role'] as String? ?? '').trim(),
      pharmacyId: (data['pharmacyId'] as String? ?? '').trim().isEmpty ? null : (data['pharmacyId'] as String).trim(),
    );
    await AuthAccountService().deleteAuthUser(id);
  }

  Future<int> deletePharmacyStaff({required String pharmacyId, String? keepUserId}) async {
    if (!TenantContext.instance.isSuperAdmin) {
      throw StateError('Only super admin can clear pharmacy users.');
    }
    final snapshot = await _firestore
        .collection(FirestoreCollections.users)
        .where('pharmacyId', isEqualTo: pharmacyId)
        .get();
    var deleted = 0;
    for (final doc in snapshot.docs) {
      if (doc.id == keepUserId) continue;
      final role = (doc.data()['role'] as String? ?? '').trim().toLowerCase();
      if (role == 'super_admin') continue;
      await doc.reference.delete();
      deleted++;
    }
    return deleted;
  }

  Future<void> setLoginPassword({required String userId, required String password}) async {
    TenantContext.instance.assertWritable();
    final next = password.trim();
    if (userId.trim().isEmpty) throw ArgumentError('User is required.');
    if (next.length < 6) throw ArgumentError('Password must be at least 6 characters.');
    final actor = FirebaseAuth.instance.currentUser?.uid;
    if (actor != null && actor == userId) {
      throw StateError('Change your own password from Settings or the lock icon.');
    }
    try {
      await AuthAccountService().setUserPassword(uid: userId, password: next);
    } catch (error) {
      final text = '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '').trim();
      throw StateError(text.isEmpty ? 'Could not set that login password.' : text);
    }
    await markTemporaryPassword(userId: userId, password: next);
    try {
      final data = (await _firestore.collection(FirestoreCollections.users).doc(userId).get()).data() ?? const {};
      final shop = (data['pharmacyId'] as String? ?? '').trim();
      ActivityLogService.record(
        ActivityAction.passwordReset,
        level: ActivityLevel.security,
        target: '${(data['displayName'] as String? ?? '').trim()} <${(data['email'] as String? ?? '').trim()}>',
        pharmacyId: shop.isEmpty ? null : shop,
      );
    } catch (_) {}
  }
}
