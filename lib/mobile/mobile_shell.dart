import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/expiry_priority.dart';
import '../backend/firestore_collections.dart';
import '../backend/models.dart';
import '../backend/announcement_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/receipt_service.dart';
import '../backend/report_service.dart';
import '../backend/shop_alerts.dart';
import '../backend/subscription_service.dart';
import '../backend/tenant_context.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';
import '../widgets/language_toggle.dart';

/// Phone companion. The selling counter and printer stay on the shop computer.
class MobileShell extends StatefulWidget {
  const MobileShell({
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
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;
  final List<GlobalKey> _sectionKeys = List<GlobalKey>.generate(7, (_) => GlobalKey());
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _salesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _medicineSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _sales;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _medicines;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _batches;
  Object? _shopError;
  var _shopReady = false;

  bool get _isShop => !widget.profile.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    if (_isShop) _listenToShop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = widget.license?.renewalNotice;
      if (!mounted || notice == null) return;
      showAppNotice(context, notice, kind: AppNoticeKind.warning);
    });
  }

  void _listenToShop() {
    final pharmacyId = (TenantContext.instance.pharmacyId ?? '').trim();
    if (pharmacyId.isEmpty) {
      _shopReady = true;
      _shopError = StateError('no-shop');
      return;
    }
    final firestore = FirebaseFirestore.instance;
    final tenant = TenantContext.instance;
    _salesSub = tenant.scoped(firestore.collection(FirestoreCollections.sales)).snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _sales = snapshot.docs;
          _shopError = null;
          _markReady();
        });
      },
      onError: _fail,
    );
    _medicineSub = tenant.scoped(firestore.collection(FirestoreCollections.medicines)).snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _medicines = snapshot.docs;
          _shopError = null;
          _markReady();
        });
      },
      onError: _fail,
    );
    _batchSub = tenant.scoped(firestore.collection(FirestoreCollections.medicineBatches)).snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _batches = snapshot.docs;
          _shopError = null;
          _markReady();
        });
      },
      onError: _fail,
    );
  }

  void _markReady() {
    _shopReady = _sales != null && _medicines != null && _batches != null;
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _shopError = error;
      _shopReady = true;
    });
  }

  @override
  void dispose() {
    _salesSub?.cancel();
    _medicineSub?.cancel();
    _batchSub?.cancel();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sectionKeys[index].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(target, alignment: 0.5, duration: const Duration(milliseconds: 220));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final alertCount = _shopReady && _shopError == null && _sales != null && _medicines != null && _batches != null
            ? _ShopPicture.fromDocs(sales: _sales!, medicines: _medicines!, batches: _batches!).alertCount
            : 0;
        final pages = widget.profile.isSuperAdmin ? _adminPages() : _shopPages();
        final index = _index.clamp(0, pages.length - 1);
        final page = pages[index];
        return Scaffold(
          backgroundColor: PhyimacyBrand.cream,
          body: Column(
            children: [
              _PhoneHeader(
                title: page.title,
                subtitle: widget.profile.isSuperAdmin
                    ? S.t('All shops', 'Maduka yote')
                    : (TenantContext.instance.pharmacyName ?? S.t('Your shop', 'Duka lako')),
              ),
              if (widget.license?.renewalNotice != null && !widget.readOnly)
                _LicenseEndingBanner(message: widget.license!.renewalNotice!),
              if (widget.readOnly) const _ReadOnlyBanner(),
              Expanded(child: page.child),
            ],
          ),
          bottomNavigationBar: _SectionBar(
            pages: pages,
            index: index,
            alertIndex: 4,
            alertCount: widget.profile.isSuperAdmin ? 0 : alertCount,
            sectionKeys: _sectionKeys,
            onSelect: _select,
          ),
        );
      },
    );
  }

  List<_PhonePage> _shopPages() {
    final showMoney = widget.profile.canSeeSalesTotals;
    return [
      _PhonePage(S.t('Dashboard', 'Dashibodi'), Icons.dashboard_rounded, _shopBody((shop) => _TodayView(shop: shop, showMoney: showMoney, onOpenAlerts: () => _select(4)))),
      _PhonePage(S.t('Sales', 'Mauzo'), Icons.payments_outlined, _shopBody((shop) => _SalesSummaryView(receipts: shop.receipts, showMoney: showMoney))),
      _PhonePage(S.t('Stock', 'Stoku'), Icons.inventory_2_outlined, _shopBody((shop) => _StockView(low: shop.lowItems, expiring: shop.expiryItems))),
      _PhonePage(S.t('Reports', 'Ripoti'), Icons.bar_chart_rounded, _ReportsView(showMoney: showMoney)),
      _PhonePage(S.t('Alerts', 'Arifa'), Icons.notifications_outlined, _shopBody((shop) => _NotificationsView(shop: shop))),
      _PhonePage(S.t('Subscription', 'Usajili'), Icons.workspace_premium_outlined, _SubscriptionView(shell: widget)),
      _PhonePage(S.t('Profile', 'Wasifu'), Icons.person_rounded, _AccountPage(shell: widget)),
    ];
  }

  List<_PhonePage> _adminPages() {
    return [
      _PhonePage(S.t('Dashboard', 'Dashibodi'), Icons.dashboard_rounded, const _AdminDashboard()),
      _PhonePage(S.t('Sales', 'Mauzo'), Icons.payments_outlined, const _ShopDeskNote(icon: Icons.point_of_sale_rounded)),
      _PhonePage(S.t('Stock', 'Stoku'), Icons.inventory_2_outlined, const _ShopDeskNote(icon: Icons.inventory_2_outlined)),
      _PhonePage(S.t('Reports', 'Ripoti'), Icons.bar_chart_rounded, const _AdminDashboard(compact: true)),
      _PhonePage(S.t('Alerts', 'Arifa'), Icons.notifications_outlined, const _AnnouncementsOnly()),
      _PhonePage(S.t('Subscription', 'Usajili'), Icons.workspace_premium_outlined, const _ShopsPage()),
      _PhonePage(S.t('Profile', 'Wasifu'), Icons.person_rounded, _AccountPage(shell: widget)),
    ];
  }

  Widget _shopBody(Widget Function(_ShopPicture shop) builder) {
    if (_shopError != null) {
      final missing = '$_shopError'.contains('no-shop');
      return _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: missing
            ? S.t('No shop on this account', 'Akaunti haina duka')
            : S.t('Could not open the shop', 'Imeshindikana kufungua duka'),
        body: missing
            ? S.t('Ask your administrator to assign this login to a shop.', 'Muombe msimamizi akuunganishe na duka.')
            : S.t('Check the phone internet, then open the app again.', 'Angalia intaneti ya simu, kisha fungua programu tena.'),
      );
    }
    if (!_shopReady || _sales == null || _medicines == null || _batches == null) {
      return const Center(child: CircularProgressIndicator(color: PhyimacyBrand.teal));
    }
    return builder(_ShopPicture.fromDocs(sales: _sales!, medicines: _medicines!, batches: _batches!));
  }
}

