import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';
import 'user_profile.dart';

class LoginEvent {
  const LoginEvent({
    required this.id,
    required this.event,
    required this.actorUid,
    required this.actorEmail,
    required this.actorName,
    required this.role,
    required this.pharmacyId,
    required this.pharmacyName,
    this.createdAt,
  });

  final String id;
  final String event;
  final String actorUid;
  final String actorEmail;
  final String actorName;
  final String role;
  final String pharmacyId;
  final String pharmacyName;
  final DateTime? createdAt;

  bool get isLogin => event == 'login';
}

class _OpenSession {
  const _OpenSession({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.pharmacyId,
    required this.pharmacyName,
  });

  final String uid;
  final String email;
  final String name;
  final String role;
  final String pharmacyId;
  final String pharmacyName;
}

class LoginLogService {
  LoginLogService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static _OpenSession? _open;

  Future<void> recordLogin(UserProfile profile) async {
    final user = _auth.currentUser;
    if (user == null || _open?.uid == user.uid) return;
    final session = _OpenSession(
      uid: user.uid,
      email: (user.email ?? profile.email).trim(),
      name: profile.displayName.trim().isNotEmpty
          ? profile.displayName.trim()
          : (user.displayName ?? '').trim(),
      role: profile.role.trim(),
      pharmacyId: (profile.pharmacyId ?? TenantContext.instance.pharmacyId ?? '').trim(),
      pharmacyName: (TenantContext.instance.pharmacyName ?? '').trim(),
    );
    await _add(session, 'login');
    _open = session;
  }

  Future<void> recordLogout() async {
    final user = _auth.currentUser;
    final session = _open;
    if (user == null || session == null || session.uid != user.uid) return;
    await _add(session, 'logout');
    _open = null;
  }

  /// Writes a sign-out for a Firebase session left open when the app last closed.
  Future<void> closePreviousSession() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final snapshot = await _firestore.collection(FirestoreCollections.users).doc(user.uid).get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final pharmacyId = (data['pharmacyId'] as String?)?.trim() ?? '';
    var pharmacyName = '';
    if (pharmacyId.isNotEmpty) {
      final shop = await _firestore.collection(FirestoreCollections.pharmacies).doc(pharmacyId).get();
      pharmacyName = (shop.data()?['name'] as String?)?.trim() ?? '';
    }
    final name = (data['displayName'] as String?)?.trim() ?? '';
    await _add(
      _OpenSession(
        uid: user.uid,
        email: (user.email ?? (data['email'] as String?) ?? '').trim(),
        name: name,
        role: (data['role'] as String?)?.trim() ?? '',
        pharmacyId: pharmacyId,
        pharmacyName: pharmacyName,
      ),
      'logout',
    );
  }

  Stream<List<LoginEvent>> watch({String? pharmacyId, int limit = 200}) {
    Query<Map<String, dynamic>> query = _firestore.collection(FirestoreCollections.loginSessions);
    final shopId = pharmacyId?.trim() ?? '';
    if (shopId.isNotEmpty) {
      query = query.where('pharmacyId', isEqualTo: shopId);
    }
    return query.orderBy('createdAt', descending: true).limit(limit).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return LoginEvent(
          id: doc.id,
          event: data['event'] as String? ?? '',
          actorUid: data['actorUid'] as String? ?? '',
          actorEmail: data['actorEmail'] as String? ?? '',
          actorName: data['actorName'] as String? ?? '',
          role: data['role'] as String? ?? '',
          pharmacyId: data['pharmacyId'] as String? ?? '',
          pharmacyName: data['pharmacyName'] as String? ?? '',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
    });
  }

  Future<void> _add(_OpenSession session, String event) async {
    await _firestore.collection(FirestoreCollections.loginSessions).add({
      'event': event,
      'actorUid': session.uid,
      'actorEmail': session.email,
      'actorName': session.name,
      'role': session.role,
      'pharmacyId': session.pharmacyId,
      'pharmacyName': session.pharmacyName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
