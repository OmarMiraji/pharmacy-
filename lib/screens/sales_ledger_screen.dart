import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/sales_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class SalesLedgerScreen extends StatefulWidget {
  const SalesLedgerScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<SalesLedgerScreen> createState() => _SalesLedgerScreenState();
}

class _SalesLedgerScreenState extends State<SalesLedgerScreen> {
  final _searchController = TextEditingController();
  DateTime _selectedDay = _dateOnly(DateTime.now());
  late Stream<List<SaleRecord>> _salesStream;
  late Stream<List<UserProfile>> _usersStream;

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  void initState() {
    super.initState();
    _salesStream = SalesService().watchSalesForDay(_selectedDay);
    final canLookupNames =
        widget.profile.role == 'admin' || widget.profile.isSuperAdmin;
    _usersStream = canLookupNames
        ? UserManagementService().watchUsers(
            pharmacyId: widget.profile.pharmacyId,
          )
        : Stream.value(const <UserProfile>[]);
  }

  void _selectDay(DateTime day) {
    final selected = _dateOnly(day);
    setState(() {
      _selectedDay = selected;
      _salesStream = SalesService().watchSalesForDay(selected);
    });
  }

  bool _isSameDay(DateTime? date, DateTime day) =>
      date != null &&
      date.year == day.year &&
      date.month == day.month &&
      date.day == day.day;

  String _dayLabel(DateTime day) =>
      '${day.day.toString().padLeft(2, '0')} ${S.monthName(day.month)} ${day.year}';

