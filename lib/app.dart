import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';
import 'backend/announcement_service.dart';
import 'backend/app_update_service.dart';
import 'backend/auth_service.dart';
import 'backend/firestore_collections.dart';
import 'backend/inventory_service.dart';
import 'backend/medicine_service.dart';
import 'backend/medicine_match.dart';
import 'backend/models.dart';
import 'backend/offline_sync_service.dart';
import 'backend/purchase_service.dart';
import 'backend/sales_service.dart';
import 'backend/receipt_service.dart';
import 'backend/permissions.dart';
import 'backend/subscription_service.dart';
import 'backend/user_management_service.dart';
import 'backend/user_profile.dart';
import 'backend/import_service.dart';
import 'backend/pharmacy_service.dart';
import 'backend/printer_settings.dart';
import 'backend/tanzania_phone.dart';
import 'backend/tenant_context.dart';
import 'backend/transactional_email_service.dart';
import 'backend/expiry_priority.dart';
import 'backend/expiry_stock.dart';
import 'backend/selling_units.dart';
import 'backend/shop_alerts.dart';
import 'l10n/app_locale.dart';
import 'theme/brand.dart';
import 'widgets/app_notice.dart';
import 'screens/subscription_admin_screen.dart';
import 'screens/receive_purchase_dialog.dart';
import 'screens/super_admin_home.dart';
import 'screens/pharmacy_workspace_settings_screen.dart';
import 'screens/app_update_screen.dart';
import 'screens/apply_app_update.dart';
import 'screens/accounts_admin_screen.dart';
import 'screens/password_security.dart';
import 'screens/staff_account_dialogs.dart';
import 'screens/chat_assistant_panel.dart';
import 'screens/login_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/suppliers_screen.dart';
import 'widgets/shop_alert_bell.dart';
import 'widgets/language_toggle.dart';

class PhyimacyApp extends StatelessWidget {
  const PhyimacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: PhyimacyBrand.appName,
      debugShowCheckedModeBanner: false,
      theme: PhyimacyBrand.material,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_authService.signOut());
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF073B3A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF5EEAD4)),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return ProfileLoader(authService: _authService, userId: user.uid);
      },
    );
  }
}

class ProfileLoader extends StatefulWidget {
  const ProfileLoader({required this.authService, required this.userId, super.key});

  final AuthService authService;
  final String userId;

  @override
  State<ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<ProfileLoader> {
  late Future<_LoadedWorkspace> _workspaceFuture;

  @override
  void initState() {
    super.initState();
    _workspaceFuture = _loadWorkspace();
  }

  @override
  void didUpdateWidget(covariant ProfileLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _workspaceFuture = _loadWorkspace();
    }
  }

  Future<_LoadedWorkspace> _loadWorkspace() async {
    try {
      final profile = await widget.authService.currentUserProfile().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('timed-out'),
      );
      if (profile == null) {
        AuthService.workspaceError =
            'No account was found for this email. Ask your administrator to create your login.';
        await widget.authService.signOut();
        throw StateError('login-rejected');
      }
      if (!profile.isActive) {
        AuthService.workspaceError = 'This account is disabled. Contact your administrator.';
        await widget.authService.signOut();
        throw StateError('login-rejected');
      }
      final session = await PharmacyService().bindSession(profile).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('timed-out'),
      );
      AuthService.workspaceError = null;
      return _LoadedWorkspace(
        profile: profile,
        license: session.license,
        readOnly: session.readOnly,
        blocked: session.blocked,
      );
    } catch (error) {
      TenantContext.instance.clear();
      final alreadySet = (AuthService.workspaceError ?? '').trim().isNotEmpty;
      if (!alreadySet) {
        final detail = '$error';
        if (detail.contains('not assigned to a shop')) {
          AuthService.workspaceError = 'This account is not assigned to a shop. Contact your administrator.';
        } else if (error is TimeoutException) {
          AuthService.workspaceError = 'Sign-in timed out. Check your internet connection and try again.';
        } else {
          AuthService.workspaceError = 'Could not sign in. Check your details or contact your administrator.';
        }
      }
      if (widget.authService.currentUser != null) {
        await widget.authService.signOut();
      }
      rethrow;
    }
  }

  void _reloadWorkspace() {
    setState(() {
      _workspaceFuture = _loadWorkspace();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedWorkspace>(
      future: _workspaceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF7F4EC),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF0F766E)),
                  SizedBox(height: 16),
                  Text('Opening your shopâ€¦'),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final workspace = snapshot.data;
        final profile = workspace?.profile;
        if (profile == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!profile.isActive) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (profile.isSuperAdmin) {
          return SuperAdminHome(profile: profile, authService: widget.authService);
        }
        if (workspace?.blocked == true) {
          return SubscriptionGateScreen(
            subscription: workspace?.license ??
                const SubscriptionState(
                  status: 'locked',
                  plan: 'trial',
                  trialEndsAt: null,
                  expiresAt: null,
                  isUnlocked: false,
                  isTrial: true,
                  access: PharmacyAccess.blocked,
                  message: 'The free trial has ended. Activate a valid token after payment.',
                ),
            onActivated: _reloadWorkspace,
          );
        }
        return DashboardScreen(
          profile: profile,
          authService: widget.authService,
          license: workspace?.license,
          readOnly: workspace?.readOnly == true,
          onLicenseChanged: _reloadWorkspace,
        );
      },
    );
  }
}

class _LoadedWorkspace {
  const _LoadedWorkspace({this.profile, this.license, this.readOnly = false, this.blocked = false});

