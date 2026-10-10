import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/login_log_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

class LoginLogsScreen extends StatefulWidget {
  const LoginLogsScreen({
    this.pharmacyId,
    this.excludeActorUid,
    this.canDelete = false,
    super.key,
  });

  /// When set, only this shop is shown. Super admin leaves this empty to see every shop.
  final String? pharmacyId;

  /// Super admin passes their own user id so their sign-in rows stay hidden.
  final String? excludeActorUid;

  final bool canDelete;

  @override
  State<LoginLogsScreen> createState() => _LoginLogsScreenState();
}

class _LoginLogsScreenState extends State<LoginLogsScreen> {
  final _selected = <String>{};
  var _busy = false;

  String _when(DateTime? value) {
    if (value == null) return '—';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/${value.year}  $hour:$minute';
  }

  String _role(String role) {
    return switch (role.trim().toLowerCase()) {
      'super_admin' => S.t('Super admin', 'Super admin'),
      'admin' => S.t('Admin', 'Admin'),
      'pharmacist' => S.t('Pharmacist', 'Mfamasia'),
      'cashier' => S.t('Cashier', 'Keshia'),
      'storekeeper' => S.t('Storekeeper', 'Mhifadhi'),
      '' => '—',
      _ => role,
    };
  }

  List<LoginEvent> _visible(List<LoginEvent> rows) {
    final hidden = (widget.excludeActorUid ?? '').trim();
    return rows.where((row) {
      if (row.role.trim().toLowerCase() == 'super_admin') return false;
      if (hidden.isNotEmpty && row.actorUid == hidden) return false;
      return true;
    }).toList();
  }

