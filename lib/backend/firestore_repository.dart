import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreRepository<T> {
  FirestoreRepository({required this.collection, required this.fromFirestore});

  final CollectionReference<Map<String, dynamic>> collection;
  final T Function(DocumentSnapshot<Map<String, dynamic>>) fromFirestore;

  Stream<List<T>> watchAll({bool activeOnly = false}) {
    Query<Map<String, dynamic>> query = collection;
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }
    return query.snapshots().map(
          (snapshot) => snapshot.docs.map(fromFirestore).toList(growable: false),
        );
  }

  Future<T?> getById(String id) async {
    final document = await collection.doc(id).get();
    return document.exists ? fromFirestore(document) : null;
  }

  Future<DocumentReference<Map<String, dynamic>>> create(
    Map<String, dynamic> data,
  ) {
    final now = FieldValue.serverTimestamp();
    return collection.add({
      ...data,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> update(String id, Map<String, dynamic> data) {
    return collection.doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archive(String id) {
    return collection.doc(id).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