  final UserProfile? profile;
  final SubscriptionState? license;
  final bool readOnly;
  final bool blocked;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.profile,
    required this.authService,
    this.license,
    this.readOnly = false,
    this.onLicenseChanged,
    super.key,
  });

  final UserProfile profile;
  final AuthService authService;
  final SubscriptionState? license;
  final bool readOnly;
  final VoidCallback? onLicenseChanged;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  int _medicinesTab = 0;
  AppUpdateCheck? _appUpdate;

  @override
  void initState() {
    super.initState();
    unawaited(OfflineSyncService.instance.start());
    AppUpdateService().check().then((value) {
      if (mounted) setState(() => _appUpdate = value);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    OfflineSyncService.instance.stop();
    super.dispose();
  }

  Future<void> _openSubscribeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 980,
          height: 640,
          child: SubscriptionGateScreen(
            embedded: true,
            subscription: widget.license ??
                const SubscriptionState(
                  status: 'locked',
                  plan: 'trial',
                  trialEndsAt: null,
                  expiresAt: null,
                  isUnlocked: false,
                  isTrial: true,
                  access: PharmacyAccess.readOnly,
                  message: 'Activate this pharmacy with a token.',
                ),
            onActivated: () {
              Navigator.pop(dialogContext);
              widget.onLicenseChanged?.call();
            },
          ),
        ),
      ),
    );
  }

  List<_DashboardDestination> get _destinations {
    if (widget.profile.isSuperAdmin) {
      return [
        _DashboardDestination(id: 'customers', label: S.t('Customers', 'Wateja'), icon: Icons.groups_rounded),
      ];
    }
    return [
        if (widget.profile.can('dashboard.view'))
          _DashboardDestination(id: 'overview', label: S.t('Overview', 'Muhtasari'), icon: Icons.grid_view_rounded),
        if (widget.profile.can('medicines.view') || widget.profile.can('inventory.view'))
          _DashboardDestination(id: 'medicines', label: S.t('Medicines', 'Dawa'), icon: Icons.medication_outlined),
        if (widget.profile.can('sales.view'))
          _DashboardDestination(id: 'sales', label: S.t('Sales', 'Mauzo'), icon: Icons.point_of_sale_outlined),
        if (widget.profile.can('purchases.view') || widget.profile.can('suppliers.manage'))
          _DashboardDestination(id: 'purchases', label: S.t('Purchases', 'Manunuzi'), icon: Icons.shopping_cart_outlined),
        if (widget.profile.can('reports.view'))
          _DashboardDestination(id: 'reports', label: S.t('Reports', 'Ripoti'), icon: Icons.bar_chart_rounded),
        if (widget.profile.can('users.manage') || widget.profile.can('settings.manage') || widget.profile.isSuperAdmin)
          _DashboardDestination(id: 'settings', label: S.t('Settings', 'Mipangilio'), icon: Icons.settings_outlined),
        if (widget.profile.isSuperAdmin)
          _DashboardDestination(id: 'system', label: S.t('System', 'Mfumo'), icon: Icons.admin_panel_settings_rounded),
      ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final destinations = _destinations;
        final safeIndex = destinations.isEmpty ? 0 : _selectedIndex.clamp(0, destinations.length - 1);
        final selected = destinations.isEmpty ? null : destinations[safeIndex];
        return Scaffold(
      backgroundColor: PhyimacyBrand.cream,
      body: Stack(
        children: [
          Row(
            children: [
          _Sidebar(
            profile: widget.profile,
            destinations: destinations,
            selectedIndex: destinations.isEmpty ? null : safeIndex,
            onSelected: (index) => setState(() => _selectedIndex = index),
            onChangePassword: () => showChangeOwnPasswordDialog(context),
            onSignOut: () {
              OfflineSyncService.instance.stop();
              TenantContext.instance.clear();
              widget.authService.signOut();
            },
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  profile: widget.profile,
                  title: selected?.label ?? PhyimacyBrand.appName,
                  onOpenExpired: () {
                    final index = destinations.indexWhere((item) => item.id == 'medicines');
                    if (index < 0) return;
                    setState(() {
                      _selectedIndex = index;
                      _medicinesTab = 2;
                    });
                  },
                ),
                ListenableBuilder(
                  listenable: OfflineSyncService.instance,
                  builder: (context, _) {
                    final sync = OfflineSyncService.instance;
                    if (sync.isOnline && sync.pendingCount == 0 && !sync.isSyncing) {
                      return const SizedBox.shrink();
                    }
                    final title = !sync.isOnline
                        ? S.t('No internet — using saved shop data', 'Hakuna intaneti — inatumia data iliyohifadhiwa')
                        : sync.isSyncing
                            ? S.t('Sending saved sales...', 'Inatuma mauzo yaliyohifadhiwa...')
                            : '${sync.pendingCount} saved sale${sync.pendingCount == 1 ? '' : 's'} waiting to send';
                    final subtitle = !sync.isOnline
                        ? (sync.pendingCount == 0
                            ? S.t('Sales still work on this PC. They send when the connection returns.', 'Mauzo bado yanaweza kufanyika. Yatatoka intaneti irudipo.')
                            : '${sync.pendingCount} sale${sync.pendingCount == 1 ? '' : 's'} saved on this computer.')
                        : (sync.lastError ?? 'Tap Send now if they stay here after the connection is back.');
                    return Material(
                      color: sync.isOnline ? const Color(0xffe8f6f2) : const Color(0xfffff4e5),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        child: Row(
                          children: [
                            Icon(
                              sync.isOnline ? Icons.cloud_upload_outlined : Icons.wifi_off_rounded,
                              color: sync.isOnline ? const Color(0xff0f766e) : const Color(0xffb45309),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.3)),
                                ],
                              ),
                            ),
                            if (sync.isOnline && sync.pendingCount > 0 && !sync.isSyncing)
                              TextButton(
                                onPressed: () => unawaited(sync.syncPending()),
                                child: const Text('Send now'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (_appUpdate?.updateAvailable == true && _appUpdate?.latest != null)
                  Material(
                    color: const Color(0xffe8f6f2),
                    child: ListTile(
                      leading: const Icon(Icons.system_update_alt_rounded, color: Color(0xff0f766e)),
                      title: Text('New version ${_appUpdate!.latest!.version} is available'),
                      trailing: FilledButton(
                        onPressed: _appUpdate!.latest!.canAutoInstall
                            ? () => applyPhyimacyUpdate(context, _appUpdate!.latest!)
                            : null,
                        child: const Text('Update now'),
                      ),
                    ),
                  ),
                StreamBuilder<List<Announcement>>(
                  stream: AnnouncementService().watchActive(),
                  builder: (context, snapshot) {
                    final notes = snapshot.data ?? const <Announcement>[];
                    if (notes.isEmpty) return const SizedBox.shrink();
                    final note = notes.first;
                    return Material(
                      color: const Color(0xffe8f1ff),
                      child: ListTile(
                        leading: const Icon(Icons.campaign_outlined, color: Color(0xff1d4ed8)),
                        title: Text(note.title),
                        subtitle: Text(note.body),
                      ),
                    );
                  },
                ),
                if (widget.license?.isTrial == true && widget.readOnly == false && widget.license?.isBlocked != true)
                  Material(
                    color: const Color(0xfffff4e5),
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined, color: Color(0xffb45309)),
                      title: Text(
                        widget.license?.trialCountdownLabel.isNotEmpty == true
                            ? widget.license!.trialCountdownLabel
                            : (widget.license?.message ?? S.t('Free trial is active.', 'Jaribio la bure linaendelea.')),
                      ),
                      subtitle: Text(
                        widget.license?.licenseEndsAt == null
                            ? S.t(
                                'Pay for a professional plan, then enter the activation code you receive.',
                                'Lipia mpango wa kitaalamu, kisha weka namba ya kuwezesha utakayopewa.',
                              )
                            : S.t(
                                'Trial ends ${widget.license!.licenseEndsAt!.day}/${widget.license!.licenseEndsAt!.month}/${widget.license!.licenseEndsAt!.year}. After that date the shop locks until you pay and enter a code.',
                                'Jaribio linaisha ${widget.license!.licenseEndsAt!.day}/${widget.license!.licenseEndsAt!.month}/${widget.license!.licenseEndsAt!.year}. Baada ya hiyo tarehe duka linafungwa hadi ulipe na uweke namba.',
                              ),
                      ),
                      trailing: FilledButton(
                        onPressed: _openSubscribeDialog,
                        child: Text(S.t('Subscribe / enter code', 'Jiandikishe / weka namba')),
                      ),
                    ),
                  ),
                if (widget.readOnly)
                  Material(
                    color: const Color(0xfffff4e5),
                    child: ListTile(
                      leading: const Icon(Icons.lock_clock_rounded, color: Color(0xffb45309)),
                      title: Text(
                        widget.license?.message ??
                            S.t(
                              'Paid subscription has ended. You can view records only until a new token is activated.',
                              'Usajili uliolipwa umeisha. Unaweza kuona kumbukumbu tu hadi namba mpya iwezeshwe.',
                            ),
                      ),
                      trailing: FilledButton(
                        onPressed: _openSubscribeDialog,
                        child: Text(S.t('Activate token', 'Weka namba')),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    child: _buildContent(selected?.id),
                  ),
                ),
              ],
            ),
          ),
        ],
          ),
          if (!widget.profile.isSuperAdmin) const ShopAssistantDock(),
        ],
      ),
    );
      },
    );
  }

  Widget _buildContent(String? destination) {
    switch (destination) {
      case 'medicines':
        return MedicinesScreen(key: ValueKey('medicines-$_medicinesTab'), profile: widget.profile, initialTab: _medicinesTab);
      case 'sales':
        return SalesScreen(profile: widget.profile);
      case 'purchases':
        return PurchasesScreen(profile: widget.profile);
      case 'reports':
        return const ReportsScreen();
      case 'settings':
        return SettingsScreen(profile: widget.profile);
      case 'system':
        return AccountsAdminScreen(profile: widget.profile);
      default:
        return OverviewScreen(profile: widget.profile);
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.profile,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onChangePassword,
    required this.onSignOut,
  });

  final UserProfile profile;
  final List<_DashboardDestination> destinations;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final shop = TenantContext.instance.pharmacyName ?? 'Pharmacy POS';
    return SizedBox(
      width: 296,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF052E2D)),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 210,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/pharmacy-shelves.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0.2, 0),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x66052E2D),
                            Color(0xE6052E2D),
                            Color(0xFF052E2D),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandMark(size: 40),
                      const SizedBox(height: 12),
                      Text(
                        PhyimacyBrand.appName,
                        style: GoogleFonts.playfairDisplay(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          fontSize: 22,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 3,
                        decoration: BoxDecoration(
                          color: PhyimacyBrand.gold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        shop,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
                  child: Text(
                    S.t('WORKSPACE', 'KAZI'),
                    style: GoogleFonts.inter(
                      color: PhyimacyBrand.gold.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    itemCount: destinations.length,
                    itemBuilder: (context, index) {
                      final destination = destinations[index];
                      final active = selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => onSelected(index),
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                              decoration: BoxDecoration(
                                color: active ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: Border(
                                  left: BorderSide(
                                    color: active ? PhyimacyBrand.gold : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    destination.icon,
                                    size: 24,
                                    color: active ? PhyimacyBrand.gold : const Color(0xFFC5DDD7),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      destination.label,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 15.5,
                                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
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
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: PhyimacyBrand.gold,
                          child: Text(
                            profile.displayName.isEmpty ? '?' : profile.displayName[0].toUpperCase(),
                            style: const TextStyle(color: Color(0xff573719), fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                S.role(profile.role),
                                style: GoogleFonts.inter(color: const Color(0xFFB7D4CC), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: S.t('Change password', 'Badilisha nenosiri'),
                          visualDensity: VisualDensity.compact,
                          onPressed: onChangePassword,
                          icon: const Icon(Icons.lock_reset_rounded, color: Color(0xFFB7D4CC), size: 21),
                        ),
                        IconButton(
                          tooltip: S.t('Sign out', 'Toka'),
                          visualDensity: VisualDensity.compact,
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_rounded, color: Color(0xFFB7D4CC), size: 21),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.profile, required this.title, this.onOpenExpired});

  final UserProfile profile;
  final String title;
  final VoidCallback? onOpenExpired;

  @override
  Widget build(BuildContext context) {
    final shop = TenantContext.instance.pharmacyName;
    return Container(
      height: 78,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: PhyimacyBrand.ink,
                    height: 1.1,
                  ),
                ),
                if ((shop ?? '').trim().isNotEmpty)
                  Text(shop!, style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.muted)),
              ],
            ),
          ),
          if (!profile.isSuperAdmin) ShopAlertBell(onOpenExpired: onOpenExpired),
          const LanguageToggle(compact: true),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: PhyimacyBrand.cream,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(profile.email, style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.muted)),
          ),
        ],
      ),
    );
  }
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late Future<_OverviewData> _overviewFuture;
  _OverviewData? _lastOverview;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _overviewFuture = _loadOverviewData().then((data) {
      _lastOverview = data;
      return data;
    });
  }

  Future<_OverviewData> _loadOverviewData({bool fromServer = false}) async {
    final firestore = FirebaseFirestore.instance;
    final tenant = TenantContext.instance;
    final options = fromServer ? const GetOptions(source: Source.server) : const GetOptions();
    if ((tenant.pharmacyId ?? '').trim().isEmpty) {
      return const _OverviewData(
        stockItems: 0,
        stockUnits: 0,
        lowStockCount: 0,
        todaySalesCount: 0,
        todaySalesMinor: 0,
        expirySoonCount: 0,
        expiredCount: 0,
        notifySoonCount: 0,
        weeklyRevenue: [],
        healthyStockCount: 0,
        recentSales: [],
      );
    }
    try {
      final medicinesSnapshot = await tenant.scoped(firestore.collection(FirestoreCollections.medicines)).get(options);
      final batchesSnapshot = await tenant.scoped(firestore.collection(FirestoreCollections.medicineBatches)).get(options);
      final salesDocs = widget.profile.canSeeSalesTotals
          ? (await tenant.scoped(firestore.collection(FirestoreCollections.sales)).get(options)).docs
          : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final medicines = medicinesSnapshot.docs;
    final lowStockCount = medicines.where((doc) {
      final data = doc.data();
      final stock = (data['quantityOnHand'] as num?)?.toInt() ?? 0;
      final reorder = (data['reorderLevel'] as num?)?.toInt() ?? 0;
      return stock <= reorder;
    }).length;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final liveSales = salesDocs.where((doc) {
      final status = (doc.data()['status'] as String?) ?? 'completed';
      return status != 'voided' && status != 'refunded';
    }).toList();

    final todaySales = liveSales.where((doc) {
      final value = doc.data()['createdAt'];
      final createdAt = value is Timestamp ? value.toDate() : null;
      return createdAt != null && createdAt.isAfter(todayStart) && createdAt.isBefore(todayEnd);
    }).toList();

    final todaySalesMinor = todaySales.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
    final medicineModels = medicinesSnapshot.docs.map(Medicine.fromFirestore).toList();
    final batchModels = batchesSnapshot.docs.map(MedicineBatch.fromFirestore).toList();
    final expiredLines = ExpiryStock.expiredLines(medicineModels, batchModels);
    final expirySoonCount = batchModels.where((batch) {
      if (batch.quantityOnHand <= 0 && medicineModels.every((medicine) => medicine.id != batch.medicineId || medicine.quantityOnHand <= 0)) {
        return false;
      }
      final expiry = batch.expiryDate.toDate();
      return ExpiryPriority.isUrgent(expiry) || ExpiryPriority.isWatch(expiry);
    }).length;
    final expiredCount = expiredLines.length;
    final notifySoonCount = ShopAlerts.fromStock(medicineModels, batchModels)
        .where((alert) => alert.kind == ShopAlertKind.expiringSoon)
        .length;

    final weeklyRevenue = <_WeeklyRevenuePoint>[];
    for (int offset = 6; offset >= 0; offset--) {
      final dayStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: offset));
      final nextDay = dayStart.add(const Duration(days: 1));
      final dayRevenue = liveSales.where((doc) {
        final value = doc.data()['createdAt'];
        final createdAt = value is Timestamp ? value.toDate() : null;
        return createdAt != null && !createdAt.isBefore(dayStart) && createdAt.isBefore(nextDay);
      }).fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
      weeklyRevenue.add(_WeeklyRevenuePoint(day: dayStart, revenueMinor: dayRevenue));
    }

    final sortedSales = liveSales.toList()
      ..sort((a, b) {
        final left = a.data()['createdAt'];
        final right = b.data()['createdAt'];
        final leftDate = left is Timestamp ? left.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = right is Timestamp ? right.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });
    final recentDocs = sortedSales.take(5).toList();
    final recentSales = <_RecentSaleEntry>[];
    for (final doc in recentDocs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] is Timestamp) ? (data['createdAt'] as Timestamp).toDate() : DateTime.now();
      var names = ((data['itemNames'] as List?) ?? const []).whereType<String>().where((name) => name.trim().isNotEmpty).toList();
      if (names.isEmpty) {
        try {
          final items = await doc.reference.collection(FirestoreCollections.saleItems).get();
          names = items.docs
              .map((item) => (item.data()['medicineName'] as String?) ?? '')
              .where((name) => name.trim().isNotEmpty)
              .toList();
        } catch (_) {}
      }
      recentSales.add(
        _RecentSaleEntry(
          id: doc.id,
          receiptNumber: (data['receiptNumber'] as String?) ?? 'Receipt',
          totalMinor: (data['totalMinor'] as num?)?.toInt() ?? 0,
          paymentMethod: (data['paymentMethod'] as String?) ?? 'cash',
          createdAt: createdAt,
          medicineNames: names,
        ),
      );
    }

    final healthyStockCount = medicines.length - lowStockCount;
    final totalUnits = medicines.fold<int>(0, (total, doc) => total + ((doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0));

    return _OverviewData(
      stockItems: medicines.length,
      stockUnits: totalUnits,
      lowStockCount: lowStockCount,
      todaySalesCount: todaySales.length,
      todaySalesMinor: todaySalesMinor,
      expirySoonCount: expirySoonCount,
      expiredCount: expiredCount,
      notifySoonCount: notifySoonCount,
      weeklyRevenue: weeklyRevenue,
      healthyStockCount: healthyStockCount,
      recentSales: recentSales,
    );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return const _OverviewData(
          stockItems: 0,
          stockUnits: 0,
          lowStockCount: 0,
          todaySalesCount: 0,
          todaySalesMinor: 0,
          expirySoonCount: 0,
          expiredCount: 0,
          notifySoonCount: 0,
          weeklyRevenue: [],
          healthyStockCount: 0,
          recentSales: [],
        );
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final next = _loadOverviewData(fromServer: true);
    setState(() {
      _refreshing = true;
      _overviewFuture = next;
    });
    try {
      _lastOverview = await next;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _voidSale(_RecentSaleEntry sale) async {
    try {
      await SalesService().voidSale(sale.id);
      if (!mounted) return;
      showAppNotice(context, S.t('Sale voided. Stock put back.', 'Mauzo yamefutwa. Stock imerudishwa.'));
      await _refresh();
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OverviewData>(
      future: _overviewFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load overview: ${snapshot.error}'));
        }
        final summary = snapshot.data ?? _lastOverview;
        if (summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final canSeeSales = widget.profile.canSeeSalesTotals;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 188,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/pharmacy-shelves.jpg',
                        fit: BoxFit.cover,
                        alignment: const Alignment(0.1, 0),
                      ),
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                Color(0x33052E2D),
                                Color(0xCC052E2D),
                                Color(0xF2052E2D),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.t('Good day, ${widget.profile.displayName.split(' ').first}.', 'Habari, ${widget.profile.displayName.split(' ').first}.'),
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              S.t('Here is what is happening in your pharmacy right now.', 'Hivi ndivyo duka lako lilivyo sasa.'),
                              style: GoogleFonts.inter(color: const Color(0xFFE7F6F2), fontSize: 14.5, height: 1.35),
                            ),
                            const Spacer(),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: TextButton.icon(
                                onPressed: _refreshing ? null : _refresh,
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                icon: _refreshing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(S.t('Refresh', 'Onyesha upya')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: _MetricCard(label: S.t('Stock items', 'Bidhaa kwenye stock'), value: '${summary.stockItems}', note: S.t('${summary.stockUnits} units in hand', 'Vipande ${summary.stockUnits} vipo'), icon: Icons.inventory_2_outlined, color: const Color(0xffdff7ee))),
                const SizedBox(width: 14),
                Expanded(child: _MetricCard(label: S.t('Low stock', 'Stock chini'), value: '${summary.lowStockCount}', note: S.t('Needs reorder attention', 'Inahitaji kuagiza tena'), icon: Icons.warning_amber_rounded, color: const Color(0xfffff0d7))),
                const SizedBox(width: 14),
                Expanded(
                  child: canSeeSales
                      ? _MetricCard(label: S.t("Today's sales", 'Mauzo ya leo'), value: 'TZS ${summary.todaySalesMinor}', note: S.t('${summary.todaySalesCount} completed sales', 'Mauzo ${summary.todaySalesCount} yamekamilika'), icon: Icons.trending_up_rounded, color: const Color(0xffe2efff))
                      : _MetricCard(label: S.t('Expiring in 2 months', 'Zinaisha miezi 2'), value: '${summary.notifySoonCount}', note: S.t('Sell these first', 'Ziuzwe kwanza'), icon: Icons.hourglass_bottom_rounded, color: const Color(0xfffff0d7)),
                ),
                const SizedBox(width: 14),
                Expanded(child: _MetricCard(label: S.t('Expired stock', 'Stock iliyoisha'), value: '${summary.expiredCount}', note: S.t('${summary.notifySoonCount} within 2 months', 'Bidhaa ${summary.notifySoonCount} ndani ya miezi 2'), icon: Icons.event_busy_rounded, color: const Color(0xffffeadf))),
              ]),
              if (summary.expiredCount > 0) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xffffeadf),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_busy_rounded, color: Color(0xffc2410c)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${summary.expiredCount} batches have already expired. Open Medicines → Expired and remove them from stock. That write-off is recorded.',
                          style: GoogleFonts.inter(color: const Color(0xff9a3412), fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (summary.expirySoonCount > 0) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xfffff0d7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.priority_high_rounded, color: Color(0xffc2410c)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${summary.expirySoonCount} batches expire within 90 days. Sell these first — POS already puts the nearest expiry at the top.',
                          style: GoogleFonts.inter(color: const Color(0xff9a3412), fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (summary.notifySoonCount > 0) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xfffff0d7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: Color(0xffc2410c)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${summary.notifySoonCount} medicine${summary.notifySoonCount == 1 ? '' : 's'} expire within 2 months. Open the bell for details, then sell them first.',
                          style: GoogleFonts.inter(color: const Color(0xff9a3412), fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canSeeSales) ...[
                    Expanded(
                      flex: 2,
                      child: _OverviewPanel(
                        title: S.t('Weekly sales revenue', 'Mauzo ya wiki'),
                        icon: Icons.bar_chart_rounded,
                        child: SizedBox(height: 180, child: _SalesBarChart(points: summary.weeklyRevenue)),
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  Expanded(
                    child: _OverviewPanel(
                      title: S.t('Stock health', 'Hali ya stock'),
                      icon: Icons.pie_chart_outline_rounded,
                      child: SizedBox(
                        height: 168,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 280;
                                final pie = compact ? 84.0 : 148.0;
                                return Row(
                              children: [
                                SizedBox(
                                  width: pie,
                                  height: pie,
                                  child: CustomPaint(
                                    painter: _StockHealthPainter(
                                      healthyPercent: summary.stockItems > 0 ? (summary.healthyStockCount / summary.stockItems) * 100 : 0,
                                      lowPercent: summary.stockItems > 0 ? (summary.lowStockCount / summary.stockItems) * 100 : 0,
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 10 : 22),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _LegendRow(label: 'Healthy', value: '${summary.healthyStockCount}', color: const Color(0xff0f766e)),
                                      const SizedBox(height: 12),
                                      _LegendRow(label: 'Low stock', value: '${summary.lowStockCount}', color: const Color(0xfff59e0b)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (canSeeSales) ...[
              const SizedBox(height: 24),
              _OverviewPanel(
                title: S.t('Recent sales activity', 'Mauzo ya hivi karibuni'),
                icon: Icons.receipt_long_rounded,
                trailing: widget.profile.can('sales.refund')
                    ? TextButton.icon(
                        onPressed: () async {
                          if (summary.recentSales.isEmpty) return;
                          final firstSale = summary.recentSales.first;
                          final shouldVoid = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Void sale?'),
                              content: Text(
                                'Reverse ${firstSale.receiptNumber}?\n${firstSale.medicinesLabel}\nStock for these medicines will be restored.',
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Void sale')),
                              ],
                            ),
                          );
                          if (shouldVoid == true && mounted) {
                            await _voidSale(firstSale);
                          }
                        },
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Void latest'),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (summary.recentSales.isEmpty)
                      const Text('No sales have been recorded yet for this period.', style: TextStyle(color: Color(0xff68807d)))
                    else
                      ...summary.recentSales.map((sale) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xffe2efff),
                                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xff183b3b), size: 19),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sale.medicinesLabel,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
                                      ),
                                      Text(
                                        '${sale.receiptNumber}  |  ${sale.paymentMethod.toUpperCase()}  |  ${sale.createdAt.day}/${sale.createdAt.month}/${sale.createdAt.year}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Color(0xff68807d), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('TZS ${sale.totalMinor}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                                if (widget.profile.can('sales.refund'))
                                  TextButton(
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Confirm void'),
                                          content: Text('Reverse ${sale.receiptNumber}?\n${sale.medicinesLabel}'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                                            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Yes, void')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true && mounted) {
                                        await _voidSale(sale);
                                      }
                                    },
                                    child: const Text('Void'),
                                  ),
                              ],
                            ),
                          )),
                  ],
                ),
              ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _OverviewData {
  const _OverviewData({
    required this.stockItems,
    required this.stockUnits,
    required this.lowStockCount,
    required this.todaySalesCount,
    required this.todaySalesMinor,
    required this.expirySoonCount,
    required this.expiredCount,
    required this.notifySoonCount,
    required this.weeklyRevenue,
    required this.healthyStockCount,
    required this.recentSales,
  });

  final int stockItems;
  final int stockUnits;
  final int lowStockCount;
  final int todaySalesCount;
  final int todaySalesMinor;
  final int expirySoonCount;
  final int expiredCount;
  final int notifySoonCount;
  final List<_WeeklyRevenuePoint> weeklyRevenue;
  final int healthyStockCount;
  final List<_RecentSaleEntry> recentSales;
}

class _WeeklyRevenuePoint {
  const _WeeklyRevenuePoint({required this.day, required this.revenueMinor});

  final DateTime day;
  final int revenueMinor;
}

class _RecentSaleEntry {
  const _RecentSaleEntry({
    required this.id,
    required this.receiptNumber,
    required this.totalMinor,
    required this.paymentMethod,
    required this.createdAt,
    this.medicineNames = const [],
  });

  final String id;
  final String receiptNumber;
  final int totalMinor;
  final String paymentMethod;
  final DateTime createdAt;
  final List<String> medicineNames;

  String get medicinesLabel {
    if (medicineNames.isEmpty) return 'Medicines not listed';
    if (medicineNames.length == 1) return medicineNames.first;
    if (medicineNames.length == 2) return '${medicineNames[0]} | ${medicineNames[1]}';
    return '${medicineNames[0]} + ${medicineNames.length - 1} more';
  }
}

class _SalesBarChart extends StatelessWidget {
  const _SalesBarChart({required this.points});

  final List<_WeeklyRevenuePoint> points;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<int>(0, (previous, point) => point.revenueMinor > previous ? point.revenueMinor : previous);
    final chartMax = maxValue <= 0 ? 1 : maxValue;
    final weekDays = const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: points.map((point) {
        final heightFactor = point.revenueMinor / chartMax;
        final height = 14 + (heightFactor * 120);
        final dayIndex = point.day.weekday % 7;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('TZS ${point.revenueMinor}', style: const TextStyle(fontSize: 9, color: Color(0xff68807d))),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  width: double.infinity,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xff7dd3c0), Color(0xff0f766e)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff0f766e).withValues(alpha: 0.17),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(weekDays[dayIndex], style: const TextStyle(fontSize: 11, color: Color(0xff68807d))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StockHealthPainter extends CustomPainter {
  const _StockHealthPainter({required this.healthyPercent, required this.lowPercent});

  final double healthyPercent;
  final double lowPercent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.38;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    final healthySweep = (healthyPercent / 100) * 2 * 3.141592653589793;
    final lowSweep = (lowPercent / 100) * 2 * 3.141592653589793;

    ringPaint.color = const Color(0xff0f766e);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3.141592653589793 / 2, healthySweep, false, ringPaint);

    ringPaint.color = const Color(0xfff59e0b);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3.141592653589793 / 2 + healthySweep, lowSweep, false, ringPaint);

    final innerCircle = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 12, innerCircle);

    final strongText = TextPainter(
      text: TextSpan(
        text: '${healthyPercent.round()}%',
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
      ),
      textDirection: TextDirection.ltr,
    );
    strongText.layout();
    strongText.paint(canvas, Offset(center.dx - strongText.width / 2, center.dy - strongText.height / 2));
  }

  @override
  bool shouldRepaint(covariant _StockHealthPainter oldDelegate) => oldDelegate.healthyPercent != healthyPercent || oldDelegate.lowPercent != lowPercent;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xff68807d), fontSize: 11),
          ),
        ),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xff183b3b))),
      ],
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.title, required this.icon, required this.child, this.trailing});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8)),
              ),
              const SizedBox(width: 10),
              Icon(icon, color: PhyimacyBrand.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.note, required this.icon, required this.color});
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x14073B3A), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, size: 20, color: PhyimacyBrand.teal),
          ),
          const SizedBox(height: 14),
          Text(label, style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          const SizedBox(height: 5),
          Text(note, style: GoogleFonts.inter(color: const Color(0xff879895), fontSize: 11)),
        ],
      ),
    );
  }
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _searchController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _authService = AuthService();
  final _cart = <String, SaleCartItem>{};
  final PrinterSettings _printerSettings = PrinterSettingsStore.instance.current;
  String _paymentMethod = 'cash';
  bool _checkingOut = false;
  String? _message;
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<Medicine> _latestMedicines = const [];
  Map<String, int> _sellableByMedicine = {};

  Future<void> _printReceiptNow(ReceiptSummary receipt) async {
    await ReceiptService().printReceipt(receipt, settings: _printerSettings, context: context);
    if (!mounted) return;
    setState(() => _message = 'Receipt ${receipt.receiptNumber} sent to printer.');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _onPosSearchChanged() {
    _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Medicine>>(
      stream: MedicineService().watchMedicines(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load POS medicines: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        _latestMedicines = snapshot.data!;
        return StreamBuilder<List<MedicineBatch>>(
          stream: MedicineService().watchAllBatches(),
          builder: (context, batchSnapshot) {
            final batches = batchSnapshot.data ?? const <MedicineBatch>[];
            final sellableQty = <String, int>{};
            final sellableExpiry = <String, DateTime>{};
            final expiredExpiry = <String, DateTime>{};
            final hasLiveBatches = <String, bool>{};
            final liveBatchCount = <String, int>{};
            for (final batch in batches) {
              if (batch.quantityOnHand <= 0) continue;
              hasLiveBatches[batch.medicineId] = true;
              final expiry = batch.expiryDate.toDate();
              if (ExpiryPriority.isExpired(expiry)) {
                final current = expiredExpiry[batch.medicineId];
                if (current == null || expiry.isBefore(current)) {
                  expiredExpiry[batch.medicineId] = expiry;
                }
              } else {
                liveBatchCount[batch.medicineId] = (liveBatchCount[batch.medicineId] ?? 0) + 1;
                sellableQty[batch.medicineId] = (sellableQty[batch.medicineId] ?? 0) + batch.quantityOnHand;
                final current = sellableExpiry[batch.medicineId];
                if (current == null || expiry.isBefore(current)) {
                  sellableExpiry[batch.medicineId] = expiry;
                }
              }
            }
            final statusExpiry = <String, DateTime>{
              ...expiredExpiry,
              ...sellableExpiry,
            };
            final query = _searchQuery;
            final medicines = MedicineMatch.unique(snapshot.data!.where((medicine) => query.isEmpty || medicine.name.toLowerCase().contains(query) || medicine.sku.toLowerCase().contains(query)).toList())
              ..sort((a, b) {
                final aExpiry = statusExpiry[a.id];
                final bExpiry = statusExpiry[b.id];
                final aExpired = aExpiry != null && ExpiryPriority.isExpired(aExpiry);
                final bExpired = bExpiry != null && ExpiryPriority.isExpired(bExpiry);
                if (aExpired != bExpired) return aExpired ? 1 : -1;
                final aUrgent = aExpiry != null && ExpiryPriority.isUrgent(aExpiry);
                final bUrgent = bExpiry != null && ExpiryPriority.isUrgent(bExpiry);
                if (aUrgent != bUrgent) return aUrgent ? -1 : 1;
                return ExpiryPriority.compare(aExpiry, bExpiry) != 0
                    ? ExpiryPriority.compare(aExpiry, bExpiry)
                    : a.name.compareTo(b.name);
              });
            _sellableByMedicine = {
              for (final medicine in snapshot.data!)
                medicine.id: hasLiveBatches[medicine.id] == true
                    ? (sellableQty[medicine.id] ?? 0)
                    : medicine.quantityOnHand,
            };
            final subtotal = _cart.values.fold<int>(0, (total, item) => total + item.totalMinor);
            final discount = int.tryParse(_discountController.text) ?? 0;
            final total = (subtotal - discount).clamp(0, subtotal);
            final sellFirstCount = medicines.where((medicine) {
              final expiry = statusExpiry[medicine.id];
              return expiry != null && ExpiryPriority.isUrgent(expiry);
            }).length;
            final expiredCount = medicines.where((medicine) {
              final expiry = statusExpiry[medicine.id];
              return expiry != null && ExpiryPriority.isExpired(expiry);
            }).length;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _PageChrome(
                  title: S.t('Sales & POS', 'Mauzo na POS'),
                  subtitle: expiredCount > 0
                      ? S.t(
                          '$sellFirstCount medicines should be sold first. $expiredCount already expired — they cannot be sold.',
                          'Dawa $sellFirstCount ziuzwe kwanza. $expiredCount zimeisha muda â€” haziwezi kuuzwa.',
                        )
                      : sellFirstCount > 0
                      ? S.t(
                          '$sellFirstCount medicines should be sold first — nearest expiry is at the top.',
                          'Dawa $sellFirstCount ziuzwe kwanza â€” zinazoisha karibu ziko juu.',
                        )
                      : S.t(
                          'Stock leaves inventory only when the sale is completed. Nearest expiry is sold first.',
                          'Stock inatoka baada ya kukamilisha mauzo. Zinazoisha karibu zinauzwa kwanza.',
                        ),
                  icon: Icons.point_of_sale_rounded,
                  trailing: _PillLabel(text: S.t('${_cart.length} line items', 'Mistari ${_cart.length}'), color: const Color(0xffdff7ee)),
                ),
                const SizedBox(height: 14),
                Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  flex: 5,
                  child: _PremiumPanel(child: _ProductPicker(medicines: medicines, cart: _cart, nearestExpiry: statusExpiry, sellableQty: _sellableByMedicine, liveBatchCount: liveBatchCount, controller: _searchController, onSearch: _onPosSearchChanged, onAdd: _addToCart)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 4,
                  child: _PremiumPanel(child: _CartPanel(cart: _cart, subtotal: subtotal, discountController: _discountController, paymentMethod: _paymentMethod, message: _message, checkingOut: _checkingOut, total: total, allowDiscount: widget.profile.can(AppPermissions.salesDiscount), onDiscountChanged: () => setState(() {}), onPaymentChanged: (value) => setState(() => _paymentMethod = value), onIncrease: _increaseCart, onDecrease: _decreaseCart, onAddPack: _addPackToCart, onEditQty: _editCartQuantity, onRemoveItem: _removeCartItem, onClearCart: _clearCart, onCheckout: () => _checkout(total, discount))),
                ),
                ])),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _addToCart(Medicine medicine) async {
    final picked = await _askSellQuantity(medicine);
    if (picked == null || !mounted) return;
    _addSell(medicine, picked.$1, picked.$2);
  }

  Future<(SellUnit, int)?> _askSellQuantity(Medicine medicine) {
    var units = medicine.sellUnits;
    if (units.isEmpty) return Future.value(null);
    var selected = units.length > 1
        ? units.firstWhere((unit) => unit.id == 'base' || unit.id == 'lot', orElse: () => units.first)
        : units.first;
    final available = _sellableByMedicine[medicine.id] ?? medicine.quantityOnHand;
    final startQty = selected.id == 'lot'
        ? (available >= medicine.saleLotSize ? medicine.saleLotSize : (available > 0 ? available : medicine.saleLotSize))
        : medicine.minSellCountFor(selected, available);
    final qty = TextEditingController(text: '$startQty');
    return showDialog<(SellUnit, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final n = int.tryParse(qty.text.trim()) ?? 0;
          final lots = selected.id == 'lot';
          final lot = medicine.saleLotSize;
          final leftoverOk = lots && available > 0 && available < lot && n == available;
          final validLot = lots && ((n >= lot && n % lot == 0 && n <= available) || leftoverOk);
          final lineTotal = lots ? medicine.priceForTablets(n) : n * selected.unitPriceMinor;
          return AlertDialog(
            title: Text(medicine.name),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    lots
                        ? S.t(
                            'Price ${medicine.sellingPriceMinor} is for $lot ${medicine.baseLabel.toLowerCase()}s together. 10 = ${medicine.sellingPriceMinor} × 2.\nStock: ${medicine.stockLabel(available)}',
                            'Bei ${medicine.sellingPriceMinor} ni ya vidonge $lot pamoja. 10 = ${medicine.sellingPriceMinor} × 2.\nStock: ${medicine.stockLabel(available)}',
                          )
                        : units.length > 1
                        ? S.t(
                            'Stock is counted in ${medicine.baseLabel.toLowerCase()}s. Sell from ${medicine.effectiveMinSaleQty} ${medicine.baseLabel.toLowerCase()}s upward (or a whole pack).\nNow: ${medicine.stockLabel(available)}',
                            'Stock inahesabiwa kwa ${medicine.baseLabel.toLowerCase()}. Uza kuanzia ${medicine.effectiveMinSaleQty} na kuendelea (au pakiti nzima).\nSasa: ${medicine.stockLabel(available)}',
                          )
                        : medicine.canSellPiecesByType
                            ? S.t(
                                'This is still sold as a whole pack. An admin should set “how many in one pack” once. Then you pick tablets here.\nStock: ${medicine.stockLabel(available)}',
                                'Bado inauzwa kama pakiti nzima. Admin aweke “vidonge ngapi kwenye pack” mara moja. Halafu hapa unachagua vidonge.\nStock: ${medicine.stockLabel(available)}',
                              )
                            : S.t(
                                'How many is the customer buying?\nStock: ${medicine.stockLabel(available)}',
                                'Mteja ananunua ngapi?\nStock: ${medicine.stockLabel(available)}',
                              ),
                    style: const TextStyle(color: Color(0xff68807d), height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  for (final unit in units)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: selected.id == unit.id ? const Color(0xffdff7ee) : const Color(0xfff4f7f6),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setDialogState(() {
                            selected = unit;
                            qty.text = unit.id == 'lot'
                                ? '${available >= medicine.saleLotSize ? medicine.saleLotSize : available}'
                                : '${medicine.minSellCountFor(unit, available)}';
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Icon(
                                  selected.id == unit.id ? Icons.radio_button_checked : Icons.radio_button_off,
                                  size: 20,
                                  color: const Color(0xff0f766e),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    unit.id == 'pack'
                                        ? S.t('Whole pack (${unit.toBase})  -  TZS ${unit.unitPriceMinor}', 'Pakiti nzima (${unit.toBase})  -  TZS ${unit.unitPriceMinor}')
                                        : unit.id == 'box'
                                            ? S.t('Box (${unit.toBase})  -  TZS ${unit.unitPriceMinor}', 'Boksi (${unit.toBase})  -  TZS ${unit.unitPriceMinor}')
                                            : unit.id == 'strip'
                                                ? S.t('Strip (${unit.toBase})  -  TZS ${unit.unitPriceMinor}', 'Strip (${unit.toBase})  -  TZS ${unit.unitPriceMinor}')
                                                : unit.id == 'lot'
                                                    ? S.t('$lot ${medicine.baseLabel.toLowerCase()}s together  -  TZS ${unit.unitPriceMinor}', 'Vidonge $lot pamoja  -  TZS ${unit.unitPriceMinor}')
                                                    : S.t('${unit.label}  -  TZS ${unit.unitPriceMinor} each', '${unit.label}  -  TZS ${unit.unitPriceMinor} moja'),
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final chip in lots
                          ? <int>[lot, lot * 2, lot * 3, lot * 4].where((value) => value <= available || value == lot)
                          : <int>[1, 2, 3, 5, 10].where((value) => value <= available || value == 1))
                        ChoiceChip(
                          label: Text(lots ? S.t('$chip tablets', 'Vidonge $chip') : '$chip'),
                          selected: n == chip,
                          onSelected: (_) => setDialogState(() => qty.text = '$chip'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _QtyButton(
                        icon: Icons.remove,
                        onPressed: () {
                          final step = lots ? lot : 1;
                          final next = n <= step ? step : n - step;
                          setDialogState(() => qty.text = '$next');
                        },
                      ),
                      Expanded(
                        child: TextField(
                    controller: qty,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: lots
                          ? S.t('Tablets', 'Vidonge')
                          : S.t('Quantity', 'Idadi'),
                    ),
                        ),
                      ),
                      _QtyButton(
                        icon: Icons.add,
                        onPressed: () {
                          final step = lots ? lot : 1;
                          setDialogState(() => qty.text = '${n + step}');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    S.t('Line total  TZS $lineTotal', 'Jumla  TZS $lineTotal'),
                    style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w800),
                  ),
                ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))),
              FilledButton(
                onPressed: lots
                    ? (validLot
                        ? () {
                            if (leftoverOk) {
                              Navigator.pop(
                                dialogContext,
                                (
                                  SellUnit(
                                    id: 'lot',
                                    label: '$n ${medicine.baseLabel}',
                                    toBase: n,
                                    unitPriceMinor: lineTotal,
                                    baseLabel: medicine.baseLabel,
                                  ),
                                  1,
                                ),
                              );
                              return;
                            }
                            Navigator.pop(dialogContext, (selected, n ~/ lot));
                          }
                        : null)
                    : (n < medicine.minSellCountFor(selected, available)
                        ? null
                        : () => Navigator.pop(dialogContext, (selected, n))),
                child: Text(S.t('Add to cart', 'Weka kwenye cart')),
              ),
            ],
          );
        },
      ),
    ).whenComplete(qty.dispose);
  }

  int _reservedBase(String medicineId) =>
      _cart.values.where((item) => item.medicineId == medicineId).fold<int>(0, (total, item) => total + item.baseQuantity);

  void _addSell(Medicine medicine, SellUnit unit, int sellQty) {
    if (sellQty <= 0) return;
    final available = _sellableByMedicine[medicine.id] ?? medicine.quantityOnHand;
    final min = medicine.minSellCountFor(unit, available);
    if (sellQty < min) {
      setState(() => _message = S.t(
            'Sell at least $min ${unit.pluralLabel.toLowerCase()} of ${medicine.name}.',
            'Uza angalau $min ya ${medicine.name}.',
          ));
      return;
    }
    final key = '${medicine.id}:${unit.id}';
    final existing = _cart[key];
    final nextSell = (existing?.quantity ?? 0) + sellQty;
    final reserved = _reservedBase(medicine.id) - (existing?.baseQuantity ?? 0) + (nextSell * unit.toBase);
    if (reserved > available) {
      setState(() => _message = available <= 0
          ? '${medicine.name} is expired or has no sellable stock. Remove it from Medicines â†’ Expired.'
          : 'Only ${medicine.stockLabel(available)} available.');
      return;
    }
    setState(() {
      _message = null;
      _cart[key] = SaleCartItem(
        medicineId: medicine.id,
        medicineName: medicine.name,
        quantity: nextSell,
        unitPriceMinor: unit.unitPriceMinor,
        unitName: unit.label,
        toBase: unit.toBase,
        sellUnitId: unit.id,
        baseLabel: medicine.baseLabel,
      );
    });
  }

  void _addPackToCart(SaleCartItem item) {
    Medicine? medicine;
    for (final candidate in _latestMedicines) {
      if (candidate.id == item.medicineId) {
        medicine = candidate;
        break;
      }
    }
    if (medicine == null) return;
    final pack = medicine.sellUnits.where((unit) => unit.id == 'pack').toList();
    if (pack.isEmpty) return;
    _addSell(medicine, pack.first, 1);
  }

  void _increaseCart(SaleCartItem item) {
    Medicine? medicine;
    for (final candidate in _latestMedicines) {
      if (candidate.id == item.medicineId) {
        medicine = candidate;
        break;
      }
    }
    final available = _sellableByMedicine[item.medicineId] ?? medicine?.quantityOnHand ?? item.baseQuantity;
    if (_reservedBase(item.medicineId) + item.toBase > available) {
      setState(() => _message = 'Only ${medicine?.stockLabel(available) ?? '$available'} available for ${item.medicineName}.');
      return;
    }
    setState(() {
      _cart[item.lineKey] = SaleCartItem(
        medicineId: item.medicineId,
        medicineName: item.medicineName,
        quantity: item.quantity + 1,
        unitPriceMinor: item.unitPriceMinor,
        unitName: item.unitName,
        toBase: item.toBase,
        sellUnitId: item.sellUnitId,
        baseLabel: item.baseLabel,
      );
      _message = null;
    });
  }

  void _decreaseCart(SaleCartItem item) {
    Medicine? medicine;
    for (final candidate in _latestMedicines) {
      if (candidate.id == item.medicineId) {
        medicine = candidate;
        break;
      }
    }
    final unit = SellUnit(
      id: item.sellUnitId,
      label: item.unitName,
      toBase: item.toBase,
      unitPriceMinor: item.unitPriceMinor,
      baseLabel: item.baseLabel,
    );
    final available = _sellableByMedicine[item.medicineId] ?? medicine?.quantityOnHand ?? item.baseQuantity;
    final min = medicine?.minSellCountFor(unit, available) ?? 1;
    setState(() {
      if (item.quantity <= min) {
        _cart.remove(item.lineKey);
      } else {
        _cart[item.lineKey] = SaleCartItem(
          medicineId: item.medicineId,
          medicineName: item.medicineName,
          quantity: item.quantity - 1,
          unitPriceMinor: item.unitPriceMinor,
          unitName: item.unitName,
          toBase: item.toBase,
          sellUnitId: item.sellUnitId,
          baseLabel: item.baseLabel,
        );
      }
    });
  }

  Future<void> _editCartQuantity(SaleCartItem item) async {
    Medicine? medicine;
    for (final candidate in _latestMedicines) {
      if (candidate.id == item.medicineId) {
        medicine = candidate;
        break;
      }
    }
    if (medicine == null) return;
    final picked = await _askSellQuantity(medicine);
    if (picked == null || !mounted) return;
    final unit = picked.$1;
    final sellQty = picked.$2;
    final available = _sellableByMedicine[medicine.id] ?? medicine.quantityOnHand;
    final reservedOthers = _reservedBase(medicine.id) - item.baseQuantity;
    if (reservedOthers + (sellQty * unit.toBase) > available) {
      setState(() => _message = S.t(
            'Only ${medicine.stockLabel(available)} available.',
            'Zimebaki ${medicine.stockLabel(available)} tu.',
          ));
      return;
    }
    setState(() {
      _cart.remove(item.lineKey);
      _cart['${medicine.id}:${unit.id}'] = SaleCartItem(
        medicineId: medicine.id,
        medicineName: medicine.name,
        quantity: sellQty,
        unitPriceMinor: unit.unitPriceMinor,
        unitName: unit.label,
        toBase: unit.toBase,
        sellUnitId: unit.id,
        baseLabel: medicine.baseLabel,
      );
      _message = null;
    });
  }

  void _removeCartItem(SaleCartItem item) {
    setState(() {
      _cart.remove(item.lineKey);
      _message = null;
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _discountController.text = '0';
      _message = 'Cart cleared.';
    });
  }

  Future<void> _checkout(int total, int discount) async {
    if (!widget.profile.can('sales.create')) {
      setState(() => _message = S.t(
            'This login can view sales but cannot complete them. Ask a shop admin to grant Complete sales.',
            'Login hii inaona mauzo lakini haiwezi kuyakamilisha. Mwambie admin wa duka atike Kamilisha mauzo.',
          ));
      return;
    }
    final user = _authService.currentUser;
    if (user == null) return;
    var appliedDiscount = discount;
    if (!widget.profile.can(AppPermissions.salesDiscount)) {
      appliedDiscount = 0;
    }
    if (appliedDiscount < 0) {
      setState(() => _message = 'Discount cannot be negative.');
      return;
    }
    if (appliedDiscount > total) {
      setState(() => _message = 'Discount cannot be greater than the sale total.');
      return;
    }
    try {
      SalesService.assertSaleDiscount(
        discountMinor: appliedDiscount,
        subtotalMinor: _cart.values.fold<int>(0, (value, item) => value + item.totalMinor),
        actor: widget.profile,
      );
    } catch (error) {
      setState(() => _message = error.toString().replaceFirst('Invalid argument(s): ', ''));
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _message = 'Add at least one medicine to complete the sale.');
      return;
    }
    setState(() { _checkingOut = true; _message = null; });
    try {
      final receiptNumber = await OfflineSyncService.instance.completeSale(items: _cart.values.toList(), soldBy: user.uid, paymentMethod: _paymentMethod, discountMinor: appliedDiscount, actor: widget.profile);
      final receipt = ReceiptSummary(
        receiptNumber: receiptNumber,
        soldBy: user.uid,
        paymentMethod: _paymentMethod,
        subtotalMinor: _cart.values.fold<int>(0, (total, item) => total + item.totalMinor),
        discountMinor: appliedDiscount,
        totalMinor: _cart.values.fold<int>(0, (value, item) => value + item.totalMinor) - appliedDiscount,
        createdAt: DateTime.now(),
        items: _cart.values.map((item) => ReceiptLineItem(name: '${item.medicineName} - ${item.receiptCaption}', quantity: item.quantity, unitPriceMinor: item.unitPriceMinor, totalMinor: item.totalMinor)).toList(),
      );
      if (mounted) {
        if (_printerSettings.autoPrintAfterSale) {
          await _printReceiptNow(receipt);
        }
        setState(() {
          _cart.clear();
          _discountController.text = '0';
          _message = null;
        });
        showAppNotice(
          context,
          receiptNumber.startsWith('L-')
              ? S.t('Sale saved offline', 'Mauzo yamehifadhiwa nje ya mtandao')
              : S.t('Sale complete', 'Mauzo yamekamilika'),
        );
      }
    } catch (error) {
      if (mounted) {
        showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
        setState(() => _message = null);
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

}

class _PillLabel extends StatelessWidget {
  const _PillLabel({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)), child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xff285957))));
}

