import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/auth_service.dart';
import '../backend/temp_password.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../widgets/app_notice.dart';

Future<void> showChangeOwnPasswordDialog(BuildContext context) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  var hideCurrent = true;
  var hideNext = true;
  var hideConfirm = true;
  try {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
          title: Text(S.t('Change my password', 'Badilisha nenosiri langu')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(S.t(
                  'Enter your current password, then choose a new one. This only changes the password for the account you are signed in with.',
                  'Weka nenosiri la sasa, kisha chagua jipya. Hii inabadilisha nenosiri la akaunti uliyoingia nayo tu.',
                )),
                const SizedBox(height: 12),
                TextField(
                  controller: current,
                  obscureText: hideCurrent,
                  decoration: passwordInputDecoration(
                    label: S.t('Current password', 'Nenosiri la sasa'),
                    hidden: hideCurrent,
                    onToggle: () => setState(() => hideCurrent = !hideCurrent),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: next,
                  obscureText: hideNext,
                  onChanged: (_) => setState(() {}),
                  decoration: passwordInputDecoration(
                    label: S.t('New password (min ${AuthService.minOwnPasswordLength} characters)',
                        'Nenosiri jipya (angalau herufi ${AuthService.minOwnPasswordLength})'),
                    hidden: hideNext,
                    onToggle: () => setState(() => hideNext = !hideNext),
                    errorText: next.text.isNotEmpty && next.text.trim().length < AuthService.minOwnPasswordLength
                        ? S.t('Use at least ${AuthService.minOwnPasswordLength} characters.',
                            'Tumia herufi ${AuthService.minOwnPasswordLength} au zaidi.')
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirm,
                  obscureText: hideConfirm,
                  onChanged: (_) => setState(() {}),
                  decoration: passwordInputDecoration(
                    label: S.t('Confirm new password', 'Thibitisha nenosiri jipya'),
                    hidden: hideConfirm,
                    onToggle: () => setState(() => hideConfirm = !hideConfirm),
                    errorText: confirm.text.isNotEmpty && next.text != confirm.text
                        ? S.t('Passwords do not match.', 'Nenosiri hayafanani.')
                        : null,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
            FilledButton(
              onPressed: next.text.trim().length >= AuthService.minOwnPasswordLength && next.text == confirm.text
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(S.t('Save password', 'Hifadhi nenosiri')),
            ),
          ],
        );
          },
        );
      },
    );
    if (saved != true || !context.mounted) return;
    if (next.text.trim() != confirm.text.trim()) {
      if (context.mounted) {
        showAppNotice(
          context,
          S.t('Passwords do not match.', 'Nenosiri hayafanani.'),
          kind: AppNoticeKind.warning,
        );
      }
      return;
    }
    await AuthService().changeOwnPassword(currentPassword: current.text, newPassword: next.text);
    if (!context.mounted) return;
    showAppNotice(context, S.t('Your password has been updated.', 'Nenosiri lako limebadilishwa.'));
  } catch (error) {
    if (context.mounted) {
      showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  } finally {
    current.dispose();
    next.dispose();
    confirm.dispose();
  }
}

Future<void> showManagedPasswordDialog(BuildContext context, UserProfile target) async {
  final password = TextEditingController(text: TempPassword.generate());
  var saving = false;
  String? issued;
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(S.t('Password for ${target.displayName}', 'Nenosiri la ${target.displayName}')),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(target.email, style: const TextStyle(color: Color(0xff68807d))),
                    const SizedBox(height: 10),
                    PasswordStatusChip(user: target),
                    const SizedBox(height: 12),
                    Text(
                      S.t(
                        'Give them a new temporary password. They sign in with it once, then the app makes them choose their own.',
                        'Mpe nenosiri la muda. Ataingia nalo mara moja, kisha app itamlazimisha kuchagua lake.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TemporaryPasswordField(controller: password, onChanged: () => setState(() {})),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))),
                FilledButton(
                  onPressed: !saving && password.text.trim().length >= 6
                      ? () async {
                          setState(() => saving = true);
                          final next = password.text.trim();
                          try {
                            await UserManagementService().setLoginPassword(userId: target.id, password: next);
                            issued = next;
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          } catch (error) {
                            if (context.mounted) {
                              setState(() => saving = false);
                              showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
                            }
                          }
                        }
                      : null,
                  child: Text(saving ? S.t('Saving…', 'Inahifadhi…') : S.t('Set temporary password', 'Weka nenosiri la muda')),
                ),
              ],
            );
          },
        );
      },
    );
    final done = issued;
    if (done != null && context.mounted) {
      await showTemporaryPasswordReadyDialog(
        context,
        title: S.t('Temporary password is ready', 'Nenosiri la muda liko tayari'),
        email: target.email,
        password: done,
        note: S.t('Share these details with them. They will choose a new password after signing in.',
            'Wape taarifa hizi. Watachagua nenosiri jipya baada ya kuingia.'),
      );
    }
  } finally {
    password.dispose();
  }
}

