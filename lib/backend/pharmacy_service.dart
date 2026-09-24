import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_account_service.dart';
import 'firestore_collections.dart';
import 'permissions.dart';
import 'pharmacy.dart';
import 'subscription_service.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class PharmacySession {
  const PharmacySession({
    required this.pharmacy,
    required this.license,
    required this.readOnly,
    this.blocked = false,
  });

  final PharmacyRecord? pharmacy;
  final SubscriptionState license;
  final bool readOnly;
  final bool blocked;
}

class ShopProvision {
  const ShopProvision({
    required this.pharmacyId,
    required this.adminUid,
    required this.adminEmail,
  });

  final String pharmacyId;
  final String adminUid;
  final String adminEmail;
}

class PharmacyService {
  PharmacyService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _legacyCollections = [
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

  Stream<List<PharmacyRecord>> watchPharmacies() {
    return _firestore.collection(FirestoreCollections.pharmacies).snapshots().map((snapshot) {
      final pharmacies = snapshot.docs.map(PharmacyRecord.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return pharmacies;
    });
  }

  Future<PharmacyRecord?> getPharmacy(String pharmacyId) async {
    try {
      final snapshot = await _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId).get();
      if (!snapshot.exists) return null;
      return PharmacyRecord.fromDoc(snapshot);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  Future<ShopProvision> createPharmacy({
    required String name,
    String? ownerEmail,
    String? ownerUserId,
    String? ownerDisplayName,
    String? ownerPassword,
    int trialDays = 7,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Pharmacy name is required.');
    var ownerId = (ownerUserId ?? '').trim();
    final ownerMail = (ownerEmail ?? '').trim().toLowerCase();
    final password = ownerPassword ?? '';
    if (ownerMail.isEmpty || password.length < 6) {
      throw ArgumentError('Shop admin email and a password of at least 6 characters are required.');
    }
    if (ownerId.isEmpty) {
      ownerId = await AuthAccountService().createAuthUser(
        email: ownerMail,
        password: password,
      );
    }
    final trialEndsAt = DateTime.now().add(Duration(days: trialDays));
    final doc = _firestore.collection(FirestoreCollections.pharmacies).doc();
    try {
      await doc.set({
        'name': trimmed,
        'ownerEmail': ownerMail,
        'ownerUserId': ownerId,
        'status': 'trial',
        'plan': 'trial',
        'isTrial': true,
        'isUnlocked': true,
        'startsAt': Timestamp.fromDate(DateTime.now()),
        'trialEndsAt': Timestamp.fromDate(trialEndsAt),
        'expiresAt': Timestamp.fromDate(trialEndsAt),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await attachPharmacyAdmin(
        pharmacyId: doc.id,
        ownerUserId: ownerId,
        ownerEmail: ownerMail,
        ownerDisplayName: ownerDisplayName,
      );
    } catch (error) {
      throw StateError(
        'Firebase login was created (uid $ownerId) but the shop record failed: $error. Use Create/repair admin login on this shop, or delete the incomplete shop and try again.',
      );
    }
    return ShopProvision(pharmacyId: doc.id, adminUid: ownerId, adminEmail: ownerMail);
  }

  Future<void> provisionAdminLogin({
    required String pharmacyId,
    required String email,
    required String password,
    String? displayName,
  }) async {
    final id = pharmacyId.trim();
    final mail = email.trim().toLowerCase();
    if (id.isEmpty) throw ArgumentError('Pharmacy is required.');
    final uid = await AuthAccountService().createAuthUser(email: mail, password: password);
    await attachPharmacyAdmin(
      pharmacyId: id,
      ownerUserId: uid,
      ownerEmail: mail,
      ownerDisplayName: displayName,
    );
    await _firestore.collection(FirestoreCollections.pharmacies).doc(id).set({
      'ownerEmail': mail,
      'ownerUserId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePharmacyProfile({
    required String pharmacyId,
    required String name,
    String? phone,
    String? address,
    String? note,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Pharmacy name is required.');
    TenantContext.instance.assertWritable();
    await _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId).set({
      'name': trimmed,
      'phone': phone?.trim() ?? '',
      'address': address?.trim() ?? '',
      'note': note?.trim() ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (TenantContext.instance.pharmacyId == pharmacyId) {
      TenantContext.instance.pharmacyName = trimmed;
    }
  }

  Future<void> deletePharmacy(String pharmacyId) async {
    final id = pharmacyId.trim();
    if (id.isEmpty) throw ArgumentError('Pharmacy is required.');
    await _firestore.collection(FirestoreCollections.pharmacies).doc(id).delete();
  }

  Future<PharmacySession> bindSession(UserProfile profile) async {
    final tenant = TenantContext.instance;
    var linkedId = (profile.pharmacyId ?? '').trim();
    if (linkedId.isEmpty && !profile.isSuperAdmin) {
      linkedId = await findOwnedPharmacyId(email: profile.email, userId: profile.id) ?? '';
    }
    if (linkedId.isNotEmpty && !profile.isSuperAdmin) {
      try {
        await _firestore.collection(FirestoreCollections.users).doc(profile.id).set({
          'pharmacyId': linkedId,
          'role': (profile.role.trim().isEmpty || profile.role == 'admin') ? 'admin' : profile.role,
          'permissions': (profile.role.trim().isEmpty || profile.role == 'admin')
              ? AppPermissions.resolvedPermissions('admin')
              : AppPermissions.resolvedPermissions(profile.role, profile.permissions),
          'email': profile.email,
          'displayName': profile.displayName,
          'isActive': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } on FirebaseException {
        // Continue with in-memory tenant even if the profile write is delayed.
      }
    }

    if (profile.isSuperAdmin && linkedId.isEmpty) {
      tenant.bind(
        isSuperAdmin: true,
        pharmacyId: null,
        pharmacyName: 'System',
        readOnly: false,
        blocked: false,
        lockMessage: null,
      );
      return const PharmacySession(
        pharmacy: null,
        license: SubscriptionState(
          status: 'active',
          plan: 'system',
          trialEndsAt: null,
          expiresAt: null,
          isUnlocked: true,
          isTrial: false,
          access: PharmacyAccess.full,
          message: 'Super admin access.',
        ),
        readOnly: false,
      );
    }

    if (linkedId.isEmpty) {
      tenant.clear();
      throw StateError(
        'This account is not assigned to a pharmacy. Super admin must attach this Auth UID to a pharmacy before login.',
      );
    }

    final pharmacy = await getPharmacy(linkedId);
    if (pharmacy == null) {
      tenant.clear();
      throw StateError('Pharmacy $linkedId was not found or this account cannot open it.');
    }
    final license = SubscriptionService.licenseFromPharmacy(pharmacy);
    final blocked = !profile.isSuperAdmin && license.isBlocked;
    final readOnly = !profile.isSuperAdmin && license.isReadOnly;
    tenant.bind(
      isSuperAdmin: profile.isSuperAdmin,
      pharmacyId: pharmacy.id,
      pharmacyName: pharmacy.name,
      readOnly: readOnly,
      blocked: blocked,
      lockMessage: license.message,
    );
    return PharmacySession(
      pharmacy: pharmacy,
      license: license,
      readOnly: readOnly,
      blocked: blocked,
    );
  }

  Future<void> attachPharmacyAdmin({
    required String pharmacyId,
    required String ownerUserId,
    required String ownerEmail,
    String? ownerDisplayName,
  }) async {
    final uid = ownerUserId.trim();
    final email = ownerEmail.trim();
    if (uid.isEmpty) throw ArgumentError('Owner Firebase Auth UID is required.');
    if (email.isEmpty) throw ArgumentError('Owner email is required.');
    await _firestore.collection(FirestoreCollections.users).doc(uid).set({
      'displayName': (ownerDisplayName ?? '').trim().isEmpty ? email : ownerDisplayName!.trim(),
      'email': email.toLowerCase(),
      'role': 'admin',
      'permissions': AppPermissions.resolvedPermissions('admin'),
      'isActive': true,
      'pharmacyId': pharmacyId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> findOwnedPharmacyId({
    required String email,
    required String userId,
    String? pharmacyIdHint,
  }) async {
    try {
      final hint = (pharmacyIdHint ?? '').trim();
      if (hint.isNotEmpty) {
        final hinted = await _firestore.collection(FirestoreCollections.pharmacies).doc(hint).get();
        if (hinted.exists) {
          final data = hinted.data() ?? const <String, dynamic>{};
          final ownerId = (data['ownerUserId'] as String? ?? '').trim();
          final ownerEmail = (data['ownerEmail'] as String? ?? '').trim().toLowerCase();
          if (ownerId == userId || ownerEmail == email.trim().toLowerCase()) {
            return hinted.id;
          }
        }
      }
      final byOwner = await _firestore
          .collection(FirestoreCollections.pharmacies)
          .where('ownerUserId', isEqualTo: userId)
          .limit(1)
          .get();
      if (byOwner.docs.isNotEmpty) return byOwner.docs.first.id;
      final mail = email.trim();
      if (mail.isEmpty) return null;
      for (final candidate in {mail, mail.toLowerCase()}) {
        final byEmail = await _firestore
            .collection(FirestoreCollections.pharmacies)
            .where('ownerEmail', isEqualTo: candidate)
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) return byEmail.docs.first.id;
      }
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
    return null;
  }

  Future<void> _migrateLegacyData(String pharmacyId) async {
    try {
      for (final collection in _legacyCollections) {
        final snapshot = await _firestore.collection(collection).limit(400).get();
        final batch = _firestore.batch();
        var writes = 0;
        for (final doc in snapshot.docs) {
          final current = doc.data()['pharmacyId'];
          if (current is String && current.trim().isNotEmpty) continue;
          batch.set(doc.reference, {'pharmacyId': pharmacyId}, SetOptions(merge: true));
          writes++;
        }
        if (writes > 0) await batch.commit();
      }

      final users = await _firestore.collection(FirestoreCollections.users).limit(400).get();
      final batch = _firestore.batch();
      var writes = 0;
      for (final doc in users.docs) {
        final data = doc.data();
        if ((data['role'] as String?) == 'super_admin') continue;
        final current = data['pharmacyId'];
        if (current is String && current.trim().isNotEmpty) continue;
        batch.set(doc.reference, {'pharmacyId': pharmacyId}, SetOptions(merge: true));
        writes++;
      }
      if (writes > 0) await batch.commit();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
  }
}
