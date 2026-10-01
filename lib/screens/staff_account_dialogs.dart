import 'package:flutter/material.dart';

import '../backend/permissions.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/tenant_context.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../widgets/app_notice.dart';
import 'password_security.dart';

Future<void> showCreateStaffDialog(
  BuildContext context, {
  required UserManagementService service,
  required bool canManageSuperAdmin,
  String? presetPharmacyId,
}) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final phone = TextEditingController();
  final employeeCode = TextEditingController();
  var role = canManageSuperAdmin ? 'admin' : 'pharmacist';
  var hidePassword = true;
  var hideConfirm = true;
  var selectedPharmacyId = (presetPharmacyId ?? TenantContext.instance.pharmacyId ?? '').trim();
  final visiblePermissions = AppPermissions.shopTickList(includeDeveloper: canManageSuperAdmin);
  final permissions = <String, bool>{
    for (final permission in visiblePermissions) permission: AppPermissions.resolvedPermissions(role)[permission] == true,
  };
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 680,
            height: 640,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.person_add_alt_1_rounded, color: Color(0xff0f766e)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(S.t('Add staff', 'Ongeza staff'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    S.t(
                      'Name, email, and password are required. Phone, staff code, shop, and permissions can be filled now.',
                      'Jina, email, na nenosiri ni lazima. Simu, namba ya staff, duka, na ruhusa unaweza kujaza sasa.',
                    ),
                    style: const TextStyle(fontSize: 13, color: Color(0xff68807d), height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(controller: name, decoration: InputDecoration(labelText: S.t('Full name', 'Jina kamili'))),
                          const SizedBox(height: 10),
                          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: S.t('Email', 'Email'))),
                          const SizedBox(height: 10),
                          TextField(
                            controller: password,
                            obscureText: hidePassword,
                            onChanged: (_) => setState(() {}),
                            decoration: passwordInputDecoration(
                              label: S.t('Password', 'Nenosiri'),
                              hidden: hidePassword,
                              onToggle: () => setState(() => hidePassword = !hidePassword),
                              errorText: password.text.isNotEmpty && password.text.trim().length < 6
                                  ? S.t('Use at least 6 characters.', 'Tumia herufi 6 au zaidi.')
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: confirmPassword,
                            obscureText: hideConfirm,
                            onChanged: (_) => setState(() {}),
                            decoration: passwordInputDecoration(
                              label: S.t('Confirm password', 'Thibitisha nenosiri'),
                              hidden: hideConfirm,
                              onToggle: () => setState(() => hideConfirm = !hideConfirm),
                              errorText: confirmPassword.text.isNotEmpty && password.text != confirmPassword.text
                                  ? S.t('Passwords do not match.', 'Nenosiri hayafanani.')
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: S.t('Phone (optional)', 'Simu (si lazima)'))),
                          const SizedBox(height: 10),
                          TextField(controller: employeeCode, decoration: InputDecoration(labelText: S.t('Staff code (optional)', 'Namba ya staff (si lazima)'))),
                          if (canManageSuperAdmin) ...[
                            const SizedBox(height: 10),
                            StreamBuilder<List<PharmacyRecord>>(
                              stream: PharmacyService().watchPharmacies(),
                              builder: (context, snapshot) {
                                final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
                                return DropdownButtonFormField<String>(
                                  initialValue: pharmacies.any((shop) => shop.id == selectedPharmacyId) ? selectedPharmacyId : null,
                                  decoration: InputDecoration(labelText: S.t('Shop', 'Duka')),
                                  items: [
                                    for (final shop in pharmacies) DropdownMenuItem(value: shop.id, child: Text(shop.name)),
                                  ],
                                  onChanged: (value) => setState(() => selectedPharmacyId = value ?? ''),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: role,
                            decoration: InputDecoration(labelText: S.t('Role', 'Wajibu')),
                            items: [
                              if (canManageSuperAdmin) DropdownMenuItem(value: 'admin', child: Text(S.t('Admin', 'Admin'))),
                              DropdownMenuItem(value: 'pharmacist', child: Text(S.t('Pharmacist', 'Pharmacist'))),
                              DropdownMenuItem(value: 'cashier', child: Text(S.t('Cashier', 'Cashier'))),
                              DropdownMenuItem(value: 'storekeeper', child: Text(S.t('Storekeeper', 'Storekeeper'))),
                            ],
                            onChanged: (value) => setState(() {
                              role = value ?? role;
                              for (final permission in visiblePermissions) {
                                permissions[permission] = AppPermissions.resolvedPermissions(role)[permission] == true;
                              }
                            }),
                          ),
                          const SizedBox(height: 16),
                          Text(S.t('Shop access', 'Ruhusa za duka'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xff0f766e))),
                          const SizedBox(height: 4),
                          Text(
                            role == 'admin'
                                ? S.t('Shop admin receives every shop permission automatically.', 'Admin wa duka anapata ruhusa zote za duka moja kwa moja.')
                                : S.t('Tick only the work this login should do in the shop.', 'Tika kazi tu ambazo login hii inaruhusiwa kufanya dukani.'),
                            style: const TextStyle(fontSize: 12, color: Color(0xff68807d), height: 1.35),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            children: [
                              for (final permission in visiblePermissions)
                                SizedBox(
                                  width: 310,
                                  child: CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(
                                      AppLocale.instance.isSw ? AppPermissions.labelSw(permission) : AppPermissions.labelEn(permission),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    value: role == 'admin' ? true : permissions[permission] == true,
                                    onChanged: role == 'admin'
                                        ? null
                                        : (value) => setState(() => permissions[permission] = value ?? false),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: password.text.trim().length >= 6 && password.text == confirmPassword.text
                            ? () async {
                          try {
                            final shopId = canManageSuperAdmin ? selectedPharmacyId : TenantContext.instance.pharmacyId;
                            await service.createLoginAndProfile(
                              displayName: name.text,
                              email: email.text,
                              password: password.text,
                              phone: phone.text,
                              employeeCode: employeeCode.text,
                              role: role,
                              permissions: role == 'admin' ? AppPermissions.resolvedPermissions('admin') : permissions,
                              isActive: true,
                              pharmacyId: shopId,
                            );
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (context.mounted) {
                              showAppNotice(context, S.t('Staff login is ready.', 'Login ya staff iko tayari.'));
                            }
                          } catch (error) {
                            if (context.mounted) {
                              showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
                            }
                          }
                        }
                            : null,
                        child: Text(S.t('Create login', 'Tengeneza login')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  name.dispose();
  email.dispose();
  password.dispose();
  confirmPassword.dispose();
  phone.dispose();
  employeeCode.dispose();
}

Future<void> showEditStaffDialog(
  BuildContext context, {
  required UserManagementService service,
  required UserProfile user,
  required bool canManageSuperAdmin,
}) async {
  var role = user.role;
  var isActive = user.isActive;
  String? selectedPharmacyId = user.pharmacyId ?? TenantContext.instance.pharmacyId;
  final name = TextEditingController(text: user.displayName);
  final email = TextEditingController(text: user.email);
  final phone = TextEditingController(text: user.phone ?? '');
  final employeeCode = TextEditingController(text: user.employeeCode);
  final visiblePermissions = AppPermissions.shopTickList(includeDeveloper: canManageSuperAdmin);
  final permissions = <String, bool>{
    for (final permission in visiblePermissions) permission: user.can(permission),
  };
  final canChangeRole = canManageSuperAdmin || (user.role != 'admin' && user.role != 'super_admin');
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 680,
            height: 640,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.manage_accounts_outlined, color: Color(0xff0f766e)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(S.t('Manage ${user.displayName}', 'Hariri ${user.displayName}'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(controller: name, decoration: InputDecoration(labelText: S.t('Full name', 'Jina kamili'))),
                          const SizedBox(height: 10),
                          TextField(controller: email, decoration: InputDecoration(labelText: S.t('Email', 'Email'))),
                          const SizedBox(height: 10),
                          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: S.t('Phone (optional)', 'Simu (si lazima)'))),
                          const SizedBox(height: 10),
                          TextField(controller: employeeCode, decoration: InputDecoration(labelText: S.t('Staff code (optional)', 'Namba ya staff (si lazima)'))),
                          if (canManageSuperAdmin) ...[
                            const SizedBox(height: 10),
                            StreamBuilder<List<PharmacyRecord>>(
                              stream: PharmacyService().watchPharmacies(),
                              builder: (context, snapshot) {
                                final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
                                return DropdownButtonFormField<String>(
                                  initialValue: pharmacies.any((shop) => shop.id == selectedPharmacyId) ? selectedPharmacyId : null,
                                  decoration: InputDecoration(labelText: S.t('Shop', 'Duka')),
                                  items: [
                                    for (final shop in pharmacies) DropdownMenuItem(value: shop.id, child: Text(shop.name)),
                                  ],
                                  onChanged: (value) => setState(() => selectedPharmacyId = value),
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: [
                                  if (user.role == 'super_admin') 'super_admin',
                                  if (canManageSuperAdmin || user.role == 'admin') 'admin',
                                  'pharmacist',
                                  'cashier',
                                  'storekeeper',
                                ].contains(role)
                                    ? role
                                    : (canManageSuperAdmin || user.role == 'admin' ? 'admin' : 'pharmacist'),
                                decoration: InputDecoration(labelText: S.t('Role', 'Wajibu')),
                                items: [
                                  if (user.role == 'super_admin')
                                    DropdownMenuItem(value: 'super_admin', child: Text(S.t('Super Admin', 'Super Admin'))),
                                  if (canManageSuperAdmin || user.role == 'admin')
                                    DropdownMenuItem(value: 'admin', child: Text(S.t('Admin', 'Admin'))),
                                  DropdownMenuItem(value: 'pharmacist', child: Text(S.t('Pharmacist', 'Pharmacist'))),
                                  DropdownMenuItem(value: 'cashier', child: Text(S.t('Cashier', 'Cashier'))),
                                  DropdownMenuItem(value: 'storekeeper', child: Text(S.t('Storekeeper', 'Storekeeper'))),
                                ],
                                onChanged: user.role == 'super_admin'
                                    ? null
                                    : (canChangeRole ? (value) => setState(() => role = value ?? role) : null),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(S.t('Account active', 'Akaunti hai')),
                                value: isActive,
                                onChanged: (value) => setState(() => isActive = value),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          Text(S.t('Shop access', 'Ruhusa za duka'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xff0f766e))),
                          const SizedBox(height: 4),
                          Text(
                            role == 'super_admin'
                                ? S.t('This is a system login. It is not a shop staff account.', 'Hii ni login ya mfumo. Si akaunti ya staff wa duka.')
                                : role == 'admin'
                                ? S.t('Shop admin receives every shop permission automatically.', 'Admin wa duka anapata ruhusa zote za duka moja kwa moja.')
                                : S.t('Tick only the work this login should do in the shop.', 'Tika kazi tu ambazo login hii inaruhusiwa kufanya dukani.'),
                            style: const TextStyle(fontSize: 12, color: Color(0xff68807d), height: 1.35),
                          ),
                          if (role != 'super_admin') ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 3,
                              children: [
                                for (final permission in visiblePermissions)
                                  SizedBox(
                                    width: 310,
                                    child: CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(
                                        AppLocale.instance.isSw ? AppPermissions.labelSw(permission) : AppPermissions.labelEn(permission),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      value: role == 'admin' ? true : permissions[permission] == true,
                                      onChanged: role == 'admin'
                                          ? null
                                          : (value) => setState(() => permissions[permission] = value ?? false),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            await service.updateProfileDetails(
                              userId: user.id,
                              displayName: name.text,
                              email: email.text,
                              phone: phone.text,
                              employeeCode: employeeCode.text,
                              role: role == 'super_admin' ? user.role : role,
                              permissions: role == 'admin' ? AppPermissions.resolvedPermissions('admin') : permissions,
                              isActive: isActive,
                              pharmacyId: selectedPharmacyId,
                            );
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (context.mounted) {
                              showAppNotice(context, S.t('Staff details have been saved.', 'Taarifa za staff zimehifadhiwa.'));
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              showAppNotice(dialogContext, friendlyActionError(error), kind: AppNoticeKind.error);
                            }
                          }
                        },
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: Text(S.t('Save user', 'Hifadhi mtumiaji')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  } finally {
    name.dispose();
    email.dispose();
    phone.dispose();
    employeeCode.dispose();
  }
}

Future<void> confirmDeleteStaffProfile(BuildContext context, UserManagementService service, UserProfile user) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(S.t('Delete profile?', 'Futa wasifu?')),
      content: Text(
        S.t(
          'Remove ${user.displayName} from this app. This does not delete the Firebase Auth login.',
          'Ondoa ${user.displayName} kwenye app hii. Hii haifuti login ya Firebase Auth.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete', 'Futa'))),
      ],
    ),
  );
  if (confirmed == true) await service.deleteProfile(user.id);
}

Future<void> showEditShopDialog(BuildContext context, PharmacyRecord shop) async {
  final name = TextEditingController(text: shop.name);
  final phone = TextEditingController(text: shop.phone ?? '');
  final address = TextEditingController(text: shop.address ?? '');
  final note = TextEditingController(text: shop.note ?? '');
  final ownerEmail = TextEditingController(text: shop.ownerEmail ?? '');
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Edit shop', 'Hariri duka')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: S.t('Pharmacy name', 'Jina la duka'))),
              const SizedBox(height: 10),
              TextField(controller: ownerEmail, decoration: InputDecoration(labelText: S.t('Owner email', 'Email ya mmiliki'))),
              const SizedBox(height: 10),
              TextField(controller: phone, decoration: InputDecoration(labelText: S.t('Phone', 'Simu'))),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: InputDecoration(labelText: S.t('Address', 'Anwani'))),
              const SizedBox(height: 10),
              TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: S.t('Notes', 'Maelezo'))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(
            onPressed: () async {
              try {
                await PharmacyService().updatePharmacyProfile(
                  pharmacyId: shop.id,
                  name: name.text,
                  phone: phone.text,
                  address: address.text,
                  note: note.text,
                  ownerEmail: ownerEmail.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: Text(S.t('Save shop', 'Hifadhi duka')),
          ),
        ],
      ),
    );
  } finally {
    name.dispose();
    phone.dispose();
    address.dispose();
    note.dispose();
    ownerEmail.dispose();
  }
}