  Future<void> _deleteIds(List<String> ids) async {
    if (ids.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await LoginLogService().deleteByIds(ids);
      if (!mounted) return;
      setState(() => _selected.removeAll(ids));
      showAppNotice(context, S.t('Login records deleted.', 'Kumbukumbu za kuingia zimefutwa.'));
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    if (_busy) return;
    final shopOnly = (widget.pharmacyId ?? '').trim().isNotEmpty;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Delete all login records?', 'Futa kumbukumbu zote za kuingia?')),
        content: Text(
          shopOnly
              ? S.t('This removes every sign-in and sign-out saved for this shop.', 'Hii inaondoa kila kuingia na kutoka iliyohifadhiwa kwa duka hili.')
              : S.t('This removes every sign-in and sign-out saved for all shops.', 'Hii inaondoa kila kuingia na kutoka iliyohifadhiwa kwa maduka yote.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete all', 'Futa zote'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await LoginLogService().deleteAll(pharmacyId: shopOnly ? widget.pharmacyId : null);
      if (!mounted) return;
      setState(_selected.clear);
      showAppNotice(context, S.t('All login records deleted.', 'Kumbukumbu zote za kuingia zimefutwa.'));
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected(List<LoginEvent> rows) async {
    final ids = _selected.where((id) => rows.any((row) => row.id == id)).toList();
    if (ids.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Delete selected records?', 'Futa kumbukumbu zilizochaguliwa?')),
        content: Text(S.t('${ids.length} sign-in records will be removed.', 'Kumbukumbu ${ids.length} za kuingia zitaondolewa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete', 'Futa'))),
        ],
      ),
    );
    if (confirm == true) await _deleteIds(ids);
  }

  @override
  Widget build(BuildContext context) {
    final shopOnly = (widget.pharmacyId ?? '').trim().isNotEmpty;
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 640.0;
            return SizedBox(
              height: height < 280 ? 640 : height,
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shopOnly
                  ? S.t(
                      'Sign-in and sign-out times for this shop. Select rows to delete one by one, or delete all.',
                      'Muda wa kuingia na kutoka kwa duka hili. Chagua mistari kufuta moja moja, au futa zote.',
                    )
                  : S.t(
                      'Sign-in and sign-out times for every shop user except your own account.',
                      'Muda wa kuingia na kutoka kwa watumiaji wote wa maduka isipokuwa akaunti yako.',
                    ),
              style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.45),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<LoginEvent>>(
                stream: LoginLogService().watch(pharmacyId: shopOnly ? widget.pharmacyId : null),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      S.t('Could not load login times. Publish the latest Firestore rules, then sign in again.', 'Imeshindwa kupakia muda wa kuingia. Chapisha rules mpya za Firestore, kisha ingia tena.'),
                      style: GoogleFonts.inter(color: const Color(0xffb42318), height: 1.4),
                    );
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final rows = _visible(snapshot.data!);
                  final visibleIds = rows.map((row) => row.id).toSet();
                  final selectedCount = _selected.where(visibleIds.contains).length;
                  final allSelected = rows.isNotEmpty && selectedCount == rows.length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.canDelete)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy || selectedCount == 0 ? null : () => _deleteSelected(rows),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: Text(S.t('Delete selected', 'Futa zilizochaguliwa')),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: const Color(0xffb42318)),
                                onPressed: _busy || rows.isEmpty ? null : _deleteAll,
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label: Text(_busy ? S.t('Deleting...', 'Inafuta...') : S.t('Delete all', 'Futa zote')),
                              ),
                            ],
                          ),
                        ),
                      if (rows.isEmpty)
                        Text(
                          S.t('No sign-in records yet. They appear after the next staff login and logout.', 'Bado hakuna kumbukumbu. Zitaonekana baada ya staff kuingia na kutoka.'),
                          style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.4),
                        )
                      else
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xffedf2f2)),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: const BoxDecoration(
                                    color: PhyimacyBrand.forest,
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                  ),
                                  child: Row(
                                    children: [
                                      if (widget.canDelete)
                                        SizedBox(
                                          width: 42,
                                          child: Checkbox(
                                            value: selectedCount == 0 ? false : (allSelected ? true : null),
                                            tristate: true,
                                            activeColor: PhyimacyBrand.gold,
                                            side: const BorderSide(color: Colors.white),
                                            onChanged: _busy
                                                ? null
                                                : (value) {
                                                    setState(() {
                                                      if (value == true) {
                                                        _selected.addAll(visibleIds);
                                                      } else {
                                                        _selected.removeAll(visibleIds);
                                                      }
                                                    });
                                                  },
                                          ),
                                        ),
                                      _head(S.t('When', 'Lini'), 18),
                                      _head(S.t('Name', 'Jina'), 18),
                                      _head(S.t('Email', 'Barua pepe'), 22),
                                      if (!shopOnly) _head(S.t('Shop', 'Duka'), 16),
                                      _head(S.t('Role', 'Cheo'), 12),
                                      _head(S.t('Action', 'Kitendo'), 14),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: rows.length,
                                    itemBuilder: (context, index) {
                                      final row = rows[index];
                                      final signedIn = row.isLogin;
                                      final name = row.actorName.trim().isEmpty ? row.actorEmail : row.actorName.trim();
                                      final picked = _selected.contains(row.id);
                                      return InkWell(
                                        onTap: !widget.canDelete || _busy
                                            ? null
                                            : () => setState(() {
                                                  if (picked) {
                                                    _selected.remove(row.id);
                                                  } else {
                                                    _selected.add(row.id);
                                                  }
                                                }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          color: picked ? const Color(0xffe7f6f2) : (index.isOdd ? const Color(0xfff7f4ec) : Colors.white),
                                          child: Row(
                                            children: [
                                              if (widget.canDelete)
                                                SizedBox(
                                                  width: 42,
                                                  child: Checkbox(
                                                    value: picked,
                                                    activeColor: PhyimacyBrand.teal,
                                                    onChanged: _busy
                                                        ? null
                                                        : (value) => setState(() {
                                                              if (value == true) {
                                                                _selected.add(row.id);
                                                              } else {
                                                                _selected.remove(row.id);
                                                              }
                                                            }),
                                                  ),
                                                ),
                                              _value(_when(row.createdAt), 18, strong: true),
                                              _value(name, 18, strong: true),
                                              _value(row.actorEmail.trim().isEmpty ? '—' : row.actorEmail, 22),
                                              if (!shopOnly) _value(row.pharmacyName.trim().isEmpty ? '—' : row.pharmacyName, 16),
                                              _value(_role(row.role), 12),
                                              Expanded(
                                                flex: 14,
                                                child: Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                    decoration: BoxDecoration(
                                                      color: (signedIn ? PhyimacyBrand.teal : const Color(0xffb45309)).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      signedIn ? S.t('Signed in', 'Aliingia') : S.t('Signed out', 'Alitoka'),
                                                      style: TextStyle(
                                                        color: signedIn ? PhyimacyBrand.teal : const Color(0xffb45309),
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

  Widget _head(String label, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(color: PhyimacyBrand.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }

  Widget _value(String text, int flex, {bool strong = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: strong ? PhyimacyBrand.ink : PhyimacyBrand.muted,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}
