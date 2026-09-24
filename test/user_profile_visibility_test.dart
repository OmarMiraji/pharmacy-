import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/permissions.dart';
import 'package:phyimacy/backend/user_profile.dart';

void main() {
  group('UserProfile visibility', () {
    test('super admin is hidden from non-super-admin viewers', () {
      final viewer = UserProfile(
        id: 'viewer-1',
        employeeCode: 'EMP-1',
        displayName: 'Admin User',
        email: 'admin@phyimacy.com',
        role: 'admin',
        permissions: const {'users.manage': true},
        isActive: true,
      );

      final superAdmin = UserProfile(
        id: 'root-1',
        employeeCode: 'ROOT',
        displayName: 'Root User',
        email: 'root@phyimacy.com',
        role: 'super_admin',
        permissions: const {'users.manage': true},
        isActive: true,
      );

      expect(superAdmin.visibleTo(viewer), isFalse);
    });

    test('super admin remains visible to the super admin account itself', () {
      final viewer = UserProfile(
        id: 'root-1',
        employeeCode: 'ROOT',
        displayName: 'Root User',
        email: 'root@phyimacy.com',
        role: 'super_admin',
        permissions: const {'users.manage': true},
        isActive: true,
      );

      expect(viewer.visibleTo(viewer), isTrue);
    });

    test('admin can access pharmacy permissions but not superadmin-only system permissions', () {
      final admin = UserProfile(
        id: 'admin-1',
        employeeCode: 'EMP-2',
        displayName: 'Branch Admin',
        email: 'admin@phyimacy.com',
        role: 'admin',
        permissions: {
          AppPermissions.usersManage: true,
          AppPermissions.settingsManage: true,
        },
        isActive: true,
      );

      expect(admin.can(AppPermissions.usersManage), isTrue);
      expect(admin.can(AppPermissions.settingsManage), isTrue);
      expect(admin.can(AppPermissions.subscriptionManage), isFalse);
      expect(admin.can(AppPermissions.licenseManage), isFalse);
      expect(admin.can(AppPermissions.appUpdatePublish), isFalse);
    });
  });
}
