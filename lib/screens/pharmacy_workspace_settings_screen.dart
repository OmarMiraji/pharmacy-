import 'package:flutter/material.dart';

import '../backend/auth_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_data_service.dart';
import '../backend/pharmacy_service.dart';
import '../backend/tenant_context.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';

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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      _toast('$error');
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
        phone: _phone.text,
        address: _address.text,
        note: _note.text,
      );
      _toast('Pharmacy information updated.');
      await _load();
    } catch (error) {
      _toast('Could not update pharmacy: $error');
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
      _toast('$error');
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
      _toast('$error');
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
      _toast('$error');
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
      _toast('$error');
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
        const Text('Pharmacy profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        const Text('Update shop information. Clear one data group or everything after entering your password.', style: TextStyle(color: Color(0xff68807d))),
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
                  decoration: const InputDecoration(labelText: 'Pharmacy name'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  enabled: _canManage && !_busy,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    if (text.length < 9) return 'Enter a valid phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _address,
                  enabled: _canManage && !_busy,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _note,
                  enabled: _canManage && !_busy,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _canManage && !_busy ? _saveProfile : null,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_busy ? 'Saving...' : 'Save pharmacy information'),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        const Text('Data tools', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _clearTarget,
          decoration: const InputDecoration(labelText: 'Clear'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All shop data')),
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
              label: const Text('Backup data'),
            ),
            FilledButton.tonalIcon(
              onPressed: _canManage && !_busy ? _restore : null,
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: const Text('Restore backup'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xffb42318)),
              onPressed: _canManage && !_busy ? _clear : null,
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Clear selected data'),
            ),
            if (widget.profile.isSuperAdmin)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xff9a3412)),
                onPressed: _busy ? null : _clearUsers,
                icon: const Icon(Icons.group_off_rounded),
                label: const Text('Clear shop users'),
              ),
          ],
        ),
      ],
    );
  }
}