Future<void> _copyText(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showAppNotice(context, done);
}

class TemporaryPasswordField extends StatelessWidget {
  const TemporaryPasswordField({required this.controller, required this.onChanged, super.key});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final value = controller.text.trim();
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
      decoration: InputDecoration(
        labelText: S.t('Temporary password', 'Nenosiri la muda'),
        helperText: S.t('They must change it the first time they sign in.', 'Atalazimika kulibadilisha mara ya kwanza akiingia.'),
        errorText: value.isNotEmpty && value.length < 6 ? S.t('Use at least 6 characters.', 'Tumia herufi 6 au zaidi.') : null,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: S.t('New password', 'Nenosiri jingine'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                controller.text = TempPassword.generate();
                onChanged();
              },
            ),
            IconButton(
              tooltip: S.t('Copy', 'Nakili'),
              icon: const Icon(Icons.copy_rounded),
              onPressed: value.isEmpty ? null : () => _copyText(context, value, S.t('Password copied', 'Nenosiri limenakiliwa')),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showTemporaryPasswordReadyDialog(
  BuildContext context, {
  required String title,
  required String email,
  required String password,
  String? note,
}) {
  final shareText = S.t(
    'PharmSpecio login\nEmail: $email\nTemporary password: $password\nYou will be asked to choose your own password after signing in.',
    'Login ya PharmSpecio\nEmail: $email\nNenosiri la muda: $password\nUtaombwa kuchagua nenosiri lako baada ya kuingia.',
  );
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.verified_user_outlined, color: Color(0xff0f766e)),
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null) ...[
              Text(note, style: const TextStyle(color: Color(0xff68807d), height: 1.4)),
              const SizedBox(height: 14),
            ],
            _CredentialRow(label: S.t('Email', 'Email'), value: email),
            const SizedBox(height: 8),
            _CredentialRow(label: S.t('Temporary password', 'Nenosiri la muda'), value: password, emphasize: true),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copyText(dialogContext, shareText, S.t('Login details copied', 'Taarifa za login zimenakiliwa')),
          icon: const Icon(Icons.copy_all_rounded, size: 18),
          label: Text(S.t('Copy all', 'Nakili zote')),
        ),
        FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Done', 'Sawa'))),
      ],
    ),
  );
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xfff2f8f6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffd7e7e4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xff68807d))),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: emphasize ? 18 : 14,
                    fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: emphasize ? 0.8 : 0,
                    color: const Color(0xff183b3b),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: S.t('Copy', 'Nakili'),
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () => _copyText(context, value, S.t('Copied', 'Imenakiliwa')),
          ),
        ],
      ),
    );
  }
}