class _PremiumPanel extends StatelessWidget {
  const _PremiumPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shadowColor: const Color(0x14073B3A),
        child: child,
      );
}

class _PageChrome extends StatelessWidget {
  const _PageChrome({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(width: 14),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: const Color(0xffdff7ee), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: PhyimacyBrand.teal, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink, height: 1.1)),
                const SizedBox(height: 4),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 14)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: trailing!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceTabs extends StatelessWidget {
  const _WorkspaceTabs({required this.labels, required this.icons, required this.index, required this.onChanged});

  final List<String> labels;
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Material(
                color: index == i ? PhyimacyBrand.teal : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icons[i], size: 18, color: index == i ? Colors.white : PhyimacyBrand.teal),
                        const SizedBox(width: 6),
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: labels.length > 3 ? 12 : 15,
                            color: index == i ? Colors.white : PhyimacyBrand.ink,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({required this.medicines, required this.cart, required this.nearestExpiry, required this.sellableQty, required this.liveBatchCount, required this.controller, required this.onSearch, required this.onAdd});
  final List<Medicine> medicines;
  final Map<String, SaleCartItem> cart;
  final Map<String, DateTime> nearestExpiry;
  final Map<String, int> sellableQty;
  final Map<String, int> liveBatchCount;
  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<Medicine> onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 10),
            Text(S.t('Medicines', 'Dawa'), style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            onChanged: (_) => onSearch(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: S.t('Search medicine by name or SKU', 'Tafuta dawa kwa jina au SKU'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: medicines.isEmpty
                ? const Center(child: Text('No matching medicines.'))
                : GridView.builder(
                    itemCount: medicines.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 280,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: 248,
                    ),
                    itemBuilder: (context, index) {
                      final medicine = medicines[index];
                      final reserved = cart.values.where((item) => item.medicineId == medicine.id).fold<int>(0, (total, item) => total + item.baseQuantity);
                      final available = sellableQty[medicine.id] ?? medicine.quantityOnHand;
                      final remaining = available - reserved;
                      final unavailable = remaining <= 0;
                      final expiry = nearestExpiry[medicine.id];
                      final expired = expiry != null && ExpiryPriority.isExpired(expiry);
                      final urgent = expiry != null && ExpiryPriority.isUrgent(expiry);

                      return RepaintBoundary(
                        child: InkWell(
                        onTap: unavailable ? null : () => onAdd(medicine),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            color: PhyimacyBrand.cream,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: expired
                                  ? const Color(0xffdc2626)
                                  : urgent
                                      ? const Color(0xfff59e0b)
                                      : const Color(0xFFE6EEEB),
                              width: expired || urgent ? 1.6 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xffdff7ee),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.medication_outlined, color: PhyimacyBrand.teal, size: 20),
                                  ),
                                  const Spacer(),
                                  if (expired)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xffffeadf),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text('Expired', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xffc2410c))),
                                    )
                                  else if (urgent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xffffeadf),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text('Sell first', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xffc2410c))),
                                    )
                                  else if (unavailable)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xfffff0d7),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text('Out', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xffb45309))),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(medicine.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xff183b3b), height: 1.15)),
                              const SizedBox(height: 2),
                              Text(medicine.sku, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
                              const Spacer(),
                              Row(
                                children: [
                                  Expanded(
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                      medicine.sellsPricedLots
                                          ? 'TZS ${medicine.sellingPriceMinor} / ${medicine.saleLotSize} ${medicine.baseLabel.toLowerCase()}s'
                                          : medicine.tracksBaseUnits
                                          ? 'TZS ${medicine.piecePriceMinor}/${medicine.baseLabel.toLowerCase()}'
                                          : 'TZS ${medicine.sellingPriceMinor}',
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xff0f766e)),
                                    ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      minimumSize: const Size(0, 36),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: unavailable ? null : () => onAdd(medicine),
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  expiry == null
                                      ? '${medicine.stockLabel(remaining)} available'
                                      : '${medicine.stockLabel(remaining)}  |  ${ExpiryPriority.label(expiry)}',
                                  if ((liveBatchCount[medicine.id] ?? 0) > 1)
                                    '${liveBatchCount[medicine.id]} batches',
                                ].join('  |  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: expired || urgent ? const Color(0xffc2410c) : const Color(0xff68807d), fontWeight: expired || urgent ? FontWeight.w700 : FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.subtotal,
    required this.discountController,
    required this.paymentMethod,
    required this.message,
    required this.checkingOut,
    required this.total,
    required this.allowDiscount,
    required this.onDiscountChanged,
    required this.onPaymentChanged,
    required this.onIncrease,
    required this.onDecrease,
    required this.onAddPack,
    required this.onEditQty,
    required this.onRemoveItem,
    required this.onClearCart,
    required this.onCheckout,
  });
  final Map<String, SaleCartItem> cart;
  final int subtotal;
  final TextEditingController discountController;
  final String paymentMethod;
  final String? message;
  final bool checkingOut;
  final int total;
  final bool allowDiscount;
  final VoidCallback onDiscountChanged;
  final ValueChanged<String> onPaymentChanged;
  final ValueChanged<SaleCartItem> onIncrease;
  final ValueChanged<SaleCartItem> onDecrease;
  final ValueChanged<SaleCartItem> onAddPack;
  final ValueChanged<SaleCartItem> onEditQty;
  final ValueChanged<SaleCartItem> onRemoveItem;
  final VoidCallback onClearCart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final items = cart.values.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(width: 4, height: 18, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 10),
            const Icon(Icons.shopping_basket_outlined, color: PhyimacyBrand.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(S.t('Current sale', 'Mauzo haya'), style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
            ),
            Text(
              S.t('${items.length} items', 'Dawa ${items.length}'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xff68807d)),
            ),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(color: const Color(0xffdff7ee), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.add_shopping_cart_outlined, color: PhyimacyBrand.teal),
                        ),
                        const SizedBox(height: 12),
                        Text(S.t('Cart is empty', 'Cart haina kitu'), style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                        const SizedBox(height: 4),
                        Text(S.t('Add medicines on the left. You can put more than one in this cart.', 'Ongeza dawa kushoto. Unaweza kuweka zaidi ya moja.'), style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12), textAlign: TextAlign.center),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final shownQty = item.sellUnitId == 'lot' ? item.baseQuantity : item.quantity;
                      return Material(
                        color: const Color(0xfff4faf8),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(item.medicineName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('TZS ${item.totalMinor}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xff0f766e))),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.sellUnitId == 'lot'
                                    ? S.t('${item.baseQuantity} tablets · TZS ${item.unitPriceMinor} per ${item.toBase}', 'Vidonge ${item.baseQuantity} · TZS ${item.unitPriceMinor} kwa ${item.toBase}')
                                    : item.receiptCaption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Color(0xff68807d)),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _QtyButton(icon: Icons.remove, onPressed: () => onDecrease(item)),
                                  InkWell(
                                    onTap: () => onEditQty(item),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      child: Text('$shownQty', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                                    ),
                                  ),
                                  _QtyButton(icon: Icons.add, onPressed: () => onIncrease(item)),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: () => onEditQty(item),
                                    child: Text(S.t('Qty', 'Idadi')),
                                  ),
                                  if (item.sellUnitId != 'pack' && item.toBase == 1)
                                    TextButton(onPressed: () => onAddPack(item), child: Text(S.t('Pack', 'Pakiti'))),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: S.t('Remove', 'Ondoa'),
                                    onPressed: () => onRemoveItem(item),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 22, color: Color(0xffb42318)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          _SaleTotalRow(label: S.t('Subtotal', 'Jumla ndogo'), value: subtotal),
          const SizedBox(height: 8),
          if (allowDiscount)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: discountController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => onDiscountChanged(),
                    decoration: InputDecoration(isDense: true, labelText: S.t('Discount', 'Punguzo'), prefixIcon: const Icon(Icons.local_offer_outlined, size: 18)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: InputDecoration(isDense: true, labelText: S.t('Pay', 'Lipa'), prefixIcon: const Icon(Icons.payments_outlined, size: 18)),
                    items: [
                      DropdownMenuItem(value: 'cash', child: Text(S.t('Cash', 'Taslimu'))),
                      DropdownMenuItem(value: 'card', child: Text(S.t('Card', 'Kadi'))),
                      DropdownMenuItem(value: 'mobile_money', child: Text(S.t('Mobile', 'Simu'))),
                    ],
                    onChanged: (value) { if (value != null) onPaymentChanged(value); },
                  ),
                ),
              ],
            )
          else
            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: InputDecoration(isDense: true, labelText: S.t('Payment method', 'Njia ya malipo'), prefixIcon: const Icon(Icons.payments_outlined, size: 18)),
              items: [
                DropdownMenuItem(value: 'cash', child: Text(S.t('Cash', 'Pesa taslimu'))),
                DropdownMenuItem(value: 'card', child: Text(S.t('Card', 'Kadi'))),
                DropdownMenuItem(value: 'mobile_money', child: Text(S.t('Mobile money', 'Simu'))),
              ],
              onChanged: (value) { if (value != null) onPaymentChanged(value); },
            ),
          const SizedBox(height: 10),
          _SaleTotalRow(label: S.t('Total', 'Jumla'), value: total, prominent: true),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(message!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xff68807d), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: cart.isEmpty || checkingOut ? null : onCheckout,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(checkingOut ? S.t('Completing sale...', 'Inakamilisha mauzo...') : S.t('Complete sale', 'Kamilisha mauzo')),
          ),
          TextButton(
            onPressed: cart.isEmpty ? null : onClearCart,
            child: Text(S.t('Clear cart', 'Futa cart')),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: PhyimacyBrand.teal),
        ),
      ),
    );
  }
}

