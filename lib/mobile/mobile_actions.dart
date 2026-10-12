import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/app_update_service.dart';
import '../backend/medicine_service.dart';
import '../backend/permissions.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class MobileUpdateCard extends StatelessWidget {
  const MobileUpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUpdateCheck>(
      future: AppUpdateService().check(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 8);
        }
        final check = snapshot.data!;
        final latest = check.latest;
        final available = check.updateAvailable;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: PhyimacyBrand.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('App update', 'Sasisho la programu'), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
              const SizedBox(height: 6),
              Text(
                available && latest != null
                    ? S.t(
                        'Version ${latest.version} is published. This phone has ${check.installedVersion}. Open it, then install the new shop copy on the computer.',
                        'Toleo ${latest.version} limetoka. Simu hii ina ${check.installedVersion}. Fungua, kisha sakinisha nakala mpya kwenye kompyuta ya duka.',
                      )
                    : S.t(
                        'This phone is on ${check.installedVersion}. A newer release will show here.',
                        'Simu hii iko ${check.installedVersion}. Toleo jipya litaonekana hapa.',
                      ),
                style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: PhyimacyBrand.muted),
              ),
              if (available && latest != null && latest.downloadUrl.startsWith('https://')) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final opened = await launchUrl(Uri.parse(latest.downloadUrl), mode: LaunchMode.externalApplication);
                    if (!context.mounted) return;
                    showAppNotice(
                      context,
                      opened
                          ? S.t('Update page opened', 'Ukurasa wa sasisho umefunguka')
                          : S.t('Could not open the update', 'Imeshindikana kufungua sasisho'),
                      kind: opened ? AppNoticeKind.success : AppNoticeKind.error,
                    );
                  },
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: Text(S.t('Open update', 'Fungua sasisho')),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class MobileTeamCard extends StatelessWidget {
  const MobileTeamCard({required this.profile, super.key});

  final UserProfile profile;

  bool get _canManage => profile.role == 'admin' || profile.can('users.manage') || profile.isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    if (!_canManage) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: PhyimacyBrand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('Staff', 'Wafanyakazi'), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
            const SizedBox(height: 4),
            Text(
              S.t('Add a cashier, pharmacist, or storekeeper for this shop.', 'Ongeza cashier, mfamasia, au mhifadhi wa duka hili.'),
              style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: PhyimacyBrand.muted),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<UserProfile>>(
              stream: UserManagementService().watchUsers(pharmacyId: profile.pharmacyId),
              builder: (context, snapshot) {
                final people = snapshot.data ?? const <UserProfile>[];
                return Column(
                  children: [
                    for (final person in people.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(person.displayName.isEmpty ? person.email : person.displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
                            Text(S.role(person.role), style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.teal, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            FilledButton.icon(
              onPressed: () => _addStaff(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(S.t('Add staff', 'Ongeza mfanyakazi')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addStaff(BuildContext context) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var role = 'cashier';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(S.t('New staff login', 'Akaunti mpya ya mfanyakazi')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: InputDecoration(labelText: S.t('Name', 'Jina'))),
                const SizedBox(height: 10),
                TextField(controller: email, decoration: InputDecoration(labelText: S.t('Email', 'Barua pepe'))),
                const SizedBox(height: 10),
                TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: S.t('Password', 'Nenosiri'))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: S.t('Role', 'Cheo')),
                  items: [
                    DropdownMenuItem(value: 'cashier', child: Text(S.role('cashier'))),
                    DropdownMenuItem(value: 'pharmacist', child: Text(S.role('pharmacist'))),
                    DropdownMenuItem(value: 'storekeeper', child: Text(S.role('storekeeper'))),
                  ],
                  onChanged: (value) => setLocal(() => role = value ?? role),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Save', 'Hifadhi'))),
          ],
        ),
      ),
    );
    if (saved != true) {
      name.dispose();
      email.dispose();
      password.dispose();
      return;
    }
    try {
      await UserManagementService().createLoginAndProfile(
        displayName: name.text,
        email: email.text,
        password: password.text,
        role: role,
        permissions: AppPermissions.resolvedPermissions(role),
        isActive: true,
        pharmacyId: profile.pharmacyId,
      );
      if (context.mounted) showAppNotice(context, S.t('Staff login created', 'Akaunti ya mfanyakazi imetengenezwa'));
    } catch (error) {
      if (context.mounted) showAppNotice(context, '$error'.replaceFirst('Bad state: ', ''), kind: AppNoticeKind.error);
    }
    name.dispose();
    email.dispose();
    password.dispose();
  }
}

Future<void> showMobileAddMedicine(BuildContext context) async {
  final name = TextEditingController();
  final price = TextEditingController();
  final qty = TextEditingController(text: '0');
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(S.t('Add medicine', 'Ongeza dawa')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: InputDecoration(labelText: S.t('Name', 'Jina'))),
          const SizedBox(height: 10),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.t('Selling price (TZS)', 'Bei ya kuuza (TZS)'))),
          const SizedBox(height: 10),
          TextField(controller: qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.t('Quantity now', 'Idadi sasa'))),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Save', 'Hifadhi'))),
      ],
    ),
  );
  if (saved == true) {
    try {
      final id = await MedicineService().createQuickMedicine(
        name: name.text,
        sellingPriceMinor: int.parse(price.text.trim()),
        createdBy: FirebaseAuth.instance.currentUser?.uid ?? 'staff',
      );
      final count = int.tryParse(qty.text.trim()) ?? 0;
      if (count > 0) {
        await MedicineService().setOnHandQuantity(
          medicineId: id,
          quantity: count,
          createdBy: FirebaseAuth.instance.currentUser?.uid ?? 'staff',
        );
      }
      if (context.mounted) showAppNotice(context, S.t('Medicine saved', 'Dawa imehifadhiwa'));
    } catch (error) {
      if (context.mounted) showAppNotice(context, '$error'.replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''), kind: AppNoticeKind.error);
    }
  }
  name.dispose();
  price.dispose();
  qty.dispose();
}

