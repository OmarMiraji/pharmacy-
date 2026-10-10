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
  static const salesDiscount = 'sales.discount';
  static const salesRefund = 'sales.refund';
  static const salesRecords = 'sales.records';
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
    salesDiscount,
    salesRefund,
    salesRecords,
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
      salesDiscount: true,
      salesRefund: true,
      salesRecords: true,
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
      salesDiscount: true,
      salesRefund: true,
      salesRecords: true,
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
      salesDiscount: true,
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
    for (final permission in pharmacyPermissions) {
      defaults.putIfAbsent(permission, () => false);
    }
    stored?.forEach((key, value) {
      if (superAdminOnlyPermissions.contains(key) && role != 'super_admin') {
        return;
      }
      defaults[key] = value == true;
    });
    if (role == 'admin') {
      for (final permission in pharmacyPermissions) {
        defaults[permission] = true;
      }
    }
    return defaults;
  }

  static List<String> shopTickList({bool includeDeveloper = false}) {
    return pharmacyPermissions.toList();
  }

  static String labelEn(String permission) => switch (permission) {
        dashboardView => 'View dashboard',
        medicinesView => 'View medicines',
        medicinesCreate => 'Add and import medicines',
        medicinesUpdate => 'Edit medicine details',
        medicinesDelete => 'Delete medicines',
        inventoryView => 'View stock and batches',
        inventoryAdjust => 'Adjust stock and write off expired items',
        salesView => 'View sales',
        salesCreate => 'Complete sales',
        salesDiscount => 'Apply discounts',
        salesRefund => 'Refund sales',
        salesRecords => 'View sale records',
        purchasesView => 'View purchases',
        purchasesCreate => 'Record purchases',
        purchasesReceive => 'Receive incoming stock',
        suppliersManage => 'Manage suppliers',
        customersManage => 'Manage customers',
        expensesManage => 'Record expenses',
        reportsView => 'View reports',
        usersManage => 'Manage staff logins',
        settingsManage => 'Shop settings and devices',
        subscriptionManage => 'Manage licenses',
        subscriptionActivate => 'Activate a license',
        subscriptionSuspend => 'Suspend a license',
        subscriptionExtend => 'Extend a license',
        paymentVerify => 'Verify payments',
        licenseManage => 'Edit license records',
        licenseReset => 'Reset a license',
        appReleaseManage => 'Manage app releases',
        appUpdatePublish => 'Publish app updates',
        _ => permission,
      };

  static String labelSw(String permission) => switch (permission) {
        dashboardView => 'Ona dashibodi',
        medicinesView => 'Ona dawa',
        medicinesCreate => 'Ongeza na import dawa',
        medicinesUpdate => 'Hariri taarifa za dawa',
        medicinesDelete => 'Futa dawa',
        inventoryView => 'Ona stock na batches',
        inventoryAdjust => 'Badilisha stock na toa zilizoisha',
        salesView => 'Ona mauzo',
        salesCreate => 'Kamilisha mauzo',
        salesDiscount => 'Weka punguzo',
        salesRefund => 'Rudisha mauzo',
        salesRecords => 'Ona kumbukumbu za mauzo',
        purchasesView => 'Ona manunuzi',
        purchasesCreate => 'Rekodi manunuzi',
        purchasesReceive => 'Pokea stock inayoingia',
        suppliersManage => 'Simamia wasambazaji',
        customersManage => 'Simamia wateja',
        expensesManage => 'Rekodi matumizi',
        reportsView => 'Ona ripoti',
        usersManage => 'Simamia login za staff',
        settingsManage => 'Mipangilio ya duka na vifaa',
        subscriptionManage => 'Simamia leseni',
        subscriptionActivate => 'Activate leseni',
        subscriptionSuspend => 'Sitisha leseni',
        subscriptionExtend => 'Ongeza muda wa leseni',
        paymentVerify => 'Thibitisha malipo',
        licenseManage => 'Hariri leseni',
        licenseReset => 'Reset leseni',
        appReleaseManage => 'Simamia matoleo ya app',
        appUpdatePublish => 'Chapisha update',
        _ => permission,
      };
}
