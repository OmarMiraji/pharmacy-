import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';

/// `security` events reach the super admin; every event is visible to the shop admin of that shop.
abstract final class ActivityLevel {
  static const shop = 'shop';
  static const security = 'security';
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.action,
    required this.level,
    required this.actorName,
    required this.actorEmail,
    required this.actorRole,
    required this.pharmacyId,
    required this.pharmacyName,
    required this.target,
    required this.detail,
    this.createdAt,
  });

  factory ActivityEntry.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    String text(String key) => (data[key] as String? ?? '').trim();
    return ActivityEntry(
      id: doc.id,
      action: text('action'),
      level: text('level'),
      actorName: text('actorName'),
      actorEmail: text('actorEmail'),
      actorRole: text('actorRole'),
      pharmacyId: text('pharmacyId'),
      pharmacyName: text('pharmacyName'),
      target: text('target'),
      detail: text('detail'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String action;
  final String level;
  final String actorName;
  final String actorEmail;
  final String actorRole;
  final String pharmacyId;
  final String pharmacyName;
  final String target;
  final String detail;
  final DateTime? createdAt;

  bool get isSecurity => level == ActivityLevel.security;
}

class ActivityPage {
  const ActivityPage(this.rows, this.cursor, {required this.hasMore});

  final List<ActivityEntry> rows;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class ActivityLogService {
  ActivityLogService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const pageSize = 30;
  static const keepDays = 180;

  CollectionReference<Map<String, dynamic>> get _logs => _firestore.collection(FirestoreCollections.activityLogs);

  /// Fire-and-forget: one write per important action, never blocks or fails the action itself.
  static void record(
    String action, {
    String level = ActivityLevel.shop,
    String? target,
    String? detail,
    String? pharmacyId,
    String? pharmacyName,
  }) {
    ActivityLogService()._write(
      action,
      level: level,
      target: target,
      detail: detail,
      pharmacyId: pharmacyId,
      pharmacyName: pharmacyName,
    );
  }

  Future<void> _write(
    String action, {
    required String level,
    String? target,
    String? detail,
    String? pharmacyId,
    String? pharmacyName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final tenant = TenantContext.instance;
      final shopId = (pharmacyId ?? tenant.pharmacyId ?? '').trim();
      if (shopId.isEmpty && !tenant.isSuperAdmin) return;
      final ownShop = shopId == (tenant.pharmacyId ?? '');
      await _logs.add({
        'action': action,
        'level': level,
        'actorUid': user.uid,
        'actorEmail': (user.email ?? '').trim().toLowerCase(),
        'actorName': tenant.actorName.isEmpty ? (user.email ?? '') : tenant.actorName,
        'actorRole': tenant.isSuperAdmin ? 'super_admin' : tenant.actorRole,
        'pharmacyId': shopId,
        'pharmacyName': (pharmacyName ?? (ownShop ? tenant.pharmacyName : null) ?? '').trim(),
        'target': _clip(target, 160),
        'detail': _clip(detail, 400),
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: keepDays))),
      });
    } catch (_) {}
  }

  static String _clip(String? value, int max) {
    final text = (value ?? '').trim();
    return text.length <= max ? text : '${text.substring(0, max - 1)}…';
  }

  /// One-time page reads (no live listeners) keep Firestore usage low.
  Future<ActivityPage> fetchShop(String pharmacyId, {DocumentSnapshot<Map<String, dynamic>>? after}) {
    return _page(_logs.where('pharmacyId', isEqualTo: pharmacyId.trim()), after);
  }

  Future<ActivityPage> fetchSecurity({DocumentSnapshot<Map<String, dynamic>>? after}) {
    return _page(_logs.where('level', isEqualTo: ActivityLevel.security), after);
  }

  Future<ActivityPage> _page(Query<Map<String, dynamic>> base, DocumentSnapshot<Map<String, dynamic>>? after) async {
    var query = base.orderBy('createdAt', descending: true).limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snap = await query.get();
    return ActivityPage(
      snap.docs.map(ActivityEntry.fromDoc).toList(),
      snap.docs.isEmpty ? after : snap.docs.last,
      hasMore: snap.docs.length == pageSize,
    );
  }
}

/// Action codes stored in `activity_logs.action`.
abstract final class ActivityAction {
  static const staffCreated = 'staff.created';
  static const staffUpdated = 'staff.updated';
  static const staffRoleChanged = 'staff.role_changed';
  static const staffDisabled = 'staff.disabled';
  static const staffEnabled = 'staff.enabled';
  static const staffDeleted = 'staff.deleted';
  static const passwordReset = 'password.reset_by_admin';
  static const passwordChanged = 'password.changed';
  static const shopCreated = 'shop.created';
  static const shopUpdated = 'shop.updated';
  static const shopDeleted = 'shop.deleted';
  static const dataRestored = 'data.restored';
  static const dataCleared = 'data.cleared';
  static const medicineCreated = 'medicine.created';
  static const medicineUpdated = 'medicine.updated';
  static const medicinePriceChanged = 'medicine.price_changed';
  static const medicineDeleted = 'medicine.deleted';
  static const medicinesImported = 'medicine.imported';
  static const stockSet = 'stock.set';
  static const stockWrittenOff = 'stock.written_off';
  static const saleVoided = 'sale.voided';
}
