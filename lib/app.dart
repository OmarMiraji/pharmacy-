import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'backend/app_update_service.dart';
import 'backend/auth_service.dart';
import 'backend/firestore_collections.dart';
import 'backend/inventory_service.dart';
import 'backend/medicine_service.dart';
import 'backend/models.dart';
import 'backend/purchase_service.dart';
import 'backend/report_service.dart';
import 'backend/sales_service.dart';
import 'backend/receipt_service.dart';
import 'backend/permissions.dart';
import 'backend/subscription_service.dart';
import 'backend/user_management_service.dart';
import 'backend/user_profile.dart';
import 'backend/import_service.dart';
import 'backend/pharmacy.dart';
import 'backend/pharmacy_service.dart';
import 'backend/printer_settings.dart';
import 'backend/tenant_context.dart';
import 'screens/subscription_admin_screen.dart';
import 'screens/pharmacy_workspace_settings_screen.dart';
import 'screens/app_update_screen.dart';
import 'screens/apply_app_update.dart';
import 'screens/accounts_admin_screen.dart';

class PhyimacyApp extends StatelessWidget {
  const PhyimacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phyimacy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0f766e),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff4f7f8),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.white,
          selectedTileColor: Color(0xffdff7ee),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfff4f7f8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        onTimeout: () => throw TimeoutException('Firebase profile load timed out.'),
      );
      if (profile == null || !profile.isActive) {
        return _LoadedWorkspace(profile: profile);
      }
      final session = await PharmacyService().bindSession(profile).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('Pharmacy workspace load timed out.'),
      );
      return _LoadedWorkspace(
        profile: profile,
        license: session.license,
        readOnly: session.readOnly,
        blocked: session.blocked,
      );
    } catch (error) {
      TenantContext.instance.clear();
      AuthService.workspaceError =
          'Account ${widget.authService.currentUser?.email ?? widget.userId} could not open its pharmacy: $error. Other accounts can still sign in.';
      await widget.authService.signOut();
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return AccessDeniedScreen(
            message: AuthService.workspaceError ?? 'Could not open pharmacy workspace: ${snapshot.error}',
          );
        }
        final workspace = snapshot.data;
        final profile = workspace?.profile;
        if (profile == null) {
          return AccessDeniedScreen(
            message: 'No users document found for Firebase Auth UID: ${widget.authService.currentUser?.uid}',
          );
        }
        if (!profile.isActive) {
          return const AccessDeniedScreen(
            message: 'Your users document exists, but isActive is not true.',
          );
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      AuthService.workspaceError = null;
      await _authService.signIn(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      setState(() {
        _error = switch (error.code) {
          'user-not-found' || 'invalid-credential' || 'wrong-password' =>
            'No Firebase login for this email, or the password is wrong. Super Admin must create the shop admin first.',
          'invalid-email' => 'Enter a valid email address.',
          'user-disabled' => 'This login is disabled.',
          'network-request-failed' => 'Network error. Check internet and try again.',
          _ => error.message ?? 'Login failed.',
        };
      });
    } catch (_) {
      setState(() => _error = 'Login failed. Check your details and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF062F2F),
              Color(0xFF0A3F3F),
              Color(0xFF0D5658),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF062F2F).withOpacity(0.35),
                      blurRadius: 35,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (AuthService.workspaceError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xffffe8e6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            AuthService.workspaceError!,
                            style: const TextStyle(color: Color(0xffb42318), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      Center(
                        child: Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF41C8B1),
                                Color(0xFF0F766E),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F766E).withOpacity(0.35),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_pharmacy_rounded,
                            size: 42,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          'PHYIMACY',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: const Color(0xFF123C3D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF58706E),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email address',
                          filled: true,
                          fillColor: const Color(0xFFF4FAF9),
                          prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF0F766E)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          filled: true,
                          fillColor: const Color(0xFFF4FAF9),
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF0F766E)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFEE9097)),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _loading ? 'Signing in...' : 'Sign in',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  AppUpdateCheck? _appUpdate;

  @override
  void initState() {
    super.initState();
    AppUpdateService().check().then((value) {
      if (mounted) setState(() => _appUpdate = value);
    }).catchError((_) {});
  }

  List<_DashboardDestination> get _destinations => [
        if (widget.profile.can('dashboard.view'))
          const _DashboardDestination('Overview', Icons.grid_view_rounded),
        if (widget.profile.can('medicines.view'))
          const _DashboardDestination('Medicines', Icons.medication_outlined),
        if (widget.profile.can('medicines.view'))
          const _DashboardDestination('Categories', Icons.category_outlined),
        if (widget.profile.can('suppliers.manage') || widget.profile.can('purchases.view'))
          const _DashboardDestination('Suppliers', Icons.local_shipping_outlined),
        if (widget.profile.can('inventory.view'))
          const _DashboardDestination('Inventory', Icons.inventory_2_outlined),
        if (widget.profile.can('sales.view'))
          const _DashboardDestination('Sales', Icons.point_of_sale_outlined),
        if (widget.profile.can('purchases.view'))
          const _DashboardDestination('Purchases', Icons.shopping_cart_outlined),
        if (widget.profile.can('reports.view'))
          const _DashboardDestination('Reports', Icons.bar_chart_rounded),
        if (widget.profile.can('users.manage') || widget.profile.can('settings.manage') || widget.profile.isSuperAdmin)
          const _DashboardDestination('Settings', Icons.settings_outlined),
        if (widget.profile.isSuperAdmin)
          const _DashboardDestination('System', Icons.admin_panel_settings_rounded),
      ];

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final safeIndex = destinations.isEmpty ? 0 : _selectedIndex.clamp(0, destinations.length - 1);
    final selected = destinations.isEmpty ? null : destinations[safeIndex];
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            profile: widget.profile,
            destinations: destinations,
            selectedIndex: destinations.isEmpty ? null : safeIndex,
            onSelected: (index) => setState(() => _selectedIndex = index),
            onSignOut: () {
              TenantContext.instance.clear();
              widget.authService.signOut();
            },
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(profile: widget.profile, title: selected?.label ?? 'Phyimacy'),
                if (_appUpdate?.updateAvailable == true && _appUpdate?.latest != null)
                  Material(
                    color: const Color(0xffe8f6f2),
                    child: ListTile(
                      leading: const Icon(Icons.system_update_alt_rounded, color: Color(0xff0f766e)),
                      title: Text('New Phyimacy ${_appUpdate!.latest!.version} is available'),
                      subtitle: const Text('Tap Update. Phyimacy installs it and reopens by itself.'),
                      trailing: FilledButton(
                        onPressed: _appUpdate!.latest!.canAutoInstall
                            ? () => applyPhyimacyUpdate(context, _appUpdate!.latest!)
                            : null,
                        child: const Text('Update now'),
                      ),
                    ),
                  ),
                if (widget.license?.isTrial == true && widget.readOnly == false && widget.license?.isBlocked != true)
                  Material(
                    color: const Color(0xffe8f6f2),
                    child: ListTile(
                      leading: const Icon(Icons.hourglass_bottom_rounded, color: Color(0xff0f766e)),
                      title: Text(
                        widget.license?.trialCountdownLabel.isNotEmpty == true
                            ? widget.license!.trialCountdownLabel
                            : (widget.license?.message ?? 'Free trial is active.'),
                      ),
                      subtitle: widget.license?.licenseEndsAt == null
                          ? null
                          : Text(
                              'Trial ends ${widget.license!.licenseEndsAt!.day}/${widget.license!.licenseEndsAt!.month}/${widget.license!.licenseEndsAt!.year}',
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
                            'Paid subscription has ended. You can view records only until a new token is activated.',
                      ),
                      trailing: FilledButton(
                        onPressed: () async {
                          await showDialog<void>(
                            context: context,
                            builder: (dialogContext) => Dialog(
                              child: SizedBox(
                                width: 520,
                                height: 560,
                                child: SubscriptionGateScreen(
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
                        },
                        child: const Text('Activate token'),
                      ),
                    ),
                  ),
                Expanded(child: _buildContent(selected?.label)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(String? destination) {
    switch (destination) {
      case 'Medicines':
        return MedicinesScreen(profile: widget.profile);
      case 'Categories':
        return CategoriesScreen(profile: widget.profile);
      case 'Suppliers':
        return SuppliersScreen(profile: widget.profile);
      case 'Inventory':
        return InventoryScreen(profile: widget.profile);
      case 'Sales':
        return SalesScreen(profile: widget.profile);
      case 'Purchases':
        return PurchasesScreen(profile: widget.profile);
      case 'Reports':
        return const ReportsScreen();
      case 'Import medicines':
        return const MedicineImportScreen();
      case 'Settings':
        return SettingsScreen(profile: widget.profile);
      case 'System':
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
    required this.onSignOut,
  });

  final UserProfile profile;
  final List<_DashboardDestination> destinations;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      color: const Color(0xff102a2b),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xffb7f1dd),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_pharmacy_rounded, color: Color(0xff102a2b)),
              ),
              const SizedBox(width: 11),
              const Text('PHYIMACY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
            ],
          ),
          const SizedBox(height: 38),
          const Text('WORKSPACE', style: TextStyle(color: Color(0xff7da09b), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
          const SizedBox(height: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: ListView.builder(
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  final active = selectedIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      selected: active,
                      selectedTileColor: const Color(0xff2b5b58),
                      onTap: () => onSelected(index),
                      leading: Icon(destination.icon, color: active ? const Color(0xffb7f1dd) : const Color(0xff91aaa6), size: 20),
                      title: Text(destination.label, style: TextStyle(color: active ? Colors.white : const Color(0xffc1d2cf), fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(color: Color(0xff2b4b4b)),
          Row(
            children: [
              CircleAvatar(radius: 17, backgroundColor: const Color(0xfff2c58b), child: Text(profile.displayName.isEmpty ? '?' : profile.displayName[0].toUpperCase(), style: const TextStyle(color: Color(0xff573719), fontWeight: FontWeight.bold))),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)), Text(profile.role, style: const TextStyle(color: Color(0xff91aaa6), fontSize: 11))])),
              IconButton(tooltip: 'Sign out', onPressed: onSignOut, icon: const Icon(Icons.logout_rounded, color: Color(0xff91aaa6), size: 19)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.profile, required this.title});

  final UserProfile profile;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xffe4ebeb)))),
      child: Row(children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xff183b3b))), const Spacer(), const Icon(Icons.notifications_none_rounded, color: Color(0xff68807d)), const SizedBox(width: 20), Text(profile.email, style: const TextStyle(fontSize: 12, color: Color(0xff68807d)))]),
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

  @override
  void initState() {
    super.initState();
    _overviewFuture = _loadOverviewData();
  }

  Future<_OverviewData> _loadOverviewData() async {
    final firestore = FirebaseFirestore.instance;
    final tenant = TenantContext.instance;
    if ((tenant.pharmacyId ?? '').trim().isEmpty) {
      return const _OverviewData(
        stockItems: 0,
        stockUnits: 0,
        lowStockCount: 0,
        todaySalesCount: 0,
        todaySalesMinor: 0,
        expirySoonCount: 0,
        weeklyRevenue: [],
        healthyStockCount: 0,
        recentSales: [],
      );
    }
    try {
      final medicinesSnapshot = await tenant.scoped(firestore.collection(FirestoreCollections.medicines)).get();
      final batchesSnapshot = await tenant.scoped(firestore.collection(FirestoreCollections.medicineBatches)).get();
      final salesSnapshot = await tenant.scoped(firestore.collection(FirestoreCollections.sales)).get();

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
    final expiryWindow = now.add(const Duration(days: 90));

    final todaySales = salesSnapshot.docs.where((doc) {
      final value = doc.data()['createdAt'];
      final createdAt = value is Timestamp ? value.toDate() : null;
      return createdAt != null && createdAt.isAfter(todayStart) && createdAt.isBefore(todayEnd);
    }).toList();

    final todaySalesMinor = todaySales.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
    final expirySoonCount = batchesSnapshot.docs.where((doc) {
      final expiry = (doc.data()['expiryDate'] as Timestamp?)?.toDate();
      return expiry != null && expiry.isBefore(expiryWindow) && !expiry.isBefore(now);
    }).length;

    final weeklyRevenue = <_WeeklyRevenuePoint>[];
    for (int offset = 6; offset >= 0; offset--) {
      final dayStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: offset));
      final nextDay = dayStart.add(const Duration(days: 1));
      final dayRevenue = salesSnapshot.docs.where((doc) {
        final value = doc.data()['createdAt'];
        final createdAt = value is Timestamp ? value.toDate() : null;
        return createdAt != null && !createdAt.isBefore(dayStart) && createdAt.isBefore(nextDay);
      }).fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
      weeklyRevenue.add(_WeeklyRevenuePoint(day: dayStart, revenueMinor: dayRevenue));
    }

    final sortedSales = salesSnapshot.docs.toList()
      ..sort((a, b) {
        final left = a.data()['createdAt'];
        final right = b.data()['createdAt'];
        final leftDate = left is Timestamp ? left.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = right is Timestamp ? right.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });
    final recentSales = sortedSales.take(5).map((doc) {
      final data = doc.data();
      final createdAt = (data['createdAt'] is Timestamp) ? (data['createdAt'] as Timestamp).toDate() : DateTime.now();
      return _RecentSaleEntry(
        id: doc.id,
        receiptNumber: (data['receiptNumber'] as String?) ?? 'Receipt',
        totalMinor: (data['totalMinor'] as num?)?.toInt() ?? 0,
        paymentMethod: (data['paymentMethod'] as String?) ?? 'cash',
        createdAt: createdAt,
      );
    }).toList();

    final healthyStockCount = medicines.length - lowStockCount;
    final totalUnits = medicines.fold<int>(0, (total, doc) => total + ((doc.data()['quantityOnHand'] as num?)?.toInt() ?? 0));

    return _OverviewData(
      stockItems: medicines.length,
      stockUnits: totalUnits,
      lowStockCount: lowStockCount,
      todaySalesCount: todaySales.length,
      todaySalesMinor: todaySalesMinor,
      expirySoonCount: expirySoonCount,
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
          weeklyRevenue: [],
          healthyStockCount: 0,
          recentSales: [],
        );
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _overviewFuture = _loadOverviewData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OverviewData>(
      future: _overviewFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load overview: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final summary = snapshot.data!;
        final hasMissingPermissions = widget.profile.missingPharmacyPermissions().isNotEmpty;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 30, 32, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Good day, ${widget.profile.displayName.split(' ').first}.', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                        const SizedBox(height: 6),
                        const Text('Here is what is happening in your pharmacy right now.', style: TextStyle(color: Color(0xff68807d))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    tooltip: 'Refresh overview',
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xff183b3b)),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Wrap(spacing: 16, runSpacing: 16, children: [
                _MetricCard(label: 'Stock items', value: '${summary.stockItems}', note: '${summary.stockUnits} units in hand', icon: Icons.inventory_2_outlined, color: const Color(0xffdff7ee)),
                _MetricCard(label: 'Low stock', value: '${summary.lowStockCount}', note: 'Needs reorder attention', icon: Icons.warning_amber_rounded, color: const Color(0xfffff0d7)),
                _MetricCard(label: 'Today\'s sales', value: 'TZS ${summary.todaySalesMinor}', note: '${summary.todaySalesCount} completed sales', icon: Icons.trending_up_rounded, color: const Color(0xffe2efff)),
                _MetricCard(label: 'Expiry watch', value: '${summary.expirySoonCount}', note: 'Batches within 90 days', icon: Icons.schedule_rounded, color: const Color(0xfff2e7ff)),
              ]),
              if (hasMissingPermissions) ...[
                const SizedBox(height: 24),
                Card(
                  color: const Color(0xfffff7e8),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.lock_outline_rounded, color: Color(0xffb45309)),
                          const SizedBox(width: 12),
                          Text('Some workspace permissions are missing', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 8),
                        Text(widget.profile.missingPharmacyPermissions().join('  •  '), style: TextStyle(color: Colors.orange.shade900, height: 1.4, fontSize: 12)),
                        const SizedBox(height: 8),
                        Text('Ask an admin to add these as boolean true inside the permissions map.', style: TextStyle(color: Colors.orange.shade900, height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.bar_chart_rounded, color: Color(0xff0f766e)), SizedBox(width: 8), Text('Weekly sales revenue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))]),
                            const SizedBox(height: 18),
                            SizedBox(height: 180, child: _SalesBarChart(points: summary.weeklyRevenue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.pie_chart_outline_rounded, color: Color(0xff0f766e)), SizedBox(width: 8), Text('Stock health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))]),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 170,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: CustomPaint(
                                      painter: _StockHealthPainter(
                                        healthyPercent: summary.stockItems > 0 ? (summary.healthyStockCount / summary.stockItems) * 100 : 0,
                                        lowPercent: summary.stockItems > 0 ? (summary.lowStockCount / summary.stockItems) * 100 : 0,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Text('Recent sales activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))),
                          if (widget.profile.can('sales.refund'))
                            TextButton.icon(
                              onPressed: () async {
                                if (summary.recentSales.isEmpty) return;
                                final firstSale = summary.recentSales.first;
                                final shouldVoid = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Void sale?'),
                                    content: Text('This will reverse the sale ${firstSale.receiptNumber} and restore stock. Continue?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Void sale')),
                                    ],
                                  ),
                                );
                                if (shouldVoid == true && mounted) {
                                  await SalesService().voidSale(firstSale.id);
                                  _refresh();
                                }
                              },
                              icon: const Icon(Icons.undo_rounded),
                              label: const Text('Void latest'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (summary.recentSales.isEmpty)
                        const Text('No sales have been recorded yet for this period.', style: TextStyle(color: Color(0xff68807d)))
                      else
                        ...summary.recentSales.map((sale) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xffe2efff),
                                child: const Icon(Icons.receipt_long_rounded, color: Color(0xff183b3b), size: 19),
                              ),
                              title: Text(sale.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                              subtitle: Text('${sale.paymentMethod.toUpperCase()} • ${sale.createdAt.day}/${sale.createdAt.month}/${sale.createdAt.year}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('TZS ${sale.totalMinor}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                                  if (widget.profile.can('sales.refund')) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (dialogContext) => AlertDialog(
                                            title: const Text('Confirm void'),
                                            content: Text('Reverse sale ${sale.receiptNumber}?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                                              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Yes, void')),
                                            ],
                                          ),
                                        );
                                        if (confirm == true && mounted) {
                                          await SalesService().voidSale(sale.id);
                                          _refresh();
                                        }
                                      },
                                      child: const Text('Void'),
                                    ),
                                  ],
                                ],
                              ),
                            )),
                    ],
                  ),
                ),
              ),
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
  });

  final String id;
  final String receiptNumber;
  final int totalMinor;
  final String paymentMethod;
  final DateTime createdAt;
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
    final radius = size.width * 0.38;
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Color(0xff68807d), fontSize: 12)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
      ],
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
    return SizedBox(
      width: 215,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffedf2f2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0f0f766e),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color(0xff285957)),
            ),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(color: Color(0xff68807d), fontSize: 12)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
            const SizedBox(height: 5),
            Text(note, style: const TextStyle(color: Color(0xff879895), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final medicineService = MedicineService();
    return StreamBuilder<List<Medicine>>(
      stream: medicineService.watchMedicines(),
      builder: (context, medicineSnapshot) {
        if (medicineSnapshot.hasError) return Center(child: Text('Could not load stock: ${medicineSnapshot.error}'));
        if (!medicineSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final medicines = medicineSnapshot.data!;
        final totalUnits = medicines.fold<int>(0, (total, medicine) => total + medicine.quantityOnHand);
        final lowStock = medicines.where((medicine) => medicine.quantityOnHand <= medicine.reorderLevel).length;
        return StreamBuilder<List<MedicineBatch>>(
          stream: medicineService.watchAllBatches(),
          builder: (context, batchSnapshot) {
            final allBatches = batchSnapshot.data ?? const <MedicineBatch>[];
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 30, 32, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Inventory control', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                const SizedBox(height: 7),
                const Text('Receive stock by batch and keep expiry tracking accurate.', style: TextStyle(color: Color(0xff68807d))),
                const SizedBox(height: 24),
                Wrap(spacing: 14, runSpacing: 14, children: [
                  _InventoryMetric(label: 'Stock units', value: '$totalUnits', icon: Icons.inventory_2_outlined, color: const Color(0xffdff7ee)),
                  _InventoryMetric(label: 'Products', value: '${medicines.length}', icon: Icons.medication_outlined, color: const Color(0xffe2efff)),
                  _InventoryMetric(label: 'Low stock', value: '$lowStock', icon: Icons.warning_amber_rounded, color: const Color(0xfffff0d7)),
                ]),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xffedf2f2)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0f0f766e),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(children: [
                    const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 10), child: Row(children: [Expanded(child: Text('Stock by medicine', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b)))), Text('Receive stock', style: TextStyle(fontSize: 12, color: Color(0xff68807d)))])),
                    if (medicines.isEmpty)
                      const Padding(padding: EdgeInsets.all(28), child: Text('Add a medicine first, then receive its stock here.'))
                    else
                      ...medicines.map((medicine) {
                        final isLow = medicine.quantityOnHand <= medicine.reorderLevel;
                        final medicineBatches = allBatches.where((batch) => batch.medicineId == medicine.id).toList();
                        final nextExpiry = medicineBatches.isNotEmpty ? medicineBatches.first.expiryDate.toDate() : null;
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: isLow ? const Color(0xfffff0d7) : const Color(0xffdff7ee), child: Icon(Icons.medication_outlined, color: isLow ? const Color(0xffb45309) : const Color(0xff0f766e))),
                          title: Text(medicine.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${medicine.sku}  •  ${medicine.quantityOnHand} ${medicine.unit} on hand${nextExpiry == null ? '' : '  •  Next expiry ${nextExpiry.day}/${nextExpiry.month}/${nextExpiry.year}'}',
                          ),
                          trailing: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            children: [
                              if (medicineBatches.isNotEmpty)
                                Chip(
                                  label: Text('${medicineBatches.length} batch${medicineBatches.length == 1 ? '' : 'es'}'),
                                  backgroundColor: const Color(0xffe2efff),
                                  labelStyle: const TextStyle(color: Color(0xff183b3b), fontSize: 11),
                                ),
                              if (profile.can('inventory.adjust'))
                                FilledButton.tonalIcon(onPressed: () => _showReceiveDialog(context, medicine), icon: const Icon(Icons.add, size: 17), label: const Text('Receive'))
                              else
                                Text(isLow ? 'Low stock' : 'Available'),
                            ],
                          ),
                        );
                      }),
                  ]),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _showReceiveDialog(BuildContext context, Medicine medicine) async {
    final formKey = GlobalKey<FormState>();
    final batch = TextEditingController();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    DateTime expiry = DateTime.now().add(const Duration(days: 365));
    final service = InventoryService();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.move_to_inbox_rounded, color: Color(0xff0f766e)),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Receive ${medicine.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))),
                      IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Add a new stock batch. The medicine total and audit movement update together.', style: TextStyle(color: Color(0xff68807d), height: 1.4)),
                    const SizedBox(height: 22),
                    _dialogField(batch, 'Batch number', Icons.qr_code_2_rounded),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _dialogNumber(quantity, 'Quantity', Icons.inventory_2_outlined)),
                      const SizedBox(width: 12),
                      Expanded(child: _dialogNumber(cost, 'Unit cost (TZS)', Icons.payments_outlined)),
                    ]),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available_outlined, color: Color(0xff0f766e)),
                      title: const Text('Expiry date'),
                      subtitle: Text('${expiry.day}/${expiry.month}/${expiry.year}'),
                      onTap: () async {
                        final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: expiry);
                        if (picked != null) setState(() => expiry = picked);
                      },
                    ),
                    const SizedBox(height: 15),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final user = AuthService().currentUser;
                          if (user == null) return;
                          await service.receiveBatch(medicineId: medicine.id, batchNumber: batch.text, expiryDate: Timestamp.fromDate(expiry), quantity: int.parse(quantity.text), unitCostMinor: int.parse(cost.text), createdBy: user.uid);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Receive stock'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    batch.dispose();
    quantity.dispose();
    cost.dispose();
  }

  Widget _dialogField(TextEditingController controller, String label, IconData icon) => TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19)),
        validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
      );

  Widget _dialogNumber(TextEditingController controller, String label, IconData icon) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19)),
        validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a whole number' : null,
      );
}