class _SaleTotalRow extends StatelessWidget {
  const _SaleTotalRow({required this.label, required this.value, this.prominent = false});
  final String label;
  final int value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontWeight: prominent ? FontWeight.w800 : FontWeight.w500, color: PhyimacyBrand.muted)),
          Text(
            'TZS $value',
            style: prominent
                ? GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)
                : GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: PhyimacyBrand.ink),
          ),
        ],
      );
}

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final service = PurchaseService();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageChrome(
          title: S.t('Purchases', 'Manunuzi'),
          subtitle: S.t(
            'Receive stock here. Quantity is added on Medicines and a batch appears on Inventory. Storekeepers use this page to bring products in.',
            'Pokea stock hapa. Idadi inaongezwa kwenye Dawa, na batch inaonekana kwenye Inventory. Storekeeper anatumia ukurasa huu kuingiza bidhaa.',
          ),
          icon: Icons.shopping_cart_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_tab == 0 && (widget.profile.can('purchases.create') || widget.profile.can('purchases.receive')))
                FilledButton.icon(onPressed: () => showReceivePurchaseDialog(context, service), icon: const Icon(Icons.add_shopping_cart_outlined), label: Text(S.t('Receive purchase', 'Pokea ununuzi'))),
              if (_tab == 1 && widget.profile.can('suppliers.manage'))
                FilledButton.icon(onPressed: () => _showSupplierDialog(context, service), icon: const Icon(Icons.person_add_alt_1_outlined), label: Text(S.t('Add supplier', 'Ongeza msambazaji'))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WorkspaceTabs(
          labels: [S.t('Received stock', 'Stock iliyopokelewa'), S.t('Suppliers', 'Wasambazaji')],
          icons: const [Icons.move_to_inbox_rounded, Icons.local_shipping_outlined],
          index: _tab,
          onChanged: (index) => setState(() => _tab = index),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _tab == 1
              ? SuppliersScreen(profile: widget.profile, embedded: true)
              : StreamBuilder<List<PurchaseRecord>>(
                  stream: service.watchPurchases(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Center(child: Text('Could not load purchases: ${snapshot.error}'));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final purchases = snapshot.data!;
                    if (purchases.isEmpty) return const _EmptyPurchaseState();
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      clipBehavior: Clip.antiAlias,
                      elevation: 2,
                      shadowColor: const Color(0x14073B3A),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: purchases.length,
                        separatorBuilder: (_, index) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final purchase = purchases[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xffffeadf),
                              child: Icon(Icons.shopping_cart_outlined, color: Color(0xffc2410c)),
                            ),
                            title: Text(
                              purchase.medicineName?.trim().isNotEmpty == true
                                  ? purchase.medicineName!
                                  : (purchase.invoiceNumber?.isNotEmpty == true ? purchase.invoiceNumber! : 'Purchase ${purchase.id.substring(0, 6)}'),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff143230)),
                            ),
                            subtitle: Text(
                              [
                                if ((purchase.supplierName ?? '').trim().isNotEmpty) purchase.supplierName!,
                                if (purchase.quantity != null) '+${purchase.quantity} added to stock',
                                purchase.status,
                              ].join('  |  '),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: PhyimacyBrand.cream, borderRadius: BorderRadius.circular(999)),
                              child: Text('TZS ${purchase.totalMinor}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _showSupplierDialog(BuildContext context, PurchaseService service) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Add supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Supplier name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: S.t('Phone (optional)', 'Simu (si lazima)'),
                hintText: TanzaniaPhone.hint,
                helperText: S.t('Tanzania mobile, e.g. 0712345678', 'Simu ya Tanzania, mfano 0712345678'),
                errorText: TanzaniaPhone.validate(phone.text),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: TanzaniaPhone.validate(phone.text) == null
                ? () async {
              final supplierName = name.text.trim();
              if (supplierName.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Supplier name is required.')));
                return;
              }
              await service.createSupplier(name: supplierName, phone: TanzaniaPhone.normalize(phone.text));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }
                : null,
            child: const Text('Save supplier'),
          ),
        ],
      ),
      ),
    );
    name.dispose();
    phone.dispose();
  }

}

