import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_collections.dart';
import 'pharmacy.dart';
import 'tenant_context.dart';

enum PharmacyAccess { full, readOnly, blocked }

class SubscriptionState {
  const SubscriptionState({
    required this.status,
    required this.plan,
    required this.trialEndsAt,
    required this.expiresAt,
    required this.isUnlocked,
    required this.isTrial,
    required this.message,
    this.startsAt,
    this.access = PharmacyAccess.full,
  });

  final String status;
  final String plan;
  final DateTime? trialEndsAt;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool isUnlocked;
  final bool isTrial;
  final String message;
  final PharmacyAccess access;

  bool get hasExpired {
    final expiry = expiresAt ?? trialEndsAt;
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  bool get canWrite => access == PharmacyAccess.full;
  bool get canRead => access != PharmacyAccess.blocked;
  bool get isReadOnly => access == PharmacyAccess.readOnly;
  bool get isBlocked => access == PharmacyAccess.blocked;

  DateTime? get licenseEndsAt => expiresAt ?? trialEndsAt;

  int get daysRemaining {
    final expiry = licenseEndsAt;
    if (expiry == null) return 0;
    final now = DateTime.now();
    if (!now.isBefore(expiry)) return 0;
    final wholeDays = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    return wholeDays < 0 ? 0 : wholeDays;
  }

  String get trialCountdownLabel {
    if (!isTrial) return '';
    if (isBlocked || hasExpired) return 'Trial ended · 0 days remaining';
    final days = daysRemaining;
    if (days <= 0) return 'Trial ends today';
    if (days == 1) return '1 day remaining in your free trial';
    return '$days days remaining in your free trial';
  }
}

class ActivationCodeRecord {
  const ActivationCodeRecord({
    required this.code,
    required this.plan,
    required this.durationDays,
    required this.isUsed,
    this.ownerEmail,
    this.note,
    this.pharmacyId,
    this.usedByPharmacyId,
    this.usedAt,
    this.createdAt,
  });

  final String code;
  final String plan;
  final int durationDays;
  final bool isUsed;
  final String? ownerEmail;
  final String? note;
  final String? pharmacyId;
  final String? usedByPharmacyId;
  final DateTime? usedAt;
  final DateTime? createdAt;

