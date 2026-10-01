import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_collections.dart';

class LicensePayment {
  const LicensePayment({
    required this.id,
    required this.pharmacyId,
    required this.pharmacyName,
    required this.customerEmail,
    required this.amountTzs,
    required this.method,
    required this.reference,
    required this.status,
    this.note,
    this.verifiedBy,
    this.createdAt,
  });

  final String id;
  final String pharmacyId;
  final String pharmacyName;
  final String customerEmail;
  final int amountTzs;
  final String method;
  final String reference;
  final String status;
  final String? note;
  final String? verifiedBy;
  final DateTime? createdAt;
}

class PaymentService {
  PaymentService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<LicensePayment>> watch() {
    return _firestore.collection(FirestoreCollections.licensePayments).snapshots().map((snapshot) {
      final rows = snapshot.docs.map((doc) {
        final data = doc.data();
        return LicensePayment(
          id: doc.id,
          pharmacyId: data['pharmacyId'] as String? ?? '',
          pharmacyName: data['pharmacyName'] as String? ?? '',
          customerEmail: data['customerEmail'] as String? ?? '',
          amountTzs: (data['amountTzs'] as num?)?.toInt() ?? 0,
          method: data['method'] as String? ?? 'manual',
          reference: data['reference'] as String? ?? '',
          status: data['status'] as String? ?? 'pending',
          note: data['note'] as String?,
          verifiedBy: data['verifiedBy'] as String?,
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
      rows.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
      return rows;
    });
  }

  Future<void> create({
    required String pharmacyId,
    required String pharmacyName,
    required String customerEmail,
    required int amountTzs,
    required String method,
    required String reference,
    String? note,
  }) async {
    await _firestore.collection(FirestoreCollections.licensePayments).add({
      'pharmacyId': pharmacyId,
      'pharmacyName': pharmacyName,
      'customerEmail': customerEmail.trim().toLowerCase(),
      'amountTzs': amountTzs,
      'method': method,
      'reference': reference.trim(),
      'note': note?.trim() ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setStatus(String paymentId, String status) async {
    await _firestore.collection(FirestoreCollections.licensePayments).doc(paymentId).set({
      'status': status,
      'verifiedBy': FirebaseAuth.instance.currentUser?.email ?? '',
      'verifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String paymentId) async {
    await _firestore.collection(FirestoreCollections.licensePayments).doc(paymentId).delete();
  }
}
