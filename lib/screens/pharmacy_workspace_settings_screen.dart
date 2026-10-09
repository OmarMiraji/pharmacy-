import 'package:flutter/material.dart';

import '../backend/auth_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_data_service.dart';
import '../backend/pharmacy_service.dart';
import '../backend/tanzania_phone.dart';
import '../backend/tenant_context.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class PharmacyWorkspaceSettingsScreen extends StatefulWidget {
  const PharmacyWorkspaceSettingsScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<PharmacyWorkspaceSettingsScreen> createState() => _PharmacyWorkspaceSettingsScreenState();
}

class _PharmacyWorkspaceSettingsScreenState extends State<PharmacyWorkspaceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  PharmacyRecord? _pharmacy;
  String? _targetPharmacyId;
  String _clearTarget = 'all';

  bool get _canManage => widget.profile.can('settings.manage') || widget.profile.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _targetPharmacyId = TenantContext.instance.pharmacyId;
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _targetPharmacyId ?? TenantContext.instance.pharmacyId;
    if (id == null || id.isEmpty) {
      setState(() {
        _loading = false;
        _pharmacy = null;
      });
      return;
    }
    final pharmacy = await PharmacyService().getPharmacy(id);
    if (!mounted) return;
    _pharmacy = pharmacy;
    _name.text = pharmacy?.name ?? '';
    _phone.text = pharmacy?.phone ?? '';
    _address.text = pharmacy?.address ?? '';
    _note.text = pharmacy?.note ?? '';
    setState(() => _loading = false);
  }

  void _toast(String message, {bool error = false}) {
    showAppNotice(context, message, kind: error ? AppNoticeKind.error : AppNoticeKind.success);
  }

  Future<bool> _confirmWithPassword({required String title, required String message}) async {
    final password = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Enter your password to confirm'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (accepted != true) {
      password.dispose();
      return false;
    }
    try {
      await AuthService().confirmPassword(password.text);
      return true;
    } catch (error) {
      _toast('$error', error: true);
      return false;
    } finally {
      password.dispose();
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final pharmacy = _pharmacy;
    if (pharmacy == null) return;
    setState(() => _busy = true);
    try {
      await PharmacyService().updatePharmacyProfile(
        pharmacyId: pharmacy.id,
        name: _name.text,
        phone: TanzaniaPhone.normalize(_phone.text),
        address: _address.text,
        note: _note.text,
      );
      _toast(S.t(
        'Shop details saved. Name, phone, address, and notes are updated.',
        'Taarifa za duka zimehifadhiwa. Jina, simu, anwani, na maelezo vimesasishwa.',
      ));
      await _load();
    } catch (error) {
      _toast(S.t('Could not save the shop details. Try again.', 'Taarifa za duka hazikuhifadhiwa. Jaribu tena.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final file = await PharmacyDataService().backupToFile();
      _toast('Backup saved: ${file.path}');
    } catch (error) {
      _toast('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await _confirmWithPassword(
      title: 'Restore backup?',
      message: 'This writes backup records into this pharmacy only. Enter your password to continue.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final count = await PharmacyDataService().restoreFromPickedFile();
      _toast('Restored $count records.');
    } catch (error) {
      _toast('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final all = _clearTarget == 'all';
    final label = all ? 'all shop data' : (PharmacyDataService.collectionLabels[_clearTarget] ?? _clearTarget);
    final ok = await _confirmWithPassword(
      title: 'Clear $label?',
      message: all
          ? 'This deletes medicines, stock, sales, purchases, customers, and expenses for this shop. Users and the license stay. Enter your password.'
          : 'This deletes only $label for this shop. Enter your password.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final service = PharmacyDataService();
      final count = all
          ? await service.clearOperationalData(pharmacyId: _targetPharmacyId)
          : await service.clearCollection(_clearTarget, pharmacyId: _targetPharmacyId);
      _toast('Cleared $count records.');
    } catch (error) {
      _toast('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearUsers() async {
    final pharmacyId = _targetPharmacyId ?? TenantContext.instance.pharmacyId;
    if (pharmacyId == null || pharmacyId.isEmpty) {
      _toast('Choose a pharmacy first.');
      return;
    }
    final ok = await _confirmWithPassword(
      title: 'Clear shop users?',
      message: 'This removes staff profiles for this pharmacy from Firestore. Super admin accounts are kept. Enter your password.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final count = await UserManagementService().deletePharmacyStaff(
        pharmacyId: pharmacyId,
        keepUserId: widget.profile.id,
      );
      _toast('Removed $count user profiles.');
    } catch (error) {
      _toast('$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.t('Shop details', 'Taarifa za duka'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        Text(S.t('Name, phone, address, and notes for this pharmacy.', 'Jina, simu, anwani, na maelezo ya duka hili.'), style: const TextStyle(color: Color(0xff68807d))),
        const SizedBox(height: 14),
        _ShopDetailsCard(pharmacy: _pharmacy),
        const SizedBox(height: 18),
        if (widget.profile.isSuperAdmin)
          StreamBuilder<List<PharmacyRecord>>(
            stream: PharmacyService().watchPharmacies(),
            builder: (context, snapshot) {
              final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
              return DropdownButtonFormField<String>(
                initialValue: pharmacies.any((pharmacy) => pharmacy.id == _targetPharmacyId) ? _targetPharmacyId : null,
                decoration: const InputDecoration(labelText: 'Pharmacy to manage'),
                items: [
                  for (final pharmacy in pharmacies)
                    DropdownMenuItem(value: pharmacy.id, child: Text(pharmacy.name)),
                ],
                onChanged: (value) {
                  setState(() {
                    _targetPharmacyId = value;
                    _loading = true;
                  });
                  _load();
                },
              );
            },
          ),
        if (widget.profile.isSuperAdmin) const SizedBox(height: 14),
        if (_pharmacy == null)
          const Text('This account is not linked to a pharmacy workspace.')
        else
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  enabled: _canManage && !_busy,
                  decoration: InputDecoration(
                    labelText: S.t('Pharmacy name', 'Jina la duka'),
                    prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty) ? S.t('Name is required', 'Jina linahitajika') : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  enabled: _canManage && !_busy,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: S.t('Phone', 'Simu'),
                    hintText: TanzaniaPhone.hint,
                    helperText: S.t('Tanzania mobile, e.g. 0712345678', 'Simu ya Tanzania, mfano 0712345678'),
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  ),
                  validator: TanzaniaPhone.validate,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _address,
                  enabled: _canManage && !_busy,
                  decoration: InputDecoration(
                    labelText: S.t('Address', 'Anwani'),
                    hintText: S.t('Street, ward, or city', 'Mtaa, kata, au mji'),
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _note,
                  enabled: _canManage && !_busy,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: S.t('Notes', 'Maelezo'),
                    hintText: S.t('Anything else about this shop', 'Maelezo mengine ya duka'),
                    prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _canManage && !_busy ? _saveProfile : null,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_busy ? S.t('Saving...', 'Inahifadhi...') : S.t('Save pharmacy information', 'Hifadhi taarifa za duka')),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        Text(S.t('Data tools', 'Zana za data'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _clearTarget,
          decoration: InputDecoration(labelText: S.t('Clear', 'Futa')),
          items: [
            DropdownMenuItem(value: 'all', child: Text(S.t('All shop data', 'Data yote ya duka'))),
            for (final entry in PharmacyDataService.collectionLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _busy ? null : (value) => setState(() => _clearTarget = value ?? 'all'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: _canManage && !_busy ? _backup : null,
              icon: const Icon(Icons.backup_rounded),
              label: Text(S.t('Backup data', 'Backup data')),
            ),
            FilledButton.tonalIcon(
              onPressed: _canManage && !_busy ? _restore : null,
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: Text(S.t('Restore backup', 'Rudisha backup')),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xffb42318)),
              onPressed: _canManage && !_busy ? _clear : null,
              icon: const Icon(Icons.delete_forever_rounded),
              label: Text(S.t('Clear selected data', 'Futa data iliyochaguliwa')),
            ),
            if (widget.profile.isSuperAdmin)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff9a3412)),
                onPressed: _busy ? null : _clearUsers,
                icon: const Icon(Icons.group_off_rounded),
                label: Text(S.t('Clear shop users', 'Futa watumiaji wa duka')),
              ),
          ],
        ),
      ],
    );
  }
}

class _ShopDetailsCard extends StatelessWidget {
  const _ShopDetailsCard({required this.pharmacy});

  final PharmacyRecord? pharmacy;

  @override
  Widget build(BuildContext context) {
    final missing = S.t('Not added yet', 'Haijawekwa');
    String show(String? value) {
      final text = (value ?? '').trim();
      return text.isEmpty ? missing : text;
    }
    final rows = <(IconData, String, String)>[
      (Icons.storefront_outlined, S.t('Pharmacy name', 'Jina la duka'), show(pharmacy?.name)),
      (Icons.phone_outlined, S.t('Phone', 'Simu'), show(pharmacy?.phone)),
      (Icons.location_on_outlined, S.t('Address', 'Anwani'), show(pharmacy?.address)),
      (Icons.notes_rounded, S.t('Notes', 'Maelezo'), show(pharmacy?.note)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: const Color(0xfff4faf8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PhyimacyBrand.line),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(row.$1, size: 18, color: PhyimacyBrand.teal),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                  ),
                  Expanded(
                    child: Text(
                      row.$3,
                      style: TextStyle(
                        color: row.$3 == missing ? const Color(0xff8aa09c) : const Color(0xff183b3b),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
