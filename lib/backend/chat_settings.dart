import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';

class ChatAssistantSettings {
  const ChatAssistantSettings({
    this.apiUrl = '',
    this.apiKey = '',
    this.model = '',
  });

  final String apiUrl;
  final String apiKey;
  final String model;

  bool get hasRemoteApi => apiUrl.trim().isNotEmpty;
}

class ChatSettingsService {
  ChatSettingsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String _docId() => 'chat_${TenantContext.instance.requirePharmacyId()}';

  Future<ChatAssistantSettings> load() async {
    try {
      final snapshot = await _firestore.collection(FirestoreCollections.settings).doc(_docId()).get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      return ChatAssistantSettings(
        apiUrl: (data['apiUrl'] as String? ?? '').trim(),
        apiKey: (data['apiKey'] as String? ?? '').trim(),
        model: (data['model'] as String? ?? '').trim(),
      );
    } catch (_) {
      return const ChatAssistantSettings();
    }
  }

  Future<void> save(ChatAssistantSettings settings) async {
    TenantContext.instance.assertWritable();
    await _firestore.collection(FirestoreCollections.settings).doc(_docId()).set(
          TenantContext.instance.withTenant({
            'apiUrl': settings.apiUrl.trim(),
            'apiKey': settings.apiKey.trim(),
            'model': settings.model.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          SetOptions(merge: true),
        );
  }
}