  factory ActivationCodeRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ActivationCodeRecord(
      code: (data['code'] as String?) ?? doc.id,
      plan: (data['plan'] as String?) ?? 'monthly',
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 30,
      isUsed: data['isUsed'] == true,
      ownerEmail: data['ownerEmail'] as String?,
      note: data['note'] as String?,
      pharmacyId: data['pharmacyId'] as String?,
      usedByPharmacyId: data['usedByPharmacyId'] as String?,
      usedAt: (data['usedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class SubscriptionService {
  SubscriptionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const planDurations = <String, int>{
    'monthly': 30,
    'quarterly': 90,
    'biannual': 180,
    'yearly': 365,
  };

  final FirebaseFirestore _firestore;
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static SubscriptionState licenseFromPharmacy(PharmacyRecord? pharmacy) {
    if (pharmacy == null) {
      return const SubscriptionState(
        status: 'locked',
        plan: 'trial',
        trialEndsAt: null,
        expiresAt: null,
        isUnlocked: false,
        isTrial: true,
        access: PharmacyAccess.blocked,
        message: 'Pharmacy license was not found.',
      );
    }
    final now = DateTime.now();
    final expiry = pharmacy.expiresAt ?? pharmacy.trialEndsAt;
    final notStarted = pharmacy.startsAt != null && now.isBefore(pharmacy.startsAt!);
    final expired = expiry != null && now.isAfter(expiry);
    final trial = pharmacy.isTrial || pharmacy.plan == 'trial' || pharmacy.status == 'trial';
    final PharmacyAccess access;
    if (!pharmacy.isUnlocked || notStarted) {
      access = PharmacyAccess.blocked;
    } else if (expired) {
      access = trial ? PharmacyAccess.blocked : PharmacyAccess.readOnly;
    } else {
      access = PharmacyAccess.full;
    }

    String message = trial ? 'Pharmacy free trial is active. You can view and enter data.' : 'Pharmacy license is active.';
    if (notStarted) {
      message = 'License starts on ${pharmacy.startsAt!.day}/${pharmacy.startsAt!.month}/${pharmacy.startsAt!.year}. Enter a valid token after the start date.';
    } else if (expired && trial) {
      message = 'The free trial has ended · 0 days remaining. Subscribe and activate a valid token to continue.';
    } else if (expired) {
      message = 'Paid subscription has ended. You can view existing records only until a new token is activated.';
    } else if (!pharmacy.isUnlocked) {
      message = 'This pharmacy is locked. Enter a valid activation token after payment.';
    } else if (trial && expiry != null) {
      final days = DateTime(expiry.year, expiry.month, expiry.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      if (days <= 0) {
        message = 'Trial ends today. Subscribe to keep full access.';
      } else if (days == 1) {
        message = '1 day remaining in your free trial.';
      } else {
        message = '$days days remaining in your free trial.';
      }
    }
    return SubscriptionState(
      status: expired ? 'expired' : pharmacy.status,
      plan: pharmacy.plan,
      trialEndsAt: pharmacy.trialEndsAt,
      startsAt: pharmacy.startsAt,
      expiresAt: pharmacy.expiresAt,
      isUnlocked: access == PharmacyAccess.full,
      isTrial: trial,
      access: access,
      message: message,
    );
  }

  String generateToken() {
    final random = Random.secure();
    String block(int length) => List.generate(
          length,
          (_) => _codeAlphabet[random.nextInt(_codeAlphabet.length)],
        ).join();
    return 'PHY-${block(4)}-${block(4)}-${block(4)}';
  }

  Future<bool> activateWithCode(String code) async {
    final pharmacyId = TenantContext.instance.pharmacyId;
    if (pharmacyId == null || pharmacyId.isEmpty || code.trim().isEmpty) return false;

    final normalized = _normalizeCode(code);
    final codeRef = _firestore.collection(FirestoreCollections.subscriptionCodes).doc(normalized);
    final codeSnap = await codeRef.get();
    if (!codeSnap.exists) return false;
    final codeData = codeSnap.data() ?? <String, dynamic>{};
    if (codeData['isUsed'] == true) return false;
    final assignedPharmacy = (codeData['pharmacyId'] as String?)?.trim();
    if (assignedPharmacy != null && assignedPharmacy.isNotEmpty && assignedPharmacy != pharmacyId) {
      return false;
    }

    final plan = (codeData['plan'] as String?) ?? 'monthly';
    final durationDays = (codeData['durationDays'] as num?)?.toInt() ?? planDurations[plan] ?? 30;
    final startsAt = (codeData['startsAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final expiry = startsAt.add(Duration(days: durationDays));
    final pharmacyRef = _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId);

    await _firestore.runTransaction((transaction) async {
      final freshCode = await transaction.get(codeRef);
      if (!freshCode.exists || freshCode.data()?['isUsed'] == true) {
        throw StateError('This token is no longer valid.');
      }
      transaction.set(
        pharmacyRef,
        {
          'status': 'active',
          'plan': plan,
          'isTrial': false,
          'isUnlocked': true,
          'startsAt': Timestamp.fromDate(startsAt),
          'expiresAt': Timestamp.fromDate(expiry),
          'trialEndsAt': null,
          'activationCode': normalized,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      transaction.update(codeRef, {
        'isUsed': true,
        'usedByPharmacyId': pharmacyId,
        'usedByUserId': FirebaseAuth.instance.currentUser?.uid,
        'usedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return true;
  }

  Future<String> createActivationToken({
    required String plan,
    required int durationDays,
    DateTime? startsAt,
    String? pharmacyId,
    String? ownerEmail,
    String? note,
  }) async {
    final code = generateToken();
    await _firestore.collection(FirestoreCollections.subscriptionCodes).doc(code).set({
      'code': code,
      'plan': plan,
      'durationDays': durationDays,
      'startsAt': startsAt == null ? null : Timestamp.fromDate(startsAt),
      'isUsed': false,
      'pharmacyId': pharmacyId?.trim() ?? '',
      'ownerEmail': ownerEmail?.trim() ?? '',
      'note': note?.trim() ?? '',
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  Stream<List<ActivationCodeRecord>> watchCodes() {
    return _firestore.collection(FirestoreCollections.subscriptionCodes).snapshots().map((snapshot) {
      final codes = snapshot.docs.map(ActivationCodeRecord.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
      return codes;
    });
  }

  Future<void> grantLicense({
    required String pharmacyId,
    required String plan,
    required DateTime startsAt,
    required DateTime expiresAt,
    String? note,
    String? paymentReference,
  }) async {
    final id = pharmacyId.trim();
    if (id.isEmpty) throw ArgumentError('Pharmacy is required.');
    await _firestore.collection(FirestoreCollections.pharmacies).doc(id).set({
      'status': 'active',
      'plan': plan,
      'isTrial': false,
      'isUnlocked': true,
      'startsAt': Timestamp.fromDate(startsAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'trialEndsAt': null,
      'note': note?.trim() ?? '',
      'paymentReference': paymentReference?.trim() ?? '',
      'grantedBy': FirebaseAuth.instance.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> extendLicense({
    required String pharmacyId,
    required int extraDays,
  }) async {
    final docRef = _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId);
    final snapshot = await docRef.get();
    final currentExpiry = (snapshot.data()?['expiresAt'] as Timestamp?)?.toDate();
    final base = currentExpiry != null && currentExpiry.isAfter(DateTime.now())
        ? currentExpiry
        : DateTime.now();
    await docRef.set({
      'status': 'active',
      'isUnlocked': true,
      'isTrial': false,
      'expiresAt': Timestamp.fromDate(base.add(Duration(days: extraDays))),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> lockLicense(String pharmacyId) async {
    await _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId).set({
      'status': 'locked',
      'isUnlocked': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unlockLicense(String pharmacyId) async {
    await _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId).set({
      'status': 'active',
      'isUnlocked': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _normalizeCode(String code) => code.trim().toUpperCase().replaceAll(' ', '');
}