class _InventoryMetric extends StatelessWidget {
  const _InventoryMetric({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xffedf2f2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0f0f766e),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: const Color(0xff285957), size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
              ],
            ),
          ],
        ),
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
  final _salesService = SalesService();
  final _authService = AuthService();
  final _cart = <String, SaleCartItem>{};
  final PrinterSettings _printerSettings = PrinterSettingsStore.instance.current;
  String _paymentMethod = 'cash';
  bool _checkingOut = false;
  String? _message;

  Future<void> _printReceiptNow(ReceiptSummary receipt) async {
    await ReceiptService().printReceipt(receipt, settings: _printerSettings, context: context);
    if (!mounted) return;
    setState(() => _message = 'Receipt ${receipt.receiptNumber} sent to printer.');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Medicine>>(
      stream: MedicineService().watchMedicines(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load POS medicines: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final query = _searchController.text.trim().toLowerCase();
        final medicines = snapshot.data!.where((medicine) => query.isEmpty || medicine.name.toLowerCase().contains(query) || medicine.sku.toLowerCase().contains(query)).toList();
        final subtotal = _cart.values.fold<int>(0, (total, item) => total + item.totalMinor);
        final discount = int.tryParse(_discountController.text) ?? 0;
        final total = (subtotal - discount).clamp(0, subtotal);
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sales & POS', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                SizedBox(height: 6),
                Text('Build a sale quickly and keep stock movements accurate.', style: TextStyle(color: Color(0xff68807d))),
              ])),
              _PillLabel(text: '${_cart.length} line items', color: const Color(0xffdff7ee)),
            ]),
            const SizedBox(height: 24),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _PremiumPanel(child: _ProductPicker(medicines: medicines, controller: _searchController, onSearch: () => setState(() {}), onAdd: _addToCart))),
              const SizedBox(width: 18),
              SizedBox(width: 380, child: _PremiumPanel(child: _CartPanel(cart: _cart, subtotal: subtotal, discountController: _discountController, paymentMethod: _paymentMethod, message: _message, checkingOut: _checkingOut, total: total, onDiscountChanged: () => setState(() {}), onPaymentChanged: (value) => setState(() => _paymentMethod = value), onIncrease: _increaseCart, onDecrease: _decreaseCart, onRemoveItem: _removeCartItem, onClearCart: _clearCart, onCheckout: () => _checkout(total, discount)))),
            ])),
          ]),
        );
      },
    );
  }

  void _addToCart(Medicine medicine) {
    final existing = _cart[medicine.id];
    final quantity = (existing?.quantity ?? 0) + 1;
    if (quantity > medicine.quantityOnHand) {
      setState(() => _message = 'Only ${medicine.quantityOnHand} ${medicine.unit} available for ${medicine.name}.');
      return;
    }
    setState(() {
      _message = null;
      _cart[medicine.id] = SaleCartItem(medicineId: medicine.id, medicineName: medicine.name, quantity: quantity, unitPriceMinor: medicine.sellingPriceMinor);
    });
  }

  void _increaseCart(SaleCartItem item) {
    setState(() {
      _cart[item.medicineId] = SaleCartItem(
        medicineId: item.medicineId,
        medicineName: item.medicineName,
        quantity: item.quantity + 1,
        unitPriceMinor: item.unitPriceMinor,
      );
      _message = null;
    });
  }

  void _decreaseCart(SaleCartItem item) {
    setState(() {
      if (item.quantity <= 1) {
        _cart.remove(item.medicineId);
      } else {
        _cart[item.medicineId] = SaleCartItem(medicineId: item.medicineId, medicineName: item.medicineName, quantity: item.quantity - 1, unitPriceMinor: item.unitPriceMinor);
      }
    });
  }

  void _removeCartItem(SaleCartItem item) {
    setState(() {
      _cart.remove(item.medicineId);
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
    final user = _authService.currentUser;
    if (user == null) return;
    if (discount < 0) {
      setState(() => _message = 'Discount cannot be negative.');
      return;
    }
    if (discount > total) {
      setState(() => _message = 'Discount cannot be greater than the sale total.');
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _message = 'Add at least one medicine to complete the sale.');
      return;
    }
    setState(() { _checkingOut = true; _message = null; });
    try {
      final receiptNumber = await _salesService.completeSale(items: _cart.values.toList(), soldBy: user.uid, paymentMethod: _paymentMethod, discountMinor: discount);
      final receipt = ReceiptSummary(
        receiptNumber: receiptNumber,
        soldBy: user.uid,
        paymentMethod: _paymentMethod,
        subtotalMinor: _cart.values.fold<int>(0, (total, item) => total + item.totalMinor),
        discountMinor: discount,
        totalMinor: total,
        createdAt: DateTime.now(),
        items: _cart.values.map((item) => ReceiptLineItem(name: item.medicineName, quantity: item.quantity, unitPriceMinor: item.unitPriceMinor, totalMinor: item.totalMinor)).toList(),
      );
      if (mounted) {
        if (_printerSettings.autoPrintAfterSale) {
          await _printReceiptNow(receipt);
        }
        setState(() {
          _cart.clear();
          _discountController.text = '0';
          _message = 'Sale completed. Receipt $receiptNumber. ${_printerSettings.autoPrintAfterSale ? 'Printed.' : 'Print when you choose.'}';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString().replaceFirst('Bad state: ', ''));
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xffedf2f2)),
          boxShadow: const [
            BoxShadow(color: Color(0x0f0f766e), blurRadius: 12, offset: Offset(0, 6)),
          ],
        ),
        child: child,
      );
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({required this.medicines, required this.controller, required this.onSearch, required this.onAdd});
  final List<Medicine> medicines;
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
          TextField(
            controller: controller,
            onChanged: (_) => onSearch(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search medicine by name or SKU',
              filled: true,
              fillColor: Color(0xfff7fbfb),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: medicines.isEmpty
                ? const Center(child: Text('No matching medicines.'))
                : GridView.builder(
                    itemCount: medicines.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.88,
                    ),
                    itemBuilder: (context, index) {
                      final medicine = medicines[index];
                      final unavailable = medicine.quantityOnHand == 0;

                      return InkWell(
                        onTap: unavailable ? null : () => onAdd(medicine),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xffedf2f2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xffe2efff),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.medication_outlined, color: Color(0xff2563eb), size: 18),
                                  ),
                                  const Spacer(),
                                  if (unavailable)
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
                              const SizedBox(height: 12),
                              Text(medicine.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                              const SizedBox(height: 6),
                              Text(medicine.sku, style: const TextStyle(fontSize: 11, color: Color(0xff68807d))),
                              const Spacer(),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('TZS ${medicine.sellingPriceMinor}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff0f766e))),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: unavailable ? null : () => onAdd(medicine),
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('${medicine.quantityOnHand} ${medicine.unit} left', style: const TextStyle(fontSize: 11, color: Color(0xff68807d))),
                            ],
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
  const _CartPanel({required this.cart, required this.subtotal, required this.discountController, required this.paymentMethod, required this.message, required this.checkingOut, required this.total, required this.onDiscountChanged, required this.onPaymentChanged, required this.onIncrease, required this.onDecrease, required this.onRemoveItem, required this.onClearCart, required this.onCheckout});
  final Map<String, SaleCartItem> cart;
  final int subtotal;
  final TextEditingController discountController;
  final String paymentMethod;
  final String? message;
  final bool checkingOut;
  final int total;
  final VoidCallback onDiscountChanged;
  final ValueChanged<String> onPaymentChanged;
  final ValueChanged<SaleCartItem> onIncrease;
  final ValueChanged<SaleCartItem> onDecrease;
  final ValueChanged<SaleCartItem> onRemoveItem;
  final VoidCallback onClearCart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final cartWidgets = cart.values.map((item) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.medicineName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                const SizedBox(height: 2),
                Text('${item.quantity} × TZS ${item.unitPriceMinor}', style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(onPressed: () => onDecrease(item), icon: const Icon(Icons.remove, size: 18), splashRadius: 18),
              Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
              IconButton(onPressed: () => onIncrease(item), icon: const Icon(Icons.add, size: 18), splashRadius: 18),
              IconButton(onPressed: () => onRemoveItem(item), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xffb42318)), splashRadius: 18),
            ],
          ),
        ],
      ),
    )).toList();
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [Icon(Icons.shopping_basket_outlined, color: Color(0xff0f766e)), SizedBox(width: 9), Text('Current sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))]),
          const SizedBox(height: 14),
          Flexible(
            child: cart.isEmpty
                ? const Center(child: Text('Add medicines to begin.'))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xfff8fbfb),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListView.separated(
                      itemCount: cartWidgets.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => cartWidgets[index],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          _SaleTotalRow(label: 'Subtotal', value: subtotal),
          const SizedBox(height: 8),
          TextField(controller: discountController, keyboardType: TextInputType.number, onChanged: (_) => onDiscountChanged(), decoration: const InputDecoration(labelText: 'Discount (TZS)', prefixIcon: Icon(Icons.local_offer_outlined))),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: paymentMethod, decoration: const InputDecoration(labelText: 'Payment method', prefixIcon: Icon(Icons.payments_outlined)), items: const [DropdownMenuItem(value: 'cash', child: Text('Cash')), DropdownMenuItem(value: 'card', child: Text('Card')), DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money'))], onChanged: (value) { if (value != null) onPaymentChanged(value); }),
          const SizedBox(height: 12),
          _SaleTotalRow(label: 'Total', value: total, prominent: true),
          if (message != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(message!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xffb45309)))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: cart.isEmpty ? null : onClearCart,
                  icon: const Icon(Icons.clear_all_rounded),
                  label: const Text('Clear cart'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: cart.isEmpty || checkingOut ? null : onCheckout,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(checkingOut ? 'Completing sale...' : 'Complete sale'),
                ),
              ),
            ],
          ),
        ],
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
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: prominent ? FontWeight.w800 : FontWeight.w500, color: const Color(0xff68807d))), Text('TZS $value', style: TextStyle(fontSize: prominent ? 20 : 14, fontWeight: FontWeight.w800, color: const Color(0xff183b3b)))]);
}

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final service = PurchaseService();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: StreamBuilder<List<SupplierOption>>(
        stream: service.watchSuppliers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not load suppliers: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final suppliers = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Suppliers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                        SizedBox(height: 6),
                        Text('Track your main medicine suppliers and their contact details.', style: TextStyle(color: Color(0xff68807d))),
                      ],
                    ),
                  ),
                  if (profile.can('suppliers.manage'))
                    FilledButton.icon(
                      onPressed: () => _showSupplierDialog(context, service),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add supplier'),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: suppliers.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xffedf2f2)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0f0f766e), blurRadius: 12, offset: Offset(0, 6)),
                          ],
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xffe2efff),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(Icons.local_shipping_outlined, size: 30, color: Color(0xff2563eb)),
                                ),
                                const SizedBox(height: 18),
                                const Text('No suppliers yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                                const SizedBox(height: 8),
                                const Text('Add the first supplier to start receiving purchases.', style: TextStyle(color: Color(0xff68807d))),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xffedf2f2)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0f0f766e), blurRadius: 12, offset: Offset(0, 6)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: ListView.separated(
                            itemCount: suppliers.length,
                            separatorBuilder: (_, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final supplier = suppliers[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xffdff7ee),
                                  child: Text(supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : 'S', style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w800)),
                                ),
                                title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                                subtitle: Text(supplier.phone?.isNotEmpty == true ? supplier.phone! : 'No phone number added', style: const TextStyle(color: Color(0xff68807d))),
                                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xff68807d)),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSupplierDialog(BuildContext context, PurchaseService service) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.local_shipping_outlined, color: Color(0xff0f766e)),
            SizedBox(width: 10),
            Text('Add supplier'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Supplier name', hintText: 'Example: Mzigo Pharma'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final supplierName = name.text.trim();
              if (supplierName.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Supplier name is required.')));
                return;
              }
              await service.createSupplier(name: supplierName, phone: phone.text, email: email.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    email.dispose();
  }
}

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final service = PurchaseService();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Purchases', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))), SizedBox(height: 6), Text('Manage suppliers and receive incoming stock by batch.', style: TextStyle(color: Color(0xff68807d)))])),
          if (profile.can('purchases.create')) FilledButton.icon(onPressed: () => _showPurchaseDialog(context, service), icon: const Icon(Icons.add_shopping_cart_outlined), label: const Text('Receive purchase')),
          const SizedBox(width: 10),
          if (profile.can('suppliers.manage')) OutlinedButton.icon(onPressed: () => _showSupplierDialog(context, service), icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('Add supplier')),
        ]),
        const SizedBox(height: 24),
        Expanded(child: StreamBuilder<List<PurchaseRecord>>(stream: service.watchPurchases(), builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not load purchases: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final purchases = snapshot.data!;
          if (purchases.isEmpty) return const _EmptyPurchaseState();
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xffedf2f2)),
              boxShadow: const [
                BoxShadow(color: Color(0x0f0f766e), blurRadius: 12, offset: Offset(0, 6)),
              ],
            ),
            child: ListView.separated(
              itemCount: purchases.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final purchase = purchases[index];
                return ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xffffeadf), child: Icon(Icons.shopping_cart_outlined, color: Color(0xffc2410c))),
                  title: Text(purchase.invoiceNumber?.isNotEmpty == true ? purchase.invoiceNumber! : 'Purchase ${purchase.id.substring(0, 6)}'),
                  subtitle: Text('Supplier: ${purchase.supplierId}  •  ${purchase.status}'),
                  trailing: Text('TZS ${purchase.totalMinor}', style: const TextStyle(fontWeight: FontWeight.w800)),
                );
              },
            ),
          );
        }))
      ]),
    );
  }

  Future<void> _showSupplierDialog(BuildContext context, PurchaseService service) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final supplierName = name.text.trim();
              if (supplierName.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Supplier name is required.')));
                return;
              }
              await service.createSupplier(name: supplierName, phone: phone.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save supplier'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
  }

  Future<void> _showPurchaseDialog(BuildContext context, PurchaseService service) async {
    final medicines = await MedicineService().watchMedicines().first;
    final suppliers = await service.watchSuppliers().first;
    if (!context.mounted) return;
    if (medicines.isEmpty || suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one supplier and one medicine before receiving stock.')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    String supplierId = suppliers.first.id;
    String medicineId = medicines.first.id;
    final batch = TextEditingController();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    final invoice = TextEditingController();
    DateTime expiry = DateTime.now().add(const Duration(days: 365));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Receive purchase'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: supplierId,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: [for (final supplier in suppliers) DropdownMenuItem(value: supplier.id, child: Text(supplier.name))],
                    onChanged: (value) => setState(() => supplierId = value ?? supplierId),
                    validator: (value) => value == null || value.isEmpty ? 'Select a supplier' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: medicineId,
                    decoration: const InputDecoration(labelText: 'Medicine'),
                    items: [for (final medicine in medicines) DropdownMenuItem(value: medicine.id, child: Text(medicine.name))],
                    onChanged: (value) => setState(() => medicineId = value ?? medicineId),
                    validator: (value) => value == null || value.isEmpty ? 'Select a medicine' : null,
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: invoice, decoration: const InputDecoration(labelText: 'Invoice number (optional)')),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: batch,
                    decoration: const InputDecoration(labelText: 'Batch number'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Batch number is required' : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Quantity'),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed <= 0) return 'Enter a valid quantity';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Unit cost (TZS)'),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed < 0) return 'Enter a valid cost';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Expiry date'),
                    subtitle: Text('${expiry.day}/${expiry.month}/${expiry.year}'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                        initialDate: expiry,
                      );
                      if (picked != null) setState(() => expiry = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final user = AuthService().currentUser;
                final amount = int.tryParse(quantity.text);
                final unitCost = int.tryParse(cost.text);
                if (user == null || amount == null || unitCost == null || amount <= 0 || unitCost < 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter valid quantity and cost before saving.')),
                  );
                  return;
                }
                await service.receivePurchase(
                  supplierId: supplierId,
                  medicineId: medicineId,
                  batchNumber: batch.text,
                  expiryDate: expiry,
                  quantity: amount,
                  unitCostMinor: unitCost,
                  createdBy: user.uid,
                  invoiceNumber: invoice.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Receive stock'),
            ),
          ],
        ),
      ),
    );

    batch.dispose();
    quantity.dispose();
    cost.dispose();
    invoice.dispose();
  }
}

