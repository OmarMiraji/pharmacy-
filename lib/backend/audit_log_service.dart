import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_collections.dart';

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.actorEmail,
    this.pharmacyId,
    this.pharmacyName,
    this.detail,
    this.createdAt,
  });

  final String id;
  final String action;
  final String actorUid;
  final String actorEmail;
  final String? pharmacyId;
  final String? pharmacyName;
  final String? detail;
  final DateTime? createdAt;
}

class AuditLogService {
  AuditLogService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> record({
    required String action,
    String? pharmacyId,
    String? pharmacyName,
    String? detail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await _firestore.collection(FirestoreCollections.auditLogs).add({
      'action': action,
      'actorUid': user?.uid ?? '',
      'actorEmail': user?.email ?? '',
      'pharmacyId': pharmacyId ?? '',
      'pharmacyName': pharmacyName ?? '',
      'detail': detail ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AuditEntry>> watch({int limit = 80}) {
    return _firestore.collection(FirestoreCollections.auditLogs).limit(limit).snapshots().map((snapshot) {
      final rows = snapshot.docs.map((doc) {
        final data = doc.data();
        return AuditEntry(
          id: doc.id,
          action: data['action'] as String? ?? '',
          actorUid: data['actorUid'] as String? ?? '',
          actorEmail: data['actorEmail'] as String? ?? '',
          pharmacyId: data['pharmacyId'] as String?,
          pharmacyName: data['pharmacyName'] as String?,
          detail: data['detail'] as String?,
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
      rows.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
      return rows;
    });
  }
}