Future<void> showMobileEditStock(BuildContext context, {required String medicineId, required String name, required int stock}) async {
  final qty = TextEditingController(text: '$stock');
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(name),
      content: TextField(
        controller: qty,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: S.t('Quantity on the shelf', 'Idadi rafuni')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Save', 'Hifadhi'))),
      ],
    ),
  );
  if (saved == true) {
    try {
      await MedicineService().setOnHandQuantity(
        medicineId: medicineId,
        quantity: int.parse(qty.text.trim()),
        createdBy: FirebaseAuth.instance.currentUser?.uid ?? 'staff',
      );
      if (context.mounted) showAppNotice(context, S.t('Stock updated', 'Stoku imesasishwa'));
    } catch (error) {
      if (context.mounted) showAppNotice(context, '$error'.replaceFirst('Bad state: ', ''), kind: AppNoticeKind.error);
    }
  }
  qty.dispose();
}

class MobileCreateShopPage extends StatefulWidget {
  const MobileCreateShopPage({super.key});

  @override
  State<MobileCreateShopPage> createState() => _MobileCreateShopPageState();
}

class _MobileCreateShopPageState extends State<MobileCreateShopPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await PharmacyService().createPharmacy(
        name: _name.text,
        ownerEmail: _email.text,
        ownerPassword: _password.text,
        ownerDisplayName: _name.text,
      );
      if (!mounted) return;
      showAppNotice(context, S.t('Pharmacy created', 'Duka limetengenezwa'));
      _name.clear();
      _email.clear();
      _password.clear();
    } catch (error) {
      if (mounted) showAppNotice(context, '$error'.replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''), kind: AppNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(S.t('New pharmacy', 'Duka jipya'), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: InputDecoration(labelText: S.t('Pharmacy name', 'Jina la duka'))),
        const SizedBox(height: 10),
        TextField(controller: _email, decoration: InputDecoration(labelText: S.t('Owner email', 'Barua pepe ya mwenye duka'))),
        const SizedBox(height: 10),
        TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: S.t('Owner password', 'Nenosiri la mwenye duka'))),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? S.t('Saving...', 'Inahifadhi...') : S.t('Create pharmacy', 'Tengeneza duka')),
        ),
      ],
    );
  }
}

class MobileTokenPage extends StatefulWidget {
  const MobileTokenPage({super.key});

  @override
  State<MobileTokenPage> createState() => _MobileTokenPageState();
}

class _MobileTokenPageState extends State<MobileTokenPage> {
  var _plan = 'monthly';
  var _busy = false;
  String? _code;

  Future<void> _make() async {
    setState(() => _busy = true);
    try {
      final days = SubscriptionService.planDurations[_plan] ?? 30;
      final code = await SubscriptionService().createActivationToken(plan: _plan, durationDays: days);
      if (!mounted) return;
      setState(() => _code = code);
      showAppNotice(context, S.t('Token created', 'Token imetengenezwa'));
    } catch (error) {
      if (mounted) showAppNotice(context, '$error'.replaceFirst('Bad state: ', ''), kind: AppNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(S.t('Activation token', 'Token ya kuwezesha'), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _plan,
          decoration: InputDecoration(labelText: S.t('Plan', 'Mpango')),
          items: [
            for (final plan in SubscriptionService.planDurations.keys)
              DropdownMenuItem(value: plan, child: Text('$plan · ${SubscriptionService.planDurations[plan]} ${S.t('days', 'siku')}')),
          ],
          onChanged: (value) => setState(() => _plan = value ?? _plan),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _make,
          child: Text(_busy ? S.t('Creating...', 'Inatengeneza...') : S.t('Generate token', 'Tengeneza token')),
        ),
        if (_code != null) ...[
          const SizedBox(height: 16),
          SelectableText(_code!, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: PhyimacyBrand.forest)),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _code!));
              if (!context.mounted) return;
              showAppNotice(context, S.t('Token copied', 'Token imenakiliwa'));
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text(S.t('Copy', 'Nakili')),
          ),
        ],
      ],
    );
  }
}