class _EmptyPurchaseState extends StatelessWidget {
  const _EmptyPurchaseState();

  @override
  Widget build(BuildContext context) => const Center(child: Text('No purchases yet. Add a supplier, then receive stock.'));
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
    _selected = widget.profile.isSuperAdmin ? 'Pharmacies and logins' : 'Shop';
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_SettingCardOption>[];

    if (widget.profile.isSuperAdmin) {
      cards.add(const _SettingCardOption(label: 'Pharmacies and logins', icon: Icons.storefront_rounded, description: 'Create a shop with its admin, then add staff'));
      cards.add(const _SettingCardOption(label: 'Licenses', icon: Icons.workspace_premium_rounded, description: 'Tokens and paid access dates'));
      cards.add(const _SettingCardOption(label: 'App updates', icon: Icons.system_update_alt_rounded, description: 'Publish or download the latest version'));
    } else {
      if (widget.profile.can('users.manage')) {
        cards.add(const _SettingCardOption(label: 'Team', icon: Icons.manage_accounts_outlined, description: 'Staff logins for this pharmacy'));
      }
      cards.add(const _SettingCardOption(label: 'Shop', icon: Icons.tune_rounded, description: 'This pharmacy name, phone, and address'));
      if (widget.profile.can('settings.manage')) {
        cards.add(const _SettingCardOption(label: 'Printer', icon: Icons.print_outlined, description: 'Receipt printer'));
        cards.add(const _SettingCardOption(label: 'Data tools', icon: Icons.storage_rounded, description: 'Backup, restore, or clear'));
      }
      cards.add(const _SettingCardOption(label: 'App updates', icon: Icons.system_update_alt_rounded, description: 'Check for a new Phyimacy version'));
    }