class _EmptyPurchaseState extends StatelessWidget {
  const _EmptyPurchaseState();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: const Color(0xffffeadf), borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.shopping_cart_outlined, size: 32, color: Color(0xffc2410c)),
            ),
            const SizedBox(height: 16),
            Text('No purchases yet', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
            const SizedBox(height: 8),
            const Text(
              'Add a supplier, then tap Receive purchase. Search an existing medicine or tap New if it is not on the list.',
              style: TextStyle(color: Color(0xff68807d)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.profile.isSuperAdmin ? 'pharmacies' : 'shop';
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_SettingCardOption>[];

    if (widget.profile.isSuperAdmin) {
      cards.add(_SettingCardOption(id: 'pharmacies', label: S.t('Pharmacies and logins', 'Maduka na login'), icon: Icons.storefront_rounded, description: S.t('Create a shop with its admin, then add staff', 'Tengeneza duka na admin, kisha ongeza staff')));
      cards.add(_SettingCardOption(id: 'licenses', label: S.t('Licenses', 'Leseni'), icon: Icons.workspace_premium_rounded, description: S.t('Tokens and paid access dates', 'Tokeni na tarehe za malipo')));
      cards.add(_SettingCardOption(id: 'password', label: S.t('Password', 'Nenosiri'), icon: Icons.lock_reset_rounded, description: S.t('Change the password for this account', 'Badilisha nenosiri la akaunti hii')));
      cards.add(_SettingCardOption(id: 'updates', label: S.t('App updates', 'Updates za app'), icon: Icons.system_update_alt_rounded, description: S.t('Publish or download the latest version', 'Chapisha au pakua toleo jipya')));
    } else {
      if (widget.profile.can('users.manage')) {
        cards.add(_SettingCardOption(id: 'team', label: S.t('Team', 'Timu'), icon: Icons.manage_accounts_outlined, description: S.t('Staff logins for this pharmacy', 'Login za staff wa duka hili')));
      }
      cards.add(_SettingCardOption(id: 'shop', label: S.t('Shop', 'Duka'), icon: Icons.tune_rounded, description: S.t('This pharmacy name, phone, and address', 'Jina, simu, na anwani ya duka')));
      if (widget.profile.can('settings.manage')) {
        cards.add(_SettingCardOption(id: 'printer', label: S.t('Printer', 'Printa'), icon: Icons.print_outlined, description: S.t('Receipt printer', 'Printa ya risiti')));
        cards.add(_SettingCardOption(id: 'data', label: S.t('Data tools', 'Data'), icon: Icons.storage_rounded, description: S.t('Backup, restore, or clear', 'Backup, rudisha, au futa')));
      }
      cards.add(_SettingCardOption(id: 'password', label: S.t('Password', 'Nenosiri'), icon: Icons.lock_reset_rounded, description: S.t('Change the password for this login', 'Badilisha nenosiri la login hii')));
      cards.add(_SettingCardOption(id: 'updates', label: S.t('App updates', 'Updates za app'), icon: Icons.system_update_alt_rounded, description: S.t('Check for a new PharmSpecio version', 'Angalia toleo jipya la PharmSpecio')));
    }

    final selectedContent = switch (_selected) {
      'printer' => const PrinterSettingsScreen(),
      'team' => TeamAccessScreen(profile: widget.profile),
      'pharmacies' => AccountsAdminScreen(profile: widget.profile),
      'licenses' => SubscriptionAdminScreen(profile: widget.profile),
      'updates' => AppUpdateScreen(profile: widget.profile),
      'password' => PasswordSettingsView(profile: widget.profile),
      _ => PharmacyWorkspaceSettingsScreen(profile: widget.profile),
    };

    final fillHeight = false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.t('Settings', 'Mipangilio'),
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: PhyimacyBrand.ink,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.profile.isSuperAdmin
                            ? S.t('Shops, licenses, password, and app updates.', 'Maduka, leseni, nenosiri, na updates.')
                            : S.t('Shop details, team, printer, data, password, and updates.', 'Taarifa za duka, timu, printa, data, nenosiri, na updates.'),
                        style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xffdff7ee),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.tune_rounded, color: PhyimacyBrand.teal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 128,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _SettingsNavTile(
                      option: cards[i],
                      selected: _selected == cards[i].id,
                      onTap: () => setState(() => _selected = cards[i].id),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        cards.firstWhere((card) => card.id == _selected, orElse: () => cards.first).icon,
                        color: PhyimacyBrand.teal,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        cards.firstWhere((card) => card.id == _selected, orElse: () => cards.first).label,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: PhyimacyBrand.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 40,
                    height: 3,
                    decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: fillHeight ? selectedContent : SingleChildScrollView(child: selectedContent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({required this.option, required this.selected, required this.onTap});

  final _SettingCardOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? PhyimacyBrand.teal : const Color(0xFFE6EEEB),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected ? const Color(0x330F766E) : const Color(0x14073B3A),
                blurRadius: selected ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xffdff7ee) : PhyimacyBrand.cream,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(option.icon, size: 18, color: selected ? PhyimacyBrand.teal : PhyimacyBrand.muted),
                  ),
                  const Spacer(),
                  if (selected)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: PhyimacyBrand.gold, shape: BoxShape.circle),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: PhyimacyBrand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                option.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 10.5, height: 1.25, color: PhyimacyBrand.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingCardOption {
  _SettingCardOption({required this.id, required this.label, required this.icon, required this.description});

  final String id;
  final String label;
  final IconData icon;
  final String description;
}

class SuperAdminSystemScreen extends StatelessWidget {
  const SuperAdminSystemScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Super admin', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
          const SizedBox(height: 8),
          Text('Full control for ${profile.email}. Generate paid tokens, grant start/end dates, lock pharmacies, manage licenses, and publish app updates.', style: const TextStyle(color: Color(0xff4a5a5d))),
          const SizedBox(height: 16),
          SubscriptionAdminScreen(profile: profile),
          const SizedBox(height: 28),
          AppUpdateScreen(profile: profile),
        ],
      ),
    );
  }
}

class _GeneralSettingsView extends StatelessWidget {
  const _GeneralSettingsView();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('General', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        SizedBox(height: 10),
        Text('Set the pharmacy defaults and core business preferences.'),
        SizedBox(height: 18),
        Text('â€¢ Default pricing norms\nâ€¢ Business profile and branding\nâ€¢ Working defaults for medicine setup\nâ€¢ Standard category naming', style: TextStyle(height: 1.8, color: Color(0xff4a5a5d))),
      ],
    );
  }
}

class _SecuritySettingsView extends StatelessWidget {
  const _SecuritySettingsView();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Security', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        SizedBox(height: 10),
        Text('Control who can view, edit, and approve sensitive operations.'),
        SizedBox(height: 18),
        Text('â€¢ Protect stock and financial changes\nâ€¢ Review access permissions\nâ€¢ Track user roles and approvals\nâ€¢ Restrict sensitive actions', style: TextStyle(height: 1.8, color: Color(0xff4a5a5d))),
      ],
    );
  }
}

class TeamAccessScreen extends StatelessWidget {
  const TeamAccessScreen({this.profile, super.key});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final service = UserManagementService();
    final canManageSuperAdmin = profile?.isSuperAdmin == true;
    final isShopAdmin = profile?.role == 'admin' && profile?.isSuperAdmin != true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.t('Add cashiers, pharmacists, and storekeepers for this pharmacy. The shop admin is created with the pharmacy and already has full shop access.', 'Ongeza cashier, pharmacist, na storekeeper. Admin wa duka anaundwa pamoja na duka na anapata ruhusa zote za duka.'),
          style: const TextStyle(color: Color(0xff68807d), height: 1.4),
        ),
        const SizedBox(height: 16),
        if (isShopAdmin)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showCreateStaffDialog(context, service: service, canManageSuperAdmin: canManageSuperAdmin),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add staff'),
            ),
          ),
        const SizedBox(height: 14),
        StreamBuilder<List<UserProfile>>(
          stream: service.watchUsers(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load team: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final users = snapshot.data!
                .where((user) => user.visibleTo(profile))
                .toList();
            if (users.isEmpty) {
              return const Text('No team logins yet. Create one with name, email, and password.');
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: users.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xffdff7ee),
                    child: Text(
                      user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase(),
                      style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [
                      user.email,
                      if ((user.phone ?? '').trim().isNotEmpty) user.phone,
                      user.role,
                      user.isActive ? 'Active' : 'Inactive',
                      if ((user.pharmacyId ?? '').trim().isNotEmpty) 'Shop linked',
                    ].join('  |  '),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if ((canManageSuperAdmin && user.id != profile?.id) ||
                          (isShopAdmin && user.id != profile?.id && user.role != 'admin' && user.role != 'super_admin'))
                        FilledButton.tonalIcon(
                          onPressed: () => showEditStaffDialog(context, service: service, user: user, canManageSuperAdmin: canManageSuperAdmin),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Manage'),
                        ),
                      if ((canManageSuperAdmin && user.id != profile?.id) ||
                          (isShopAdmin && user.id != profile?.id && user.role != 'admin' && user.role != 'super_admin'))
                        IconButton(
                          tooltip: 'Set password',
                          onPressed: () => showManagedPasswordDialog(context, user),
                          icon: const Icon(Icons.password_rounded, color: Color(0xff0f766e)),
                        ),
                      if ((canManageSuperAdmin && user.id != profile?.id) ||
                          (isShopAdmin && user.id != profile?.id && user.role != 'admin' && user.role != 'super_admin'))
                        IconButton(
                          tooltip: 'Delete profile',
                          onPressed: () => confirmDeleteStaffProfile(context, service, user),
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({required this.title, required this.subtitle, required this.icon, required this.accent, required this.actions, super.key});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<String> actions;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))), const SizedBox(height: 7), Text(subtitle, style: const TextStyle(color: Color(0xff68807d))), const SizedBox(height: 28), Card(child: Padding(padding: const EdgeInsets.all(26), child: Row(children: [Container(width: 58, height: 58, decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: accent, size: 28)), const SizedBox(width: 18), const Expanded(child: Text('This workspace is connected to your pharmacy account. The next transaction records you add will appear here.', style: TextStyle(color: Color(0xff506764), height: 1.5))), ...actions.map((action) => Padding(padding: const EdgeInsets.only(left: 10), child: OutlinedButton(onPressed: null, child: Text(action))))])))]));
}

class MedicineImportScreen extends StatefulWidget {
  const MedicineImportScreen({super.key});

  @override
  State<MedicineImportScreen> createState() => _MedicineImportScreenState();
}

class _MedicineImportScreenState extends State<MedicineImportScreen> {
  final _controller = TextEditingController();
  MedicineImportValidationResult? _result;
  String? _selectedFileName;
  bool _busy = false;
  int _importDone = 0;
  int _importTotal = 0;
  String? _lastImportMessage;

