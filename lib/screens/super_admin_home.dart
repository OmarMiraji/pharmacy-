import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/tenant_context.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../theme/brand.dart';
import '../l10n/app_locale.dart';
import '../widgets/language_toggle.dart';
import 'app_update_screen.dart';
import 'chat_assistant_panel.dart';
import 'password_security.dart';
import 'pharmacy_workspace_settings_screen.dart';
import 'subscription_admin_screen.dart';
import 'support_directory_screen.dart';

class SuperAdminHome extends StatefulWidget {
  const SuperAdminHome({required this.profile, required this.authService, super.key});

  final UserProfile profile;
  final AuthService authService;

  @override
  State<SuperAdminHome> createState() => _SuperAdminHomeState();
}

class _SuperAdminHomeState extends State<SuperAdminHome> {
  int _index = 0;

  static const _items = [
    ('Customers', Icons.groups_rounded),
    ('Shops', Icons.storefront_rounded),
    ('Licenses', Icons.workspace_premium_rounded),
    ('Logins', Icons.manage_accounts_outlined),
    ('Support data', Icons.storage_rounded),
    ('App updates', Icons.system_update_alt_rounded),
    ('Password', Icons.lock_reset_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final selected = _items[_index.clamp(0, _items.length - 1)];
        return Scaffold(
      backgroundColor: PhyimacyBrand.cream,
      body: Stack(
        children: [
          Row(
            children: [
          SizedBox(
            width: 296,
            child: ColoredBox(
              color: const Color(0xFF052E2D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BrandMark(size: 40),
                        const SizedBox(height: 12),
                        Text(PhyimacyBrand.appName.toUpperCase(), style: GoogleFonts.playfairDisplay(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.4, fontSize: 22, height: 1)),
                        const SizedBox(height: 10),
                        Container(width: 40, height: 3, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
                        const SizedBox(height: 10),
                        Text('System support', style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.78), fontSize: 13.5)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
                    child: Text('CONSOLE', style: GoogleFonts.inter(color: PhyimacyBrand.gold.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final active = _index == index;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _index = index),
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  color: active ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Icon(item.$2, color: Colors.white, size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(item.$1, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15.5)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                    child: Column(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.lock_reset_rounded, color: Colors.white70),
                            title: Text('My password', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                            onTap: () => showChangeOwnPasswordDialog(context),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.logout_rounded, color: Colors.white70),
                            title: Text('Sign out', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                            onTap: () {
                              TenantContext.instance.clear();
                              widget.authService.signOut();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 78,
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Row(
                    children: [
                      Container(width: 4, height: 32, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(selected.$1, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink, height: 1.1)),
                            Text('Support the shops that use PharmSpecio', style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.muted)),
                          ],
                        ),
                      ),
                      Text(widget.profile.email, style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.muted)),
                      const SizedBox(width: 12),
                      const LanguageToggle(compact: true),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                    child: selected.$1 == 'Logins' || selected.$1 == 'Customers' || selected.$1 == 'Shops'
                        ? _body(selected.$1)
                        : SingleChildScrollView(child: _body(selected.$1)),
                  ),
                ),
              ],
            ),
          ),
        ],
          ),
          const ShopAssistantDock(supportMode: true),
        ],
      ),
    );
      },
    );
  }

  Widget _body(String label) {
    switch (label) {
      case 'Shops':
        return SupportDirectoryScreen(profile: widget.profile, initialTab: 0);
      case 'Licenses':
        return SubscriptionAdminScreen(profile: widget.profile);
      case 'Logins':
        return SupportDirectoryScreen(profile: widget.profile, initialTab: 1);
      case 'Support data':
        return PharmacyWorkspaceSettingsScreen(profile: widget.profile);
      case 'App updates':
        return AppUpdateScreen(profile: widget.profile);
      case 'Password':
        return PasswordSettingsView(profile: widget.profile);
      default:
        return _CustomerDashboard(profile: widget.profile);
    }
  }
}

