import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecurityAlert {
  const SecurityAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.pharmacyName,
    required this.actorName,
    required this.actorEmail,
    required this.read,
    required this.emailed,
    this.createdAt,
  });

  factory SecurityAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    String text(String key) => (data[key] as String? ?? '').trim();
    return SecurityAlert(
      id: doc.id,
      type: text('type'),
      severity: text('severity'),
      title: text('title'),
      message: text('message'),
      pharmacyName: text('pharmacyName'),
      actorName: text('actorName'),
      actorEmail: text('actorEmail'),
      read: data['read'] == true,
      emailed: data['emailed'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String type;
  final String severity;
  final String title;
  final String message;
  final String pharmacyName;
  final String actorName;
  final String actorEmail;
  final bool read;
  final bool emailed;
  final DateTime? createdAt;

  bool get isCritical => severity == 'critical';

  SecurityAlert copyRead() => SecurityAlert(
        id: id,
        type: type,
        severity: severity,
        title: title,
        message: message,
        pharmacyName: pharmacyName,
        actorName: actorName,
        actorEmail: actorEmail,
        read: true,
        emailed: emailed,
        createdAt: createdAt,
      );
}

class SecurityAlertService {
  SecurityAlertService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const pageSize = 30;

  CollectionReference<Map<String, dynamic>> get _alerts => _firestore.collection('security_alerts');

  /// Listens to unread alerts only, so reads stay at zero while nothing new happens.
  Stream<List<SecurityAlert>> watchUnread() {
    return _alerts.where('read', isEqualTo: false).limit(50).snapshots().map((snap) {
      final rows = snap.docs.map(SecurityAlert.fromDoc).toList();
      rows.sort((a, b) => (b.createdAt ?? DateTime(2100)).compareTo(a.createdAt ?? DateTime(2100)));
      return rows;
    });
  }

  Future<(List<SecurityAlert>, DocumentSnapshot<Map<String, dynamic>>?, bool)> fetch({
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    var query = _alerts.orderBy('createdAt', descending: true).limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snap = await query.get();
    return (
      snap.docs.map(SecurityAlert.fromDoc).toList(),
      snap.docs.isEmpty ? after : snap.docs.last,
      snap.docs.length == pageSize,
    );
  }

  Map<String, dynamic> get _readPatch => {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
        'readBy': FirebaseAuth.instance.currentUser?.email ?? '',
      };

  Future<void> markRead(String id) => _alerts.doc(id).update(_readPatch);

  Future<void> markAllRead(Iterable<String> ids) async {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 400) {
      final batch = _firestore.batch();
      for (final id in list.skip(i).take(400)) {
        batch.update(_alerts.doc(id), _readPatch);
      }
      await batch.commit();
    }
  }
}