/// Shows whether a login still uses the temporary password (with copy) or the owner has changed it.
class PasswordStatusChip extends StatelessWidget {
  const PasswordStatusChip({required this.user, super.key});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final temp = (user.tempPassword ?? '').trim();
    if (user.mustChangePassword) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xff9a6700)),
            backgroundColor: const Color(0xfffff6dd),
            side: const BorderSide(color: Color(0xfff1d58a)),
            label: Text(
              temp.isEmpty
                  ? S.t('Temporary password', 'Nenosiri la muda')
                  : S.t('Temporary: $temp', 'La muda: $temp'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xff6b4a00)),
            ),
          ),
          if (temp.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: S.t('Copy temporary password', 'Nakili nenosiri la muda'),
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () => _copyText(context, temp, S.t('Password copied', 'Nenosiri limenakiliwa')),
            ),
        ],
      );
    }
    if (user.passwordChangedAt != null) {
      return Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xff0f766e)),
        backgroundColor: const Color(0xffe7f6f1),
        side: const BorderSide(color: Color(0xffb9e0d6)),
        label: Text(
          S.t('Password changed', 'Nenosiri limebadilishwa'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xff0f5f58)),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Full-screen gate shown after sign-in while the account still uses an admin-issued password.
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({required this.profile, required this.onChanged, super.key});

  final UserProfile profile;
  final VoidCallback onChanged;

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  var _hideNext = true;
  var _hideConfirm = true;
  var _busy = false;
  late var _knowsTemp = (widget.profile.tempPassword ?? '').isNotEmpty;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _valid {
    final next = _next.text.trim();
    return next.length >= AuthService.minOwnPasswordLength &&
        next == _confirm.text.trim() &&
        (_knowsTemp || _current.text.isNotEmpty);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final auth = AuthService();
      await auth.changeOwnPassword(
        currentPassword: _knowsTemp ? widget.profile.tempPassword! : _current.text,
        newPassword: _next.text,
      );
      try {
        await auth.clearTemporaryPasswordFlag();
      } catch (_) {}
      if (!mounted) return;
      showAppNotice(context, S.t('Your new password is saved.', 'Nenosiri lako jipya limehifadhiwa.'));
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      if (_knowsTemp && '$error'.contains('Wrong password')) {
        setState(() {
          _busy = false;
          _knowsTemp = false;
        });
        showAppNotice(
          context,
          S.t('Enter the password you just used to sign in.', 'Weka nenosiri ulilotumia kuingia sasa hivi.'),
          kind: AppNoticeKind.warning,
        );
        return;
      }
      setState(() => _busy = false);
      showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = _next.text.trim();
    return Scaffold(
      backgroundColor: const Color(0xfff4f8f7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(color: Color(0xffd7e7e4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset_rounded, size: 44, color: Color(0xff0f766e)),
                      const SizedBox(height: 12),
                      Text(
                        S.t('Choose your own password', 'Chagua nenosiri lako'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        S.t(
                          'Hi ${widget.profile.displayName}, you signed in with a temporary password. Pick a new one that only you know before continuing.',
                          'Habari ${widget.profile.displayName}, umeingia kwa nenosiri la muda. Chagua jipya unalolijua wewe tu kabla ya kuendelea.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xff68807d), height: 1.45),
                      ),
                      const SizedBox(height: 18),
                      if (!_knowsTemp) ...[
                        TextField(
                          controller: _current,
                          obscureText: true,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(labelText: S.t('Temporary password', 'Nenosiri la muda')),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _next,
                        obscureText: _hideNext,
                        onChanged: (_) => setState(() {}),
                        decoration: passwordInputDecoration(
                          label: S.t('New password (min ${AuthService.minOwnPasswordLength} characters)',
                              'Nenosiri jipya (angalau herufi ${AuthService.minOwnPasswordLength})'),
                          hidden: _hideNext,
                          onToggle: () => setState(() => _hideNext = !_hideNext),
                          errorText: next.isNotEmpty && next.length < AuthService.minOwnPasswordLength
                              ? S.t('Use at least ${AuthService.minOwnPasswordLength} characters.',
                                  'Tumia herufi ${AuthService.minOwnPasswordLength} au zaidi.')
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _confirm,
                        obscureText: _hideConfirm,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (_valid && !_busy) _save();
                        },
                        decoration: passwordInputDecoration(
                          label: S.t('Confirm new password', 'Thibitisha nenosiri jipya'),
                          hidden: _hideConfirm,
                          onToggle: () => setState(() => _hideConfirm = !_hideConfirm),
                          errorText: _confirm.text.isNotEmpty && next != _confirm.text.trim()
                              ? S.t('Passwords do not match.', 'Nenosiri hayafanani.')
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _valid && !_busy ? _save : null,
                        child: Text(_busy ? S.t('Saving…', 'Inahifadhi…') : S.t('Save and continue', 'Hifadhi na uendelee')),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _busy ? null : () => AuthService().signOut(),
                        child: Text(S.t('Sign out', 'Toka')),
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

InputDecoration passwordInputDecoration({
  required String label,
  required bool hidden,
  required VoidCallback onToggle,
  String? errorText,
  String? helperText,
}) {
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    helperText: helperText,
    suffixIcon: IconButton(
      tooltip: hidden ? S.t('Show password', 'Onyesha nenosiri') : S.t('Hide password', 'Ficha nenosiri'),
      onPressed: onToggle,
      icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
    ),
  );
}

class PasswordSettingsView extends StatelessWidget {
  const PasswordSettingsView({required this.profile, super.key});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.t('Password', 'Nenosiri'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 8),
        Text(
          S.t(
            'Change this password while you are signed in. Staff who forget theirs must ask the shop admin. Shop admins who are locked out must ask the system administrator.',
            'Badilisha nenosiri ukiwa umeingia. Staff aliyesahau aombe admin wa duka. Admin aliyefungwa aombe msimamizi wa mfumo.',
          ),
          style: const TextStyle(color: Color(0xff68807d), height: 1.45),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_reset_rounded, color: Color(0xff0f766e)),
          title: Text(profile.email),
          subtitle: Text(S.role(profile.role)),
          trailing: FilledButton(
            onPressed: () => showChangeOwnPasswordDialog(context),
            child: Text(S.t('Change my password', 'Badilisha nenosiri langu')),
          ),
        ),
      ],
    );
  }
}