    final selectedContent = switch (_selected) {
      'Printer' => const PrinterSettingsScreen(),
      'Team' => TeamAccessScreen(profile: widget.profile),
      'Pharmacies and logins' => AccountsAdminScreen(profile: widget.profile),
      'Licenses' => SubscriptionAdminScreen(profile: widget.profile),
      'App updates' => AppUpdateScreen(profile: widget.profile),
      'Data tools' => PharmacyWorkspaceSettingsScreen(profile: widget.profile),
      _ => PharmacyWorkspaceSettingsScreen(profile: widget.profile),
    };

    final fillHeight = false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
          const SizedBox(height: 6),
          const Text('Manage account defaults, print setup, access control, and pharmacy preferences.', style: TextStyle(color: Color(0xff68807d))),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards.map((card) {
              final active = _selected == card.label;
              return SizedBox(
                width: 230,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = card.label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xffdff7ee) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: active ? const Color(0xff0f766e) : const Color(0xffdfe7e7),
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: active ? const Color(0xffb7f1dd) : const Color(0xfff2f5f5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(card.icon, color: const Color(0xff0f766e)),
                        ),
                        const SizedBox(height: 12),
                        Text(card.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                        const SizedBox(height: 6),
                        Text(card.description, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: fillHeight
                    ? selectedContent
                    : SingleChildScrollView(child: selectedContent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingCardOption {
  const _SettingCardOption({required this.label, required this.icon, required this.description});

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
        Text('• Default pricing norms\n• Business profile and branding\n• Working defaults for medicine setup\n• Standard category naming', style: TextStyle(height: 1.8, color: Color(0xff4a5a5d))),
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
        Text('• Protect stock and financial changes\n• Review access permissions\n• Track user roles and approvals\n• Restrict sensitive actions', style: TextStyle(height: 1.8, color: Color(0xff4a5a5d))),
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
        const Text('Team', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        const Text('Add cashiers, pharmacists, and storekeepers for this pharmacy. The shop admin login is created with the pharmacy.', style: TextStyle(color: Color(0xff68807d))),
        const SizedBox(height: 16),
        if (isShopAdmin)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _showCreateProfileDialog(context, service, canManageSuperAdmin: canManageSuperAdmin),
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
                    ].join('  •  '),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if ((canManageSuperAdmin && user.id != profile?.id) ||
                          (isShopAdmin && user.id != profile?.id && user.role != 'admin' && user.role != 'super_admin'))
                        FilledButton.tonalIcon(
                          onPressed: () => _showEditor(context, service, user, canManageSuperAdmin: canManageSuperAdmin),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('Manage'),
                        ),
                      if ((canManageSuperAdmin && user.id != profile?.id) ||
                          (isShopAdmin && user.id != profile?.id && user.role != 'admin' && user.role != 'super_admin'))
                        IconButton(
                          tooltip: 'Delete profile',
                          onPressed: () => _deleteProfile(context, service, user),
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

  Future<void> _showCreateProfileDialog(BuildContext context, UserManagementService service, {required bool canManageSuperAdmin}) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var role = 'pharmacist';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
        title: const Text('Add staff'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Each person needs a new email that is not already in Firebase. If create failed before, cashier@gmail.com may already exist — use cashier2@gmail.com or the original password.',
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'pharmacist', child: Text('Pharmacist')),
                  DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  DropdownMenuItem(value: 'storekeeper', child: Text('Storekeeper')),
                ],
                onChanged: (value) => setState(() => role = value ?? role),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                await service.createLoginAndProfile(
                  displayName: name.text,
                  email: email.text,
                  password: password.text,
                  role: role,
                  permissions: AppPermissions.resolvedPermissions(role),
                  isActive: true,
                  pharmacyId: TenantContext.instance.pharmacyId,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Staff login created for this pharmacy.')),
                  );
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: const Text('Create login'),
          ),
        ],
        ),
      ),
    );
    name.dispose();
    email.dispose();
    password.dispose();
  }

