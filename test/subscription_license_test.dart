import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/pharmacy.dart';
import 'package:phyimacy/backend/subscription_service.dart';

PharmacyRecord _pharmacy({
  required bool isTrial,
  required DateTime expiresAt,
  bool isUnlocked = true,
  String status = 'trial',
  String plan = 'trial',
}) {
  return PharmacyRecord(
    id: 'pharm-1',
    name: 'Test Pharmacy',
    status: status,
    plan: plan,
    isUnlocked: isUnlocked,
    isTrial: isTrial,
    expiresAt: expiresAt,
    trialEndsAt: expiresAt,
  );
}

void main() {
  group('licenseFromPharmacy', () {
    test('active trial can read and write', () {
      final license = SubscriptionService.licenseFromPharmacy(
        _pharmacy(isTrial: true, expiresAt: DateTime.now().add(const Duration(days: 5))),
      );
      expect(license.access, PharmacyAccess.full);
      expect(license.canWrite, isTrue);
      expect(license.canRead, isTrue);
    });

    test('expired trial is fully blocked', () {
      final license = SubscriptionService.licenseFromPharmacy(
        _pharmacy(isTrial: true, expiresAt: DateTime.now().subtract(const Duration(days: 1))),
      );
      expect(license.access, PharmacyAccess.blocked);
      expect(license.canRead, isFalse);
      expect(license.canWrite, isFalse);
    });

    test('trial ending later today is already blocked on that calendar date', () {
      final now = DateTime.now();
      final laterToday = DateTime(now.year, now.month, now.day, 23, 59);
      final license = SubscriptionService.licenseFromPharmacy(
        _pharmacy(isTrial: true, expiresAt: laterToday),
      );
      expect(license.access, PharmacyAccess.blocked);
      expect(license.hasExpired, isTrue);
    });

    test('trial ending tomorrow stays writable', () {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1, hours: 10));
      final license = SubscriptionService.licenseFromPharmacy(
        _pharmacy(isTrial: true, expiresAt: tomorrow),
      );
      expect(license.access, PharmacyAccess.full);
      expect(license.hasExpired, isFalse);
    });

    test('expired paid subscription is read only', () {
      final license = SubscriptionService.licenseFromPharmacy(
        _pharmacy(
          isTrial: false,
          status: 'active',
          plan: 'monthly',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      );
      expect(license.access, PharmacyAccess.readOnly);
      expect(license.canRead, isTrue);
      expect(license.canWrite, isFalse);
    });

    test('active trial reports remaining days', () {
      final license = SubscriptionService.licenseFromPharmacy(
        _pharmacy(isTrial: true, expiresAt: DateTime.now().add(const Duration(days: 5, hours: 2))),
      );
      expect(license.daysRemaining, 5);
      expect(license.trialCountdownLabel, contains('5 days remaining'));
    });
  });

  test('unused token shows its duration and a used token shows pharmacy time left', () {
    expect(
      SubscriptionService.tokenRemainingLabel(isUsed: false, durationDays: 30),
      '30 days ready to activate',
    );
    final now = DateTime(2026, 10, 7, 12);
    final pharmacy = PharmacyRecord(
      id: 'pharm-1',
      name: 'Afya Pharmacy',
      status: 'active',
      plan: 'monthly',
      isUnlocked: true,
      isTrial: false,
      expiresAt: DateTime(2026, 10, 17, 18),
    );
    expect(
      SubscriptionService.tokenRemainingLabel(isUsed: true, durationDays: 30, pharmacy: pharmacy, now: now),
      '10 days left',
    );
    expect(
      SubscriptionService.tokenRemainingLabel(isUsed: true, durationDays: 30, now: now),
      'Used · pharmacy not linked',
    );
  });
}