  Future<void> _downloadTemplate() async {
    const fileName = 'phyimacy_medicine_import_template.csv';
    final csv = MedicineImportService.generateTemplateCsv();
    final directory = await getDownloadsDirectory() ?? Directory.systemTemp;
    final file = File('${directory.path}/$fileName');
    await file.create(recursive: true);
    await file.writeAsString(csv);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Template downloaded to ${file.path}')),
    );
  }

  Future<void> _pickCsvFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xls', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final selectedName = file.name;
      final rawBytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
      if (rawBytes == null || rawBytes.isEmpty) {
        throw StateError('The selected file was empty.');
      }

      final parsed = MedicineImportService.parseBytes(rawBytes, fileName: selectedName);
      if (!mounted) return;
      _controller.text = parsed.displayText;
      setState(() {
        _selectedFileName = selectedName;
        _result = parsed.result;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded: $selectedName')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open selected file: $error')),
      );
    }
  }

  void _validateInput() {
    setState(() {
      _result = MedicineImportService.validateCsv(_controller.text);
    });
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file content to validate.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Validation complete.')),
    );
  }

  void _cancelImport() {
    setState(() {
      _controller.clear();
      _selectedFileName = null;
      _result = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import cleared.')),
    );
  }

  Future<void> _importValidatedRows() async {
    final validRows = _result?.validRows ?? const <MedicineImportRow>[];
    if (validRows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no valid rows to import.')),
      );
      return;
    }
    if (_busy) return;

    setState(() {
      _busy = true;
      _importDone = 0;
      _importTotal = validRows.length;
      _lastImportMessage = 'Importing ${validRows.length} medicinesâ€¦';
    });

    try {
      final report = await MedicineService().importMedicines(
        validRows
            .map((row) => {
                  'sku': row.sku,
                  'medicine_name': row.medicineName,
                  'category': row.category,
                  'unit': row.unit,
                  'pack_size': row.packSize.toString(),
                  'strip_size': row.stripSize.toString(),
                  'box_size': row.boxSize.toString(),
                  'min_sale_qty': row.minSaleQty.toString(),
                  'stock_as': row.openingAsTablets ? 'tablets' : 'packs',
                  'buying_price': row.buyingPriceMinor.toString(),
                  'selling_price': row.sellingPriceMinor.toString(),
                  'reorder_level': row.reorderLevel.toString(),
                  'opening_quantity': row.openingQuantity.toString(),
                  'expiry_date': row.expiryDate,
                  'batch_number': row.batchNumber,
                  'requires_prescription': row.requiresPrescription ? 'yes' : '',
                })
            .toList(),
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _importDone = done;
            _importTotal = total;
            _lastImportMessage = 'Importing $done of $totalâ€¦';
          });
        },
      );

      if (!mounted) return;
      final message = report.imported == 0 && report.skippedExisting > 0
          ? 'No new medicines. ${report.skippedExisting} were already in the catalogue (same SKU).'
          : 'Imported ${report.imported}. Skipped ${report.skippedExisting} already in stock.${report.failed > 0 ? ' ${report.failed} failed.' : ''}';
      setState(() {
        _busy = false;
        _lastImportMessage = message;
        if (report.imported > 0) {
          _controller.clear();
          _result = null;
          _selectedFileName = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
      if (report.imported > 0 && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastImportMessage = 'Import failed: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final validRows = _result?.validRows ?? const <MedicineImportRow>[];
    final invalidRows = _result?.invalidRows ?? const <MedicineImportInvalidRow>[];
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: Color(0xff183b3b)),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                const Text('Import medicines', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Download the template, fill the same fields as Add medicine, then import.', style: TextStyle(color: Color(0xff68807d))),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xffedf2f2)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0f0f766e), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _downloadTemplate,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download template'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickCsvFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Excel file'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _validateInput,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Validate rows'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || validRows.isEmpty ? null : _importValidatedRows,
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.file_upload_outlined),
                        label: Text(_busy ? 'Importing $_importDone/$_importTotal' : 'Import rows'),
                      ),
                      TextButton.icon(
                        onPressed: _cancelImport,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_busy)
                    LinearProgressIndicator(
                      value: _importTotal == 0 ? null : _importDone / _importTotal,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  if (_busy) const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xfff3f8f7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _busy
                          ? 'Importing $_importDone of $_importTotal. Keep this window open.'
                          : (_lastImportMessage ?? (_selectedFileName == null ? 'No file selected yet.' : 'Selected file: $_selectedFileName')),
                      style: const TextStyle(color: Color(0xff183b3b), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              constraints: const BoxConstraints(minHeight: 260),
              child: TextField(
                controller: _controller,
                minLines: 12,
                maxLines: 20,
                decoration: const InputDecoration(
                  labelText: 'Excel rows',
                  helperText: 'Use the exact template headers shown below. The import will reject missing or invalid values.',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _SummaryChip(label: 'Valid rows', value: '${validRows.length}', color: const Color(0xffdff7ee)),
                const SizedBox(width: 12),
                _SummaryChip(label: 'Invalid rows', value: '${invalidRows.length}', color: const Color(0xfffff0d7)),
              ],
            ),
            const SizedBox(height: 24),
            if (invalidRows.isNotEmpty) ...[
              const Text('Invalid rows', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
              const SizedBox(height: 12),
              ...invalidRows.map((row) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Row ${row.rowNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text((row.errors).join(', '), style: const TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 18),
            const Text('Required columns', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MedicineImportService.requiredHeaders.map((header) => Chip(label: Text(header))).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Optional columns', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
            const SizedBox(height: 8),
            const Text(
              'Leave blank if not needed. For tablets, stock_as = tablets (count) or packs. min_sale_qty defaults to 5 for tablets. Liquids stay whole items.',
              style: TextStyle(color: Color(0xff68807d)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MedicineImportService.optionalHeaders.map((header) => Chip(label: Text(header))).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
      );
}

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterSettings _settings = PrinterSettingsStore.instance.current;
  List<String> _printers = const ['Default Windows printer', 'Thermal 80mm receipt printer', 'PDF print preview'];

  String get _effectivePrinterValue {
    if (_printers.contains(_settings.defaultPrinterName)) {
      return _settings.defaultPrinterName;
    }
    if (_printers.contains(_settings.selectedPrinterName)) {
      return _settings.selectedPrinterName;
    }
    return _printers.first;
  }

  void _persistSettings() {
    PrinterSettingsStore.instance.set(_settings);
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;
    _persistSettings();
    final selected = _settings.selectedPrinterName.isNotEmpty ? _settings.selectedPrinterName : _effectivePrinterValue;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Printer settings saved. Active printer: ${selected.isEmpty ? 'Default Windows printer' : selected}')),
    );
  }

  Future<void> _pickWindowsPrinter() async {
    final printers = await Printing.listPrinters();
    if (!mounted || printers.isEmpty) {
      return;
    }
    final selected = await showDialog<Printer>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Select printer'),
        children: printers.map((printer) => SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(printer),
          child: Text(printer.name),
        )).toList(),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (!_printers.contains(selected.name)) {
        _printers = [..._printers, selected.name];
      }
      _settings = _settings.copyWith(
        defaultPrinterName: selected.name,
        selectedPrinterName: selected.name,
        selectedPrinterUrl: selected.url,
      );
      _persistSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Printer settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
          const SizedBox(height: 6),
          const Text('Choose the default receipt printer and decide whether a print should happen automatically or only when you press Print.', style: TextStyle(color: Color(0xff68807d))),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xffedf2f2)),
              boxShadow: const [
                BoxShadow(color: Color(0x0f0f766e), blurRadius: 12, offset: Offset(0, 6)),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xffdff7ee),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.print_outlined, color: Color(0xff0f766e)),
                    ),
                    const SizedBox(width: 12),
                    const Text('Receipt printer setup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_effectivePrinterValue),
                        initialValue: _effectivePrinterValue,
                        decoration: const InputDecoration(labelText: 'Receipt printer'),
                        items: _printers.map((printer) => DropdownMenuItem(value: printer, child: Text(printer))).toList(),
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings.copyWith(defaultPrinterName: value ?? _effectivePrinterValue);
                            _persistSettings();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _pickWindowsPrinter,
                      child: const Text('Select printer'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _settings.paperMode,
                  decoration: const InputDecoration(labelText: 'Receipt paper mode'),
                  items: const [
                    DropdownMenuItem(value: 'thermal', child: Text('Thermal receipt (80mm)')),
                    DropdownMenuItem(value: 'standard', child: Text('Standard paper')),
                    DropdownMenuItem(value: 'pdf', child: Text('PDF preview')),
                  ],
                  onChanged: (value) => setState(() => _settings = _settings.copyWith(paperMode: value ?? _settings.paperMode)),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  initialValue: _settings.receiptPaperWidthMm.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Receipt width (mm)'),
                  onChanged: (value) {
                    final parsed = int.tryParse(value) ?? 80;
                    setState(() => _settings = _settings.copyWith(receiptPaperWidthMm: parsed));
                  },
                ),
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(S.t('Auto-print receipt after sale', 'Chapisha risiti baada ya mauzo')),
                  value: _settings.autoPrintAfterSale,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings.copyWith(autoPrintAfterSale: value);
                      _persistSettings();
                    });
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save settings'),
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

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    required this.profile,
    this.embedded = false,
    this.onOpenMedicine,
    this.onDeleteMedicine,
    super.key,
  });

  final UserProfile profile;
  final bool embedded;
  final void Function(Medicine medicine)? onOpenMedicine;
  final void Function(Medicine medicine)? onDeleteMedicine;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = MedicineService();
    return Padding(
      padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(28),
      child: StreamBuilder<List<CategoryOption>>(
        stream: service.watchCategories(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load categories: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final categories = snapshot.data!;
          return StreamBuilder<List<Medicine>>(
            stream: service.watchMedicines(),
            builder: (context, medicineSnapshot) {
              final medicines = MedicineMatch.unique(medicineSnapshot.data ?? const <Medicine>[]);
              final query = _search.text.trim().toLowerCase();
              final visible = categories.where((category) {
                if (query.isEmpty) return true;
                if (category.name.toLowerCase().contains(query)) return true;
                return medicines.any((medicine) => medicine.categoryId == category.id && MedicineMatch.matches(medicine, query));
              }).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.embedded) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Categories', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xff183b3b))),
                              const SizedBox(height: 6),
                              Text(S.t('Group medicines by type. Search a product to find its category.', 'Panga dawa kwa aina. Tafuta dawa ili kuona kundi lake.'), style: const TextStyle(color: Color(0xff68807d))),
                            ],
                          ),
                        ),
                        if (widget.profile.can('medicines.update'))
                          FilledButton.icon(
                            onPressed: () => _editCategory(context, service),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(S.t('Add category', 'Ongeza kundi')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: S.t('Search a product or category', 'Tafuta dawa au kundi'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(onPressed: () => setState(_search.clear), icon: const Icon(Icons.close_rounded)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: categories.isEmpty
                        ? Card(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 62,
                                      height: 62,
                                      decoration: BoxDecoration(
                                        color: const Color(0xfff2e7ff),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: const Icon(Icons.folder_open_rounded, size: 30, color: Color(0xff7c3aed)),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(S.t('No categories yet', 'Bado hakuna makundi'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                                    const SizedBox(height: 8),
                                    Text(S.t('Add your first category to start organizing medicines.', 'Ongeza kundi la kwanza ili kupanga dawa.'), style: const TextStyle(color: Color(0xff68807d))),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : visible.isEmpty
                            ? Center(child: Text(S.t('No product or category matches that search.', 'Hakuna dawa wala kundi linalofanana na utafutaji huo.')))
                            : Card(
                                clipBehavior: Clip.antiAlias,
                                child: ListView.separated(
                                  itemCount: visible.length,
                                  separatorBuilder: (_, index) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final category = visible[index];
                                    final products = medicines.where((medicine) => medicine.categoryId == category.id).toList();
                                    final shown = query.isEmpty ? products : products.where((medicine) => MedicineMatch.matches(medicine, query)).toList();
                                    return Theme(
                                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                      child: ExpansionTile(
                                        initiallyExpanded: query.isNotEmpty,
                                        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        leading: Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: const Color(0xffe1f4ef),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.category_rounded, color: Color(0xff0f766e)),
                                        ),
                                        title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                                        subtitle: Text(
                                          S.t('${products.length} products', 'Dawa ${products.length}'),
                                          style: const TextStyle(color: Color(0xff68807d)),
                                        ),
                                        trailing: widget.profile.can('medicines.update')
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: S.t('Edit category', 'Hariri kundi'),
                                                    onPressed: () => _editCategory(context, service, category: category),
                                                    icon: const Icon(Icons.edit_outlined, color: Color(0xff0f766e)),
                                                  ),
                                                  IconButton(
                                                    tooltip: S.t('Delete category', 'Futa kundi'),
                                                    onPressed: () => _deleteCategory(context, service, category, products.length),
                                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                                                  ),
                                                ],
                                              )
                                            : null,
                                        children: [
                                          if (shown.isEmpty)
                                            ListTile(
                                              title: Text(
                                                products.isEmpty
                                                    ? S.t('No products in this category yet.', 'Bado hakuna dawa kwenye kundi hili.')
                                                    : S.t('No product in this category matches that search.', 'Hakuna dawa kwenye kundi hili inayofanana na utafutaji.'),
                                                style: const TextStyle(color: Color(0xff68807d)),
                                              ),
                                            )
                                          else
                                            for (final medicine in shown)
                                              ListTile(
                                                contentPadding: const EdgeInsets.fromLTRB(78, 0, 16, 0),
                                                title: Text(medicine.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                                subtitle: Text([medicine.sku, medicine.stockLabel()].join('  |  ')),
                                                trailing: widget.onDeleteMedicine == null
                                                    ? null
                                                    : IconButton(
                                                        tooltip: S.t('Delete this medicine', 'Futa dawa hii'),
                                                        onPressed: () => widget.onDeleteMedicine!(medicine),
                                                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                                                      ),
                                                onTap: widget.onOpenMedicine == null ? null : () => widget.onOpenMedicine!(medicine),
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
      ),
    );
  }

  Future<void> _editCategory(BuildContext context, MedicineService service, {CategoryOption? category}) async {
    final controller = TextEditingController(text: category?.name ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(category == null ? S.t('Add category', 'Ongeza kundi') : S.t('Edit category', 'Hariri kundi')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: S.t('Category name', 'Jina la kundi'),
            hintText: S.t('Example: Antibiotics', 'Mfano: Antibiotics'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(S.t('Category name is required.', 'Jina la kundi linahitajika.'))));
                return;
              }
              try {
                if (category == null) {
                  await service.createCategory(name);
                } else {
                  await service.updateCategory(categoryId: category.id, name: name);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(friendlyActionError(error))));
                }
              }
            },
            child: Text(S.t('Save', 'Hifadhi')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _deleteCategory(BuildContext context, MedicineService service, CategoryOption category, int productCount) async {
    if (productCount > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('Move those $productCount medicines first, then delete this category.', 'Hamisha dawa hizo $productCount kwanza, kisha futa kundi hili.'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Delete ${category.name}?', 'Futa ${category.name}?')),
        content: Text(S.t('This category will be removed. Medicines already saved stay in the catalogue.', 'Kundi hili litaondolewa. Dawa zilizohifadhiwa zinabaki kwenye orodha.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete', 'Futa'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.deleteCategory(category.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('Category deleted.', 'Kundi limefutwa.'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyActionError(error))));
      }
    }
  }
}

class _DashboardDestination {
  _DashboardDestination({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;

  NavigationRailDestination get navigationDestination => NavigationRailDestination(
        icon: Icon(icon),
        label: Text(label),
      );
}

class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({required this.profile, this.initialTab = 0, super.key});

  final UserProfile profile;
  final int initialTab;

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  late int _tab = widget.initialTab.clamp(0, 3);
  final _catalogueSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    MedicineService().consolidateDuplicateMedicinesOnce();
  }

  @override
  void dispose() {
    _catalogueSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = MedicineService();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageChrome(
            title: S.t('Medicines', 'Dawa'),
            subtitle: S.t(
              'Catalogue, daily stock, expired write-off, and categories together.',
              'Orodha, stock ya siku, zilizoisha, na makundi pamoja.',
            ),
            icon: Icons.medication_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_tab == 0 && widget.profile.can('medicines.create')) ...[
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const MedicineImportScreen()),
                    ),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(S.t('Import CSV', 'Import CSV')),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _showAddMedicineDialog(context, service),
                    icon: const Icon(Icons.add),
                    label: Text(S.t('Add medicine', 'Ongeza dawa')),
                  ),
                ],
                if (_tab == 3 && widget.profile.can('medicines.update'))
                  FilledButton.icon(
                    onPressed: () => _showAddCategoryDialog(context, service),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add category'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _WorkspaceTabs(
            labels: [
              S.t('Catalogue', 'Orodha'),
              S.t('Stock', 'Stock'),
              S.t('Expired', 'Zilizoisha'),
              S.t('Categories', 'Makundi'),
            ],
            icons: const [Icons.medication_outlined, Icons.inventory_2_outlined, Icons.event_busy_rounded, Icons.category_outlined],
            index: _tab,
            onChanged: (index) => setState(() => _tab = index),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _tab == 1
                ? InventoryScreen(profile: widget.profile, embedded: true)
                : _tab == 2
                    ? _expiredTab(service)
                    : _tab == 3
                        ? CategoriesScreen(
                            profile: widget.profile,
                            embedded: true,
                            onOpenMedicine: (medicine) => _showAddMedicineDialog(context, service, medicine: medicine),
                            onDeleteMedicine: (medicine) => _confirmDeleteMedicine(context, service, medicine),
                          )
                        : _catalogue(service),
          ),
        ],
      ),
    );
  }

  Widget _expiredTab(MedicineService service) {
    return StreamBuilder<List<Medicine>>(
      stream: service.watchMedicines(),
      builder: (context, medicineSnapshot) {
        return StreamBuilder<List<MedicineBatch>>(
          stream: service.watchAllBatches(),
          builder: (context, batchSnapshot) {
            if (batchSnapshot.hasError) return Center(child: Text('Could not load expired stock: ${batchSnapshot.error}'));
            if (!medicineSnapshot.hasData || !batchSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final medicines = medicineSnapshot.data!;
            final batches = batchSnapshot.data!;
            final expired = ExpiryStock.expiredLines(medicines, batches);
            if (expired.isEmpty) {
              final missingDates = ExpiryStock.productsWithoutExpiry(medicines, batches);
              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))]),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      missingDates > 0
                          ? '$missingDates products have stock but no expiry date. Open the medicine, add a batch, and set 30/6/2026 so it can appear here.'
                          : 'No expired stock is sitting in the list right now.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final units = expired.fold<int>(0, (total, line) => total + line.quantity);
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_busy_rounded, color: Color(0xffc2410c)),
                    title: Text('${expired.length} expired items  |  $units units'),
                    subtitle: const Text('Remove them from stock. The quantity is recorded as an expiry write-off.'),
                    trailing: widget.profile.can('inventory.adjust')
                        ? FilledButton(
                            onPressed: () => _writeOffExpired(context, service, expired),
                            child: const Text('Remove all'),
                          )
                        : null,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: expired.length,
                      separatorBuilder: (_, index) => const Divider(height: 1, indent: 20),
                      itemBuilder: (context, index) {
                        final line = expired[index];
                        return ListTile(
                          title: Text(line.medicineName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            [
                              line.sku,
                              if (line.batchNumber != null && line.batchNumber!.isNotEmpty) 'Batch ${line.batchNumber}',
                              ExpiryPriority.label(line.expiry),
                            ].where((part) => part.isNotEmpty).join('  |  '),
                          ),
                          trailing: Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('${line.quantity} ${line.unit}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xffc2410c))),
                              if (widget.profile.can('inventory.adjust'))
                                FilledButton.tonal(
                                  onPressed: () => _writeOffExpired(context, service, [line]),
                                  child: const Text('Remove'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteMedicine(BuildContext context, MedicineService service, Medicine medicine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Delete ${medicine.name}?', 'Futa ${medicine.name}?')),
        content: Text(
          S.t(
            'This removes only this medicine from the catalogue. The category stays. Other medicines are not deleted.',
            'Hii inaondoa dawa hii tu kwenye orodha. Kundi linabaki. Dawa nyingine hazifutwi.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete medicine', 'Futa dawa'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.archiveMedicine(medicine.id);
      if (!context.mounted) return;
      showAppNotice(context, S.t('${medicine.name} has been removed.', '${medicine.name} imeondolewa.'));
    } catch (error) {
      if (!context.mounted) return;
      showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  }

  Future<void> _writeOffExpired(BuildContext context, MedicineService service, List<ExpiredStockLine> lines) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove expired stock?'),
        content: const Text('Those units leave the stock list. The quantity is saved as expired write-off so daily tracking stays correct. This cannot be sold.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove from stock')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final userId = AuthService().currentUser?.uid ?? 'staff';
      final units = await service.writeOffExpiredLines(lines: lines, createdBy: userId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$units expired units removed from stock and recorded.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Widget _catalogue(MedicineService service) {
    return StreamBuilder<List<Medicine>>(
      stream: service.watchMedicines(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load medicines: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final allMedicines = MedicineMatch.unique(snapshot.data!);
        if (allMedicines.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: const Center(child: Text('No medicines yet. Add the first medicine.')),
          );
        }
        return StreamBuilder<List<MedicineBatch>>(
          stream: service.watchAllBatches(),
          builder: (context, batchSnapshot) {
            final batches = batchSnapshot.data ?? const <MedicineBatch>[];
            final query = _catalogueSearch.text.trim();
            final medicines = query.isEmpty ? allMedicines : allMedicines.where((medicine) => MedicineMatch.matches(medicine, query)).toList();
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _catalogueSearch,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: S.t('Search medicine name or SKU', 'Tafuta jina la dawa au SKU'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(onPressed: () => setState(_catalogueSearch.clear), icon: const Icon(Icons.close_rounded)),
                    ),
                  ),
                ),
                Expanded(
                  child: medicines.isEmpty
                      ? Center(child: Text(S.t('No medicine matches that search.', 'Hakuna dawa inayofanana na utafutaji huo.')))
                      : Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              child: ListView.separated(
                itemCount: medicines.length,
                separatorBuilder: (_, index) => const Divider(height: 1, indent: 20),
                itemBuilder: (context, index) {
                  final medicine = medicines[index];
                  final lowStock = medicine.quantityOnHand <= medicine.reorderLevel;
                  DateTime? statusExpiry = medicine.expiryDate?.toDate();
                  for (final batch in batches) {
                    if (batch.medicineId != medicine.id) continue;
                    if (batch.quantityOnHand <= 0 && medicine.quantityOnHand <= 0) continue;
                    final date = batch.expiryDate.toDate();
                    if (statusExpiry == null || ExpiryPriority.compare(date, statusExpiry) < 0) {
                      statusExpiry = date;
                    }
                  }
                  final expired = statusExpiry != null && ExpiryPriority.isExpired(statusExpiry);
                  final urgent = statusExpiry != null && ExpiryPriority.isUrgent(statusExpiry);
                  final badge = expired
                      ? 'Expired'
                      : urgent
                          ? 'Sell first'
                          : lowStock
                              ? 'Reorder'
                              : 'In stock';
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    title: Text(medicine.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      [
                        medicine.sku,
                        medicine.stockLabel(),
                        if (medicine.sellsLoose) 'Loose sale on',
                        if (statusExpiry != null) ExpiryPriority.label(statusExpiry),
                      ].join('  |  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: FittedBox(
                      child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.profile.can('medicines.update'))
                          IconButton(
                            tooltip: 'Edit medicine',
                            onPressed: () => _showAddMedicineDialog(context, service, medicine: medicine),
                            icon: const Icon(Icons.edit_outlined, color: Color(0xff0f766e)),
                          ),
                        if (widget.profile.can('medicines.delete'))
                          IconButton(
                            tooltip: S.t('Delete this medicine', 'Futa dawa hii'),
                            onPressed: () => _confirmDeleteMedicine(context, service, medicine),
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: expired || urgent || lowStock ? const Color(0xffffeadf) : const Color(0xffdff7ee),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(badge, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    ),
                    onTap: () => _showBatches(context, service, medicine),
                  );
                },
              ),
            ),
                ),
              ],
            ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddMedicineDialog(BuildContext context, MedicineService service, {Medicine? medicine}) async {
    final editing = medicine != null;
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: medicine?.name ?? '');
    final sku = TextEditingController(text: medicine?.sku ?? '');
    final unit = TextEditingController(text: medicine?.unit ?? 'Tablet');
    final purchasePrice = TextEditingController(text: medicine == null ? '' : '${medicine.purchasePriceMinor}');
    final sellingPrice = TextEditingController(text: medicine == null ? '' : '${medicine.sellingPriceMinor}');
    final reorderLevel = TextEditingController(text: medicine == null ? '10' : '${medicine.reorderLevel}');
    var stockByTabletsPreview = medicine == null
        ? true
        : medicine.canSellPiecesByType && medicine.packSize <= 1;
    final openingQty = TextEditingController(
      text: medicine == null
          ? ''
          : '${stockByTabletsPreview || medicine.packSize <= 1 || !medicine.canSellPiecesByType ? medicine.quantityOnHand : medicine.quantityOnHand ~/ medicine.piecesPerPack}',
    );
    final batchNumber = TextEditingController();
    final packSize = TextEditingController(text: medicine == null ? '1' : '${medicine.packSize}');
    final stripSize = TextEditingController(text: medicine == null || medicine.stripSize <= 0 ? '' : '${medicine.stripSize}');
    final boxSize = TextEditingController(text: medicine == null || medicine.boxSize <= 0 ? '' : '${medicine.boxSize}');
    final minSaleQty = TextEditingController(
      text: medicine == null
          ? '5'
          : '${medicine.effectiveMinSaleQty}',
    );
    String? selectedCategoryId = medicine?.categoryId;
    var prescription = medicine?.requiresPrescription ?? false;
    var baseUnit = BaseUnits.normalize(medicine?.unit ?? 'Tablet');
    var stockByTablets = medicine == null
        ? true
        : medicine.canSellPiecesByType && medicine.packSize <= 1;
    DateTime? expiryDate = medicine?.expiryDate?.toDate();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: AppLocale.instance,
        builder: (context, _) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 560,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 25, 28, 20),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xffdff7ee), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.medication_outlined, color: Color(0xff0f766e))),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(editing ? S.t('Edit medicine', 'Hariri dawa') : S.t('Add medicine', 'Ongeza dawa'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                              const SizedBox(height: 3),
                              Text(
                                editing
                                    ? S.t('Update price, expiry date, and product details', 'Sasisha bei, tarehe ya kuisha, na maelezo ya dawa')
                                    : S.t('Create a product record with price and expiry date', 'Unda rekodi ya dawa na bei na tarehe ya kuisha'),
                                style: const TextStyle(fontSize: 12, color: Color(0xff68807d)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                      ]),
                      const SizedBox(height: 26),
                      _FormSectionLabel(S.t('Medicine details', 'Maelezo ya dawa')),
                      const SizedBox(height: 10),
                      _requiredField(name, S.t('Medicine name', 'Jina la dawa'), icon: Icons.medication_outlined),
                      const SizedBox(height: 10),
                      Row(children: [Expanded(child: _requiredField(sku, S.t('SKU / code', 'SKU / namba'), icon: Icons.qr_code_2_rounded)), const SizedBox(width: 12), Expanded(child: DropdownButtonFormField<String>(
                        initialValue: BaseUnits.options.contains(baseUnit) ? baseUnit : 'Tablet',
                        decoration: InputDecoration(
                          labelText: S.t('This is a', 'Hii ni'),
                          helperText: S.t(
                            'Tablet or capsule: sell from 5 pieces. Bottle/syrup: whole item only.',
                            'Kidonge: uza kuanzia vidonge 5. Chupa/maji: kipande kizima tu.',
                          ),
                          prefixIcon: const Icon(Icons.inventory_2_outlined, size: 19),
                        ),
                        items: [for (final option in BaseUnits.options) DropdownMenuItem(value: option, child: Text(_baseUnitLabel(option)))],
                        onChanged: (value) => setDialogState(() {
                          baseUnit = value ?? baseUnit;
                          unit.text = baseUnit;
                          if (BaseUnits.sellsByPiece(baseUnit)) {
                            if (stockByTablets) packSize.text = '1';
                            if ((int.tryParse(minSaleQty.text) ?? 0) < 1) minSaleQty.text = '5';
                          } else {
                            stockByTablets = false;
                            packSize.text = '1';
                          }
                        }),
                      ))]),
                      const SizedBox(height: 22),
                      _FormSectionLabel(S.t('Classification', 'Aina')),
                      const SizedBox(height: 10),
                      StreamBuilder<List<CategoryOption>>(
                        stream: service.watchCategories(),
                        builder: (context, snapshot) {
                          final categories = snapshot.data ?? const <CategoryOption>[];
                          Widget content;
                          if (snapshot.hasError) {
                            content = Text(S.t('Could not load categories: ${snapshot.error}', 'Imeshindikana kupakia makundi: ${snapshot.error}'), style: const TextStyle(color: Colors.red));
                          } else if (snapshot.connectionState == ConnectionState.waiting && categories.isEmpty) {
                            content = const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                          } else if (categories.isEmpty) {
                            content = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(S.t('No categories yet. Create one before saving a medicine.', 'Bado hakuna kundi. Unda kwanza kabla ya kuhifadhi dawa.'), style: const TextStyle(color: Color(0xff68807d))),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      final created = await _showAddCategoryDialog(context, service);
                                      if (created && context.mounted) {
                                        setDialogState(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.add_circle_outline_rounded),
                                    label: Text(S.t('Add category', 'Ongeza kundi')),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            final items = categories
                                .map((category) => DropdownMenuItem<String>(
                                      value: category.id,
                                      child: Text(category.name),
                                    ))
                                .toList();
                            content = DropdownButtonFormField<String>(
                              initialValue: selectedCategoryId == null || !items.any((item) => item.value == selectedCategoryId) ? null : selectedCategoryId,
                              items: items,
                              onChanged: (value) => setDialogState(() => selectedCategoryId = value),
                              decoration: InputDecoration(
                                labelText: S.t('Category', 'Kundi'),
                                prefixIcon: const Icon(Icons.category_outlined),
                              ),
                              validator: (value) => value == null || value.isEmpty ? S.t('Select a category', 'Chagua kundi') : null,
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              content,
                              if (categories.isNotEmpty || snapshot.connectionState != ConnectionState.waiting)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      final created = await _showAddCategoryDialog(context, service);
                                      if (created && context.mounted) {
                                        setDialogState(() {});
                                      }
                                    },
                                    icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                    label: Text(S.t('New category', 'Kundi jipya')),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      _FormSectionLabel(S.t('Price & stock', 'Bei na stock')),
                      const SizedBox(height: 10),
                      if (BaseUnits.sellsByPiece(baseUnit)) ...[
                        Text(S.t('How do you want to enter stock?', 'Unataka kuingiza stock vipi?'), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: true,
                              label: Text(S.t('By tablet count', 'Kwa idadi ya vidonge')),
                              icon: const Icon(Icons.medication_outlined, size: 18),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text(S.t('By pack', 'Kwa pakiti')),
                              icon: const Icon(Icons.inventory_2_outlined, size: 18),
                            ),
                          ],
                          selected: {stockByTablets},
                          onSelectionChanged: (value) => setDialogState(() {
                            final next = value.first;
                            final current = int.tryParse(openingQty.text.trim());
                            final size = int.tryParse(packSize.text.trim()) ?? 1;
                            if (editing && current != null && current >= 0) {
                              if (stockByTablets && !next && size > 1) {
                                openingQty.text = '${current ~/ size}';
                              } else if (!stockByTablets && next && size > 1) {
                                openingQty.text = '${current * size}';
                              }
                            }
                            stockByTablets = next;
                            if (stockByTablets) {
                              packSize.text = '1';
                            } else if ((int.tryParse(packSize.text) ?? 1) <= 1) {
                              packSize.text = '10';
                            }
                          }),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(children: [
                        Expanded(
                          child: _numberField(
                            purchasePrice,
                            BaseUnits.sellsByPiece(baseUnit) && stockByTablets
                                ? S.t('Buying price of ${int.tryParse(minSaleQty.text.trim()) ?? 5} tablets (TZS)', 'Bei ya kununua ya vidonge ${int.tryParse(minSaleQty.text.trim()) ?? 5} (TZS)')
                                : BaseUnits.sellsByPiece(baseUnit)
                                    ? S.t('Buying price of one pack (TZS)', 'Bei ya kununua ya pakiti moja (TZS)')
                                    : S.t('Buying price of one item (TZS)', 'Bei ya kununua ya kipande kimoja (TZS)'),
                            icon: Icons.payments_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: sellingPrice,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: BaseUnits.sellsByPiece(baseUnit) && stockByTablets
                                  ? S.t('Selling price of ${int.tryParse(minSaleQty.text.trim()) ?? 5} tablets (TZS)', 'Bei ya kuuza ya vidonge ${int.tryParse(minSaleQty.text.trim()) ?? 5} (TZS)')
                                  : BaseUnits.sellsByPiece(baseUnit)
                                      ? S.t('Selling price of one pack (TZS)', 'Bei ya kuuza ya pakiti moja (TZS)')
                                      : S.t('Selling price of one item (TZS)', 'Bei ya kuuza ya kipande kimoja (TZS)'),
                              prefixIcon: const Icon(Icons.sell_outlined, size: 19),
                            ),
                            validator: (value) => int.tryParse(value ?? '') == null ? S.t('Enter a whole number', 'Weka namba kamili') : null,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        BaseUnits.sellsByPiece(baseUnit) && stockByTablets
                            ? S.t(
                                '400 means those ${int.tryParse(minSaleQty.text.trim()) ?? 5} tablets together. 10 tablets = 400 × 2 = 800.',
                                '400 ni bei ya vidonge ${int.tryParse(minSaleQty.text.trim()) ?? 5} pamoja. Vidonge 10 = 400 × 2 = 800.',
                              )
                            : BaseUnits.sellsByPiece(baseUnit)
                                ? S.t(
                                    'Enter pack prices. The app divides them by tablets-in-one-pack to get the price of one tablet.',
                                    'Weka bei za pakiti. App inagawanya kwa vidonge vya pakiti moja ili kupata bei ya kidonge kimoja.',
                                  )
                                : S.t(
                                    'Enter the price of one bottle, tube, or whole item.',
                                    'Weka bei ya chupa, tube, au kipande kimoja kizima.',
                                  ),
                        style: const TextStyle(fontSize: 12, color: Color(0xff68807d), height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: openingQty,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: BaseUnits.sellsByPiece(baseUnit) && stockByTablets
                              ? S.t('Units in stock now (tablets)', 'Idadi iliyopo sasa (vidonge)')
                              : BaseUnits.sellsByPiece(baseUnit)
                                  ? S.t('Units in stock now (packs)', 'Idadi iliyopo sasa (pakiti)')
                                  : S.t('Units in stock now', 'Idadi iliyopo sasa'),
                          helperText: editing
                              ? S.t('This is the real quantity on the shelf. Change it if the count is wrong.', 'Hii ndiyo idadi halisi rafuni. Badilisha kama hesabu si sahihi.')
                              : S.t('How many are on the shelf right now?', 'Zipo ngapi rafuni sasa?'),
                          prefixIcon: const Icon(Icons.inventory_2_outlined, size: 19),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return editing ? S.t('Enter stock on hand', 'Weka stock iliyopo') : null;
                          return int.tryParse(value.trim()) == null ? S.t('Enter a whole number', 'Weka namba kamili') : null;
                        },
                      ),
                      if (!editing) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: batchNumber,
                          decoration: InputDecoration(labelText: S.t('Batch no. (optional)', 'Namba ya batch (si lazima)'), prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 19)),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _numberField(reorderLevel, S.t('Alert me when stock reaches', 'Niarifu stock ikifika'), icon: Icons.warning_amber_rounded),
                      if (BaseUnits.sellsByPiece(baseUnit) && !stockByTablets) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: packSize,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: S.t('Tablets in one pack', 'Vidonge kwenye pakiti moja'),
                            prefixIcon: const Icon(Icons.grid_view_rounded, size: 19),
                          ),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed < 2) return S.t('Enter 2 or more', 'Weka 2 au zaidi');
                            return null;
                          },
                        ),
                      ],
                      if (BaseUnits.sellsByPiece(baseUnit)) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: minSaleQty,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: S.t('Tablets sold together at this price (e.g. 5)', 'Vidonge vinavyouzwa pamoja kwa bei hii (mf. 5)'),
                            helperText: S.t('If price is 400 and this is 5, then 5 tablets = 400 and 10 tablets = 800.', 'Bei ikiwa 400 na hapa ni 5, vidonge 5 = 400 na 10 = 800.'),
                            prefixIcon: const Icon(Icons.filter_5_rounded, size: 19),
                          ),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed < 1) return S.t('Enter 1 or more', 'Weka 1 au zaidi');
                            return null;
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          S.t(
                            'Syrups and other liquids are sold whole. Only tablets/capsules can be sold from 5 pieces.',
                            'Dawa za maji zinauzwa zima. Vidonge/capsule tu ndivyo vinavyouzwa kuanzia 5.',
                          ),
                          style: const TextStyle(color: Color(0xff0f766e), height: 1.35),
                        ),
                      ],
                      if (BaseUnits.sellsByPiece(baseUnit) && !stockByTablets) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: TextFormField(controller: stripSize, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.t('Strip size (optional)', 'Ukubwa wa strip (si lazima)'), helperText: S.t('e.g. 10', 'mf. 10'), prefixIcon: const Icon(Icons.view_week_outlined, size: 19)))),
                          const SizedBox(width: 12),
                          Expanded(child: TextFormField(controller: boxSize, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: S.t('Box size (optional)', 'Ukubwa wa boksi (si lazima)'), helperText: S.t('e.g. 100', 'mf. 100'), prefixIcon: const Icon(Icons.inventory_outlined, size: 19)))),
                        ]),
                      ],
                      const SizedBox(height: 10),
                      _FormSectionLabel(S.t('Expiry', 'Kuisha')),
                      const SizedBox(height: 8),
                      _ExpiryDateFields(
                        value: expiryDate,
                        allowPast: editing,
                        onChanged: (picked) => setDialogState(() => expiryDate = picked),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        S.t('Change day, month, and year separately. Required if stock is more than 0.', 'Badilisha siku, mwezi, na mwaka kila moja. Lazima stock ikiwa zaidi ya 0.'),
                        style: const TextStyle(fontSize: 12, color: Color(0xff68807d), height: 1.35),
                      ),
                      const SizedBox(height: 5),
                      CheckboxListTile(contentPadding: EdgeInsets.zero, value: prescription, onChanged: (value) => setDialogState(() => prescription = value ?? false), title: Text(S.t('Requires prescription', 'Inahitaji dawa ya daktari')), subtitle: Text(S.t('Flag this medicine for controlled dispensing', 'Weka alama dawa hii kwa usambazaji unaodhibitiwa')), controlAffinity: ListTileControlAffinity.leading),
                      const SizedBox(height: 15),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))), const SizedBox(width: 10), FilledButton.icon(onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        if (selectedCategoryId == null || selectedCategoryId!.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('Select a category before saving.', 'Chagua kundi kabla ya kuhifadhi.'))));
                          return;
                        }
                        final qty = int.tryParse(openingQty.text.trim()) ?? 0;
                        if (qty > 0 && expiryDate == null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('Set the expiry date before saving stock.', 'Weka tarehe ya kuisha kabla ya kuhifadhi stock.'))));
                          return;
                        }
                        try {
                          final parsedPack = BaseUnits.sellsByPiece(baseUnit)
                              ? (stockByTablets ? 1 : int.parse(packSize.text))
                              : 1;
                          final parsedMin = BaseUnits.sellsByPiece(baseUnit)
                              ? (int.tryParse(minSaleQty.text.trim()) ?? 5)
                              : 0;
                          if (editing) {
                            await service.updateMedicine(
                              medicineId: medicine.id,
                              name: name.text,
                              sku: sku.text,
                              categoryId: selectedCategoryId!,
                              unit: baseUnit,
                              purchasePriceMinor: int.parse(purchasePrice.text),
                              sellingPriceMinor: int.parse(sellingPrice.text),
                              reorderLevel: int.parse(reorderLevel.text),
                              requiresPrescription: prescription,
                              packSize: parsedPack,
                              stripSize: stockByTablets ? 0 : int.tryParse(stripSize.text.trim()) ?? 0,
                              boxSize: stockByTablets ? 0 : int.tryParse(boxSize.text.trim()) ?? 0,
                              minSaleQty: parsedMin,
                              allowLooseSale: BaseUnits.sellsByPiece(baseUnit),
                              expiryDate: expiryDate,
                            );
                            final enteredStock = int.tryParse(openingQty.text.trim());
                            if (enteredStock != null) {
                              final nextQty = stockByTablets || !BaseUnits.sellsByPiece(baseUnit) ? enteredStock : enteredStock * parsedPack;
                              await service.setOnHandQuantity(
                                medicineId: medicine.id,
                                quantity: nextQty,
                                createdBy: AuthService().currentUser?.uid ?? 'staff',
                                expiryDate: expiryDate,
                              );
                            }
                          } else {
                            final userId = AuthService().currentUser?.uid ?? 'staff';
                            await service.createMedicine(
                              name: name.text,
                              sku: sku.text,
                              categoryId: selectedCategoryId!,
                              unit: baseUnit,
                              purchasePriceMinor: int.parse(purchasePrice.text),
                              sellingPriceMinor: int.parse(sellingPrice.text),
                              reorderLevel: int.parse(reorderLevel.text),
                              requiresPrescription: prescription,
                              packSize: parsedPack,
                              stripSize: stockByTablets ? 0 : int.tryParse(stripSize.text.trim()) ?? 0,
                              boxSize: stockByTablets ? 0 : int.tryParse(boxSize.text.trim()) ?? 0,
                              minSaleQty: parsedMin,
                              allowLooseSale: BaseUnits.sellsByPiece(baseUnit),
                              expiryDate: expiryDate,
                              openingQuantity: qty,
                              openingAsTablets: stockByTablets || !BaseUnits.sellsByPiece(baseUnit),
                              batchNumber: batchNumber.text,
                              createdBy: userId,
                            );
                          }
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        } catch (error) {
                          if (!context.mounted) return;
                          final text = '$error';
                          final denied = text.contains('permission-denied');
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                              denied
                                  ? S.t(
                                      'This cashier login cannot edit medicines. Sell from Sales, or ask an admin / pharmacist to save catalogue changes.',
                                      'Akaunti hii haiwezi kuhariri dawa. Uza kwenye Sales, au muombe admin/pharmacist ahifadhi mabadiliko ya katalogi.',
                                    )
                                  : text,
                            ),
                          ));
                        }
                      }, icon: const Icon(Icons.check_rounded, size: 18), label: Text(editing ? S.t('Save changes', 'Hifadhi mabadiliko') : S.t('Save medicine', 'Hifadhi dawa')))]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
    name.dispose();
    sku.dispose();
    unit.dispose();
    purchasePrice.dispose();
    sellingPrice.dispose();
    reorderLevel.dispose();
    openingQty.dispose();
    batchNumber.dispose();
    packSize.dispose();
    stripSize.dispose();
    boxSize.dispose();
    minSaleQty.dispose();
  }

  Future<bool> _showAddCategoryDialog(BuildContext context, MedicineService service) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: AppLocale.instance,
        builder: (context, _) => AlertDialog(
        title: Text(S.t('Add category', 'Ongeza kundi')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.t('Category name', 'Jina la kundi')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(S.t('Category name is required.', 'Jina la kundi linahitajika.'))));
                return;
              }
              await service.createCategory(name);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: Text(S.t('Save', 'Hifadhi')),
          ),
        ],
      ),
      ),
    );
    controller.dispose();
    return created ?? false;
  }

  Future<void> _showBatches(BuildContext context, MedicineService service, Medicine medicine) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${medicine.name} batches'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: StreamBuilder<List<MedicineBatch>>(
            stream: service.watchBatches(medicine.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final batches = snapshot.data!;
              if (batches.isEmpty) return const Center(child: Text('No batches recorded yet.'));
              return ListView.separated(
                itemCount: batches.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final batch = batches[index];
                  final expiry = batch.expiryDate.toDate();
                  return ListTile(
                    title: Text(batch.batchNumber),
                    subtitle: Text(ExpiryPriority.label(expiry)),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${batch.quantityOnHand} units', style: TextStyle(fontWeight: FontWeight.w800, color: ExpiryPriority.isExpired(expiry) ? const Color(0xffc2410c) : PhyimacyBrand.ink)),
                        if (widget.profile.can('inventory.adjust') && ExpiryPriority.isExpired(expiry) && (batch.quantityOnHand > 0 || medicine.quantityOnHand > 0))
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _writeOffExpired(context, service, [
                                ExpiredStockLine(
                                  medicineId: medicine.id,
                                  medicineName: medicine.name,
                                  sku: medicine.sku,
                                  unit: medicine.unit,
                                  quantity: batch.quantityOnHand > 0 ? batch.quantityOnHand : medicine.quantityOnHand,
                                  expiry: expiry,
                                  batchId: batch.id,
                                  batchNumber: batch.batchNumber,
                                ),
                              ]);
                            },
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          if (widget.profile.can('inventory.adjust'))
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _showAddBatchDialog(context, service, medicine);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add batch'),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddBatchDialog(BuildContext context, MedicineService service, Medicine medicine) async {
    final formKey = GlobalKey<FormState>();
    final batchNumber = TextEditingController();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    DateTime expiryDate = DateTime.now().add(const Duration(days: 365));
    final inventoryService = InventoryService();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add batch: ${medicine.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _requiredField(batchNumber, 'Batch number'),
                _numberField(quantity, medicine.piecesPerPack > 1 ? 'Packs' : 'Quantity'),
                _numberField(cost, 'Unit cost (minor units)'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Expiry: ${expiryDate.day}/${expiryDate.month}/${expiryDate.year}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: expiryDate,
                    );
                    if (picked != null) setDialogState(() => expiryDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final user = AuthService().currentUser;
                if (user == null) return;
                await inventoryService.receiveBatch(
                  medicineId: medicine.id,
                  batchNumber: batchNumber.text,
                  expiryDate: Timestamp.fromDate(expiryDate),
                  quantity: int.parse(quantity.text),
                  unitCostMinor: int.parse(cost.text),
                  createdBy: user.uid,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    batchNumber.dispose();
    quantity.dispose();
    cost.dispose();
  }

  String _baseUnitLabel(String unit) {
    switch (unit) {
      case 'Tablet':
        return S.t('Tablet', 'Kidonge');
      case 'Capsule':
        return S.t('Capsule', 'Kapsuli');
      case 'Bottle':
        return S.t('Bottle', 'Chupa');
      case 'Tube':
        return S.t('Tube', 'Tube');
      case 'Vial':
        return S.t('Vial', 'Vial');
      case 'Ampoule':
        return S.t('Ampoule', 'Ampoule');
      case 'Sachet':
        return S.t('Sachet', 'Sachet');
      case 'Piece':
        return S.t('Piece', 'Kipande');
      case 'Strip':
        return S.t('Strip', 'Strip');
      default:
        return unit;
    }
  }

  Widget _requiredField(TextEditingController controller, String label, {IconData? icon}) => TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 19)),
        validator: (value) => value == null || value.trim().isEmpty ? S.t('Required', 'Lazima') : null,
      );

  Widget _numberField(TextEditingController controller, String label, {IconData? icon}) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 19)),
        validator: (value) => int.tryParse(value ?? '') == null ? S.t('Enter a whole number', 'Weka namba kamili') : null,
      );
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Color(0xff0f766e)));
}