  Future<void> _deleteProfile(BuildContext context, UserManagementService service, UserProfile user) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Delete profile?'), content: Text('Remove ${user.displayName} from the Firestore users collection? This does not delete the Firebase Auth account.'), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))]));
    if (confirmed == true) await service.deleteProfile(user.id);
  }

  Future<void> _showEditor(BuildContext context, UserManagementService service, UserProfile user, {required bool canManageSuperAdmin}) async {
    var role = user.role;
    var isActive = user.isActive;
    String? selectedPharmacyId = user.pharmacyId ?? TenantContext.instance.pharmacyId;
    final name = TextEditingController(text: user.displayName);
    final email = TextEditingController(text: user.email);
    final phone = TextEditingController(text: user.phone ?? '');
    final employeeCode = TextEditingController(text: user.employeeCode);
    final visiblePermissions = canManageSuperAdmin
        ? AppPermissions.all.toList()
        : AppPermissions.all.where((permission) => !AppPermissions.superAdminOnlyPermissions.contains(permission)).toList();
    final permissions = <String, bool>{for (final permission in visiblePermissions) permission: user.can(permission)};
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => Dialog(
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
                    const Icon(Icons.manage_accounts_outlined, color: Color(0xffbe185d)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Manage ${user.displayName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                          const SizedBox(height: 10),
                          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                          const SizedBox(height: 10),
                          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                          const SizedBox(height: 10),
                          TextField(controller: employeeCode, decoration: const InputDecoration(labelText: 'Staff code')),
                          if (canManageSuperAdmin) ...[
                            const SizedBox(height: 10),
                            StreamBuilder<List<PharmacyRecord>>(
                              stream: PharmacyService().watchPharmacies(),
                              builder: (context, snapshot) {
                                final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
                                return DropdownButtonFormField<String>(
                                  initialValue: pharmacies.any((pharmacy) => pharmacy.id == selectedPharmacyId) ? selectedPharmacyId : null,
                                  decoration: const InputDecoration(labelText: 'Pharmacy'),
                                  items: [
                                    for (final pharmacy in pharmacies)
                                      DropdownMenuItem(value: pharmacy.id, child: Text(pharmacy.name)),
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
                                initialValue: role,
                                decoration: const InputDecoration(labelText: 'Role'),
                                items: [
                                  if (canManageSuperAdmin || user.role == 'super_admin') const DropdownMenuItem(value: 'super_admin', child: Text('Super admin')),
                                  if (canManageSuperAdmin || user.role == 'admin') const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                  const DropdownMenuItem(value: 'pharmacist', child: Text('Pharmacist')),
                                  const DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                                  const DropdownMenuItem(value: 'storekeeper', child: Text('Storekeeper')),
                                ],
                                onChanged: user.role == 'admin' || user.role == 'super_admin'
                                    ? null
                                    : (value) => setState(() => role = value ?? role),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Account active'),
                                value: isActive,
                                onChanged: (value) => setState(() => isActive = value),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          const Text('Permissions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xff0f766e))),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            children: [
                              for (final permission in visiblePermissions)
                                SizedBox(
                                  width: 270,
                                  child: CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(permission, style: const TextStyle(fontSize: 12)),
                                    value: permissions[permission] == true,
                                    onChanged: (value) => setState(() => permissions[permission] = value ?? false),
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
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
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
                              role: role,
                              permissions: permissions,
                              isActive: isActive,
                              pharmacyId: selectedPharmacyId,
                            );
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          } catch (error) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save user'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )),
      );
    } finally {
      name.dispose();
      email.dispose();
      phone.dispose();
      employeeCode.dispose();
    }
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime? _from;
  DateTime? _to;
  late Future<DetailedReport> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = ReportService().loadDetailedReport(from: _from, to: _to);
  }

  void _reload() {
    setState(() {
      _reportFuture = ReportService().loadDetailedReport(from: _from, to: _to);
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
    );

    if (picked == null || !mounted) return;
    _from = picked.start;
    _to = picked.end;
    _reload();
  }

  String _rangeLabel() {
    if (_from == null || _to == null) {
      return 'This month';
    }
    final start = '${_from!.day}/${_from!.month}/${_from!.year}';
    final end = '${_to!.day}/${_to!.month}/${_to!.year}';
    return '$start - $end';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DetailedReport>(
      future: _reportFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load reports: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final report = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 36),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const SizedBox(
                  width: 420,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Reports & insights', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                    SizedBox(height: 6),
                    Text('Real pharmacy sales, purchases, and medicine performance.', style: TextStyle(color: Color(0xff68807d))),
                  ]),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _from = null;
                    _to = null;
                    _reload();
                  },
                  icon: const Icon(Icons.calendar_today_rounded),
                  label: const Text('This month'),
                ),
                FilledButton.icon(
                  onPressed: _pickCustomRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(_rangeLabel()),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(spacing: 14, runSpacing: 14, children: [
              _ReportCard(label: 'Sales revenue', value: 'TZS ${report.salesTotalMinor}', note: '${report.salesCount} completed sales', icon: Icons.trending_up_rounded, color: const Color(0xffdff7ee)),
              _ReportCard(label: 'Purchases', value: 'TZS ${report.purchasesTotalMinor}', note: '${report.purchasesCount} purchase records', icon: Icons.shopping_cart_outlined, color: const Color(0xffffeadf)),
              _ReportCard(label: 'Gross profit', value: 'TZS ${report.grossProfitMinor}', note: 'Net margin after stock cost', icon: Icons.paid_rounded, color: const Color(0xffe2efff)),
              _ReportCard(label: 'Stock units', value: '${report.stockUnits}', note: '${report.lowStockCount} products need attention', icon: Icons.inventory_2_outlined, color: const Color(0xfffff0d7)),
            ]),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [Icon(Icons.bar_chart_rounded, color: Color(0xff0f766e)), SizedBox(width: 8), Text('Medicine performance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b)))]),
                    const SizedBox(height: 14),
                    if (report.medicinePerformance.isEmpty)
                      const Text('No medicine activity in this selected range.', style: TextStyle(color: Color(0xff68807d)))
                    else
                      SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          columnSpacing: 18,
                          headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
                          dataTextStyle: const TextStyle(color: Color(0xff506764)),
                          columns: const [
                            DataColumn(label: Text('Medicine')),
                            DataColumn(label: Text('Units')),
                            DataColumn(label: Text('Revenue')),
                            DataColumn(label: Text('Cost')),
                            DataColumn(label: Text('Profit')),
                          ],
                          rows: report.medicinePerformance.take(12).map((row) => DataRow(cells: [
                            DataCell(Text(row.medicineName)),
                            DataCell(Text('${row.unitsSold}')),
                            DataCell(Text('TZS ${row.revenueMinor}')),
                            DataCell(Text('TZS ${row.costMinor}')),
                            DataCell(Text('TZS ${row.grossProfitMinor}')),
                          ])).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(child: Padding(padding: const EdgeInsets.all(22), child: Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xfff2e7ff), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.insights_rounded, color: Color(0xff7c3aed))), const SizedBox(width: 14), Expanded(child: Text('Report range: ${_rangeLabel()} • Sales and purchases are read from Firestore and matched to medicine item records for the selected period.', style: TextStyle(color: Color(0xff506764), height: 1.45))),]))),
          ]),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.label, required this.value, required this.note, required this.icon, required this.color});
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffedf2f2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0f0f766e),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: const Color(0xff285957), size: 20),
            ),
            const SizedBox(height: 15),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
            const SizedBox(height: 5),
            Text(note, style: const TextStyle(fontSize: 11, color: Color(0xff879895))),
          ],
        ),
      ),
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
      final rawBytes = file.bytes;
      final content = rawBytes != null
          ? String.fromCharCodes(rawBytes)
          : await File(file.path!).readAsString();

      if (!mounted) return;
      _controller.text = content;
      setState(() {
        _selectedFileName = selectedName;
        _result = MedicineImportService.validateCsv(content);
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

    try {
      await MedicineService().importMedicines(validRows.map((row) => {
        'sku': row.sku,
        'medicine_name': row.medicineName,
        'category': row.category,
        'strength': row.strength,
        'form': row.form,
        'unit': row.unit,
        'pack_size': row.packSize,
        'supplier_name': row.supplierName,
        'buying_price_minor': row.buyingPriceMinor.toString(),
        'selling_price_minor': row.sellingPriceMinor.toString(),
        'reorder_level': row.reorderLevel.toString(),
        'quantity_on_hand': row.quantityOnHand.toString(),
        'expiry_date': row.expiryDate,
        'batch_number': row.batchNumber,
      }).toList());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${validRows.length} valid medicine rows.')),
      );
      setState(() {
        _controller.clear();
        _result = null;
      });
    } catch (error) {
      if (!mounted) return;
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
            const Text('Download the Excel template, upload the file, and import only valid rows.', style: TextStyle(color: Color(0xff68807d))),
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
                        onPressed: _downloadTemplate,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download template'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickCsvFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload Excel file'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _validateInput,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Validate rows'),
                      ),
                      FilledButton.icon(
                        onPressed: (validRows.isEmpty) ? null : _importValidatedRows,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Import rows'),
                      ),
                      TextButton.icon(
                        onPressed: _cancelImport,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xfff3f8f7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _selectedFileName == null ? 'No file selected yet.' : 'Selected file: $_selectedFileName',
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
                  title: const Text('Auto-print receipt after sale'),
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

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final service = MedicineService();
    return Padding(
      padding: const EdgeInsets.all(28),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Categories', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xff183b3b))),
                        const SizedBox(height: 6),
                        const Text('Group medicines by type to keep your catalogue organized.', style: TextStyle(color: Color(0xff68807d))),
                      ],
                    ),
                  ),
                  if (profile.can('medicines.update'))
                    FilledButton.icon(
                      onPressed: () => _showAddCategoryDialog(context, service),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add category'),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.category_rounded,
                      label: 'Total categories',
                      value: '${categories.length}',
                      color: const Color(0xffdff7ee),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _InfoChip(
                      icon: Icons.inventory_2_outlined,
                      label: 'Active inventory groups',
                      value: categories.isEmpty ? '0' : '${categories.length}',
                      color: const Color(0xffe2efff),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
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
                                const Text('No categories yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xff183b3b))),
                                const SizedBox(height: 8),
                                const Text('Add your first category to start organizing medicines.', style: TextStyle(color: Color(0xff68807d))),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          itemCount: categories.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                              subtitle: Text('ID: ${category.id}', style: const TextStyle(color: Color(0xff68807d))),
                              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xff68807d)),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddCategoryDialog(BuildContext context, MedicineService service) async {
    final controller = TextEditingController();
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.category_rounded, color: Color(0xff0f766e)),
            SizedBox(width: 10),
            Text('Add category'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'Example: Antibiotics',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Category name is required.')));
                return;
              }
              await service.createCategory(name);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe4ebeb)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xff183b3b)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardDestination {
  const _DashboardDestination(this.label, this.icon);

  final String label;
  final IconData icon;

  NavigationRailDestination get navigationDestination => NavigationRailDestination(
        icon: Icon(icon),
        label: Text(label),
      );
}