class _PhonePage {
  const _PhonePage(this.title, this.icon, this.child);
  final String title;
  final IconData icon;
  final Widget child;
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PhyimacyBrand.forest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Image.asset(PhyimacyBrand.logoAsset, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: PhyimacyBrand.gold, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseEndingBanner extends StatelessWidget {
  const _LicenseEndingBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFF4D6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_busy_rounded, size: 18, color: Color(0xFF8A5A00)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: const Color(0xFF8A5A00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFF4D6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF8A5A00)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                S.t('License ended. You can look, not change records.', 'Leseni imeisha. Unaweza kuona, si kubadili kumbukumbu.'),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF8A5A00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayView extends StatelessWidget {
  const _TodayView({required this.shop, required this.showMoney, required this.onOpenAlerts});

  final _ShopPicture shop;
  final bool showMoney;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (shop.alertCount > 0) ...[
          _WhiteCard(
            child: InkWell(
              onTap: onOpenAlerts,
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: Color(0xFFC2410C)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.t('${shop.alertCount} alerts', 'Arifa ${shop.alertCount}'), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                        Text(S.t('Low stock and medicines nearing expiry', 'Stoku ndogo na dawa zinazoisha muda'), style: _cardHint()),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: PhyimacyBrand.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            _StatCard(
              label: S.t("Today's sales", 'Mauzo ya leo'),
              value: showMoney ? ReceiptSummary.tzs(shop.todayMinor) : '${shop.todayCount}',
              hint: showMoney
                  ? S.t('${shop.todayCount} receipts', 'Risiti ${shop.todayCount}')
                  : S.t('Receipts today', 'Risiti za leo'),
              icon: Icons.payments_outlined,
            ),
            _StatCard(
              label: S.t('Receipts', 'Risiti'),
              value: '${shop.todayCount}',
              hint: S.t('From the shop computer', 'Kutoka kompyuta ya duka'),
              icon: Icons.receipt_long_outlined,
            ),
            _StatCard(
              label: S.t('Low stock', 'Stoku ndogo'),
              value: '${shop.lowItems.length}',
              hint: S.t('Below the reorder line', 'Chini ya kiwango'),
              icon: Icons.inventory_2_outlined,
            ),
            _StatCard(
              label: S.t('Expiring', 'Zinazoisha muda'),
              value: '${shop.expiryItems.length}',
              hint: S.t('Expired or due soon', 'Zimeisha au zinakaribia'),
              icon: Icons.event_busy_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('This week', 'Wiki hii'), style: _cardTitle()),
              const SizedBox(height: 4),
              Text(
                showMoney
                    ? S.t('Sales recorded on the shop computer', 'Mauzo yaliyoandikwa kwenye kompyuta ya duka')
                    : S.t('Receipts recorded on the shop computer', 'Risiti zilizoandikwa kwenye kompyuta ya duka'),
                style: _cardHint(),
              ),
              const SizedBox(height: 18),
              _WeekChart(days: shop.week, showMoney: showMoney),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesView extends StatelessWidget {
  const _SalesView({required this.receipts, required this.showMoney, this.embedded = false});

  final List<_PhoneReceipt> receipts;
  final bool showMoney;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) {
      if (embedded) {
        return _WhiteCard(
          child: Text(
            S.t('No receipts in this period.', 'Hakuna risiti katika kipindi hiki.'),
            style: _cardHint(),
          ),
        );
      }
      return _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: S.t('No receipts yet', 'Bado hakuna risiti'),
        body: S.t(
          'Receipts made on the shop computer appear here.',
          'Risiti zinazotoka kwenye kompyuta ya duka zitaonekana hapa.',
        ),
      );
    }
    final cards = [
      for (var index = 0; index < receipts.length; index++) ...[
        if (index > 0) const SizedBox(height: 10),
        _receiptCard(receipts[index], showMoney),
      ],
    ];
    if (embedded) return Column(children: cards);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: cards,
    );
  }
}

Widget _receiptCard(_PhoneReceipt receipt, bool showMoney) {
  return _WhiteCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: PhyimacyBrand.cream,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.receipt_rounded, color: PhyimacyBrand.teal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(receipt.number, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
              const SizedBox(height: 2),
              Text(_when(receipt.at), style: _cardHint()),
              if (receipt.items.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  receipt.items.take(3).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.35, color: PhyimacyBrand.ink),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _paymentLabel(receipt.payment),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: PhyimacyBrand.teal),
              ),
            ],
          ),
        ),
        if (showMoney)
          Text(
            ReceiptSummary.tzs(receipt.totalMinor),
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest),
          ),
      ],
    ),
  );
}

