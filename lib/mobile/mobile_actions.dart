import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/app_update_service.dart';
import '../backend/firestore_collections.dart';
import '../backend/medicine_service.dart';
import '../backend/models.dart';
import '../backend/selling_units.dart';
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

Future<void> showMobileAddMedicine(BuildContext context) {
  return showMobileMedicineSheet(context);
}

Future<void> showMobileEditMedicine(BuildContext context, Medicine medicine) {
  return showMobileMedicineSheet(context, medicine: medicine);
}

Future<void> showMobileMedicineSheet(BuildContext context, {Medicine? medicine}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _MedicineSheet(medicine: medicine),
  );
}

class _MedicineSheet extends StatefulWidget {
  const _MedicineSheet({this.medicine});

  final Medicine? medicine;

  @override
  State<_MedicineSheet> createState() => _MedicineSheetState();
}

class _MedicineSheetState extends State<_MedicineSheet> {
  late final TextEditingController _name;
  late final TextEditingController _sell;
  late final TextEditingController _buy;
  late final TextEditingController _qty;
  late final TextEditingController _reorder;
  late String _unit;
  late bool _prescription;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final medicine = widget.medicine;
    _name = TextEditingController(text: medicine?.name ?? '');
    _sell = TextEditingController(text: medicine == null ? '' : '${medicine.sellingPriceMinor}');
    _buy = TextEditingController(text: medicine == null ? '' : '${medicine.purchasePriceMinor}');
    _qty = TextEditingController(text: '${medicine?.quantityOnHand ?? 0}');
    _reorder = TextEditingController(text: '${medicine?.reorderLevel ?? 0}');
    final unit = BaseUnits.normalize(medicine?.unit ?? 'Tablet');
    _unit = BaseUnits.options.contains(unit) ? unit : 'Tablet';
    _prescription = medicine?.requiresPrescription ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _sell.dispose();
    _buy.dispose();
    _qty.dispose();
    _reorder.dispose();
    super.dispose();
  }

  int? _whole(String raw) {
    final value = int.tryParse(raw.trim().replaceAll(',', ''));
    if (value == null || value < 0) return null;
    return value;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sell = _whole(_sell.text);
    final buy = _whole(_buy.text.isEmpty ? '0' : _buy.text);
    final qty = _whole(_qty.text.isEmpty ? '0' : _qty.text);
    final reorder = _whole(_reorder.text.isEmpty ? '0' : _reorder.text);
    if (name.isEmpty || sell == null || buy == null || qty == null || reorder == null) {
      showAppNotice(context, S.t('Name and prices are required. Use whole numbers.', 'Jina na bei zinahitajika. Tumia namba kamili.'), kind: AppNoticeKind.error);
      return;
    }
    setState(() => _busy = true);
    final actor = FirebaseAuth.instance.currentUser?.uid ?? 'staff';
    try {
      final service = MedicineService();
      final existing = widget.medicine;
      if (existing == null) {
        final id = await service.createQuickMedicine(name: name, sellingPriceMinor: sell, createdBy: actor);
        final snap = await FirebaseFirestore.instance.collection(FirestoreCollections.medicines).doc(id).get();
        final data = snap.data() ?? const <String, dynamic>{};
        await service.updateMedicine(
          medicineId: id,
          name: name,
          sku: (data['sku'] as String?) ?? '',
          categoryId: (data['categoryId'] as String?) ?? '',
          unit: _unit,
          purchasePriceMinor: buy,
          sellingPriceMinor: sell,
          reorderLevel: reorder,
          requiresPrescription: _prescription,
        );
        if (qty > 0) {
          await service.setOnHandQuantity(medicineId: id, quantity: qty, createdBy: actor);
        }
      } else {
        await service.updateMedicine(
          medicineId: existing.id,
          name: name,
          sku: existing.sku,
          categoryId: existing.categoryId,
          unit: _unit,
          purchasePriceMinor: buy,
          sellingPriceMinor: sell,
          reorderLevel: reorder,
          requiresPrescription: _prescription,
          packSize: existing.packSize,
          stripSize: existing.stripSize,
          boxSize: existing.boxSize,
          minSaleQty: existing.minSaleQty,
          allowLooseSale: existing.allowLooseSale,
          allowHalfBlister: existing.allowHalfBlister,
        );
        if (qty != existing.quantityOnHand) {
          await service.setOnHandQuantity(medicineId: existing.id, quantity: qty, createdBy: actor);
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
      showAppNotice(context, S.t('Medicine saved', 'Dawa imehifadhiwa'));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(
        context,
        '$error'.replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''),
        kind: AppNoticeKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.medicine != null;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: PhyimacyBrand.line, borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  editing ? S.t('Edit medicine', 'Hariri dawa') : S.t('Add medicine', 'Ongeza dawa'),
                  style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  S.t('Name, prices, shelf quantity, and reorder level.', 'Jina, bei, idadi rafuni, na kiwango cha kuagiza tena.'),
                  style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.35),
                ),
                const SizedBox(height: 16),
                _field(_name, S.t('Medicine name', 'Jina la dawa')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _field(_sell, S.t('Selling price', 'Bei ya kuuza'), number: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_buy, S.t('Buying price', 'Bei ya kununua'), number: true)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _field(_qty, S.t('Quantity now', 'Idadi sasa'), number: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_reorder, S.t('Reorder at', 'Agiza tena ukifika'), number: true)),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _unit,
                  decoration: _decoration(S.t('Unit', 'Kipimo')),
                  items: [
                    for (final option in BaseUnits.options)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: _busy ? null : (value) => setState(() => _unit = value ?? _unit),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: PhyimacyBrand.teal,
                  title: Text(S.t('Needs a prescription', 'Inahitaji agizo la daktari'), style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  value: _prescription,
                  onChanged: _busy ? null : (value) => setState(() => _prescription = value),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: PhyimacyBrand.forest,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(_busy ? S.t('Saving...', 'Inahifadhi...') : S.t('Save medicine', 'Hifadhi dawa'), style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: PhyimacyBrand.cream,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: PhyimacyBrand.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: PhyimacyBrand.line)),
    );
  }

  Widget _field(TextEditingController controller, String label, {bool number = false}) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: _decoration(label),
    );
  }
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
            DropdownMenuItem(value: 'monthly', child: Text(S.t('Monthly · TZS 50,000', 'Kila mwezi · TZS 50,000'))),
            DropdownMenuItem(value: 'quarterly', child: Text(S.t('3 months · TZS 150,000', 'Miezi 3 · TZS 150,000'))),
            DropdownMenuItem(value: 'biannual', child: Text(S.t('6 months · TZS 300,000', 'Miezi 6 · TZS 300,000'))),
            DropdownMenuItem(value: 'yearly', child: Text(S.t('Yearly · TZS 600,000', 'Mwaka · TZS 600,000'))),
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