class _ExpiryDateFields extends StatelessWidget {
  const _ExpiryDateFields({
    required this.value,
    required this.onChanged,
    this.allowPast = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowPast;

  static const _monthEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static const _monthSw = ['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final year = value?.year ?? now.year + 1;
    final month = value?.month ?? now.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final day = (value?.day ?? now.day).clamp(1, daysInMonth);
    final startYear = allowPast ? now.year - 5 : now.year;
    final years = [for (var y = startYear; y <= now.year + 15; y++) y];

    void apply({int? nextDay, int? nextMonth, int? nextYear}) {
      final y = nextYear ?? year;
      final m = nextMonth ?? month;
      final maxDay = DateTime(y, m + 1, 0).day;
      final d = (nextDay ?? day).clamp(1, maxDay);
      onChanged(DateTime(y, m, d));
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('exp-day-$year-$month-$day'),
            initialValue: value == null ? null : day,
            isExpanded: true,
            decoration: InputDecoration(labelText: S.t('Day', 'Siku'), prefixIcon: const Icon(Icons.today_outlined, size: 18)),
            items: [for (var d = 1; d <= daysInMonth; d++) DropdownMenuItem(value: d, child: Text('$d'))],
            onChanged: (picked) {
              if (picked != null) apply(nextDay: picked);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            key: ValueKey('exp-month-$year-$month'),
            initialValue: value == null ? null : month,
            isExpanded: true,
            decoration: InputDecoration(labelText: S.t('Month', 'Mwezi'), prefixIcon: const Icon(Icons.calendar_view_month_outlined, size: 18)),
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(S.t(_monthEn[m - 1], _monthSw[m - 1]))),
            ],
            onChanged: (picked) {
              if (picked != null) apply(nextMonth: picked);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('exp-year-$year'),
            initialValue: value == null ? null : year,
            isExpanded: true,
            decoration: InputDecoration(labelText: S.t('Year', 'Mwaka'), prefixIcon: const Icon(Icons.event_outlined, size: 18)),
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (picked) {
              if (picked != null) apply(nextYear: picked);
            },
          ),
        ),
      ],
    );
  }
}

