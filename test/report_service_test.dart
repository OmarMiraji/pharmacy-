import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/report_service.dart';
import 'package:phyimacy/backend/user_profile.dart';

void main() {
  test('buildDateRange normalizes a custom date range to aware start and end timestamps', () {
    final range = ReportService.buildDateRange(
      from: DateTime(2026, 5, 10),
      to: DateTime(2026, 5, 15),
    );

    expect(range.start.day, 10);
    expect(range.start.hour, 0);
    expect(range.end.day, 15);
    expect(range.end.hour, 23);
    expect(range.end.minute, 59);
  });

  test('buildDateRange defaults to the current month when no dates are provided', () {
    final now = DateTime.now();
    final range = ReportService.buildDateRange();

    expect(range.start.year, now.year);
    expect(range.start.month, now.month);
    expect(range.start.day, 1);
    expect(range.end.year, now.year);
    expect(range.end.month, now.month);
    expect(range.end.day, DateTime(now.year, now.month + 1, 0).day);
  });

  test('super admin profile bypasses subscription gate', () {
    const profile = UserProfile(
      id: 'developer',
      employeeCode: 'ROOT',
      displayName: 'Developer',
      email: 'dev@phyimacy.com',
      role: 'super_admin',
      permissions: {
        'dashboard.view': true,
        'users.manage': true,
      },
      isActive: true,
    );

    expect(profile.isSuperAdmin, isTrue);
    expect(profile.can('users.manage'), isTrue);
  });
}
