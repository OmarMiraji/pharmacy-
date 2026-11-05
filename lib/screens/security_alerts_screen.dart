import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../backend/security_alert_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class SecurityAlertsScreen extends StatefulWidget {
  const SecurityAlertsScreen({super.key});

  @override
  State<SecurityAlertsScreen> createState() => _SecurityAlertsScreenState();
}

class _SecurityAlertsScreenState extends State<SecurityAlertsScreen> {
  final _service = SecurityAlertService();
  late final Stream<List<SecurityAlert>> _unread = _service.watchUnread();
  final _rows = <SecurityAlert>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  var _hasMore = false;
  var _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (rows, cursor, hasMore) = await _service.fetch(after: reset ? null : _cursor);
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(rows);
        _cursor = cursor;
        _hasMore = hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyActionError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(SecurityAlert alert) async {
    try {
      await _service.markRead(alert.id);
      if (!mounted) return;
      setState(() {
        final i = _rows.indexWhere((row) => row.id == alert.id);
        if (i >= 0) _rows[i] = alert.copyRead();
      });
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  }

  Future<void> _markAll(List<SecurityAlert> unread) async {
    if (unread.isEmpty) return;
    try {
      await _service.markAllRead(unread.map((row) => row.id));
      if (!mounted) return;
      await _load(reset: true);
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  }

  String _when(DateTime? value) {
    if (value == null) return S.t('just now', 'sasa hivi');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}  ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SecurityAlert>>(
      stream: _unread,
      builder: (context, snapshot) {
        final unread = snapshot.data ?? const <SecurityAlert>[];
        final critical = unread.where((row) => row.isCritical).length;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(S.t('Security alerts', 'Tahadhari za usalama'),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                  ),
                  IconButton.filledTonal(
                    tooltip: S.t('Refresh', 'Onyesha upya'),
                    onPressed: _loading ? null : () => _load(reset: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: unread.isEmpty ? null : () => _markAll(unread),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text(S.t('Mark all read', 'Zote nimeziona')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                S.t(
                  'Urgent alerts are also emailed to every super admin straight away, and a summary is emailed each morning at 7:00 when anything happened.',
                  'Tahadhari za dharura zinatumwa pia kwa email ya kila super admin papo hapo, na muhtasari unatumwa kila asubuhi saa 1:00 kama kuna kilichotokea.',
                ),
                style: const TextStyle(color: Color(0xff68807d), height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _stat(S.t('Unread', 'Hazijasomwa'), '${unread.length}', unread.isEmpty ? const Color(0xff0f766e) : const Color(0xffb54708)),
                  _stat(S.t('Urgent unread', 'Za dharura'), '$critical', critical == 0 ? const Color(0xff0f766e) : const Color(0xffb42318)),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xffb42318))),
              if (_rows.isEmpty && _loading)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(S.t('No alerts. The system looks calm.', 'Hakuna tahadhari. Mfumo uko shwari.'),
                        style: const TextStyle(color: Color(0xff68807d))),
                  ),
                )
              else
                for (final row in _rows) _tile(row),
              if (_hasMore)
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _load(),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(S.t('Load older', 'Pakia za zamani zaidi')),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff68807d))),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _tile(SecurityAlert row) {
    final color = row.isCritical ? const Color(0xffb42318) : const Color(0xffb54708);
    final who = row.actorName.isNotEmpty ? '${row.actorName} <${row.actorEmail}>' : row.actorEmail;
    final meta = [
      if (who.trim().isNotEmpty) who,
      if (row.pharmacyName.isNotEmpty) row.pharmacyName,
      _when(row.createdAt),
      if (row.emailed) S.t('emailed', 'imetumwa email'),
    ].join('  •  ');
    return Opacity(
      opacity: row.read ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: row.read ? const Color(0xffe6ece9) : color.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(row.isCritical ? Icons.gpp_maybe_rounded : Icons.warning_amber_rounded, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(row.title, style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          row.isCritical ? S.t('Urgent', 'Dharura') : S.t('Warning', 'Onyo'),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                        ),
                      ),
                    ],
                  ),
                  if (row.message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(row.message, style: const TextStyle(color: Color(0xff183b3b), height: 1.35)),
                  ],
                  const SizedBox(height: 4),
                  Text(meta, style: const TextStyle(fontSize: 12, color: Color(0xff68807d))),
                ],
              ),
            ),
            if (!row.read)
              TextButton(onPressed: () => _markRead(row), child: Text(S.t('Seen', 'Nimeona'))),
          ],
        ),
      ),
    );
  }
}
