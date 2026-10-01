import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_collections.dart';

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.isActive,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final bool isActive;
  final DateTime? createdAt;
}

class AnnouncementService {
  AnnouncementService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<Announcement>> watchAll() {
    return _firestore.collection(FirestoreCollections.announcements).snapshots().map((snapshot) {
      final rows = snapshot.docs.map((doc) {
        final data = doc.data();
        return Announcement(
          id: doc.id,
          title: data['title'] as String? ?? '',
          body: data['body'] as String? ?? '',
          isActive: data['isActive'] != false,
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
      rows.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
      return rows;
    });
  }

  Stream<List<Announcement>> watchActive() {
    return watchAll().map((rows) => rows.where((row) => row.isActive).toList());
  }

  Future<void> publish({required String title, required String body}) async {
    await _firestore.collection(FirestoreCollections.announcements).add({
      'title': title.trim(),
      'body': body.trim(),
      'isActive': true,
      'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setActive(String id, bool isActive) async {
    await _firestore.collection(FirestoreCollections.announcements).doc(id).set({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _firestore.collection(FirestoreCollections.announcements).doc(id).delete();
  }
}
