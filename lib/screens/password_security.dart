import 'package:flutter/material.dart';

import '../backend/auth_service.dart';
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
                    label: S.t('New password (min 6 characters)', 'Nenosiri jipya (angalau herufi 6)'),
                    hidden: hideNext,
                    onToggle: () => setState(() => hideNext = !hideNext),
                    errorText: next.text.isNotEmpty && next.text.trim().length < 6
                        ? S.t('Use at least 6 characters.', 'Tumia herufi 6 au zaidi.')
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
              onPressed: next.text.trim().length >= 6 && next.text == confirm.text
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
  final password = TextEditingController();
  final confirm = TextEditingController();
  var hidePassword = true;
  var hideConfirm = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(S.t('Password for ${target.displayName}', 'Nenosiri la ${target.displayName}')),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(target.email, style: const TextStyle(color: Color(0xff68807d))),
                    const SizedBox(height: 8),
                    Text(
                      S.t(
                        'Enter a new password. They can sign in with it immediately. Do not send an email reset.',
                        'Weka nenosiri jipya. Wanaweza kuingia nacho mara moja. Usitume email ya reset.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: hidePassword,
                      onChanged: (_) => setState(() {}),
                      decoration: passwordInputDecoration(
                        label: S.t('New password (min 6 characters)', 'Nenosiri jipya (angalau herufi 6)'),
                        hidden: hidePassword,
                        onToggle: () => setState(() => hidePassword = !hidePassword),
                        errorText: password.text.isNotEmpty && password.text.trim().length < 6
                            ? S.t('Use at least 6 characters.', 'Tumia herufi 6 au zaidi.')
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirm,
                      obscureText: hideConfirm,
                      onChanged: (_) => setState(() {}),
                      decoration: passwordInputDecoration(
                        label: S.t('Confirm password', 'Thibitisha nenosiri'),
                        hidden: hideConfirm,
                        onToggle: () => setState(() => hideConfirm = !hideConfirm),
                        errorText: confirm.text.isNotEmpty && password.text != confirm.text
                            ? S.t('Passwords do not match.', 'Nenosiri hayafanani.')
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Cancel', 'Ghairi'))),
                FilledButton(
                  onPressed: password.text.trim().length >= 6 && password.text == confirm.text
                      ? () async {
                          try {
                            await UserManagementService().setLoginPassword(userId: target.id, password: password.text);
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                            if (context.mounted) {
                              showAppNotice(
                                context,
                                S.t('Password updated. They can sign in with it now.', 'Nenosiri limebadilishwa. Wanaweza kuingia nalo sasa.'),
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
                            }
                          }
                        }
                      : null,
                  child: Text(S.t('Set password', 'Weka nenosiri')),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    password.dispose();
    confirm.dispose();
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
