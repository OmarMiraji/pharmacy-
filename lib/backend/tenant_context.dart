import 'package:cloud_firestore/cloud_firestore.dart';

class TenantContext {
  TenantContext._();
  static final TenantContext instance = TenantContext._();

  String? pharmacyId;
  String? pharmacyName;
  bool isSuperAdmin = false;
  bool readOnly = false;
  bool blocked = false;
  String? lockMessage;

  void bind({
    required bool isSuperAdmin,
    String? pharmacyId,
    String? pharmacyName,
    required bool readOnly,
    bool blocked = false,
    String? lockMessage,
  }) {
    this.isSuperAdmin = isSuperAdmin;
    this.pharmacyId = pharmacyId;
    this.pharmacyName = pharmacyName;
    this.blocked = blocked && !isSuperAdmin;
    this.readOnly = (readOnly || this.blocked) && !isSuperAdmin;
    this.lockMessage = lockMessage;
  }

  void clear() {
    pharmacyId = null;
    pharmacyName = null;
    isSuperAdmin = false;
    readOnly = false;
    blocked = false;
    lockMessage = null;
  }

  String requirePharmacyId() {
    final id = pharmacyId?.trim() ?? '';
    if (id.isEmpty) {
      throw StateError('This account is not linked to a pharmacy.');
    }
    return id;
  }

  void assertWritable() {
    if (isSuperAdmin) return;
    if (blocked) {
      throw StateError(
        lockMessage ??
            'The free trial has ended. Activate a valid token after payment to use this pharmacy.',
      );
    }
    if (readOnly) {
      throw StateError(
        lockMessage ??
            'Subscription for this pharmacy has ended. You can view records but cannot add or change data.',
      );
    }
  }

  Map<String, dynamic> withTenant(Map<String, dynamic> data) {
    return {
      ...data,
      'pharmacyId': requirePharmacyId(),
    };
  }

  Query<Map<String, dynamic>> scoped(CollectionReference<Map<String, dynamic>> collection) {
    return collection.where('pharmacyId', isEqualTo: requirePharmacyId());
  }
}
