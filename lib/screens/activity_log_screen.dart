import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../backend/activity_log_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

/// Shop admins pass [pharmacyId] and see every important action in their shop.
/// Super admin leaves it empty and sees only security events from every shop.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({this.pharmacyId, super.key});

  final String? pharmacyId;

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

enum _Group { all, staff, stock, sales, data }

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _service = ActivityLogService();
  final _rows = <ActivityEntry>[];
  final _search = TextEditingController();
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  var _hasMore = false;
  var _loading = false;
  String? _error;
  var _group = _Group.all;

  bool get _systemView => (widget.pharmacyId ?? '').trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final after = reset ? null : _cursor;
      final page = _systemView
          ? await _service.fetchSecurity(after: after)
          : await _service.fetchShop(widget.pharmacyId!, after: after);
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(page.rows);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyActionError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _Group _groupOf(String action) {
    if (action.startsWith('staff.') || action.startsWith('password.')) return _Group.staff;
    if (action.startsWith('medicine.') || action.startsWith('stock.')) return _Group.stock;
    if (action.startsWith('sale.')) return _Group.sales;
    return _Group.data;
  }

  String _groupLabel(_Group group) => switch (group) {
        _Group.all => S.t('All', 'Zote'),
        _Group.staff => S.t('Staff & passwords', 'Staff na nenosiri'),
        _Group.stock => S.t('Medicines & stock', 'Dawa na stock'),
        _Group.sales => S.t('Sales', 'Mauzo'),
        _Group.data => S.t('Shop & data', 'Duka na data'),
      };

  (String, IconData, Color) _describe(String action) {
    const teal = Color(0xff0f766e);
    const red = Color(0xffb42318);
    const amber = Color(0xffb54708);
    return switch (action) {
      ActivityAction.staffCreated => (S.t('Added a login', 'Ameongeza login'), Icons.person_add_alt_1_rounded, teal),
      ActivityAction.staffUpdated => (S.t('Changed login access', 'Amebadilisha ruhusa za login'), Icons.manage_accounts_outlined, amber),
      ActivityAction.staffRoleChanged => (S.t('Changed a role', 'Amebadilisha cheo'), Icons.swap_vert_rounded, amber),
      ActivityAction.staffDisabled => (S.t('Disabled a login', 'Amefunga login'), Icons.person_off_outlined, red),
      ActivityAction.staffEnabled => (S.t('Enabled a login', 'Amefungua login'), Icons.person_outline_rounded, teal),
      ActivityAction.staffDeleted => (S.t('Deleted a login', 'Amefuta login'), Icons.person_remove_alt_1_outlined, red),
      ActivityAction.passwordReset => (S.t('Set a password for someone', 'Ameweka nenosiri la mtu'), Icons.password_rounded, amber),
      ActivityAction.passwordChanged => (S.t('Changed own password', 'Amebadilisha nenosiri lake'), Icons.lock_reset_rounded, teal),
      ActivityAction.shopCreated => (S.t('Created a shop', 'Ametengeneza duka'), Icons.add_business_outlined, teal),
      ActivityAction.shopUpdated => (S.t('Edited shop details', 'Amehariri taarifa za duka'), Icons.storefront_outlined, teal),
      ActivityAction.shopDeleted => (S.t('Deleted a shop', 'Amefuta duka'), Icons.store_mall_directory_outlined, red),
      ActivityAction.dataRestored => (S.t('Restored a backup', 'Amerudisha backup'), Icons.settings_backup_restore_rounded, amber),
      ActivityAction.dataCleared => (S.t('Cleared shop data', 'Amefuta data ya duka'), Icons.delete_sweep_outlined, red),
      ActivityAction.medicineCreated => (S.t('Added a medicine', 'Ameongeza dawa'), Icons.medication_outlined, teal),
      ActivityAction.medicineUpdated => (S.t('Edited a medicine', 'Amehariri dawa'), Icons.edit_outlined, teal),
      ActivityAction.medicinePriceChanged => (S.t('Changed a price', 'Amebadilisha bei'), Icons.sell_outlined, amber),
      ActivityAction.medicineDeleted => (S.t('Removed a medicine', 'Ameondoa dawa'), Icons.delete_outline_rounded, red),
      ActivityAction.medicinesImported => (S.t('Imported medicines', 'Ameingiza dawa kwa wingi'), Icons.upload_file_rounded, teal),
      ActivityAction.stockSet => (S.t('Changed stock count', 'Amebadilisha idadi ya stock'), Icons.inventory_2_outlined, amber),
      ActivityAction.stockWrittenOff => (S.t('Removed expired stock', 'Ameondoa stock iliyoisha muda'), Icons.event_busy_rounded, amber),
      ActivityAction.saleVoided => (S.t('Cancelled a sale', 'Ameghairi mauzo'), Icons.receipt_long_outlined, red),
      _ => (action, Icons.history_rounded, teal),
    };
  }

  String _role(String role) => switch (role.trim().toLowerCase()) {
        'super_admin' => S.t('Super admin', 'Super admin'),
        'admin' => S.t('Admin', 'Admin'),
        'pharmacist' => S.t('Pharmacist', 'Mfamasia'),
        'cashier' => S.t('Cashier', 'Keshia'),
        'storekeeper' => S.t('Storekeeper', 'Mhifadhi'),
        _ => role,
      };

  String _when(DateTime? value) {
    if (value == null) return S.t('just now', 'sasa hivi');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}  ${two(value.hour)}:${two(value.minute)}';
  }

  List<ActivityEntry> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      if (_group != _Group.all && _groupOf(row.action) != _group) return false;
      if (query.isEmpty) return true;
      return '${row.actorName} ${row.actorEmail} ${row.target} ${row.detail} ${row.pharmacyName}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _systemView
              ? S.t('Security activity across all shops: logins added or removed, roles, passwords, shops, and data restores.',
                  'Shughuli za usalama kwenye maduka yote: login kuongezwa au kufutwa, vyeo, nenosiri, maduka, na kurudisha data.')
              : S.t('Important actions by your staff: who added, edited, removed, or cancelled what, and when.',
                  'Vitendo muhimu vya staff wako: nani ameongeza, amehariri, ameondoa, au ameghairi nini, na lini.'),
          style: const TextStyle(color: Color(0xff68807d), height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: S.t('Search name, email, medicine…', 'Tafuta jina, email, dawa…'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: S.t('Refresh', 'Onyesha upya'),
              onPressed: _loading ? null : () => _load(reset: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final group in _Group.values)
              if (!_systemView || group != _Group.sales)
                ChoiceChip(
                  label: Text(_groupLabel(group)),
                  selected: _group == group,
                  onSelected: (_) => setState(() => _group = group),
                ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: Color(0xffb42318))),
          ),
        if (_rows.isEmpty && _loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _rows.isEmpty
                    ? S.t('No activity recorded yet.', 'Bado hakuna shughuli zilizorekodiwa.')
                    : S.t('Nothing matches this filter.', 'Hakuna kinacholingana na kichujio hiki.'),
                style: const TextStyle(color: Color(0xff68807d)),
              ),
            ),
          )
        else
          for (final row in rows) _tile(row),
        if (_hasMore) ...[
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : () => _load(),
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more_rounded),
              label: Text(S.t('Load older', 'Pakia za zamani zaidi')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tile(ActivityEntry row) {
    final (label, icon, color) = _describe(row.action);
    final who = row.actorName.isEmpty ? row.actorEmail : row.actorName;
    final meta = [
      '$who${row.actorRole.isEmpty ? '' : ' · ${_role(row.actorRole)}'}',
      if (_systemView && row.pharmacyName.isNotEmpty) row.pharmacyName,
      _when(row.createdAt),
    ].join('  •  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffe6ece9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                    if (row.target.isNotEmpty)
                      Text(row.target, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xff183b3b))),
                    if (!_systemView && row.isSecurity)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xfffff6dd), borderRadius: BorderRadius.circular(6)),
                        child: Text(S.t('Security', 'Usalama'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xff6b4a00))),
                      ),
                  ],
                ),
                if (row.detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(row.detail, style: const TextStyle(color: Color(0xff183b3b), height: 1.3)),
                ],
                const SizedBox(height: 4),
                Text(meta, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
