import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_account_service.dart';
import 'firestore_collections.dart';
import 'permissions.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class UserManagementService {
  UserManagementService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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
    return query.snapshots().map(
          (snapshot) => snapshot.docs.map(UserProfile.fromFirestore).where((user) {
            if (tenant.isSuperAdmin) return true;
            return user.role != 'super_admin';
          }).toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName)),
        );
  }

  Future<void> updateAccess({
    required String userId,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
  }) {
    TenantContext.instance.assertWritable();
    if (!AppPermissions.roleDefaults.containsKey(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported role.');
    }
    final actorId = FirebaseAuth.instance.currentUser?.uid;
    if (!TenantContext.instance.isSuperAdmin && actorId != null && actorId == userId) {
      throw StateError('You cannot change your own access. Ask Super Admin.');
    }
    final resolved = AppPermissions.resolvedPermissions(role, permissions);
    return _firestore.collection(FirestoreCollections.users).doc(userId).update({
      'role': role,
      'permissions': resolved,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      if ((TenantContext.instance.pharmacyId ?? '').trim().isNotEmpty)
        'pharmacyId': TenantContext.instance.pharmacyId,
    });
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
  }) {
    TenantContext.instance.assertWritable();
    if (!AppPermissions.roleDefaults.containsKey(role)) {
      throw ArgumentError.value(role, 'role', 'Unsupported role.');
    }
    final actorId = FirebaseAuth.instance.currentUser?.uid;
    if (!TenantContext.instance.isSuperAdmin && actorId != null && actorId == userId) {
      throw StateError('You cannot change your own access. Ask Super Admin.');
    }
    if (displayName.trim().isEmpty || email.trim().isEmpty) {
      throw ArgumentError('Name and email are required.');
    }
    final tenantId = (pharmacyId ?? TenantContext.instance.pharmacyId ?? '').trim();
    final resolved = AppPermissions.resolvedPermissions(role, permissions);
    return _firestore.collection(FirestoreCollections.users).doc(userId).set({
      'displayName': displayName.trim(),
      'email': email.trim(),
      'phone': (phone ?? '').trim(),
      'role': role,
      'permissions': resolved,
      'isActive': isActive,
      if ((employeeCode ?? '').trim().isNotEmpty) 'employeeCode': employeeCode!.trim(),
      if (role != 'super_admin' && tenantId.isNotEmpty) 'pharmacyId': tenantId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> createLoginAndProfile({
    required String displayName,
    required String email,
    required String password,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
    String? pharmacyId,
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
    final uid = await AuthAccountService().createAuthUser(email: mail, password: password);
    await createProfile(
      userId: uid,
      displayName: displayName,
      email: email.trim().toLowerCase(),
      role: role,
      permissions: permissions,
      isActive: isActive,
      pharmacyId: shopId,
    );
    return uid;
  }

  Future<void> createProfile({
    required String userId,
    required String displayName,
    required String email,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
    String? pharmacyId,
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
      'role': role,
      'permissions': AppPermissions.resolvedPermissions(role, permissions),
      'isActive': isActive,
      if (role != 'super_admin') 'pharmacyId': tenantId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteProfile(String userId) {
    if (!TenantContext.instance.isSuperAdmin) {
      TenantContext.instance.assertWritable();
    }
    return _firestore.collection(FirestoreCollections.users).doc(userId).delete();
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
}