class MedicinesScreen extends StatelessWidget {
  const MedicinesScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final service = MedicineService();
    return StreamBuilder<List<Medicine>>(
      stream: service.watchMedicines(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load medicines: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final medicines = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Medicines', style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  if (profile.can('medicines.create'))
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const MedicineImportScreen()),
                          ),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Import CSV'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _showAddMedicineDialog(context, service),
                          icon: const Icon(Icons.add),
                          label: const Text('Add medicine'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: medicines.isEmpty
                    ? const Center(child: Text('No medicines yet. Add the first medicine.'))
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListView.separated(
                          itemCount: medicines.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final medicine = medicines[index];
                            final lowStock = medicine.quantityOnHand <= medicine.reorderLevel;
                            return ListTile(
                              title: Text(medicine.name),
                              subtitle: Text('${medicine.sku}  •  ${medicine.unit}  •  ${medicine.quantityOnHand} in stock'),
                              trailing: Chip(
                                label: Text(lowStock ? 'Reorder' : 'In stock'),
                                backgroundColor: lowStock ? Colors.orange.shade100 : Colors.green.shade100,
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
  }

  Future<void> _showAddMedicineDialog(BuildContext context, MedicineService service) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final sku = TextEditingController();
    final unit = TextEditingController(text: 'box');
    final purchasePrice = TextEditingController();
    final sellingPrice = TextEditingController();
    final reorderLevel = TextEditingController(text: '10');
    String? selectedCategoryId;
    var prescription = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
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
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Add medicine', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff183b3b))), SizedBox(height: 3), Text('Create a product record for your pharmacy catalogue', style: TextStyle(fontSize: 12, color: Color(0xff68807d)))])),
                        IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                      ]),
                      const SizedBox(height: 26),
                      const _FormSectionLabel('Medicine details'),
                      const SizedBox(height: 10),
                      _requiredField(name, 'Medicine name', icon: Icons.medication_outlined),
                      const SizedBox(height: 10),
                      Row(children: [Expanded(child: _requiredField(sku, 'SKU / code', icon: Icons.qr_code_2_rounded)), const SizedBox(width: 12), Expanded(child: _requiredField(unit, 'Unit', icon: Icons.inventory_2_outlined))]),
                      const SizedBox(height: 22),
                      const _FormSectionLabel('Classification'),
                      const SizedBox(height: 10),
                      StreamBuilder<List<CategoryOption>>(
                        stream: service.watchCategories(),
                        builder: (context, snapshot) {
                          final categories = snapshot.data ?? const <CategoryOption>[];
                          Widget content;
                          if (snapshot.hasError) {
                            content = Text('Could not load categories: ${snapshot.error}', style: const TextStyle(color: Colors.red));
                          } else if (snapshot.connectionState == ConnectionState.waiting && categories.isEmpty) {
                            content = const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)));
                          } else if (categories.isEmpty) {
                            content = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('No categories yet. Create one before saving a medicine.', style: TextStyle(color: Color(0xff68807d))),
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
                                    label: const Text('Add category'),
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
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                prefixIcon: Icon(Icons.category_outlined),
                              ),
                              validator: (value) => value == null || value.isEmpty ? 'Select a category' : null,
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
                                    label: const Text('New category'),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      const _FormSectionLabel('Pricing & stock'),
                      const SizedBox(height: 10),
                      Row(children: [Expanded(child: _numberField(purchasePrice, 'Purchase price (TZS)', icon: Icons.payments_outlined)), const SizedBox(width: 12), Expanded(child: _numberField(sellingPrice, 'Selling price (TZS)', icon: Icons.sell_outlined))]),
                      const SizedBox(height: 10),
                      _numberField(reorderLevel, 'Alert me when stock reaches', icon: Icons.warning_amber_rounded),
                      const SizedBox(height: 5),
                      CheckboxListTile(contentPadding: EdgeInsets.zero, value: prescription, onChanged: (value) => setDialogState(() => prescription = value ?? false), title: const Text('Requires prescription'), subtitle: const Text('Flag this medicine for controlled dispensing'), controlAffinity: ListTileControlAffinity.leading),
                      const SizedBox(height: 15),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), const SizedBox(width: 10), FilledButton.icon(onPressed: () async { if (!formKey.currentState!.validate()) return; if (selectedCategoryId == null || selectedCategoryId!.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a category before saving.'))); return; } await service.createMedicine(name: name.text, sku: sku.text, categoryId: selectedCategoryId!, unit: unit.text, purchasePriceMinor: int.parse(purchasePrice.text), sellingPriceMinor: int.parse(sellingPrice.text), reorderLevel: int.parse(reorderLevel.text), requiresPrescription: prescription); if (dialogContext.mounted) Navigator.pop(dialogContext); }, icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Save medicine'))]),
                    ],
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
  }

  Future<bool> _showAddCategoryDialog(BuildContext context, MedicineService service) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Category name is required.')));
                return;
              }
              await service.createCategory(name);
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
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
                    subtitle: Text('Expires ${expiry.day}/${expiry.month}/${expiry.year}'),
                    trailing: Text('${batch.quantityOnHand} units'),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          if (profile.can('inventory.adjust'))
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
                _numberField(quantity, 'Quantity'),
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

  Widget _requiredField(TextEditingController controller, String label, {IconData? icon}) => TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 19)),
        validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
      );

  Widget _numberField(TextEditingController controller, String label, {IconData? icon}) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 19)),
        validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a whole number' : null,
      );
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Color(0xff0f766e)));
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
                    message ?? 'This account cannot open Phyimacy.',
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
  const SubscriptionGateScreen({required this.subscription, this.onActivated, super.key});

  final SubscriptionState subscription;
  final VoidCallback? onActivated;

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
        setState(() => _message = 'Invalid or used activation code.');
        return;
      }
      setState(() => _message = 'Plan activated successfully. Opening pharmacy...');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      widget.onActivated?.call();
    } catch (error) {
      setState(() => _message = 'Activation failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f7f8),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xffdff7ee),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              widget.subscription.isTrial ? 'Trial ended · subscribe to continue' : 'Subscription required',
                              style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.subscription.isTrial ? 'Your free trial has ended.' : 'Access to Phyimacy is currently locked.',
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
                          ),
                          const SizedBox(height: 10),
                          Text(widget.subscription.message, style: const TextStyle(color: Color(0xff68807d), fontSize: 16)),
                          const SizedBox(height: 18),
                          Text(
                            widget.subscription.trialCountdownLabel.isNotEmpty
                                ? widget.subscription.trialCountdownLabel
                                : '${widget.subscription.daysRemaining} days remaining',
                            style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                          if (widget.subscription.licenseEndsAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Trial / plan ended: ${widget.subscription.licenseEndsAt!.day}/${widget.subscription.licenseEndsAt!.month}/${widget.subscription.licenseEndsAt!.year}',
                              style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.w700),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _PlanOptionCard(
                            title: 'Monthly',
                            price: 'TZS 120,000',
                            detail: 'Best for small pharmacies',
                            badge: 'Popular',
                          ),
                          const SizedBox(height: 12),
                          _PlanOptionCard(
                            title: '6 Months',
                            price: 'TZS 600,000',
                            detail: 'Lower effective monthly cost',
                            badge: 'Value',
                          ),
                          const SizedBox(height: 12),
                          _PlanOptionCard(
                            title: 'Yearly',
                            price: 'TZS 1,100,000',
                            detail: 'Maximum savings and full access',
                            badge: 'Best value',
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => AuthService().signOut(),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xfff7faf9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xffdfe7e7)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Activate your access', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                            const SizedBox(height: 12),
                            const Text('Use your activation code after payment. This is checked on Firebase and blocks app access until valid.', style: TextStyle(color: Color(0xff68807d), height: 1.5)),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _codeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'Enter activation code',
                                prefixIcon: Icon(Icons.vpn_key_rounded),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _loading ? null : _activateCode,
                              child: Text(_loading ? 'Activating...' : 'Activate plan'),
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
                            const Text('Payment flow', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                            const SizedBox(height: 10),
                            const Text('1. Customer pays monthly / 6 months / yearly.\n2. Admin or support sends activation code.\n3. Code is stored in Firebase and validated before app access is unlocked.', style: TextStyle(color: Color(0xff68807d), height: 1.7)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
      child: Row(
        children: [
          Expanded(
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
          const SizedBox(width: 14),
          Text(price, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        ],
      ),
    );
  }
}