  String _amount(int amount) {
    final digits = amount.abs().toString();
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
      grouped.write(digits[index]);
    }
    return '${amount < 0 ? '-' : ''}TZS $grouped';
  }

  Future<void> _chooseDay() async {
    final today = _dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay.isAfter(today) ? today : _selectedDay,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: S.t('Choose sales date', 'Chagua tarehe ya mauzo'),
    );
    if (picked == null || !mounted) return;
    _selectDay(picked);
  }

  void _shiftDay(int days) {
    final nextDay = _selectedDay.add(Duration(days: days));
    if (nextDay.isAfter(_dateOnly(DateTime.now()))) return;
    _selectDay(nextDay);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserProfile>>(
      stream: _usersStream,
      builder: (context, usersSnapshot) {
        final names = <String, String>{
          for (final user in usersSnapshot.data ?? const <UserProfile>[])
            if (user.displayName.trim().isNotEmpty)
              user.id: user.displayName.trim(),
        };
        return StreamBuilder<List<SaleRecord>>(
          stream: _salesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  S.t('Could not load sales.', 'Imeshindwa kupakia mauzo.'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sales = snapshot.data!;
            final daySales = sales;
            final live = daySales.where((sale) => !sale.isVoided).toList();
            final voided = daySales.where((sale) => sale.isVoided).toList();
            final liveTotal = live.fold<int>(
              0,
              (total, sale) => total + sale.totalMinor,
            );
            final query = _searchController.text.trim().toLowerCase();
            final visibleSales = daySales.where((sale) {
              if (query.isEmpty) return true;
              final seller = _seller(sale, names).toLowerCase();
              return sale.receiptNumber.toLowerCase().contains(query) ||
                  sale.itemNames.any(
                    (name) => name.toLowerCase().contains(query),
                  ) ||
                  seller.contains(query) ||
                  sale.paymentMethod.toLowerCase().contains(query) ||
                  sale.status.toLowerCase().contains(query);
            }).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _selectedDayBar(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _summary(
                        S.t('Sales completed', 'Mauzo yaliyokamilika'),
                        '${live.length}',
                        _dayLabel(_selectedDay),
                        const Color(0xffdff7ee),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summary(
                        S.t('Sales total', 'Jumla ya mauzo'),
                        _amount(liveTotal),
                        S.t(
                          'Voided receipts excluded',
                          'Risiti zilizofutwa hazijahesabiwa',
                        ),
                        const Color(0xffe2efff),
                        featured: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _summary(
                        S.t('Voided', 'Yaliyofutwa'),
                        '${voided.length}',
                        S.t(
                          'Reversed on this date',
                          'Zilizorejeshwa tarehe hii',
                        ),
                        const Color(0xffffeadf),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: S.t(
                      'Search receipt, medicine, seller, or status',
                      'Tafuta risiti, dawa, muuzaji, au hali',
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: S.t('Clear search', 'Futa utafutaji'),
                            onPressed: () => setState(_searchController.clear),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: daySales.isEmpty
                      ? Center(
                          child: Text(
                            S.t(
                              'No sales recorded for ${_dayLabel(_selectedDay)}.',
                              'Hakuna mauzo yaliyorekodiwa tarehe ${_dayLabel(_selectedDay)}.',
                            ),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: PhyimacyBrand.muted,
                              height: 1.4,
                            ),
                          ),
                        )
                      : visibleSales.isEmpty
                      ? Center(
                          child: Text(
                            S.t(
                              'No sales match that search.',
                              'Hakuna mauzo yanayolingana na utafutaji huo.',
                            ),
                          ),
                        )
                      : Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          clipBehavior: Clip.antiAlias,
                          elevation: 2,
                          shadowColor: const Color(0x14073B3A),
                          child: ListView.separated(
                            itemCount: visibleSales.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final sale = visibleSales[index];
                              return _SaleTile(
                                sale: sale,
                                seller: _seller(sale, names),
                                canVoid:
                                    widget.profile.can('sales.refund') &&
                                    !sale.isVoided,
                                onOpen: () => _openDetail(context, sale, names),
                                onVoid: () => _confirmVoid(context, sale),
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

  Widget _selectedDayBar() {
    final today = _dateOnly(DateTime.now());
    final isToday = _isSameDay(_selectedDay, today);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xff103f3b),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1c073b3a),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xffdff7ee).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Color(0xff79d9c4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t('Sales for', 'Mauzo ya'),
                  style: const TextStyle(
                    color: Color(0xffafd0c9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _dayLabel(_selectedDay),
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: S.t('Previous day', 'Siku iliyopita'),
            onPressed: () => _shiftDay(-1),
            color: Colors.white,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          OutlinedButton.icon(
            onPressed: _chooseDay,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xff75b8aa)),
            ),
            icon: const Icon(Icons.edit_calendar_rounded, size: 17),
            label: Text(S.t('Choose date', 'Chagua tarehe')),
          ),
          IconButton(
            tooltip: S.t('Next day', 'Siku inayofuata'),
            onPressed: isToday ? null : () => _shiftDay(1),
            color: Colors.white,
            disabledColor: const Color(0xff73908b),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (!isToday)
            TextButton(
              onPressed: () => setState(() => _selectedDay = today),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xff8be0cb),
              ),
              child: Text(S.t('Today', 'Leo')),
            ),
        ],
      ),
    );
  }

  String _seller(SaleRecord sale, Map<String, String> names) {
    final stored = sale.soldByName.trim();
    if (stored.isNotEmpty) return stored;
    final lookedUp = names[sale.soldBy];
    if (lookedUp != null && lookedUp.isNotEmpty) return lookedUp;
    if (sale.soldBy == widget.profile.id &&
        widget.profile.displayName.trim().isNotEmpty) {
      return widget.profile.displayName.trim();
    }
    return S.t('Staff', 'Staff');
  }

  Future<void> _confirmVoid(BuildContext context, SaleRecord sale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Void this sale?', 'Futa mauzo haya?')),
        content: Text(
          S.t(
            'Reverse ${sale.receiptNumber}? Stock goes back, and this receipt stops counting as a sale. The void time stays on the record.',
            'Futa ${sale.receiptNumber}? Stock inarudi, na risiti hii hahesabiwi tena kama mauzo. Muda wa kufuta unabaki kwenye kumbukumbu.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.t('Cancel', 'Ghairi')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.t('Void sale', 'Futa mauzo')),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final name = widget.profile.displayName.trim().isNotEmpty
          ? widget.profile.displayName.trim()
          : widget.profile.email;
      await SalesService().voidSale(
        sale.id,
        voidedBy: AuthService().currentUser?.uid ?? widget.profile.id,
        voidedByName: name,
      );
      if (!context.mounted) return;
      showAppNotice(
        context,
        S.t(
          'Sale voided. It is no longer counted as sold.',
          'Mauzo yamefutwa. Hayahahesabiwi tena kama yameuzwa.',
        ),
      );
    } catch (error) {
      if (context.mounted) {
        showAppNotice(
          context,
          friendlyActionError(error),
          kind: AppNoticeKind.error,
        );
      }
    }
  }

  Future<void> _openDetail(
    BuildContext context,
    SaleRecord sale,
    Map<String, String> names,
  ) async {
    final seller = _seller(sale, names);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SaleDetailDialog(sale: sale, seller: seller),
    );
  }

  Widget _summary(
    String label,
    String value,
    String note,
    Color color, {
    bool featured = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: featured ? const Color(0xff0f766e) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: featured ? null : Border.all(color: const Color(0xffe2ebe8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14073B3A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 18,
              color: PhyimacyBrand.teal,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              color: featured ? const Color(0xffd4eee8) : PhyimacyBrand.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: featured ? Colors.white : PhyimacyBrand.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: GoogleFonts.inter(
              color: featured
                  ? const Color(0xffc1e4dc)
                  : const Color(0xff879895),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.sale,
    required this.seller,
    required this.canVoid,
    required this.onOpen,
    required this.onVoid,
  });

  final SaleRecord sale;
  final String seller;
  final bool canVoid;
  final VoidCallback onOpen;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final voided = sale.isVoided;
    final medicines = sale.itemNames.isEmpty
        ? S.t('Open for the full list', 'Fungua kuona orodha kamili')
        : sale.itemNames.join(' · ');
    return ListTile(
      onTap: onOpen,
      isThreeLine: voided,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: voided
            ? const Color(0xffffeadf)
            : const Color(0xffdff7ee),
        child: Icon(
          voided ? Icons.undo_rounded : Icons.receipt_long_rounded,
          color: voided ? const Color(0xffc2410c) : PhyimacyBrand.teal,
        ),
      ),
      title: Text(
        medicines,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: voided ? PhyimacyBrand.muted : PhyimacyBrand.ink,
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        voided
            ? '${sale.receiptNumber}  ·  $seller  ·  ${_when(sale.createdAt)}\n${S.t('Voided', 'Imefutwa')} ${_when(sale.voidedAt)}${sale.voidedByName.trim().isEmpty ? '' : '  ·  ${sale.voidedByName.trim()}'}'
            : '${sale.receiptNumber}  ·  $seller  ·  ${sale.paymentMethod.toUpperCase()}  ·  ${_when(sale.createdAt)}',
        maxLines: 2,
        style: TextStyle(
          color: voided ? const Color(0xffc2410c) : PhyimacyBrand.muted,
          fontSize: 12,
          height: 1.35,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                voided
                    ? S.t('Reversed', 'Imerejeshwa')
                    : 'TZS ${sale.totalMinor}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: voided ? const Color(0xffc2410c) : PhyimacyBrand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: voided
                      ? const Color(0xffffeadf)
                      : const Color(0xffdff7ee),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  voided ? S.t('Voided', 'Imefutwa') : S.t('Sold', 'Imeuzwa'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: voided
                        ? const Color(0xffc2410c)
                        : PhyimacyBrand.teal,
                  ),
                ),
              ),
            ],
          ),
          if (canVoid)
            TextButton(onPressed: onVoid, child: Text(S.t('Void', 'Futa'))),
        ],
      ),
    );
  }
}

