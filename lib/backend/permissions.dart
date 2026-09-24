abstract final class AppPermissions {
  static const dashboardView = 'dashboard.view';
  static const medicinesView = 'medicines.view';
  static const medicinesCreate = 'medicines.create';
  static const medicinesUpdate = 'medicines.update';
  static const medicinesDelete = 'medicines.delete';
  static const inventoryView = 'inventory.view';
  static const inventoryAdjust = 'inventory.adjust';
  static const salesView = 'sales.view';
  static const salesCreate = 'sales.create';
  static const salesRefund = 'sales.refund';
  static const purchasesView = 'purchases.view';
  static const purchasesCreate = 'purchases.create';
  static const purchasesReceive = 'purchases.receive';
  static const suppliersManage = 'suppliers.manage';
  static const customersManage = 'customers.manage';
  static const expensesManage = 'expenses.manage';
  static const reportsView = 'reports.view';
  static const usersManage = 'users.manage';
  static const settingsManage = 'settings.manage';

  static const subscriptionManage = 'subscription.manage';
  static const subscriptionActivate = 'subscription.activate';
  static const subscriptionSuspend = 'subscription.suspend';
  static const subscriptionExtend = 'subscription.extend';
  static const paymentVerify = 'payment.verify';
  static const licenseManage = 'license.manage';
  static const licenseReset = 'license.reset';
  static const appReleaseManage = 'app_release.manage';
  static const appUpdatePublish = 'app_update.publish';

  static const pharmacyPermissions = <String>{
    dashboardView,
    medicinesView,
    medicinesCreate,
    medicinesUpdate,
    medicinesDelete,
    inventoryView,
    inventoryAdjust,
    salesView,
    salesCreate,
    salesRefund,
    purchasesView,
    purchasesCreate,
    purchasesReceive,
    suppliersManage,
    customersManage,
    expensesManage,
    reportsView,
    usersManage,
    settingsManage,
  };

  static const developerSystemPermissions = <String>{
    subscriptionManage,
    subscriptionActivate,
    subscriptionSuspend,
    subscriptionExtend,
    paymentVerify,
    licenseManage,
    licenseReset,
    appReleaseManage,
    appUpdatePublish,
  };

  static const superAdminOnlyPermissions = developerSystemPermissions;

  static const all = <String>{
    ...pharmacyPermissions,
    ...developerSystemPermissions,
  };

  static const roleDefaults = <String, Map<String, bool>>{
    'super_admin': {
      dashboardView: true,
      medicinesView: true,
      medicinesCreate: true,
      medicinesUpdate: true,
      medicinesDelete: true,
      inventoryView: true,
      inventoryAdjust: true,
      salesView: true,
      salesCreate: true,
      salesRefund: true,
      purchasesView: true,
      purchasesCreate: true,
      purchasesReceive: true,
      suppliersManage: true,
      customersManage: true,
      expensesManage: true,
      reportsView: true,
      usersManage: true,
      settingsManage: true,
      subscriptionManage: true,
      subscriptionActivate: true,
      subscriptionSuspend: true,
      subscriptionExtend: true,
      paymentVerify: true,
      licenseManage: true,
      licenseReset: true,
      appReleaseManage: true,
      appUpdatePublish: true,
    },
    'admin': {
      dashboardView: true,
      medicinesView: true,
      medicinesCreate: true,
      medicinesUpdate: true,
      medicinesDelete: true,
      inventoryView: true,
      inventoryAdjust: true,
      salesView: true,
      salesCreate: true,
      salesRefund: true,
      purchasesView: true,
      purchasesCreate: true,
      purchasesReceive: true,
      suppliersManage: true,
      customersManage: true,
      expensesManage: true,
      reportsView: true,
      usersManage: true,
      settingsManage: true,
    },
    'pharmacist': {
      dashboardView: true,
      medicinesView: true,
      medicinesCreate: true,
      medicinesUpdate: true,
      inventoryView: true,
      inventoryAdjust: true,
      salesView: true,
      salesCreate: true,
      purchasesView: true,
      purchasesReceive: true,
      suppliersManage: true,
      customersManage: true,
      reportsView: true,
    },
    'cashier': {
      dashboardView: true,
      medicinesView: true,
      inventoryView: true,
      salesView: true,
      salesCreate: true,
      customersManage: true,
    },
    'storekeeper': {
      dashboardView: true,
      medicinesView: true,
      medicinesCreate: true,
      medicinesUpdate: true,
      inventoryView: true,
      inventoryAdjust: true,
      purchasesView: true,
      purchasesCreate: true,
      purchasesReceive: true,
      suppliersManage: true,
      reportsView: true,
    },
  };

  static Map<String, bool> resolvedPermissions(String role, [Map<String, bool>? stored]) {
    final defaults = Map<String, bool>.from(roleDefaults[role] ?? const <String, bool>{});
    if (role == 'admin') {
      for (final permission in pharmacyPermissions) {
        defaults[permission] = true;
      }
    }
    stored?.forEach((key, value) {
      if (value == true && !superAdminOnlyPermissions.contains(key)) {
        defaults[key] = true;
      }
    });
    return defaults;
  }
}
