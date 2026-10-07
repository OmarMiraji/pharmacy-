import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/payment_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/tenant_context.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../theme/brand.dart';
import '../l10n/app_locale.dart';
import '../widgets/language_toggle.dart';
import 'announcements_admin_screen.dart';
import 'login_logs_screen.dart';
import 'app_update_screen.dart';
import 'audit_logs_screen.dart';
import 'chat_assistant_panel.dart';
import 'customers_console_screen.dart';
import 'password_security.dart';
import 'payments_admin_screen.dart';
import 'pharmacy_workspace_settings_screen.dart';
import 'security_center_screen.dart';
import 'subscription_admin_screen.dart';
import 'support_directory_screen.dart';

class SuperAdminHome extends StatefulWidget {
  const SuperAdminHome({required this.profile, required this.authService, super.key});

  final UserProfile profile;
  final AuthService authService;

  @override
  State<SuperAdminHome> createState() => _SuperAdminHomeState();
}

class _NavDest {
  const _NavDest(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

class _NavSection {
  const _NavSection(this.title, this.items);
  final String title;
  final List<_NavDest> items;
}

class _SuperAdminHomeState extends State<SuperAdminHome> {
  String _id = 'dashboard';

  List<_NavSection> get _sections => [
        _NavSection('OVERVIEW', [
          _NavDest('dashboard', S.t('Dashboard', 'Dashibodi'), Icons.dashboard_rounded),
          _NavDest('logins', S.t('Login logs', 'Muda wa kuingia'), Icons.schedule_rounded),
          _NavDest('updates', S.t('App updates', 'Updates'), Icons.system_update_alt_rounded),
        ]),
        _NavSection('CUSTOMERS', [
          _NavDest('customers', S.t('Customers', 'Wateja'), Icons.groups_rounded),
          _NavDest('shops', S.t('Pharmacies / Shops', 'Maduka'), Icons.storefront_rounded),
          _NavDest('users', S.t('Users & Logins', 'Watumiaji'), Icons.manage_accounts_outlined),
        ]),
        _NavSection('LICENSING', [
          _NavDest('licenses', S.t('Licenses', 'Leseni'), Icons.workspace_premium_rounded),
          _NavDest('payments', S.t('Payments', 'Malipo'), Icons.payments_outlined),
        ]),
        _NavSection('SYSTEM', [
          _NavDest('support', S.t('Support data', 'Data ya msaada'), Icons.storage_rounded),
          _NavDest('audit', S.t('Audit logs', 'Audit'), Icons.receipt_long_rounded),
          _NavDest('security', S.t('Security', 'Usalama'), Icons.shield_outlined),
        ]),
        _NavSection('UPDATES', [
          _NavDest('announcements', S.t('Announcements', 'Matangazo'), Icons.campaign_outlined),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final destinations = [for (final section in _sections) ...section.items];
        final selected = destinations.firstWhere((item) => item.id == _id, orElse: () => destinations.first);
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
                        Text(S.t('System control', 'Udhibiti wa mfumo'), style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.78), fontSize: 13.5)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      children: [
                        for (final section in _sections) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                            child: Text(section.title, style: GoogleFonts.inter(color: PhyimacyBrand.gold.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
                          ),
                          for (final item in section.items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => setState(() => _id = item.id),
                                  borderRadius: BorderRadius.circular(16),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: _id == item.id ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(item.icon, color: Colors.white, size: 22),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(item.label, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
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
                            Text(selected.label, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink, height: 1.1)),
                            Text(
                              '${S.t('Logged in as', 'Umeingia kama')} ${widget.profile.email} · Super Admin',
                              style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.muted),
                            ),
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
                    child: _page(selected.id),
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

  Widget _page(String id) {
    final child = _body(id);
    if (id == 'licenses' || id == 'updates' || id == 'support') {
      return SingleChildScrollView(child: child);
    }
    return child;
  }

  Widget _body(String id) {
    switch (id) {
      case 'customers':
        return const CustomersConsoleScreen();
      case 'shops':
        return SupportDirectoryScreen(profile: widget.profile, initialTab: 0);
      case 'users':
        return SupportDirectoryScreen(profile: widget.profile, initialTab: 1);
      case 'licenses':
        return SubscriptionAdminScreen(profile: widget.profile);
      case 'payments':
        return const PaymentsAdminScreen();
      case 'support':
        return PharmacyWorkspaceSettingsScreen(profile: widget.profile);
      case 'audit':
        return const AuditLogsScreen();
      case 'logins':
        return const LoginLogsScreen();
      case 'security':
        return const SecurityCenterScreen();
      case 'updates':
        return AppUpdateScreen(profile: widget.profile);
      case 'announcements':
        return const AnnouncementsAdminScreen();
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
            return StreamBuilder<List<LicensePayment>>(
              stream: PaymentService().watch(),
              builder: (context, paySnap) {
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
            final users = userSnap.data ?? const <UserProfile>[];
            try {
              return _dashboardBody(shops, users, paySnap.data ?? const <LicensePayment>[]);
            } catch (_) {
              return const Center(child: Text('Could not draw the customer dashboard. Open Shops to work with pharmacies.'));
            }
              },
            );
          },
        );
      },
    );
  }

  Widget _dashboardBody(List<PharmacyRecord> shops, List<UserProfile> users, List<LicensePayment> payments) {
            final staffByShop = <String, int>{};
            for (final user in users) {
              final id = (user.pharmacyId ?? '').trim();
              if (id.isEmpty) continue;
              staffByShop[id] = (staffByShop[id] ?? 0) + 1;
            }

            var trials = 0, paid = 0, locked = 0, viewOnly = 0, endingSoon = 0, expired = 0;
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
              if (license.hasExpired) expired++;
              if (license.canWrite && license.daysRemaining > 0 && license.daysRemaining <= 7) {
                endingSoon++;
              }
            }
            final pendingPay = payments.where((row) => row.status == 'pending').length;
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
                        'Your customers are the pharmacies on PharmSpecio. Create shops, grant licenses, and help logins here. Sales and stock stay inside each shop. App updates is in the left menu: a new version reaches every shop only after you publish it and each shop installs it.',
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
                        card('Active pharmacies', '${shops.length - locked}', 'Not locked', Icons.storefront_rounded, const Color(0xffdff7ee)),
                        card('Expired', '$expired', 'Need a new token', Icons.event_busy_rounded, const Color(0xffffeadf)),
                        card('On trial', '$trials', 'Can still enter data', Icons.hourglass_bottom_rounded, const Color(0xffe8f1ff)),
                        card('Pending payments', '$pendingPay', 'Verify then grant license', Icons.payments_outlined, const Color(0xfffff0d7)),
                        card('Paid active', '$paid', 'Full access', Icons.verified_rounded, const Color(0xffdff7ee)),
                        card('Shop logins', '${users.length}', 'Admins and staff across shops', Icons.groups_rounded, const Color(0xfff2e7ff)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Subscription alerts', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                      const SizedBox(height: 8),
                      Text('⚠ $endingSoon pharmacies expire within 7 days'),
                      Text('⚠ $pendingPay pending payments to verify'),
                      Text('⚠ $locked pharmacies are locked'),
                      Text('⚠ $viewOnly paid shops are view-only after expiry'),
                    ],
                  ),
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
                      Text(S.t('Logins', 'Login'), style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                      const SizedBox(height: 8),
                      if (users.isEmpty)
                        Text(S.t('No logins in Firebase yet.', 'Bado hakuna login kwenye Firebase.'))
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingTextStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12, color: PhyimacyBrand.ink),
                            columns: [
                              DataColumn(label: Text(S.t('Name', 'Jina'))),
                              DataColumn(label: Text(S.t('Email / login', 'Email / login'))),
                              DataColumn(label: Text(S.t('Role', 'Wajibu'))),
                              DataColumn(label: Text(S.t('Shop', 'Duka'))),
                              DataColumn(label: Text(S.t('Status', 'Hali'))),
                            ],
                            rows: [
                              for (final user in users)
                                DataRow(
                                  cells: [
                                    DataCell(Text(user.displayName.isEmpty ? '—' : user.displayName)),
                                    DataCell(Text(user.email)),
                                    DataCell(Text(user.isSuperAdmin ? 'super admin' : user.role)),
                                    DataCell(Text(_loginShopLabel(user, shops))),
                                    DataCell(Text(user.isActive ? S.t('Active', 'Hai') : S.t('Disabled', 'Imefungwa'))),
                                  ],
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
  }

  String _loginShopLabel(UserProfile user, List<PharmacyRecord> shops) {
    for (final shop in shops) {
      if (shop.id == user.pharmacyId) return shop.name;
    }
    if (user.isSuperAdmin) return 'System';
    return '—';
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
