import 'package:cloud_firestore/cloud_firestore.dart';

class PharmacyRecord {
  const PharmacyRecord({
    required this.id,
    required this.name,
    required this.status,
    required this.plan,
    required this.isUnlocked,
    required this.isTrial,
    this.ownerEmail,
    this.ownerUserId,
    this.startsAt,
    this.expiresAt,
    this.trialEndsAt,
    this.note,
    this.phone,
    this.address,
  });

  final String id;
  final String name;
  final String status;
  final String plan;
  final bool isUnlocked;
  final bool isTrial;
  final String? ownerEmail;
  final String? ownerUserId;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;
  final String? note;
  final String? phone;
  final String? address;

  factory PharmacyRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return PharmacyRecord(
      id: doc.id,
      name: _string(data['name']) ?? 'Pharmacy',
      status: _string(data['status']) ?? 'trial',
      plan: _string(data['plan']) ?? 'trial',
      isUnlocked: data['isUnlocked'] == true,
      isTrial: data['isTrial'] == true || _string(data['plan']) == 'trial',
      ownerEmail: _string(data['ownerEmail']),
      ownerUserId: _string(data['ownerUserId']),
      startsAt: _date(data['startsAt']),
      expiresAt: _date(data['expiresAt']),
      trialEndsAt: _date(data['trialEndsAt']),
      note: _string(data['note']),
      phone: _string(data['phone']),
      address: _string(data['address']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
