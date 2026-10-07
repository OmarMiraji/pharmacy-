import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/audit_log_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/transactional_email_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class SubscriptionAdminScreen extends StatefulWidget {
  const SubscriptionAdminScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<SubscriptionAdminScreen> createState() => _SubscriptionAdminScreenState();
}

class _SubscriptionAdminScreenState extends State<SubscriptionAdminScreen> {
  final _service = SubscriptionService();
  final _pharmacies = PharmacyService();
  final _tokenEmailController = TextEditingController();
  final _noteController = TextEditingController();
  final _paymentRefController = TextEditingController();
  final _customDaysController = TextEditingController(text: '30');

  String _plan = 'monthly';
  int _durationDays = 30;
  DateTime _startsAt = DateTime.now();
  bool _creating = false;
  String? _lastToken;
  String? _selectedPharmacyId;
  String? _lastEmailNote;
  bool _emailToken = true;
  final _searchController = TextEditingController();
  String _shopFilter = 'all';
  String _tokenFilter = 'all';

  @override
  void dispose() {
    _tokenEmailController.dispose();
    _noteController.dispose();
    _paymentRefController.dispose();
    _customDaysController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  int get _days => _plan == 'custom' ? (int.tryParse(_customDaysController.text.trim()) ?? 30) : _durationDays;

  Future<void> _generateToken() async {
    final sendTo = _tokenEmailController.text.trim();
    setState(() => _creating = true);
    try {
      final token = await _service.createActivationToken(
        plan: _plan == 'custom' ? 'custom' : _plan,
        durationDays: _days,
        startsAt: _startsAt,
        pharmacyId: _selectedPharmacyId,
        ownerEmail: sendTo,
        note: _noteController.text.trim(),
      );
      await Clipboard.setData(ClipboardData(text: token));
      await AuditLogService().record(
        action: 'TOKEN_CREATED',
        pharmacyId: _selectedPharmacyId,
        detail: token,
      );
      String? mailNote;
      var inactiveEmail = false;
      if (_emailToken) {
        final active = await UserManagementService().isActiveEmail(sendTo);
        if (!active) {
          inactiveEmail = true;
          mailNote = 'email-inactive';
        } else {
          String shopName = '';
          if ((_selectedPharmacyId ?? '').isNotEmpty) {
            final shop = await PharmacyService().getPharmacy(_selectedPharmacyId!);
            shopName = shop?.name ?? '';
          }
          mailNote = await TransactionalEmailService().notifyLicenseToken(
            toEmail: sendTo,
            shopName: shopName,
            token: token,
            plan: _plan,
            days: _days,
          );
        }
      }
      final sent = _emailToken && !inactiveEmail && mailNote == null;
      final shortNote = sent
          ? S.t('Token sent', 'Token imetumwa')
          : inactiveEmail
              ? S.t('Email is not active', 'Barua pepe haiko active')
              : mailNote == 'email-not-ready'
                  ? S.t('Set up Gmail first', 'Weka Gmail kwanza')
                  : mailNote == null
                      ? null
                      : S.t('Email was not sent', 'Barua pepe haijatumwa');
      setState(() {
        _lastToken = token;
        _lastEmailNote = shortNote;
      });
      if (mounted) {
        if (sent) {
          showAppNotice(context, shortNote!);
        } else if (inactiveEmail) {
          showAppNotice(context, shortNote!, kind: AppNoticeKind.warning);
        } else if (shortNote != null) {
          showAppNotice(context, shortNote, kind: AppNoticeKind.error);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('Token created', 'Token imetengenezwa')}: $token')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create token: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _grantDirect() async {
    final pharmacyId = _selectedPharmacyId?.trim() ?? '';
    if (pharmacyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a pharmacy first.')),
      );
      return;
    }
    final expiresAt = _startsAt.add(Duration(days: _days));
    try {
      await _service.grantLicense(
        pharmacyId: pharmacyId,
        plan: _plan == 'custom' ? 'custom' : _plan,
        startsAt: _startsAt,
        expiresAt: expiresAt,
        note: _noteController.text.trim(),
        paymentReference: _paymentRefController.text.trim(),
      );
      await AuditLogService().record(
        action: 'GRANTED_SUBSCRIPTION',
        pharmacyId: pharmacyId,
        detail: 'until ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}',
      );
      try {
        final pharmacy = await PharmacyService().getPharmacy(pharmacyId);
        await TransactionalEmailService().notifySubscriptionActivated(
          toEmail: pharmacy?.ownerEmail ?? '',
          displayName: pharmacy?.name ?? '',
          shopName: pharmacy?.name ?? '',
          plan: _plan == 'custom' ? 'custom' : _plan,
          expiresAt: expiresAt,
        );
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pharmacy licensed until ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}. Write access is restored.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grant failed: $error')),
        );
      }
    }
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _startsAt = picked);
  }

  Future<void> _deleteToken(ActivationCodeRecord code, PharmacyRecord? pharmacy) async {
    final expired = code.isUsed && SubscriptionService.usedTokenExpired(pharmacy);
    final hideOnly = code.isUsed && !expired;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('Delete this token?', 'Uifute token hii?')),
        content: Text(
          !code.isUsed
              ? S.t('${code.code} has not been used. It will be deleted from the database and cannot be activated.', '${code.code} haijatumika. Itafutwa kwenye database na haitaweza kuwezesha.')
              : expired
                  ? S.t('${code.code} has expired. It will be deleted from the database. The shop record stays as it is.', '${code.code} imeisha. Itafutwa kwenye database. Rekodi ya duka inabaki kama ilivyo.')
                  : S.t('${code.code} is already in use. It will leave your list only. The shop keeps working.', '${code.code} tayari inatumika. Itaondoka kwenye orodha yako tu. Duka linaendelea kufanya kazi.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(S.t('Delete', 'Futa'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteActivationToken(code.code, hideOnly: hideOnly);
      await AuditLogService().record(action: hideOnly ? 'TOKEN_HIDDEN' : 'TOKEN_DELETED', detail: code.code);
      if (!mounted) return;
      final message = hideOnly
          ? S.t('Removed from your list. The shop license is unchanged.', 'Imeondoka kwenye orodha yako. Leseni ya duka haijabadilika.')
          : S.t('Deleted from the database.', 'Imefutwa kwenye database.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete token: $error')));
    }
  }

  Future<void> _deleteUnusedTokens() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete unused tokens?'),
        content: const Text(
          'This removes every token that has not been used yet. Used tokens stay. Shops that already activated keep their license.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete unused')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await _service.deleteUnusedActivationTokens();
      await AuditLogService().record(action: 'UNUSED_TOKENS_DELETED', detail: '$count');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count == 0 ? 'No unused tokens.' : 'Deleted $count unused token${count == 1 ? '' : 's'}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete unused tokens: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pharmacy licenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        const Text(
          'License is for the whole pharmacy. When it expires, every staff member can still view records but cannot add sales, stock, or users until you grant a new token.',
          style: TextStyle(color: Color(0xff68807d), height: 1.45),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(width: 420, child: _buildIssuerCard()),
            SizedBox(width: 420, child: _buildGrantCard()),
          ],
        ),
        const SizedBox(height: 22),
        _buildLicenseBoard(),
      ],
    );
  }

  Widget _pharmacySelector() {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: _pharmacies.watchPharmacies(),
      builder: (context, snapshot) {
        final pharmacies = snapshot.data ?? const <PharmacyRecord>[];
        return DropdownButtonFormField<String>(
          initialValue: pharmacies.any((pharmacy) => pharmacy.id == _selectedPharmacyId) ? _selectedPharmacyId : null,
          decoration: const InputDecoration(labelText: 'Pharmacy'),
          items: [
            for (final pharmacy in pharmacies)
              DropdownMenuItem(value: pharmacy.id, child: Text(pharmacy.name)),
          ],
          onChanged: (value) async {
            setState(() => _selectedPharmacyId = value);
            if ((value ?? '').isEmpty) return;
            final shop = await _pharmacies.getPharmacy(value!);
            if (!mounted) return;
            if ((shop?.ownerEmail ?? '').trim().isNotEmpty) {
              _tokenEmailController.text = shop!.ownerEmail!.trim();
            }
          },
        );
      },
    );
  }

  Widget _buildIssuerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Generate token after payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            _pharmacySelector(),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _plan,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Monthly · 30 days')),
                DropdownMenuItem(value: 'quarterly', child: Text('Quarterly · 90 days')),
                DropdownMenuItem(value: 'biannual', child: Text('6 months · 180 days')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly · 365 days')),
                DropdownMenuItem(value: 'custom', child: Text('Custom days')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _plan = value;
                  _durationDays = SubscriptionService.planDurations[value] ?? _durationDays;
                });
              },
            ),
            if (_plan == 'custom') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customDaysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Duration (days)'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _tokenEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Send token to this email'),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _emailToken,
              onChanged: (value) => setState(() => _emailToken = value ?? true),
              title: Text(S.t('Send this token by email', 'Tuma token hii kwa barua pepe')),
              subtitle: Text(S.t('Only when this is ticked. An inactive email is not sent, and the token is still created.', 'Inatuma tu ukiweka tiki. Barua pepe isiyo active haitumwi, na token bado inatengenezwa.')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Payment note'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickStart,
              style: OutlinedButton.styleFrom(
                foregroundColor: PhyimacyBrand.forest,
                side: const BorderSide(color: Color(0xffd7e5e1)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.event_rounded),
              label: Text('Starts ${_startsAt.day}/${_startsAt.month}/${_startsAt.year}'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _creating ? null : _generateToken,
              style: FilledButton.styleFrom(
                backgroundColor: PhyimacyBrand.forest,
                foregroundColor: PhyimacyBrand.gold,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.vpn_key_rounded),
              label: Text(_creating ? 'Creating...' : 'Generate pharmacy token'),
            ),
            if (_lastToken != null) ...[
              const SizedBox(height: 12),
              SelectableText(_lastToken!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xff0f766e))),
              if (_lastEmailNote != null) ...[
                const SizedBox(height: 6),
                Text(_lastEmailNote!, style: const TextStyle(color: Color(0xff68807d))),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGrantCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Grant paid access', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Create shops under Pharmacies and logins. Here you only extend or unlock a shop after payment.', style: TextStyle(color: Color(0xff68807d), height: 1.4)),
            const SizedBox(height: 12),
            _pharmacySelector(),
            const SizedBox(height: 10),
            TextField(
              controller: _paymentRefController,
              decoration: const InputDecoration(labelText: 'Payment reference (M-Pesa / bank)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _grantDirect,
              style: FilledButton.styleFrom(
                backgroundColor: PhyimacyBrand.forest,
                foregroundColor: PhyimacyBrand.gold,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.verified_rounded),
              label: const Text('Grant paid access to selected pharmacy'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseBoard() {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        return StreamBuilder<List<PharmacyRecord>>(
          stream: _pharmacies.watchPharmacies(),
          builder: (context, pharmacySnap) {
            return StreamBuilder<List<ActivationCodeRecord>>(
              stream: _service.watchCodes(),
              builder: (context, codeSnap) {
                if (pharmacySnap.hasError) return Text('Could not load pharmacies: ${pharmacySnap.error}');
                if (codeSnap.hasError) return Text('Could not load tokens: ${codeSnap.error}');
                if (!pharmacySnap.hasData || !codeSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final pharmacies = pharmacySnap.data!;
                final codes = codeSnap.data!;
                final byId = {for (final shop in pharmacies) shop.id: shop};
                final query = _searchController.text.trim().toLowerCase();
                final visibleShops = pharmacies.where((shop) => _shopMatches(shop, query) && _shopMatchesFilter(shop)).toList()
                  ..sort((a, b) => _daysLeft(a).compareTo(_daysLeft(b)));
                final visibleTokens = codes.where((code) => _tokenMatches(code, byId, query) && _tokenMatchesFilter(code)).toList();
                final active = pharmacies.where((shop) => shop.isUnlocked && _daysLeft(shop) > 7).length;
                final expiring = pharmacies.where((shop) => shop.isUnlocked && _daysLeft(shop) > 0 && _daysLeft(shop) <= 7).length;
                final attention = pharmacies.where((shop) => !shop.isUnlocked || _daysLeft(shop) <= 0).length;
                final unused = codes.where((code) => !code.isUsed).length;
                final used = codes.where((code) => code.isUsed).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: S.t('Search pharmacy, email, or token', 'Tafuta duka, barua pepe, au tokeni'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _consolePanel(
                      icon: Icons.storefront_rounded,
                      title: S.t('Pharmacies', 'Maduka'),
                      subtitle: S.t('Open a shop to see its license, then manage it.', 'Fungua duka uone leseni yake, kisha usimamie.'),
                      filters: [
                        _filterButton(id: 'all', label: S.t('All', 'Zote'), count: '${pharmacies.length}', icon: Icons.apps_rounded, selected: _shopFilter, accent: PhyimacyBrand.forest, onSelected: (value) => setState(() => _shopFilter = value)),
                        _filterButton(id: 'active', label: S.t('Active', 'Hai'), count: '$active', icon: Icons.verified_rounded, selected: _shopFilter, accent: PhyimacyBrand.teal, onSelected: (value) => setState(() => _shopFilter = value)),
                        _filterButton(id: 'expiring', label: S.t('Expiring', 'Inaisha'), count: '$expiring', icon: Icons.schedule_rounded, selected: _shopFilter, accent: const Color(0xffb45309), onSelected: (value) => setState(() => _shopFilter = value)),
                        _filterButton(id: 'ended', label: S.t('Ended', 'Imeisha'), count: '$attention', icon: Icons.lock_outline_rounded, selected: _shopFilter, accent: const Color(0xffb42318), onSelected: (value) => setState(() => _shopFilter = value)),
                      ],
                      child: _pharmacyTable(visibleShops, pharmacies.isEmpty, codes),
                    ),
                    const SizedBox(height: 18),
                    _consolePanel(
                      icon: Icons.vpn_key_rounded,
                      title: S.t('Activation tokens', 'Tokeni'),
                      subtitle: S.t('Unused tokens can be deleted. A used token does not remove the shop license.', 'Tokeni ambazo hazijatumika zinaweza kufutwa. Tokeni iliyotumika haiondoi leseni ya duka.'),
                      trailing: OutlinedButton.icon(
                        onPressed: _deleteUnusedTokens,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PhyimacyBrand.gold,
                          side: BorderSide(color: PhyimacyBrand.gold.withValues(alpha: 0.8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: Text(S.t('Delete unused', 'Futa zisizotumika')),
                      ),
                      filters: [
                        _filterButton(id: 'all', label: S.t('All', 'Zote'), count: '${codes.length}', icon: Icons.apps_rounded, selected: _tokenFilter, accent: PhyimacyBrand.forest, onSelected: (value) => setState(() => _tokenFilter = value)),
                        _filterButton(id: 'unused', label: S.t('Unused', 'Hazijatumika'), count: '$unused', icon: Icons.key_off_rounded, selected: _tokenFilter, accent: const Color(0xffb45309), onSelected: (value) => setState(() => _tokenFilter = value)),
                        _filterButton(id: 'used', label: S.t('Used', 'Zimetumika'), count: '$used', icon: Icons.key_rounded, selected: _tokenFilter, accent: PhyimacyBrand.teal, onSelected: (value) => setState(() => _tokenFilter = value)),
                      ],
                      child: _tokenTable(visibleTokens, byId, codes.isEmpty),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  bool _shopMatches(PharmacyRecord shop, String query) {
    if (query.isEmpty) return true;
    return shop.name.toLowerCase().contains(query) || (shop.ownerEmail ?? '').toLowerCase().contains(query) || shop.plan.toLowerCase().contains(query);
  }

  bool _shopMatchesFilter(PharmacyRecord shop) {
    final days = _daysLeft(shop);
    return switch (_shopFilter) {
      'active' => shop.isUnlocked && days > 7,
      'expiring' => shop.isUnlocked && days > 0 && days <= 7,
      'ended' => !shop.isUnlocked || days <= 0,
      _ => true,
    };
  }

  bool _tokenMatches(ActivationCodeRecord code, Map<String, PharmacyRecord> byId, String query) {
    if (query.isEmpty) return true;
    final shop = byId[code.linkedPharmacyId];
    return code.code.toLowerCase().contains(query) ||
        code.plan.toLowerCase().contains(query) ||
        (code.ownerEmail ?? '').toLowerCase().contains(query) ||
        (shop?.name ?? '').toLowerCase().contains(query);
  }

  bool _tokenMatchesFilter(ActivationCodeRecord code) {
    return switch (_tokenFilter) {
      'unused' => !code.isUsed,
      'used' => code.isUsed,
      _ => true,
    };
  }

  int _daysLeft(PharmacyRecord pharmacy) => SubscriptionService.calendarDaysRemaining(pharmacy.expiresAt ?? pharmacy.trialEndsAt);

  int _spanDays(PharmacyRecord pharmacy) {
    final end = pharmacy.expiresAt ?? pharmacy.trialEndsAt;
    if (pharmacy.startsAt != null && end != null) {
      final days = DateTime(end.year, end.month, end.day).difference(DateTime(pharmacy.startsAt!.year, pharmacy.startsAt!.month, pharmacy.startsAt!.day)).inDays;
      if (days > 0) return days;
    }
    return SubscriptionService.planDurations[pharmacy.plan] ?? 30;
  }

  Widget _consolePanel({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> filters,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffe3eeeb)),
        boxShadow: const [BoxShadow(color: Color(0x12073B3A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: const BoxDecoration(
              color: PhyimacyBrand.forest,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: PhyimacyBrand.gold, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: GoogleFonts.playfairDisplay(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.3)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                if (narrow) {
                  return Wrap(spacing: 8, runSpacing: 8, children: [for (final filter in filters) SizedBox(width: 168, child: filter)]);
                }
                return Row(children: [
                  for (var i = 0; i < filters.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: filters[i]),
                  ],
                ]);
              },
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child),
        ],
      ),
    );
  }

  Widget _filterButton({
    required String id,
    required String label,
    required String count,
    required IconData icon,
    required String selected,
    required Color accent,
    required ValueChanged<String> onSelected,
  }) {
    final on = selected == id;
    return Material(
      color: on ? PhyimacyBrand.forest : const Color(0xfff7f4ec),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => onSelected(id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? PhyimacyBrand.gold : const Color(0xffe3eeeb)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: on ? PhyimacyBrand.gold : accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: on ? Colors.white : PhyimacyBrand.ink, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: on ? Colors.white.withValues(alpha: 0.14) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(count, style: GoogleFonts.inter(color: on ? PhyimacyBrand.gold : accent, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogAction(String label, VoidCallback onPressed, {bool danger = false}) {
    final color = danger ? const Color(0xffb42318) : PhyimacyBrand.forest;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: danger ? const Color(0xffe7c1bd) : const Color(0xffd7e5e1)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _pharmacyTable(List<PharmacyRecord> shops, bool noneAtAll, List<ActivationCodeRecord> codes) {
    return _ledger(
      headers: [
        _head(S.t('Pharmacy', 'Duka'), 28),
        _head(S.t('Plan', 'Mpango'), 12),
        _head(S.t('Email', 'Barua pepe'), 22),
        _head(S.t('Status', 'Hali'), 12),
        _head(S.t('Days left', 'Siku'), 14),
        _head(S.t('Ends', 'Inaisha'), 12),
      ],
      trailing: SizedBox(width: 118, child: _head(S.t('Actions', 'Vitendo'), 0)),
      empty: noneAtAll
          ? S.t('No pharmacies yet. Create one after a customer signs up.', 'Hakuna maduka bado. Tengeneza duka baada ya mteja kujisajili.')
          : S.t('No pharmacies match this view.', 'Hakuna duka linalolingana na mwonekano huu.'),
      rows: [
        for (var i = 0; i < shops.length; i++) _pharmacyRow(shops[i], i, codes),
      ],
    );
  }

  Widget _pharmacyRow(PharmacyRecord pharmacy, int index, List<ActivationCodeRecord> codes) {
    final days = _daysLeft(pharmacy);
    final span = _spanDays(pharmacy);
    final progress = span <= 0 ? 0.0 : (days / span).clamp(0.0, 1.0);
    final ended = !pharmacy.isUnlocked || days <= 0;
    final expiring = !ended && days <= 7;
    final color = ended ? const Color(0xffb42318) : expiring ? const Color(0xffb45309) : PhyimacyBrand.teal;
    final status = !pharmacy.isUnlocked
        ? S.t('Locked', 'Imefungwa')
        : days <= 0
            ? S.t('Ended', 'Imeisha')
            : pharmacy.isTrial
                ? S.t('Trial', 'Majaribio')
                : S.t('Active', 'Inaendelea');
    final phone = (pharmacy.phone ?? '').trim();
    return _row(
      index: index,
      cells: [
        _cell(
          flex: 28,
          child: InkWell(
            onTap: () => _openPharmacy(pharmacy, codes),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: PhyimacyBrand.forest, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          pharmacy.name.trim().isEmpty ? '?' : pharmacy.name.trim()[0].toUpperCase(),
                          style: GoogleFonts.inter(color: PhyimacyBrand.gold, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          pharmacy.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink),
                        ),
                      ),
                    ],
                  ),
                  if (phone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, top: 2),
                      child: Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: PhyimacyBrand.muted)),
                    ),
                ],
              ),
            ),
          ),
        ),
        _cell(flex: 12, child: Text(pharmacy.plan, style: const TextStyle(fontWeight: FontWeight.w600, color: PhyimacyBrand.ink))),
        _cell(
          flex: 22,
          child: Text(
            (pharmacy.ownerEmail ?? '').trim().isEmpty ? '—' : pharmacy.ownerEmail!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PhyimacyBrand.muted),
          ),
        ),
        _cell(flex: 12, child: Align(alignment: Alignment.centerLeft, child: _statusChip(status, color))),
        _cell(
          flex: 14,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$days', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(minHeight: 4, value: progress, backgroundColor: const Color(0xffedf2f2), color: color),
              ),
            ],
          ),
        ),
        _cell(flex: 12, child: Text(_fmt(pharmacy.expiresAt ?? pharmacy.trialEndsAt), style: const TextStyle(fontWeight: FontWeight.w600, color: PhyimacyBrand.ink))),
      ],
      trailing: PopupMenuButton<String>(
        tooltip: S.t('Manage this pharmacy', 'Simamia duka hili'),
        padding: EdgeInsets.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xffd7e5e1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.t('Manage', 'Simamia'), style: const TextStyle(fontWeight: FontWeight.w700, color: PhyimacyBrand.forest, fontSize: 13)),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, size: 18, color: PhyimacyBrand.forest),
            ],
          ),
        ),
        onSelected: (value) async {
          switch (value) {
            case 'edit':
              await _renamePharmacy(pharmacy);
            case 'extend':
              await _extendPharmacy(pharmacy);
            case 'lock':
              await _lockPharmacy(pharmacy);
            case 'unlock':
              await _service.unlockLicense(pharmacy.id);
              await AuditLogService().record(action: 'UNLOCKED_WRITES', pharmacyId: pharmacy.id, pharmacyName: pharmacy.name);
            case 'off':
              await _deactivatePharmacy(pharmacy);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'edit', child: Text(S.t('Edit', 'Hariri'))),
          PopupMenuItem(value: 'extend', child: Text(S.t('Extend', 'Ongeza muda'))),
          PopupMenuItem(value: 'lock', child: Text(S.t('Lock writes', 'Funga maandishi'))),
          PopupMenuItem(value: 'unlock', child: Text(S.t('Unlock', 'Fungua'))),
          PopupMenuItem(value: 'off', child: Text(S.t('Deactivate', 'Zima'))),
        ],
      ),
    );
  }

  Future<void> _openPharmacy(PharmacyRecord pharmacy, List<ActivationCodeRecord> codes) async {
    final days = _daysLeft(pharmacy);
    final ended = !pharmacy.isUnlocked || days <= 0;
    final expiring = !ended && days <= 7;
    final color = ended ? const Color(0xffb42318) : expiring ? const Color(0xffb45309) : PhyimacyBrand.teal;
    final status = !pharmacy.isUnlocked
        ? S.t('Locked', 'Imefungwa')
        : days <= 0
            ? S.t('Ended', 'Imeisha')
            : pharmacy.isTrial
                ? S.t('Trial', 'Majaribio')
                : S.t('Active', 'Inaendelea');
    final linked = codes.where((code) => code.linkedPharmacyId == pharmacy.id).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
                decoration: const BoxDecoration(
                  color: PhyimacyBrand.forest,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pharmacy.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(pharmacy.plan, style: const TextStyle(color: PhyimacyBrand.gold, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: const TextStyle(color: PhyimacyBrand.gold, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: Row(
                  children: [
                    Text('$days', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: color, height: 1)),
                    const SizedBox(width: 10),
                    Text(days == 1 ? S.t('day left', 'siku imebaki') : S.t('days left', 'siku zimebaki'), style: const TextStyle(color: PhyimacyBrand.muted, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _detailTile(S.t('Email', 'Barua pepe'), (pharmacy.ownerEmail ?? '').trim().isEmpty ? '—' : pharmacy.ownerEmail!.trim()),
                    _detailTile(S.t('Phone', 'Simu'), (pharmacy.phone ?? '').trim().isEmpty ? '—' : pharmacy.phone!.trim()),
                    _detailTile(S.t('Address', 'Anwani'), (pharmacy.address ?? '').trim().isEmpty ? '—' : pharmacy.address!.trim()),
                    _detailTile(S.t('Starts', 'Inaanza'), _fmt(pharmacy.startsAt)),
                    _detailTile(S.t('Ends', 'Inaisha'), _fmt(pharmacy.expiresAt ?? pharmacy.trialEndsAt)),
                    _detailTile(S.t('Writes', 'Maandishi'), pharmacy.isUnlocked ? S.t('Open', 'Wazi') : S.t('Locked', 'Imefungwa')),
                    if ((pharmacy.note ?? '').trim().isNotEmpty) _detailTile(S.t('Note', 'Maelezo'), pharmacy.note!.trim()),
                  ],
                ),
              ),
              if (linked.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(S.t('Tokens for this pharmacy', 'Tokeni za duka hili'), style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                      const SizedBox(height: 6),
                      for (final code in linked.take(6))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${code.code}  ·  ${code.plan}  ·  ${code.isUsed ? S.t('Used', 'Imetumika') : S.t('Unused', 'Haijatumika')}', style: const TextStyle(color: PhyimacyBrand.muted)),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _dialogAction(S.t('Edit', 'Hariri'), () { Navigator.pop(dialogContext); _renamePharmacy(pharmacy); }),
                    _dialogAction(S.t('Extend', 'Ongeza muda'), () { Navigator.pop(dialogContext); _extendPharmacy(pharmacy); }),
                    _dialogAction(S.t('Unlock', 'Fungua'), () async {
                      Navigator.pop(dialogContext);
                      await _service.unlockLicense(pharmacy.id);
                      await AuditLogService().record(action: 'UNLOCKED_WRITES', pharmacyId: pharmacy.id, pharmacyName: pharmacy.name);
                    }),
                    _dialogAction(S.t('Lock writes', 'Funga maandishi'), () { Navigator.pop(dialogContext); _lockPharmacy(pharmacy); }, danger: true),
                    _dialogAction(S.t('Deactivate', 'Zima'), () { Navigator.pop(dialogContext); _deactivatePharmacy(pharmacy); }, danger: true),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: PhyimacyBrand.forest,
                        foregroundColor: PhyimacyBrand.gold,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(S.t('Close', 'Funga')),
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

  Widget _detailTile(String label, String value) {
    return Container(
      width: 188,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xfff7f4ec),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: PhyimacyBrand.muted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
        ],
      ),
    );
  }

  Widget _tokenTable(List<ActivationCodeRecord> codes, Map<String, PharmacyRecord> byId, bool noneAtAll) {
    return _ledger(
      headers: [
        _head(S.t('Token', 'Tokeni'), 22),
        _head(S.t('Pharmacy', 'Duka'), 20),
        _head(S.t('Plan', 'Mpango'), 12),
        _head(S.t('Time left', 'Muda'), 18),
        _head(S.t('Status', 'Hali'), 12),
        _head(S.t('Email', 'Barua pepe'), 16),
      ],
      trailing: const SizedBox(width: 88),
      empty: noneAtAll
          ? S.t('No tokens yet.', 'Hakuna tokeni bado.')
          : S.t('No tokens match this view.', 'Hakuna tokeni inayolingana na mwonekano huu.'),
      rows: [
        for (var i = 0; i < codes.length; i++) _tokenRow(codes[i], byId[codes[i].linkedPharmacyId], i),
      ],
    );
  }

  Widget _tokenRow(ActivationCodeRecord code, PharmacyRecord? pharmacy, int index) {
    final remaining = SubscriptionService.tokenRemainingLabel(
      isUsed: code.isUsed,
      durationDays: code.durationDays,
      pharmacy: code.isUsed ? pharmacy : null,
    );
    final shopName = code.linkedPharmacyId.isEmpty
        ? S.t('Not linked', 'Haijaunganishwa')
        : (pharmacy?.name ?? S.t('Unknown pharmacy', 'Duka halijulikani'));
    final color = code.isUsed ? PhyimacyBrand.teal : const Color(0xffb45309);
    final ends = pharmacy == null ? null : (pharmacy.expiresAt ?? pharmacy.trialEndsAt);
    final detail = [
      if (!code.isUsed && code.startsAt != null) '${S.t('Starts', 'Inaanza')} ${_fmt(code.startsAt)}',
      if (code.isUsed && ends != null) '${S.t('Ends', 'Inaisha')} ${_fmt(ends)}',
      if ((code.note ?? '').trim().isNotEmpty) code.note!.trim(),
    ].join(' · ');
    return _row(
      index: index,
      cells: [
        _cell(
          flex: 22,
          child: SelectableText(code.code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2, color: PhyimacyBrand.ink)),
        ),
        _cell(flex: 20, child: Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: PhyimacyBrand.teal))),
        _cell(flex: 12, child: Text(code.plan, style: const TextStyle(fontWeight: FontWeight.w600))),
        _cell(
          flex: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(remaining, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              if (detail.isNotEmpty)
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: PhyimacyBrand.muted)),
            ],
          ),
        ),
        _cell(flex: 12, child: Align(alignment: Alignment.centerLeft, child: _statusChip(code.isUsed ? S.t('Used', 'Imetumika') : S.t('Unused', 'Haijatumika'), color))),
        _cell(
          flex: 16,
          child: Text(
            (code.ownerEmail ?? '').trim().isEmpty ? '—' : code.ownerEmail!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PhyimacyBrand.muted),
          ),
        ),
      ],
      trailing: SizedBox(
        width: 88,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: S.t('Copy', 'Nakili'),
              onPressed: () => Clipboard.setData(ClipboardData(text: code.code)),
              icon: const Icon(Icons.copy_rounded, size: 18, color: PhyimacyBrand.teal),
            ),
            IconButton(
              tooltip: S.t('Delete', 'Futa'),
              onPressed: () => _deleteToken(code, pharmacy),
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xffb42318)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledger({
    required List<Widget> headers,
    required Widget trailing,
    required String empty,
    required List<Widget> rows,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 860 ? 860.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xffe4edeb)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: PhyimacyBrand.forest,
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(children: [...headers, trailing]),
                  ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
                      child: Align(alignment: Alignment.centerLeft, child: Text(empty, style: const TextStyle(color: PhyimacyBrand.muted))),
                    )
                  else
                    ...rows,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _head(String label, int flex) {
    final text = Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Color(0xffe8c47a), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
    );
    if (flex <= 0) return text;
    return Expanded(flex: flex, child: text);
  }

  Widget _cell({required int flex, required Widget child}) {
    return Expanded(flex: flex, child: child);
  }

  Widget _row({required int index, required List<Widget> cells, required Widget trailing}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: BoxDecoration(
        color: index.isOdd ? const Color(0xfff7f4ec) : Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xffedf2f2))),
      ),
      child: Row(
        children: [
          ...cells,
          trailing,
        ],
      ),
    );
  }

  Future<void> _renamePharmacy(PharmacyRecord pharmacy) async {
    final controller = TextEditingController(text: pharmacy.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit pharmacy'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Pharmacy name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _pharmacies.updatePharmacyProfile(pharmacyId: pharmacy.id, name: name, note: pharmacy.note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pharmacy updated.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $error')));
      }
    }
  }

  Future<void> _extendPharmacy(PharmacyRecord pharmacy) async {
    final daysController = TextEditingController(text: '30');
    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Extend subscription'),
        content: TextField(
          controller: daysController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days (7, 15, 30, 90, 180, 365…)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(daysController.text.trim())),
            child: const Text('Extend'),
          ),
        ],
      ),
    );
    if (days == null || days <= 0) return;
    await _service.extendLicense(pharmacyId: pharmacy.id, extraDays: days);
    await AuditLogService().record(action: 'EXTENDED_SUBSCRIPTION', pharmacyId: pharmacy.id, pharmacyName: pharmacy.name, detail: '+$days days');
  }

  Future<void> _lockPharmacy(PharmacyRecord pharmacy) async {
    final reason = TextEditingController(text: 'Subscription expired');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Lock ${pharmacy.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This stops new sales, stock changes, and purchases. Login and viewing records can remain.'),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lock pharmacy')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.lockLicense(pharmacy.id);
    await AuditLogService().record(action: 'LOCKED_WRITES', pharmacyId: pharmacy.id, pharmacyName: pharmacy.name, detail: reason.text.trim());
  }

  Future<void> _deactivatePharmacy(PharmacyRecord pharmacy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate pharmacy?'),
        content: Text('${pharmacy.name} will be locked. Data stays. This is safer than Delete.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Deactivate')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.lockLicense(pharmacy.id);
    await AuditLogService().record(action: 'DEACTIVATED_PHARMACY', pharmacyId: pharmacy.id, pharmacyName: pharmacy.name);
  }

  String _fmt(DateTime? value) {
    if (value == null) return '—';
    return '${value.day}/${value.month}/${value.year}';
  }
}