class _StockView extends StatelessWidget {
  const _StockView({required this.low, required this.expiring});

  final List<_LowMedicine> low;
  final List<_ExpiryLine> expiring;

  @override
  Widget build(BuildContext context) {
    if (low.isEmpty && expiring.isEmpty) {
      return _EmptyState(
        icon: Icons.verified_outlined,
        title: S.t('Stock looks fine', 'Stoku iko sawa'),
        body: S.t('No low medicines and nothing is close to expiry.', 'Hakuna dawa chini ya kiwango, wala zinazokaribia kuisha muda.'),
      );
    }
    final expiredCount = expiring.where((item) => item.expired).length;
    final soonCount = expiring.length - expiredCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(label: S.t('Low', 'Chini'), value: '${low.length}'),
            _CountChip(label: S.t('Expiring', 'Zinaisha'), value: '$soonCount'),
            _CountChip(label: S.t('Expired', 'Zimeisha'), value: '$expiredCount'),
          ],
        ),
        const SizedBox(height: 14),
        Text(S.t('Low stock', 'Zilizo chini'), style: _sectionTitle()),
        const SizedBox(height: 8),
        if (low.isEmpty)
          _WhiteCard(child: Text(S.t('None right now.', 'Hakuna kwa sasa.'), style: _cardHint()))
        else
          for (final item in low) ...[
            _WhiteCard(
              child: Row(
                children: [
                  const Icon(Icons.medication_outlined, color: PhyimacyBrand.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                        const SizedBox(height: 2),
                        Text(
                          S.t('${item.stock} left · reorder ${item.reorder}', 'Zimebaki ${item.stock} · kiwango ${item.reorder}'),
                          style: _cardHint(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 10),
        Text(S.t('Nearing expiry', 'Zinazokaribia kuisha muda'), style: _sectionTitle()),
        const SizedBox(height: 8),
        if (expiring.isEmpty)
          _WhiteCard(child: Text(S.t('None in the next 60 days.', 'Hakuna katika siku 60 zijazo.'), style: _cardHint()))
        else
          for (final item in expiring) ...[
            _WhiteCard(
              child: Row(
                children: [
                  Icon(
                    item.expired ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                    color: item.expired ? const Color(0xFFC2410C) : const Color(0xFF8A5A00),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                        const SizedBox(height: 2),
                        Text(item.detail, style: _cardHint()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _AccountPage extends StatelessWidget {
  const _AccountPage({required this.shell});

  final MobileShell shell;

  @override
  Widget build(BuildContext context) {
    final profile = shell.profile;
    final shop = (TenantContext.instance.pharmacyName ?? '').trim();
    final initial = profile.displayName.trim().isEmpty ? 'P' : profile.displayName.trim()[0].toUpperCase();
    final days = shell.license?.daysRemaining;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _WhiteCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: PhyimacyBrand.forest,
                child: Text(initial, style: GoogleFonts.playfairDisplay(color: PhyimacyBrand.gold, fontSize: 24, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.displayName.trim().isEmpty ? profile.email : profile.displayName, style: _cardTitle()),
                    const SizedBox(height: 2),
                    Text(S.role(profile.role), style: _cardHint()),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          child: Column(
            children: [
              _AccountRow(
                icon: Icons.storefront_outlined,
                label: S.t('Shop', 'Duka'),
                value: profile.isSuperAdmin
                    ? S.t('All shops', 'Maduka yote')
                    : (shop.isEmpty ? S.t('Not assigned', 'Haijaunganishwa') : shop),
              ),
              const Divider(height: 22, color: PhyimacyBrand.line),
              _AccountRow(
                icon: Icons.badge_outlined,
                label: S.t('Name', 'Jina'),
                value: profile.displayName.trim().isEmpty ? '—' : profile.displayName.trim(),
              ),
              if (profile.email.trim().isNotEmpty) ...[
                const Divider(height: 22, color: PhyimacyBrand.line),
                _AccountRow(icon: Icons.mail_outline_rounded, label: S.t('Email', 'Barua pepe'), value: profile.email.trim()),
              ],
              if ((profile.phone ?? '').trim().isNotEmpty) ...[
                const Divider(height: 22, color: PhyimacyBrand.line),
                _AccountRow(icon: Icons.phone_outlined, label: S.t('Phone', 'Simu'), value: profile.phone!.trim()),
              ],
              if (days != null) ...[
                const Divider(height: 22, color: PhyimacyBrand.line),
                _AccountRow(
                  icon: Icons.workspace_premium_outlined,
                  label: S.t('License', 'Leseni'),
                  value: days <= 0
                      ? S.t('Ended', 'Imeisha')
                      : S.t('$days days left', 'Siku $days zimebaki'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('Language', 'Lugha'), style: _cardTitle()),
                    const SizedBox(height: 2),
                    Text(S.t('English or Kiswahili', 'Kiingereza au Kiswahili'), style: _cardHint()),
                  ],
                ),
              ),
              const LanguageToggle(compact: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          child: Text(
            S.t(
              'Selling and printing stay on the shop computer. This phone has the dashboard, sales summary, stock, reports, alerts, subscription, and profile.',
              'Uuzaji na printa hubaki kwenye kompyuta ya duka. Simu ina dashibodi, muhtasari wa mauzo, stoku, ripoti, arifa, usajili, na wasifu.',
            ),
            style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: PhyimacyBrand.muted),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => _signOut(context),
          icon: const Icon(Icons.logout_rounded),
          label: Text(S.t('Sign out', 'Toka')),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Sign out?', 'Utoke?')),
        content: Text(S.t('You will need your email and password to open the shop again.', 'Utahitaji barua pepe na nenosiri kufungua duka tena.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Stay', 'Baki'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Sign out', 'Toka'))),
        ],
      ),
    );
    if (leave == true) await shell.authService.signOut();
  }
}

class _ShopsPage extends StatelessWidget {
  const _ShopsPage();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: PharmacyService().watchPharmacies(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: S.t('Could not load shops', 'Imeshindikana kupakia maduka'),
            body: S.t('Check the phone internet and try again.', 'Angalia intaneti ya simu kisha jaribu tena.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: PhyimacyBrand.teal));
        }
        final shops = snapshot.data!;
        if (shops.isEmpty) {
          return _EmptyState(
            icon: Icons.storefront_outlined,
            title: S.t('No shops yet', 'Bado hakuna maduka'),
            body: S.t('Shops you create on the computer appear here.', 'Maduka unayoyaunda kwenye kompyuta yataonekana hapa.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: shops.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final shop = shops[index];
            final days = SubscriptionService.calendarDaysRemaining(shop.expiresAt ?? shop.trialEndsAt);
            return _WhiteCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shop.name, style: _cardTitle()),
                        const SizedBox(height: 4),
                        Text(
                          shop.isTrial ? S.t('Trial', 'Majaribio') : shop.plan,
                          style: _cardHint(),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$days',
                        style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w700, color: PhyimacyBrand.forest, height: 1),
                      ),
                      Text(
                        S.t('days left', 'siku zimebaki'),
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF8A6A2F), height: 1.2),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({
    required this.pages,
    required this.index,
    required this.alertIndex,
    required this.alertCount,
    required this.sectionKeys,
    required this.onSelect,
  });

  final List<_PhonePage> pages;
  final int index;
  final int alertIndex;
  final int alertCount;
  final List<GlobalKey> sectionKeys;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            itemCount: pages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, itemIndex) {
              final page = pages[itemIndex];
              final selected = itemIndex == index;
              final showBadge = itemIndex == alertIndex && alertCount > 0;
              return InkWell(
                key: sectionKeys[itemIndex],
                onTap: () => onSelect(itemIndex),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 84,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? PhyimacyBrand.forest : PhyimacyBrand.cream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? PhyimacyBrand.forest : PhyimacyBrand.line),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: showBadge,
                        backgroundColor: const Color(0xFFC2410C),
                        label: Text(alertCount > 99 ? '99+' : '$alertCount', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
                        child: Icon(page.icon, size: 18, color: selected ? PhyimacyBrand.gold : PhyimacyBrand.teal),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : PhyimacyBrand.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _SalesRange { today, week, month }

class _SalesSummaryView extends StatefulWidget {
  const _SalesSummaryView({required this.receipts, required this.showMoney});

  final List<_PhoneReceipt> receipts;
  final bool showMoney;

  @override
  State<_SalesSummaryView> createState() => _SalesSummaryViewState();
}

class _SalesSummaryViewState extends State<_SalesSummaryView> {
  _SalesRange _range = _SalesRange.today;

  @override
  Widget build(BuildContext context) {
    final bounds = _rangeBounds(_range);
    final rows = [
      for (final receipt in widget.receipts)
        if (receipt.at != null && !receipt.at!.isBefore(bounds.$1) && receipt.at!.isBefore(bounds.$2)) receipt,
    ];
    final total = rows.fold<int>(0, (running, receipt) => running + receipt.totalMinor);
    final average = rows.isEmpty ? 0 : total ~/ rows.length;
    final byMethod = <String, int>{};
    for (final receipt in rows) {
      final key = receipt.payment.trim().isEmpty ? 'sale' : receipt.payment.trim().toLowerCase();
      byMethod[key] = (byMethod[key] ?? 0) + (widget.showMoney ? receipt.totalMinor : 1);
    }
    final peak = byMethod.values.fold<int>(0, (max, value) => value > max ? value : max);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _RangeChips(
          labels: [
            S.t('Today', 'Leo'),
            S.t('This week', 'Wiki hii'),
            S.t('This month', 'Mwezi huu'),
          ],
          index: _SalesRange.values.indexOf(_range),
          onChanged: (value) => setState(() => _range = _SalesRange.values[value]),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _StatCard(
              label: S.t('Sales', 'Mauzo'),
              value: widget.showMoney ? ReceiptSummary.tzs(total) : '${rows.length}',
              hint: S.t('${rows.length} receipts', 'Risiti ${rows.length}'),
              icon: Icons.payments_outlined,
            ),
            _StatCard(
              label: S.t('Average receipt', 'Wastani wa risiti'),
              value: widget.showMoney ? ReceiptSummary.tzs(average) : '—',
              hint: S.t('From the shop computer', 'Kutoka kompyuta ya duka'),
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WhiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('How customers paid', 'Wateja walilipa vipi'), style: _cardTitle()),
              const SizedBox(height: 10),
              if (byMethod.isEmpty)
                Text(S.t('No payments in this period.', 'Hakuna malipo katika kipindi hiki.'), style: _cardHint())
              else
                for (final entry in byMethod.entries) ...[
                  Row(
                    children: [
                      Expanded(child: Text(_paymentLabel(entry.key), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
                      Text(widget.showMoney ? ReceiptSummary.tzs(entry.value) : '${entry.value}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: peak <= 0 ? 0 : entry.value / peak,
                      backgroundColor: PhyimacyBrand.cream,
                      color: PhyimacyBrand.gold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(S.t('Recent receipts', 'Risiti za hivi karibuni'), style: _sectionTitle()),
        const SizedBox(height: 8),
        _SalesView(receipts: rows.take(20).toList(), showMoney: widget.showMoney, embedded: true),
      ],
    );
  }
}

class _ReportsView extends StatefulWidget {
  const _ReportsView({required this.showMoney});

  final bool showMoney;

  @override
  State<_ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<_ReportsView> {
  var _month = false;
  late Future<DetailedReport> _future = _load();

  Future<DetailedReport> _load() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = _month ? DateTime(now.year, now.month, 1) : today.subtract(const Duration(days: 6));
    return ReportService().loadDetailedReport(from: start, to: today);
  }

  void _setMonth(bool month) {
    setState(() {
      _month = month;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _RangeChips(
          labels: [S.t('This week', 'Wiki hii'), S.t('This month', 'Mwezi huu')],
          index: _month ? 1 : 0,
          onChanged: (value) => _setMonth(value == 1),
        ),
        const SizedBox(height: 12),
        FutureBuilder<DetailedReport>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator(color: PhyimacyBrand.teal)),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.t('Could not load the report', 'Imeshindikana kupakia ripoti'), style: _cardTitle()),
                    const SizedBox(height: 6),
                    Text(S.t('Check the phone internet and try again.', 'Angalia intaneti ya simu kisha jaribu tena.'), style: _cardHint()),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => _setMonth(_month), child: Text(S.t('Try again', 'Jaribu tena'))),
                  ],
                ),
              );
            }
            final report = snapshot.data!;
            final top = report.medicinePerformance.where((row) => row.unitsSold > 0).take(8).toList();
            return Column(
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    _StatCard(
                      label: S.t('Sales revenue', 'Mapato ya mauzo'),
                      value: widget.showMoney ? ReceiptSummary.tzs(report.salesTotalMinor) : '${report.salesCount}',
                      hint: S.t('${report.salesCount} receipts', 'Risiti ${report.salesCount}'),
                      icon: Icons.trending_up_rounded,
                    ),
                    _StatCard(
                      label: S.t('Purchases', 'Manunuzi'),
                      value: widget.showMoney ? ReceiptSummary.tzs(report.purchasesTotalMinor) : '${report.purchasesCount}',
                      hint: S.t('${report.purchasesCount} records', 'Rekodi ${report.purchasesCount}'),
                      icon: Icons.shopping_cart_outlined,
                    ),
                    if (widget.showMoney)
                      _StatCard(
                        label: S.t('Gross profit', 'Faida ghafi'),
                        value: ReceiptSummary.tzs(report.grossProfitMinor),
                        hint: S.t('Sales minus purchases', 'Mauzo ukitoa manunuzi'),
                        icon: Icons.paid_outlined,
                      ),
                    _StatCard(
                      label: S.t('Stock', 'Stoku'),
                      value: '${report.lowStockCount}',
                      hint: S.t('${report.medicineCount} medicines · ${report.stockUnits} units', 'Dawa ${report.medicineCount} · vipimo ${report.stockUnits}'),
                      icon: Icons.inventory_2_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: Text(S.t('Top medicines', 'Dawa zinazoongoza'), style: _sectionTitle())),
                const SizedBox(height: 8),
                if (top.isEmpty)
                  _WhiteCard(child: Text(S.t('No medicines sold in this period.', 'Hakuna dawa ziliuzwa katika kipindi hiki.'), style: _cardHint()))
                else
                  for (final row in top) ...[
                    _WhiteCard(
                      child: Row(
                        children: [
                          const Icon(Icons.medication_outlined, color: PhyimacyBrand.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.medicineName, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                                Text(S.t('${row.unitsSold} sold', 'Zimeuzwa ${row.unitsSold}'), style: _cardHint()),
                              ],
                            ),
                          ),
                          if (widget.showMoney)
                            Text(ReceiptSummary.tzs(row.revenueMinor), style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _NotificationsView extends StatelessWidget {
  const _NotificationsView({required this.shop});

  final _ShopPicture shop;

  @override
  Widget build(BuildContext context) {
    final expired = shop.expiryItems.where((item) => item.expired).toList();
    final soon = shop.expiryItems.where((item) => !item.expired).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const _AnnouncementsBlock(),
        Text(S.t('Stock alerts', 'Arifa za stoku'), style: _sectionTitle()),
        const SizedBox(height: 8),
        if (shop.alertCount == 0)
          _WhiteCard(child: Text(S.t('No stock alerts right now.', 'Hakuna arifa za stoku kwa sasa.'), style: _cardHint()))
        else ...[
          for (final item in expired) _alertCard(item.name, item.detail, Icons.warning_amber_rounded, const Color(0xFFC2410C)),
          for (final item in soon) _alertCard(item.name, item.detail, Icons.schedule_rounded, const Color(0xFF8A5A00)),
          for (final item in shop.lowItems)
            _alertCard(
              item.name,
              S.t('${item.stock} left · reorder ${item.reorder}', 'Zimebaki ${item.stock} · kiwango ${item.reorder}'),
              Icons.inventory_2_outlined,
              PhyimacyBrand.teal,
            ),
        ],
      ],
    );
  }

  Widget _alertCard(String title, String body, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _WhiteCard(
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                  Text(body, style: _cardHint()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementsBlock extends StatelessWidget {
  const _AnnouncementsBlock();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Announcement>>(
      stream: AnnouncementService().watchActive(),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Announcement>[];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('Announcements', 'Matangazo'), style: _sectionTitle()),
            const SizedBox(height: 8),
            for (final row in rows.take(8)) ...[
              _WhiteCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                    if (row.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(row.body, style: _cardHint()),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _AnnouncementsOnly extends StatelessWidget {
  const _AnnouncementsOnly();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const _AnnouncementsBlock(),
        _WhiteCard(
          child: Text(
            S.t(
              'Shop stock alerts appear when you sign in to that shop.',
              'Arifa za stoku zinaonekana ukiingia kwenye duka husika.',
            ),
            style: _cardHint(),
          ),
        ),
      ],
    );
  }
}

class _SubscriptionView extends StatefulWidget {
  const _SubscriptionView({required this.shell});

  final MobileShell shell;

  @override
  State<_SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends State<_SubscriptionView> {
  final _codeController = TextEditingController();
  var _loading = false;
  String? _message;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final ok = await SubscriptionService().activateWithCode(_codeController.text);
      if (!mounted) return;
      setState(() {
        _message = ok
            ? S.t('Plan activated.', 'Mpango umewezeshwa.')
            : S.t('Invalid or used activation code.', 'Namba si sahihi au imeshatumika.');
      });
      if (ok) widget.shell.onLicenseChanged?.call();
    } catch (error) {
      var text = '$error';
      if (text.startsWith('Bad state: ')) text = text.substring(11);
      if (text.startsWith('Exception: ')) text = text.substring(11);
      if (mounted) setState(() => _message = text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final license = widget.shell.license;
    final days = license?.daysRemaining ?? 0;
    final ended = license == null || license.hasExpired || license.isBlocked;
    final canActivate = widget.shell.profile.role == 'admin';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _WhiteCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_planLabel(license?.plan ?? 'trial'), style: _cardHint()),
                    const SizedBox(height: 4),
                    Text(
                      license == null
                          ? S.t('No license', 'Hakuna leseni')
                          : ended
                              ? S.t('Ended', 'Imeisha')
                              : license.isReadOnly
                                  ? S.t('Read only', 'Kusoma tu')
                                  : license.isTrial
                                      ? S.t('Trial', 'Majaribio')
                                      : S.t('Active', 'Inaendelea'),
                      style: _cardTitle(),
                    ),
                    if (license?.licenseEndsAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        S.t('Ends ${ExpiryPriority.format(license!.licenseEndsAt!)}', 'Inaisha ${ExpiryPriority.format(license.licenseEndsAt!)}'),
                        style: _cardHint(),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  Text('$days', style: GoogleFonts.playfairDisplay(fontSize: 36, fontWeight: FontWeight.w700, color: PhyimacyBrand.forest, height: 1)),
                  Text(S.t('days left', 'siku zimebaki'), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF8A6A2F))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _planCard(S.t('Monthly', 'Kila mwezi'), 'TZS 120,000', S.t('Best for small pharmacies', 'Inafaa maduka madogo')),
        _planCard(S.t('6 months', 'Miezi 6'), 'TZS 600,000', S.t('Lower monthly cost', 'Bei ya mwezi inakuwa nafuu')),
        _planCard(S.t('Yearly', 'Mwaka'), 'TZS 1,100,000', S.t('Full year of access', 'Mwaka mzima wa matumizi')),
        if (canActivate) ...[
          const SizedBox(height: 4),
          _WhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('Activation code', 'Namba ya kuwezesha'), style: _cardTitle()),
                const SizedBox(height: 4),
                Text(S.t('Pay, then enter the code from your administrator.', 'Lipa, kisha weka namba kutoka kwa msimamizi.'), style: _cardHint()),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'PHY-XXXX-XXXX-XXXX'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, style: _cardHint()),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loading ? null : _activate,
                  child: Text(_loading ? S.t('Checking...', 'Inaangalia...') : S.t('Activate', 'Wezesha')),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _planCard(String title, String price, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _WhiteCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                  Text(detail, style: _cardHint()),
                ],
              ),
            ),
            Text(price, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest)),
          ],
        ),
      ),
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: PharmacyService().watchPharmacies(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: S.t('Could not load shops', 'Imeshindikana kupakia maduka'),
            body: S.t('Check the phone internet and try again.', 'Angalia intaneti ya simu kisha jaribu tena.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: PhyimacyBrand.teal));
        }
        final shops = snapshot.data!;
        final ending = <PharmacyRecord>[];
        var ended = 0;
        for (final shop in shops) {
          final days = SubscriptionService.calendarDaysRemaining(shop.expiresAt ?? shop.trialEndsAt);
          if (days <= 0) {
            ended += 1;
          } else if (days <= 7) {
            ending.add(shop);
          }
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _StatCard(label: S.t('Shops', 'Maduka'), value: '${shops.length}', hint: S.t('All pharmacies', 'Maduka yote'), icon: Icons.storefront_outlined),
                _StatCard(label: S.t('Ending soon', 'Zinaisha karibu'), value: '${ending.length}', hint: S.t('7 days or less', 'Siku 7 au chini'), icon: Icons.hourglass_bottom_rounded),
                _StatCard(label: S.t('Ended', 'Zimeisha'), value: '$ended', hint: S.t('Need a new license', 'Zinahitaji leseni'), icon: Icons.lock_outline_rounded),
                _StatCard(label: S.t('Active', 'Zinaendelea'), value: '${shops.length - ended}', hint: S.t('Still on a license', 'Bado zina leseni'), icon: Icons.verified_outlined),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 14),
              Text(S.t('Licenses ending this week', 'Leseni zinazoisha wiki hii'), style: _sectionTitle()),
              const SizedBox(height: 8),
              if (ending.isEmpty)
                _WhiteCard(child: Text(S.t('No shop license ends in the next 7 days.', 'Hakuna leseni inayoisha katika siku 7.'), style: _cardHint()))
              else
                for (final shop in ending) ...[
                  _WhiteCard(
                    child: Row(
                      children: [
                        Expanded(child: Text(shop.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
                        Text(
                          S.t(
                            '${SubscriptionService.calendarDaysRemaining(shop.expiresAt ?? shop.trialEndsAt)} days',
                            'Siku ${SubscriptionService.calendarDaysRemaining(shop.expiresAt ?? shop.trialEndsAt)}',
                          ),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ],
        );
      },
    );
  }
}

class _ShopDeskNote extends StatelessWidget {
  const _ShopDeskNote({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: icon,
      title: S.t('Open a shop login', 'Ingia kwa akaunti ya duka'),
      body: S.t(
        'Sales, stock, and reports belong to each shop. This administrator login shows shops, licenses, and alerts.',
        'Mauzo, stoku, na ripoti viko ndani ya kila duka. Akaunti hii ya msimamizi inaonyesha maduka, leseni, na arifa.',
      ),
    );
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < labels.length; i++)
          ChoiceChip(
            label: Text(labels[i]),
            selected: i == index,
            onSelected: (_) => onChanged(i),
            selectedColor: PhyimacyBrand.gold,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest),
            backgroundColor: Colors.white,
            side: const BorderSide(color: PhyimacyBrand.line),
          ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PhyimacyBrand.line),
      ),
      child: Text('$value $label', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: PhyimacyBrand.forest)),
    );
  }
}

(DateTime, DateTime) _rangeBounds(_SalesRange range) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 1));
  return switch (range) {
    _SalesRange.today => (today, end),
    _SalesRange.week => (today.subtract(const Duration(days: 6)), end),
    _SalesRange.month => (DateTime(now.year, now.month, 1), end),
  };
}

String _planLabel(String plan) {
  return switch (plan) {
    'monthly' => S.t('Monthly', 'Kila mwezi'),
    'quarterly' => S.t('3 months', 'Miezi 3'),
    'biannual' => S.t('6 months', 'Miezi 6'),
    'yearly' => S.t('Yearly', 'Mwaka'),
    _ => S.t('Trial', 'Majaribio'),
  };
}

class _ShopPicture {
  const _ShopPicture({
    required this.todayMinor,
    required this.todayCount,
    required this.week,
    required this.receipts,
    required this.lowItems,
    required this.expiryItems,
  });

  final int todayMinor;
  final int todayCount;
  final List<_WeekDay> week;
  final List<_PhoneReceipt> receipts;
  final List<_LowMedicine> lowItems;
  final List<_ExpiryLine> expiryItems;

  int get alertCount => lowItems.length + expiryItems.length;

  factory _ShopPicture.fromDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sales,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> medicines,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> batches,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final medicineModels = medicines.map(Medicine.fromFirestore).where((item) => item.isActive).toList();
    final batchModels = batches.map(MedicineBatch.fromFirestore).toList();
    final alerts = ShopAlerts.fromStock(medicineModels, batchModels);

    final live = sales.where((doc) {
      final status = (doc.data()['status'] as String?) ?? 'completed';
      return status != 'voided' && status != 'refunded';
    }).toList()
      ..sort((a, b) {
        final left = _dateOf(a.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = _dateOf(b.data()['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });

    final todaySales = live.where((doc) {
      final created = _dateOf(doc.data()['createdAt']);
      return created != null && !created.isBefore(todayStart) && created.isBefore(todayStart.add(const Duration(days: 1)));
    });

    final week = <_WeekDay>[];
    for (var offset = 6; offset >= 0; offset--) {
      final start = todayStart.subtract(Duration(days: offset));
      final end = start.add(const Duration(days: 1));
      final daySales = live.where((doc) {
        final created = _dateOf(doc.data()['createdAt']);
        return created != null && !created.isBefore(start) && created.isBefore(end);
      });
      final minor = daySales.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));
      week.add(_WeekDay(day: start, minor: minor, count: daySales.length));
    }

    final low = <_LowMedicine>[
      for (final medicine in medicineModels)
        if (medicine.quantityOnHand <= medicine.reorderLevel)
          _LowMedicine(name: medicine.name, stock: medicine.quantityOnHand, reorder: medicine.reorderLevel),
    ]..sort((a, b) => a.stock.compareTo(b.stock));

    return _ShopPicture(
      todayMinor: todaySales.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0)),
      todayCount: todaySales.length,
      week: week,
      receipts: [
        for (final doc in live)
          _PhoneReceipt(
            number: (doc.data()['receiptNumber'] as String?)?.trim().isNotEmpty == true
                ? doc.data()['receiptNumber'] as String
                : doc.id,
            totalMinor: (doc.data()['totalMinor'] as num?)?.toInt() ?? 0,
            payment: (doc.data()['paymentMethod'] as String?) ?? '',
            at: _dateOf(doc.data()['createdAt']),
            items: [
              for (final name in (doc.data()['itemNames'] as List?) ?? const [])
                if ('$name'.trim().isNotEmpty) '$name'.trim(),
            ],
          ),
      ],
      lowItems: low,
      expiryItems: [
        for (final alert in alerts)
          _ExpiryLine(
            name: alert.title,
            expired: alert.kind == ShopAlertKind.expired,
            detail: _expiryDetail(alert),
          ),
      ],
    );
  }
}

class _WeekDay {
  const _WeekDay({required this.day, required this.minor, required this.count});
  final DateTime day;
  final int minor;
  final int count;
}

class _PhoneReceipt {
  const _PhoneReceipt({
    required this.number,
    required this.totalMinor,
    required this.payment,
    required this.at,
    required this.items,
  });

  final String number;
  final int totalMinor;
  final String payment;
  final DateTime? at;
  final List<String> items;
}

class _LowMedicine {
  const _LowMedicine({required this.name, required this.stock, required this.reorder});
  final String name;
  final int stock;
  final int reorder;
}

class _ExpiryLine {
  const _ExpiryLine({required this.name, required this.expired, required this.detail});
  final String name;
  final bool expired;
  final String detail;
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.showMoney});

  final List<_WeekDay> days;
  final bool showMoney;

  @override
  Widget build(BuildContext context) {
    final peak = days.fold<int>(0, (max, day) => (showMoney ? day.minor : day.count) > max ? (showMoney ? day.minor : day.count) : max);
    final scale = peak <= 0 ? 1 : peak;
    return SizedBox(
      height: 148,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      showMoney ? _compactMoney(day.minor) : '${day.count}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: PhyimacyBrand.muted),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (((showMoney ? day.minor : day.count) / scale).clamp(0.0, 1.0) * 0.92) + 0.08,
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: day.day.day == DateTime.now().day && day.day.month == DateTime.now().month
                                  ? PhyimacyBrand.teal
                                  : PhyimacyBrand.gold,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_weekday(day.day), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.hint, required this.icon});

  final String label;
  final String value;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: PhyimacyBrand.teal, size: 20),
          const Spacer(),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: PhyimacyBrand.forest)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cardHint()),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PhyimacyBrand.line),
        boxShadow: const [BoxShadow(color: Color(0x12073B3A), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: PhyimacyBrand.teal, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: _cardHint())),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value, textAlign: TextAlign.right, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _WhiteCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: PhyimacyBrand.teal),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: _cardTitle()),
              const SizedBox(height: 6),
              Text(body, textAlign: TextAlign.center, style: _cardHint()),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _cardTitle() => GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink);

TextStyle _cardHint() => GoogleFonts.inter(fontSize: 12, height: 1.35, color: PhyimacyBrand.muted);

TextStyle _sectionTitle() => GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: PhyimacyBrand.forest);

DateTime? _dateOf(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String _when(DateTime? value) {
  if (value == null) return S.t('Just now', 'Sasa hivi');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final clock = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  if (day == today) return '${S.t('Today', 'Leo')} $clock';
  if (day == today.subtract(const Duration(days: 1))) return '${S.t('Yesterday', 'Jana')} $clock';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} $clock';
}

String _paymentLabel(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'cash' => S.t('Cash', 'Taslimu'),
    'mobile' || 'mobile_money' || 'mpesa' || 'm-pesa' => S.t('Mobile money', 'Simu'),
    'card' => S.t('Card', 'Kadi'),
    'credit' => S.t('Credit', 'Mkopo'),
    _ => raw.trim().isEmpty ? S.t('Sale', 'Mauzo') : raw.trim(),
  };
}

String _expiryDetail(ShopAlert alert) {
  final days = ExpiryPriority.daysLeft(alert.expiry);
  final when = alert.kind == ShopAlertKind.expired
      ? S.t('Expired', 'Imeisha muda')
      : days <= 0
          ? S.t('Expires today', 'Inaisha leo')
          : S.t('In $days days', 'Siku $days');
  return '$when · ${alert.quantity} · ${ExpiryPriority.format(alert.expiry)}';
}

String _weekday(DateTime day) {
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const sw = ['Jum', 'Jnn', 'Jtn', 'Alh', 'Ijm', 'Jms', 'Jpi'];
  return S.t(en[day.weekday - 1], sw[day.weekday - 1]);
}

String _compactMoney(int minor) {
  if (minor >= 1000000) return '${(minor / 1000000).toStringAsFixed(1)}M';
  if (minor >= 1000) return '${(minor / 1000).toStringAsFixed(minor >= 10000 ? 0 : 1)}k';
  return '$minor';
}