class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message ?? 'This account cannot open PharmSpecio.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => AuthService().signOut(),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out and use another account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SubscriptionGateScreen extends StatefulWidget {
  const SubscriptionGateScreen({
    required this.subscription,
    this.onActivated,
    this.embedded = false,
    super.key,
  });

  final SubscriptionState subscription;
  final VoidCallback? onActivated;
  final bool embedded;

  @override
  State<SubscriptionGateScreen> createState() => _SubscriptionGateScreenState();
}

class _SubscriptionGateScreenState extends State<SubscriptionGateScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _message;

  Future<void> _activateCode() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final result = await SubscriptionService().activateWithCode(_codeController.text);
      if (!mounted) return;
      if (!result) {
        setState(() => _message = S.t('Invalid or used activation code.', 'Namba si sahihi au imeshatumika.'));
        return;
      }
      setState(() => _message = S.t('Plan activated successfully. Opening pharmacy...', 'Mpango umewezeshwa. Inafungua duka...'));
      try {
        final pharmacy = await PharmacyService().getPharmacy(TenantContext.instance.pharmacyId ?? '');
        await TransactionalEmailService().notifySubscriptionActivated(
          toEmail: pharmacy?.ownerEmail ?? FirebaseAuth.instance.currentUser?.email ?? '',
          displayName: pharmacy?.name ?? '',
          shopName: pharmacy?.name ?? '',
          plan: pharmacy?.plan ?? 'paid',
          expiresAt: pharmacy?.expiresAt,
        );
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
      widget.onActivated?.call();
    } catch (error) {
      var text = error.toString();
      if (text.startsWith('Bad state: ')) text = text.substring(11);
      if (text.startsWith('Exception: ')) text = text.substring(11);
      setState(() => _message = text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final ended = widget.subscription.hasExpired || widget.subscription.isBlocked;
        final title = widget.subscription.isTrial
            ? (ended
                ? S.t('Your free trial has ended.', 'Jaribio lako la bure limeisha.')
                : S.t('Subscribe to keep using PharmSpecio.', 'Jiandikishe ili uendelee kutumia PharmSpecio.'))
            : S.t('Access to PharmSpecio is currently locked.', 'Matumizi ya PharmSpecio yamefungwa kwa sasa.');
        return Scaffold(
          backgroundColor: const Color(0xfff4f7f8),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 720;
                        final plans = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xffdff7ee),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                ended
                                    ? S.t('Trial ended · subscribe to continue', 'Jaribio limeisha · jiandikishe ili uendelee')
                                    : S.t('Professional subscription', 'Usajili wa kitaalamu'),
                                style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                            const SizedBox(height: 10),
                            Text(
                              widget.subscription.message,
                              style: const TextStyle(color: Color(0xff68807d), fontSize: 16),
                            ),
                            if (widget.subscription.licenseEndsAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                S.t(
                                  'End date: ${widget.subscription.licenseEndsAt!.day}/${widget.subscription.licenseEndsAt!.month}/${widget.subscription.licenseEndsAt!.year}',
                                  'Tarehe ya mwisho: ${widget.subscription.licenseEndsAt!.day}/${widget.subscription.licenseEndsAt!.month}/${widget.subscription.licenseEndsAt!.year}',
                                ),
                                style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w700),
                              ),
                            ],
                            const SizedBox(height: 20),
                            _PlanOptionCard(
                              title: S.t('Monthly', 'Kila mwezi'),
                              price: 'TZS 120,000',
                              detail: S.t('Best for small pharmacies', 'Inafaa maduka madogo'),
                              badge: S.t('Popular', 'Inayopendwa'),
                            ),
                            const SizedBox(height: 12),
                            _PlanOptionCard(
                              title: S.t('6 Months', 'Miezi 6'),
                              price: 'TZS 600,000',
                              detail: S.t('Lower effective monthly cost', 'Bei ya mwezi inakuwa nafuu'),
                              badge: S.t('Value', 'Thamani'),
                            ),
                            const SizedBox(height: 12),
                            _PlanOptionCard(
                              title: S.t('Yearly', 'Mwaka'),
                              price: 'TZS 1,100,000',
                              detail: S.t('Maximum savings and full access', 'Akiba kubwa na matumizi kamili'),
                              badge: S.t('Best value', 'Nafuu zaidi'),
                            ),
                            if (!widget.embedded) ...[
                              const SizedBox(height: 18),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: () => AuthService().signOut(),
                                  icon: const Icon(Icons.logout_rounded),
                                  label: Text(S.t('Sign out', 'Toka')),
                                ),
                              ),
                            ],
                          ],
                        );
                        final activate = Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xfff7faf9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xffdfe7e7)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.t('Activate your access', 'Wezesha matumizi'),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                S.t(
                                  'Pay for a plan, then enter the activation code from support. The shop stays locked until that code is valid.',
                                  'Lipia mpango, kisha weka namba ya kuwezesha utakayopewa. Duka linabaki limefungwa hadi namba iwe sahihi.',
                                ),
                                style: const TextStyle(color: Color(0xff68807d), height: 1.5),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _codeController,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: Color(0xff183b3b),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'PHY-XXXX-XXXX-XXXX',
                                  helperText: S.t(
                                    'Paste the whole code, including the last 4 characters.',
                                    'Bandika namba yote, pamoja na herufi 4 za mwisho.',
                                  ),
                                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton(
                                  onPressed: _loading ? null : _activateCode,
                                  child: Text(_loading ? S.t('Activating...', 'Inawezesha...') : S.t('Activate plan', 'Wezesha mpango')),
                                ),
                              ),
                              if (_message != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xffe8f6f2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(_message!, style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w700)),
                                ),
                              ],
                              const SizedBox(height: 18),
                              const Divider(),
                              const SizedBox(height: 12),
                              Text(
                                S.t('How payment works', 'Malipo yanavyokwenda'),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                S.t(
                                  '1. Pay monthly, 6 months, or yearly.\n2. Support sends you an activation code.\n3. Enter the code here to unlock the shop.',
                                  '1. Lipa kwa mwezi, miezi 6, au mwaka.\n2. Unapewa namba ya kuwezesha.\n3. Weka namba hapa ili kufungua duka.',
                                ),
                                style: const TextStyle(color: Color(0xff68807d), height: 1.7),
                              ),
                            ],
                          ),
                        );
                        final children = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: stacked
                              ? [plans, const SizedBox(height: 24), activate]
                              : [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: plans),
                                      const SizedBox(width: 24),
                                      Expanded(child: activate),
                                    ],
                                  ),
                                ],
                        );
                        return SingleChildScrollView(child: children);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.detail,
    required this.badge,
  });

  final String title;
  final String price;
  final String detail;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xfff8fbfb),
        border: Border.all(color: const Color(0xffdfe7e7)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(color: Color(0xff68807d))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xffdff7ee),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(badge, style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w700, fontSize: 11)),
          ),
          Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        ],
      ),
    );
  }
}
