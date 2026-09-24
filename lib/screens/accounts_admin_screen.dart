import 'package:flutter/material.dart';

import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';

class AccountsAdminScreen extends StatefulWidget {
  const AccountsAdminScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<AccountsAdminScreen> createState() => _AccountsAdminScreenState();
}

class _AccountsAdminScreenState extends State<AccountsAdminScreen> {
  final _pharmacies = PharmacyService();
  final _users = UserManagementService();
  final _shopName = TextEditingController();
  final _adminName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _selectedPharmacyId;
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _shopName.dispose();
    _adminName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _createShopAndAdmin() async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = 'Creating Firebase login, then pharmacy, then user profile...';
    });
    try {
      final result = await _pharmacies.createPharmacy(
        name: _shopName.text.trim(),
        ownerEmail: _email.text.trim(),
        ownerDisplayName: _adminName.text.trim(),
        ownerPassword: _password.text,
      );
      if (!mounted) return;
      _shopName.clear();
      _adminName.clear();
      _email.clear();
      _password.clear();
      setState(() {
        _selectedPharmacyId = result.pharmacyId;
        _failed = false;
        _message =
            'Created.\nPharmacy ID: ${result.pharmacyId}\nAdmin UID: ${result.adminUid}\nSign in with ${result.adminEmail} and the password you set.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = '$error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fixAdminLogin(PharmacyRecord pharmacy) async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = 'Creating Firebase login for ${pharmacy.name}...';
    });
    try {
      await _pharmacies.provisionAdminLogin(
        pharmacyId: pharmacy.id,
        email: _email.text.trim().isEmpty ? (pharmacy.ownerEmail ?? '') : _email.text.trim(),
        password: _password.text,
        displayName: _adminName.text.trim().isEmpty ? pharmacy.name : _adminName.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _failed = false;
        _message = 'Admin login is ready. Sign in with that email and password.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = '$error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Create pharmacy + admin', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        const Text(
          'Haujachagua duka kwanza. Jaza fomu hii: Firebase inatengeneza pharmacy ID na user ID peke yake, kisha inaziunganisha.',
          style: TextStyle(color: Color(0xff68807d), height: 1.45),
        ),
        const SizedBox(height: 16),
        TextField(controller: _shopName, enabled: !_busy, decoration: const InputDecoration(labelText: 'Pharmacy name')),
        const SizedBox(height: 10),
        TextField(controller: _adminName, enabled: !_busy, decoration: const InputDecoration(labelText: 'Admin full name')),
        const SizedBox(height: 10),
        TextField(controller: _email, enabled: !_busy, decoration: const InputDecoration(labelText: 'Admin email (this is the login)')),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Admin password (min 6 characters)'),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _createShopAndAdmin,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_business_rounded),
          label: Text(_busy ? 'Creating in Firebase...' : 'Create pharmacy and admin login'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _failed ? const Color(0xffffe8e6) : const Color(0xffe8f6f2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_message!, style: TextStyle(color: _failed ? const Color(0xffb42318) : const Color(0xff0f766e), height: 1.5)),
          ),
        ],
        const SizedBox(height: 28),
        const Text('Shops already in Firebase', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 10),
        StreamBuilder<List<PharmacyRecord>>(
          stream: _pharmacies.watchPharmacies(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load pharmacies: ${snapshot.error}');
            }
            if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
            final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
            if (pharmacies.isEmpty) {
              return const Text('No shops yet. Use the form above. You do not select a shop first.');
            }
            final selected = pharmacies.firstWhere(
              (pharmacy) => pharmacy.id == _selectedPharmacyId,
              orElse: () => pharmacies.first,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final pharmacy in pharmacies)
                      ChoiceChip(
                        label: Text(pharmacy.name),
                        selected: pharmacy.id == selected.id,
                        onSelected: (_) => setState(() => _selectedPharmacyId = pharmacy.id),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(selected.name, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                Text(
                  'Pharmacy ID ${selected.id}\nAdmin ${selected.ownerEmail ?? 'not linked'}',
                  style: const TextStyle(color: Color(0xff68807d), height: 1.4),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _fixAdminLogin(selected),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Repair admin login for selected shop'),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<UserProfile>>(
                  stream: _users.watchUsers(pharmacyId: selected.id),
                  builder: (context, usersSnapshot) {
                    if (usersSnapshot.hasError) return Text('Users: ${usersSnapshot.error}');
                    if (!usersSnapshot.hasData) return const SizedBox.shrink();
                    final users = usersSnapshot.data!.where((user) => user.role != 'super_admin').toList();
                    if (users.isEmpty) {
                      return const Text('No Firebase user profile linked to this shop yet.');
                    }
                    return Column(
                      children: [
                        for (final user in users)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${user.email}  •  ${user.role}  •  uid ${user.id}'),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
