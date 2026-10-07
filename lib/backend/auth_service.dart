import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_account_service.dart';
import 'firestore_collections.dart';
import 'login_log_service.dart';
import 'medicine_service.dart';
import 'permissions.dart';
import 'pharmacy_service.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class AuthSignals extends ChangeNotifier {
  AuthSignals._();
  static final instance = AuthSignals._();

  void bump() {
    notifyListeners();
  }
}

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  static String? workspaceError;

  Future<void> confirmPassword(String password) async {
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null || email.trim().isEmpty) {
      throw StateError('You are not signed in.');
    }
    if (password.isEmpty) throw ArgumentError('Password is required.');
    try {
      final credential = EmailAuthProvider.credential(email: email, password: password);
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'wrong-password' || error.code == 'invalid-credential') {
        throw StateError('Wrong password.');
      }
      throw StateError(error.message ?? 'Could not confirm password.');
    }
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final next = newPassword.trim();
    if (next.length < 6) throw ArgumentError('New password must be at least 6 characters.');
    await confirmPassword(currentPassword);
    try {
      await currentUser!.updatePassword(next);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'weak-password') {
        throw StateError('Choose a stronger password (at least 6 characters).');
      }
      throw StateError(error.message ?? 'Could not change password.');
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await AuthAccountService().sendPasswordReset(email);
  }

  Future<void> signOut() async {
    try {
      await LoginLogService().recordLogout();
    } catch (_) {}
    MedicineService.dropSharedListeners();
    TenantContext.instance.clear();
    await _auth.signOut();
    AuthSignals.instance.bump();
  }

  Future<UserCredential> signIn({required String email, required String password}) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } finally {
      AuthSignals.instance.bump();
    }
  }

  Future<String?> currentUserRole() async {
    final user = currentUser;
    if (user == null) return null;

    final token = await user.getIdTokenResult();
    final claimRole = token.claims?['role'];
    if (claimRole is String && claimRole.trim().isNotEmpty) {
      return claimRole.trim().toLowerCase();
    }

    final snapshot = await FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .get();

    if (!snapshot.exists) return null;
    final profile = UserProfile.fromFirestore(snapshot);
    return profile.role.trim().toLowerCase();
  }

  Future<UserProfile?> currentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final userDocRef = FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user.uid);
    final snapshot = await _readUserDocument(userDocRef);

    final firestoreRole = snapshot.exists ? UserProfile.fromFirestore(snapshot).role.trim().toLowerCase() : '';
    final isRootAccount = firestoreRole == 'super_admin';

    if (snapshot.exists) {
      final profile = UserProfile.fromFirestore(snapshot);
      if (isRootAccount) {
        final seed = UserProfile(
          id: user.uid,
          employeeCode: 'ROOT',
          displayName: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : (profile.displayName.isNotEmpty ? profile.displayName : 'Developer'),
          email: user.email ?? profile.email,
          role: 'super_admin',
          permissions: {for (final permission in AppPermissions.all) permission: true},
          isActive: true,
          pharmacyId: profile.pharmacyId,
        );
        await userDocRef.set({
          'displayName': seed.displayName,
          'email': seed.email,
          'role': seed.role,
          'permissions': seed.permissions,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return seed;
      }

      final ownedPharmacyId = await PharmacyService().findOwnedPharmacyId(
        email: user.email ?? profile.email,
        userId: user.uid,
        pharmacyIdHint: profile.pharmacyId,
      );
      const staffRoles = {'pharmacist', 'cashier', 'storekeeper'};
      final isShopAdmin = profile.role == 'admin'
          || (ownedPharmacyId ?? '').trim().isNotEmpty
          || ((profile.pharmacyId ?? '').trim().isNotEmpty && !staffRoles.contains(profile.role));
      if (isShopAdmin) {
        final pharmacyId = (ownedPharmacyId ?? profile.pharmacyId ?? '').trim();
        final upgraded = UserProfile(
          id: profile.id,
          employeeCode: profile.employeeCode,
          displayName: profile.displayName,
          email: (user.email ?? profile.email).trim(),
          role: 'admin',
          permissions: AppPermissions.resolvedPermissions('admin'),
          isActive: true,
          phone: profile.phone,
          pharmacyId: pharmacyId.isEmpty ? profile.pharmacyId : pharmacyId,
        );
        try {
          await userDocRef.set({
            'displayName': upgraded.displayName,
            'email': upgraded.email,
            'role': upgraded.role,
            'permissions': upgraded.permissions,
            'isActive': true,
            if ((upgraded.pharmacyId ?? '').trim().isNotEmpty) 'pharmacyId': upgraded.pharmacyId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } on FirebaseException {
          // Rules may still be catching up; the in-memory profile already has full shop access.
        }
        return upgraded;
      }
      return profile;
    }

    if (isRootAccount) {
      final seed = UserProfile(
        id: user.uid,
        employeeCode: 'ROOT',
        displayName: user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : 'Developer',
        email: user.email ?? '',
        role: 'super_admin',
        permissions: {for (final permission in AppPermissions.all) permission: true},
        isActive: true,
      );
      await userDocRef.set({
        'displayName': seed.displayName,
        'email': seed.email,
        'role': seed.role,
        'permissions': seed.permissions,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return seed;
    }

    return null;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readUserDocument(
    DocumentReference<Map<String, dynamic>> userDocRef,
  ) async {
    try {
      return await userDocRef.get();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      await currentUser?.getIdToken();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return userDocRef.get();
    }
  }

  Future<void> updateUserAccess({
    required String userId,
    required String role,
    required Map<String, bool> permissions,
    required bool isActive,
  }) {
    return FirebaseFirestore.instance.collection(FirestoreCollections.users).doc(userId).update({
      'role': role,
      'permissions': permissions,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