class _SaleDetailDialog extends StatelessWidget {
  const _SaleDetailDialog({required this.sale, required this.seller});

  final SaleRecord sale;
  final String seller;

  @override
  Widget build(BuildContext context) {
    final voided = sale.isVoided;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 560,
        child: FutureBuilder<List<SaleLine>>(
          future: SalesService().saleLines(sale.id),
          builder: (context, snapshot) {
            final lines = snapshot.data ?? const <SaleLine>[];
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sale.receiptNumber,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: PhyimacyBrand.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: voided
                            ? const Color(0xffffeadf)
                            : const Color(0xffdff7ee),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        voided
                            ? S.t(
                                'Voided — not counted as a sale',
                                'Imefutwa — haihesabiwi kama mauzo',
                              )
                            : S.t('Sold', 'Imeuzwa'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: voided
                              ? const Color(0xffc2410c)
                              : PhyimacyBrand.teal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _line(S.t('Sold by', 'Aliuza'), seller),
                  _line(S.t('Sold at', 'Imeuzwa saa'), _when(sale.createdAt)),
                  _line(
                    S.t('Payment', 'Malipo'),
                    sale.paymentMethod.toUpperCase(),
                  ),
                  if (voided) ...[
                    _line(
                      S.t('Voided at', 'Imefutwa saa'),
                      _when(sale.voidedAt),
                    ),
                    if (sale.voidedByName.trim().isNotEmpty)
                      _line(
                        S.t('Voided by', 'Alifuta'),
                        sale.voidedByName.trim(),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    S.t('Items', 'Bidhaa'),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: PhyimacyBrand.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (lines.isEmpty)
                    Text(
                      sale.itemNames.isEmpty
                          ? S.t(
                              'No item lines saved.',
                              'Hakuna mistari ya bidhaa.',
                            )
                          : sale.itemNames.join('\n'),
                      style: GoogleFonts.inter(
                        color: PhyimacyBrand.muted,
                        height: 1.4,
                      ),
                    )
                  else
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: PhyimacyBrand.ink,
                                ),
                              ),
                            ),
                            Text(
                              '${line.quantity}${line.unit.isEmpty ? '' : ' ${line.unit}'}',
                              style: const TextStyle(
                                color: PhyimacyBrand.muted,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'TZS ${line.totalMinor}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  const Divider(height: 28),
                  _money(S.t('Subtotal', 'Jumla ndogo'), sale.subtotalMinor),
                  if (sale.discountMinor > 0)
                    _money(S.t('Discount', 'Punguzo'), sale.discountMinor),
                  _money(S.t('Total', 'Jumla'), sale.totalMinor, strong: true),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(S.t('Close', 'Funga')),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: PhyimacyBrand.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: PhyimacyBrand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _money(String label, int value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              color: PhyimacyBrand.muted,
            ),
          ),
          Text(
            'TZS $value',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: strong ? 18 : 14,
              color: PhyimacyBrand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

String _when(DateTime? value) {
  if (value == null) return '—';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day/$month/${value.year}  $hour:$minute';
}
