import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../backend/firestore_collections.dart';
import '../backend/system_control_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';
import 'staff_account_dialogs.dart';

class EmergencyToolsScreen extends StatefulWidget {
  const EmergencyToolsScreen({super.key});

  @override
  State<EmergencyToolsScreen> createState() => _EmergencyToolsScreenState();
}

class _EmergencyToolsScreenState extends State<EmergencyToolsScreen> {
  final _control = SystemControlService.instance;
  final _message = TextEditingController();
  final _minBuild = TextEditingController();
  final _email = TextEditingController();
  var _busy = false;
  UserProfile? _found;
  String? _findNote;

  @override
  void initState() {
    super.initState();
    _message.text = _control.config.value.message;
    final min = _control.config.value.minBuild;
    _minBuild.text = min > 0 ? '$min' : '';
  }

  @override
  void dispose() {
    _message.dispose();
    _minBuild.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showAppNotice(context, done);
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMaintenance(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(S.t('Turn on maintenance mode?', 'Washa maintenance mode?')),
          content: Text(S.t(
            'Every shop user is moved to a maintenance screen right away and cannot work until you turn it off. Super admins keep full access.',
            'Kila mtumiaji wa duka atapelekwa kwenye skrini ya matengenezo papo hapo na hataweza kufanya kazi mpaka uizime. Super admin wanaendelea kama kawaida.',
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Turn on', 'Washa'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(
      () => _control.setMaintenance(on: on, message: _message.text),
      on
          ? S.t('Maintenance mode is ON.', 'Maintenance mode imewashwa.')
          : S.t('Maintenance mode is off. Shops can work again.', 'Maintenance mode imezimwa. Maduka yanaendelea.'),
    );
  }

  Future<void> _findUser() async {
    final mail = _email.text.trim().toLowerCase();
    if (!mail.contains('@')) return;
    setState(() {
      _found = null;
      _findNote = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .where('email', isEqualTo: mail)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        if (snap.docs.isEmpty) {
          _findNote = S.t('No login uses that email.', 'Hakuna login yenye email hiyo.');
        } else {
          _found = UserProfile.fromFirestore(snap.docs.first);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _findNote = friendlyActionError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SystemControl>(
      valueListenable: _control.config,
      builder: (context, config, _) {
        final thisBuild = _control.installedBuild.value ?? 0;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.t('Emergency tools', 'Zana za dharura'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
              const SizedBox(height: 6),
              Text(
                S.t('Use these when something goes wrong. Every change is saved in Security activity.',
                    'Tumia hizi tatizo likitokea. Kila badiliko linarekodiwa kwenye Shughuli za usalama.'),
                style: const TextStyle(color: Color(0xff68807d)),
              ),
              const SizedBox(height: 16),
              _card(
                icon: Icons.logout_rounded,
                title: S.t('Sign a login out of every device', 'Mtoe mtumiaji kwenye vifaa vyote'),
                body: S.t(
                  'For a lost phone, a stolen password, or a staff member who has left. The open app closes within seconds.',
                  'Kwa simu iliyopotea, nenosiri lililoibiwa, au staff aliyeondoka. App iliyo wazi inafungwa ndani ya sekunde chache.',
                ),
                children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        onSubmitted: (_) => _findUser(),
                        decoration: InputDecoration(labelText: S.t('Login email', 'Email ya login'), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(onPressed: _findUser, child: Text(S.t('Find', 'Tafuta'))),
                  ]),
                  if (_findNote != null) ...[
                    const SizedBox(height: 8),
                    Text(_findNote!, style: const TextStyle(color: Color(0xffb42318))),
                  ],
                  if (_found != null) ...[
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(_found!.displayName.isEmpty ? _found!.email : _found!.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${_found!.email}  •  ${_found!.role}  •  ${_found!.isActive ? S.t('Active', 'Hai') : S.t('Disabled', 'Imefungwa')}'),
                      trailing: _found!.isSuperAdmin
                          ? const ProtectedSuperAdminBadge()
                          : ForceSignOutButton(user: _found!, onDone: _findUser),
                    ),
                  ],
                ],
              ),
              _card(
                icon: Icons.construction_rounded,
                title: S.t('Maintenance mode', 'Maintenance mode'),
                body: S.t(
                  'Stops every shop user from working (for example during a serious problem or a data repair). Super admins are not affected.',
                  'Inasimamisha kila mtumiaji wa duka (mfano wakati wa tatizo kubwa au kurekebisha data). Super admin hawaathiriwi.',
                ),
                children: [
                  TextField(
                    controller: _message,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: S.t('Message shown to users (optional)', 'Ujumbe kwa watumiaji (si lazima)'),
                      hintText: S.t('We are fixing a problem. Back by 3:00 PM.', 'Tunarekebisha tatizo. Tutarudi saa 9:00 mchana.'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: config.maintenance,
                    onChanged: _busy ? null : _toggleMaintenance,
                    title: Text(
                      config.maintenance
                          ? S.t('ON: shops are stopped', 'IMEWASHWA: maduka yamesimamishwa')
                          : S.t('Off: shops are working', 'Imezimwa: maduka yanafanya kazi'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: config.maintenance ? const Color(0xffb42318) : const Color(0xff0f766e),
                      ),
                    ),
                  ),
                  if (config.maintenance)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => _control.setMaintenance(on: true, message: _message.text),
                                S.t('Message updated.', 'Ujumbe umesasishwa.')),
                        child: Text(S.t('Update message', 'Sasisha ujumbe')),
                      ),
                    ),
                ],
              ),
              _card(
                icon: Icons.system_update_alt_rounded,
                title: S.t('Require an app update', 'Lazimisha update'),
                body: S.t(
                  'Older apps stop and ask to update before continuing. The build number is the part after "+" in the version, e.g. 1.0.37+39 → 39.',
                  'App za zamani zinasimama na kuomba update kabla ya kuendelea. Build number ni namba baada ya "+" kwenye toleo, mfano 1.0.37+39 → 39.',
                ),
                children: [
                  Text(
                    config.minBuild > 0
                        ? S.t('Now required: ${config.minVersion.isEmpty ? '' : '${config.minVersion} '}(build ${config.minBuild})',
                            'Sasa inahitajika: ${config.minVersion.isEmpty ? '' : '${config.minVersion} '}(build ${config.minBuild})')
                        : S.t('No minimum version is set.', 'Hakuna toleo la lazima.'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _minBuild,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: S.t('Minimum build', 'Build ya chini'), isDense: true),
                        ),
                      ),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () {
                                final value = int.tryParse(_minBuild.text.trim()) ?? 0;
                                if (value <= 0) return;
                                _run(
                                  () => _control.setMinimumBuild(
                                    build: value,
                                    version: value == thisBuild ? _control.installedVersion : '',
                                  ),
                                  S.t('Older apps must now update.', 'App za zamani lazima zifanye update sasa.'),
                                );
                              },
                        child: Text(S.t('Require', 'Lazimisha')),
                      ),
                      if (thisBuild > 0)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _minBuild.text = '$thisBuild';
                                  _run(
                                    () => _control.setMinimumBuild(build: thisBuild, version: _control.installedVersion),
                                    S.t('Everyone must now use ${_control.installedVersion} or newer.',
                                        'Kila mtu lazima atumie ${_control.installedVersion} au jipya zaidi.'),
                                  );
                                },
                          child: Text(S.t('Use this version (${_control.installedVersion}+$thisBuild)',
                              'Tumia toleo hili (${_control.installedVersion}+$thisBuild)')),
                        ),
                      if (config.minBuild > 0)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _minBuild.clear();
                                  _run(() => _control.setMinimumBuild(build: 0, version: ''),
                                      S.t('Update requirement removed.', 'Lazima ya update imeondolewa.'));
                                },
                          child: Text(S.t('Remove requirement', 'Ondoa lazima')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.t('Only require a version after its Windows and Android builds have finished publishing.',
                        'Lazimisha toleo tu baada ya build zake za Windows na Android kukamilika kuchapishwa.'),
                    style: const TextStyle(fontSize: 12, color: Color(0xffb54708)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card({required IconData icon, required String title, required String body, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: const Color(0xff0f766e)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: PhyimacyBrand.ink))),
          ]),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Color(0xff68807d), height: 1.4)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
