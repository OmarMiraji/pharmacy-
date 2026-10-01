import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/medicine_service.dart';
import '../backend/models.dart';
import '../backend/shop_alerts.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import 'app_notice.dart';

class ShopAlertBell extends StatefulWidget {
  const ShopAlertBell({this.onOpenExpired, super.key});

  final VoidCallback? onOpenExpired;

  @override
  State<ShopAlertBell> createState() => _ShopAlertBellState();
}

class _ShopAlertBellState extends State<ShopAlertBell> {
  var _toasted = false;

  void _maybeToast(List<ShopAlert> alerts) {
    if (_toasted) return;
    _toasted = true;
    final expired = alerts.where((alert) => alert.kind == ShopAlertKind.expired).length;
    final soon = alerts.where((alert) => alert.kind == ShopAlertKind.expiringSoon).length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (expired > 0) {
        showAppNotice(
          context,
          S.t(
            '$expired medicine${expired == 1 ? '' : 's'} already expired. Open notifications.',
            'Dawa $expired zimeshaisha muda. Fungua arifa.',
          ),
          kind: AppNoticeKind.warning,
        );
      } else if (soon > 0) {
        showAppNotice(
          context,
          S.t(
            '$soon medicine${soon == 1 ? '' : 's'} expire within 2 months.',
            'Dawa $soon zinaisha ndani ya miezi 2.',
          ),
          kind: AppNoticeKind.warning,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = MedicineService();
    return StreamBuilder<List<Medicine>>(
      stream: service.watchMedicines(),
      builder: (context, medicineSnapshot) {
        return StreamBuilder<List<MedicineBatch>>(
          stream: service.watchAllBatches(),
          builder: (context, batchSnapshot) {
            final alerts = ShopAlerts.fromStock(
              medicineSnapshot.data ?? const <Medicine>[],
              batchSnapshot.data ?? const <MedicineBatch>[],
            );
            if (medicineSnapshot.hasData && batchSnapshot.hasData) {
              _maybeToast(alerts);
            }
            final count = alerts.length;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: IconButton(
                tooltip: count == 0 ? S.t('No stock alerts', 'Hakuna arifa za stock') : '$count ${S.t('stock alerts', 'arifa za stock')}',
                onPressed: () => _openInbox(context, alerts),
                icon: Badge(
                  isLabelVisible: count > 0,
                  backgroundColor: const Color(0xffc2410c),
                  label: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                  child: Icon(
                    count > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                    color: count > 0 ? const Color(0xffc2410c) : PhyimacyBrand.ink,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openInbox(BuildContext context, List<ShopAlert> alerts) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 460,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xffffeadf),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.notifications_active_rounded, color: Color(0xffc2410c)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.t('Stock alerts', 'Arifa za stock'),
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: PhyimacyBrand.ink,
                              ),
                            ),
                            Text(
                              alerts.isEmpty
                                  ? S.t('No expiry warnings right now', 'Hakuna onyo la kuisha sasa')
                                  : S.t(
                                      '${alerts.length} notice${alerts.length == 1 ? '' : 's'} · 2-month warning and expired stock',
                                      'Arifa ${alerts.length} · onyo la miezi 2 na dawa zilizoisha',
                                    ),
                              style: GoogleFonts.inter(fontSize: 12, color: PhyimacyBrand.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: alerts.isEmpty
                      ? Center(
                          child: Text(
                            S.t('No stock expires within 2 months.', 'Hakuna stock inayoisha ndani ya miezi 2.'),
                            style: GoogleFonts.inter(color: PhyimacyBrand.muted),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: alerts.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final alert = alerts[index];
                            final expired = alert.kind == ShopAlertKind.expired;
                            return Material(
                              color: expired ? const Color(0xffffeadf) : const Color(0xfffff0d7),
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                leading: Icon(
                                  expired ? Icons.event_busy_rounded : Icons.hourglass_bottom_rounded,
                                  color: const Color(0xffc2410c),
                                ),
                                title: Text(
                                  alert.title,
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff9a3412)),
                                ),
                                subtitle: Text(
                                  alert.body,
                                  style: const TextStyle(height: 1.35, color: Color(0xff9a3412)),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (alerts.any((alert) => alert.kind == ShopAlertKind.expired) && widget.onOpenExpired != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        widget.onOpenExpired!();
                      },
                      icon: const Icon(Icons.event_busy_rounded, size: 18),
                      label: Text(S.t('Open expired stock', 'Fungua stock iliyoisha')),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