class _CustomerDashboard extends StatelessWidget {
  const _CustomerDashboard({required this.profile});

  final UserProfile profile;

  String _fmt(DateTime? date) {
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _accessLabel(SubscriptionState license) {
    if (license.isBlocked) return 'Locked';
    if (license.isReadOnly) return 'View only';
    if (license.isTrial) return 'Trial';
    return 'Paid';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: PharmacyService().watchPharmacies(),
      builder: (context, shopSnap) {
        return StreamBuilder<List<UserProfile>>(
          stream: UserManagementService().watchUsers(),
          builder: (context, userSnap) {
            if (shopSnap.connectionState == ConnectionState.waiting && !shopSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (shopSnap.hasError && shopSnap.data == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Could not load customers. Open Shops to create or open pharmacies.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final shops = shopSnap.data ?? const <PharmacyRecord>[];
            final users = (userSnap.data ?? const <UserProfile>[]).where((user) => !user.isSuperAdmin).toList();
            try {
              return _dashboardBody(shops, users);
            } catch (_) {
              return const Center(child: Text('Could not draw the customer dashboard. Open Shops to work with pharmacies.'));
            }
          },
        );
      },
    );
  }

  Widget _dashboardBody(List<PharmacyRecord> shops, List<UserProfile> users) {
            final staffByShop = <String, int>{};
            for (final user in users) {
              final id = (user.pharmacyId ?? '').trim();
              if (id.isEmpty) continue;
              staffByShop[id] = (staffByShop[id] ?? 0) + 1;
            }

            var trials = 0, paid = 0, locked = 0, viewOnly = 0, endingSoon = 0;
            for (final shop in shops) {
              final license = SubscriptionService.licenseFromPharmacy(shop);
              if (license.isBlocked) {
                locked++;
              } else if (license.isReadOnly) {
                viewOnly++;
              } else if (license.isTrial) {
                trials++;
              } else {
                paid++;
              }
              if (license.canWrite && license.daysRemaining > 0 && license.daysRemaining <= 7) {
                endingSoon++;
              }
            }
            final greeting = profile.displayName.trim().isEmpty
                ? 'there'
                : profile.displayName.trim().split(RegExp(r'\s+')).first;

            return ListView(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                  decoration: BoxDecoration(
                    color: PhyimacyBrand.forest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('System console', style: GoogleFonts.inter(color: PhyimacyBrand.gold, fontWeight: FontWeight.w700, letterSpacing: 1.4, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text('Good day, $greeting.', style: GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white, height: 1.1)),
                      const SizedBox(height: 8),
                      Text(
                        'Your customers are the pharmacies on PharmSpecio. Create shops, grant licenses, and help logins here. Sales and stock stay inside each shop.',
                        style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.82), height: 1.45, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 1100;
                    final cardWidth = wide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;
                    Widget card(String label, String value, String note, IconData icon, Color color) {
                      return SizedBox(
                        width: cardWidth,
                        child: _metric(label, value, note, icon, color),
                      );
                    }
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        card('Shops', '${shops.length}', 'Customer pharmacies', Icons.storefront_rounded, const Color(0xffdff7ee)),
                        card('On trial', '$trials', 'Can still enter data', Icons.hourglass_bottom_rounded, const Color(0xffe8f1ff)),
                        card('Paid active', '$paid', 'Full access', Icons.verified_rounded, const Color(0xffdff7ee)),
                        card('Need you', '${locked + viewOnly + endingSoon}', '$endingSoon ending · $locked locked · $viewOnly view only', Icons.support_agent_rounded, const Color(0xffffeadf)),
                        card('Shop logins', '${users.length}', 'Admins and staff across shops', Icons.groups_rounded, const Color(0xfff2e7ff)),
                        card('Unlinked logins', '${users.where((user) => (user.pharmacyId ?? '').trim().isEmpty).length}', 'Login exists but no shop', Icons.link_off_rounded, const Color(0xfffff0d7)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer pharmacies', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                      const SizedBox(height: 8),
                      if (shops.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text('No shops yet. Open Shops to create a pharmacy and its admin login.'),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingTextStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12, color: PhyimacyBrand.ink),
                            columns: const [
                              DataColumn(label: Text('Shop')),
                              DataColumn(label: Text('Owner')),
                              DataColumn(label: Text('Access')),
                              DataColumn(label: Text('Ends')),
                              DataColumn(label: Text('Days left')),
                              DataColumn(label: Text('Logins')),
                            ],
                            rows: shops.map((shop) {
                              final license = SubscriptionService.licenseFromPharmacy(shop);
                              final owner = (shop.ownerEmail ?? '').trim();
                              return DataRow(
                                cells: [
                                  DataCell(Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  DataCell(Text(owner.isEmpty ? '—' : owner)),
                                  DataCell(Text(_accessLabel(license))),
                                  DataCell(Text(_fmt(license.licenseEndsAt))),
                                  DataCell(Text('${license.daysRemaining}')),
                                  DataCell(Text('${staffByShop[shop.id] ?? 0}')),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
  }

  Widget _metric(String label, String value, String note, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(backgroundColor: color, child: Icon(icon, color: PhyimacyBrand.teal)),
          const SizedBox(height: 12),
          Text(label, style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          const SizedBox(height: 4),
          Text(note, style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12, height: 1.3)),
        ],
      ),
    );
  }
}

class _SupportLoginsView extends StatefulWidget {
  const _SupportLoginsView({required this.profile});

  final UserProfile profile;

  @override
  State<_SupportLoginsView> createState() => _SupportLoginsViewState();
}

class _SupportLoginsViewState extends State<_SupportLoginsView> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: PharmacyService().watchPharmacies(),
      builder: (context, shopSnap) {
        final names = {for (final shop in shopSnap.data ?? const <PharmacyRecord>[]) shop.id: shop.name};
        return StreamBuilder<List<UserProfile>>(
          stream: UserManagementService().watchUsers(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Could not load logins: ${snapshot.error}');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final query = _query;
            final users = snapshot.data!.where((user) {
              if (user.isSuperAdmin) return false;
              if (query.isEmpty) return true;
              final shop = names[user.pharmacyId ?? ''] ?? '';
              return user.displayName.toLowerCase().contains(query) ||
                  user.email.toLowerCase().contains(query) ||
                  shop.toLowerCase().contains(query);
            }).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Help a shop login. You can disable an account or set a password. You do not sell or receive stock from here.', style: TextStyle(color: Color(0xff68807d), height: 1.4)),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                      if (!mounted) return;
                      setState(() => _query = _search.text.trim().toLowerCase());
                    });
                  },
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search name, email, or shop'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    child: users.isEmpty
                        ? const Center(child: Text('No matching logins.'))
                        : ListView.separated(
                            itemCount: users.length,
                            separatorBuilder: (_, index) => const Divider(height: 1, indent: 18),
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final shop = names[user.pharmacyId ?? ''] ?? ((user.pharmacyId ?? '').trim().isEmpty ? 'No shop linked' : 'Unknown shop');
                              return ListTile(
                                title: Text(user.displayName.isEmpty ? user.email : user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${user.email}  •  ${user.role}  •  $shop  •  ${user.isActive ? 'Active' : 'Disabled'}'),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    IconButton(
                                      tooltip: user.isActive ? 'Disable login' : 'Enable login',
                                      onPressed: () => UserManagementService().updateAccess(
                                        userId: user.id,
                                        role: user.role == 'super_admin' ? 'admin' : user.role,
                                        permissions: user.permissions,
                                        isActive: !user.isActive,
                                      ),
                                      icon: Icon(user.isActive ? Icons.person_off_outlined : Icons.person_outline_rounded, color: PhyimacyBrand.teal),
                                    ),
                                    IconButton(
                                      tooltip: 'Set password',
                                      onPressed: () => showManagedPasswordDialog(context, user),
                                      icon: const Icon(Icons.password_rounded, color: PhyimacyBrand.teal),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
