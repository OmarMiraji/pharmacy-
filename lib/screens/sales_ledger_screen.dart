import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/sales_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class SalesLedgerScreen extends StatelessWidget {
  const SalesLedgerScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final canLookupNames = profile.role == 'admin' || profile.isSuperAdmin;
    return StreamBuilder<List<UserProfile>>(
      stream: canLookupNames ? UserManagementService().watchUsers(pharmacyId: profile.pharmacyId) : Stream.value(const <UserProfile>[]),
      builder: (context, usersSnapshot) {
        final names = <String, String>{
          for (final user in usersSnapshot.data ?? const <UserProfile>[])
            if (user.displayName.trim().isNotEmpty) user.id: user.displayName.trim(),
        };
        return StreamBuilder<List<SaleRecord>>(
          stream: SalesService().watchSales(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(S.t('Could not load sales.', 'Imeshindwa kupakia mauzo.')));
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final sales = snapshot.data!;
            final live = sales.where((sale) => !sale.isVoided).toList();
            final voided = sales.where((sale) => sale.isVoided).toList();
            final liveTotal = live.fold<int>(0, (total, sale) => total + sale.totalMinor);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _summary(S.t('Completed sales', 'Mauzo yaliyokamilika'), '${live.length}', S.t('Counted as sold', 'Yanahesabiwa kuwa yameuzwa'), const Color(0xffdff7ee))),
                    const SizedBox(width: 12),
                    Expanded(child: _summary(S.t('Sales total', 'Jumla ya mauzo'), 'TZS $liveTotal', S.t('Voided sales are left out', 'Yaliyofutwa hayajaingizwa'), const Color(0xffe2efff))),
                    const SizedBox(width: 12),
                    Expanded(child: _summary(S.t('Voided', 'Yaliyofutwa'), '${voided.length}', S.t('Stock returned, not a sale', 'Stock imerudishwa, si mauzo'), const Color(0xffffeadf))),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: sales.isEmpty
                      ? Center(
                          child: Text(
                            S.t('No sales yet. Completed receipts appear here with the person who sold them.', 'Bado hakuna mauzo. Risiti zilizokamilika zitaonekana hapa pamoja na aliyewauza.'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.4),
                          ),
                        )
                      : Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          clipBehavior: Clip.antiAlias,
                          elevation: 2,
                          shadowColor: const Color(0x14073B3A),
                          child: ListView.separated(
                            itemCount: sales.length,
                            separatorBuilder: (_, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final sale = sales[index];
                              return _SaleTile(
                                sale: sale,
                                seller: _seller(sale, names),
                                canVoid: profile.can('sales.refund') && !sale.isVoided,
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

  String _seller(SaleRecord sale, Map<String, String> names) {
    final stored = sale.soldByName.trim();
    if (stored.isNotEmpty) return stored;
    final lookedUp = names[sale.soldBy];
    if (lookedUp != null && lookedUp.isNotEmpty) return lookedUp;
    if (sale.soldBy == profile.id && profile.displayName.trim().isNotEmpty) return profile.displayName.trim();
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
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Void sale', 'Futa mauzo'))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final name = profile.displayName.trim().isNotEmpty ? profile.displayName.trim() : profile.email;
      await SalesService().voidSale(
        sale.id,
        voidedBy: AuthService().currentUser?.uid ?? profile.id,
        voidedByName: name,
      );
      if (!context.mounted) return;
      showAppNotice(context, S.t('Sale voided. It is no longer counted as sold.', 'Mauzo yamefutwa. Hayahahesabiwi tena kama yameuzwa.'));
    } catch (error) {
      if (context.mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  }

  Future<void> _openDetail(BuildContext context, SaleRecord sale, Map<String, String> names) async {
    final seller = _seller(sale, names);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SaleDetailDialog(sale: sale, seller: seller),
    );
  }

  Widget _summary(String label, String value, String note, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 16, offset: Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long_rounded, size: 18, color: PhyimacyBrand.teal)),
          const SizedBox(height: 10),
          Text(label, style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          const SizedBox(height: 2),
          Text(note, style: GoogleFonts.inter(color: const Color(0xff879895), fontSize: 11)),
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
    final medicines = sale.itemNames.isEmpty ? S.t('Open for the full list', 'Fungua kuona orodha kamili') : sale.itemNames.join(' · ');
    return ListTile(
      onTap: onOpen,
      isThreeLine: voided,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: voided ? const Color(0xffffeadf) : const Color(0xffdff7ee),
        child: Icon(voided ? Icons.undo_rounded : Icons.receipt_long_rounded, color: voided ? const Color(0xffc2410c) : PhyimacyBrand.teal),
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
        style: TextStyle(color: voided ? const Color(0xffc2410c) : PhyimacyBrand.muted, fontSize: 12, height: 1.35),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('TZS ${sale.totalMinor}', style: TextStyle(fontWeight: FontWeight.w800, color: voided ? PhyimacyBrand.muted : PhyimacyBrand.ink, decoration: voided ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: voided ? const Color(0xffffeadf) : const Color(0xffdff7ee),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  voided ? S.t('Voided', 'Imefutwa') : S.t('Sold', 'Imeuzwa'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: voided ? const Color(0xffc2410c) : PhyimacyBrand.teal),
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
                      Expanded(child: Text(sale.receiptNumber, style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: voided ? const Color(0xffffeadf) : const Color(0xffdff7ee), borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        voided ? S.t('Voided — not counted as a sale', 'Imefutwa — haihesabiwi kama mauzo') : S.t('Sold', 'Imeuzwa'),
                        style: TextStyle(fontWeight: FontWeight.w800, color: voided ? const Color(0xffc2410c) : PhyimacyBrand.teal),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _line(S.t('Sold by', 'Aliuza'), seller),
                  _line(S.t('Sold at', 'Imeuzwa saa'), _when(sale.createdAt)),
                  _line(S.t('Payment', 'Malipo'), sale.paymentMethod.toUpperCase()),
                  if (voided) ...[
                    _line(S.t('Voided at', 'Imefutwa saa'), _when(sale.voidedAt)),
                    if (sale.voidedByName.trim().isNotEmpty) _line(S.t('Voided by', 'Alifuta'), sale.voidedByName.trim()),
                  ],
                  const SizedBox(height: 12),
                  Text(S.t('Items', 'Bidhaa'), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                  else if (lines.isEmpty)
                    Text(
                      sale.itemNames.isEmpty ? S.t('No item lines saved.', 'Hakuna mistari ya bidhaa.') : sale.itemNames.join('\n'),
                      style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.4),
                    )
                  else
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(line.name, style: const TextStyle(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
                            Text('${line.quantity}${line.unit.isEmpty ? '' : ' ${line.unit}'}', style: const TextStyle(color: PhyimacyBrand.muted)),
                            const SizedBox(width: 16),
                            Text('TZS ${line.totalMinor}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                  const Divider(height: 28),
                  _money(S.t('Subtotal', 'Jumla ndogo'), sale.subtotalMinor),
                  if (sale.discountMinor > 0) _money(S.t('Discount', 'Punguzo'), sale.discountMinor),
                  _money(S.t('Total', 'Jumla'), sale.totalMinor, strong: true),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: Text(S.t('Close', 'Funga')))),
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
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: PhyimacyBrand.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
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
          Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500, color: PhyimacyBrand.muted)),
          Text('TZS $value', style: TextStyle(fontWeight: FontWeight.w800, fontSize: strong ? 18 : 14, color: PhyimacyBrand.ink)),
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
