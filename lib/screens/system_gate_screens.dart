import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/auth_service.dart';
import '../backend/system_control_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import 'app_update_screen.dart';

class _GateFrame extends StatelessWidget {
  const _GateFrame({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.authService,
    this.child,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final AuthService authService;
  final Widget? child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhyimacyBrand.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: PhyimacyBrand.line),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(icon, size: 48, color: color),
                    const SizedBox(height: 14),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                    const SizedBox(height: 10),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xff183b3b))),
                    if (child != null) ...[const SizedBox(height: 18), child!],
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (action != null) action!,
                        OutlinedButton.icon(
                          onPressed: authService.signOut,
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: Text(S.t('Sign out', 'Toka')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({required this.control, required this.authService, super.key});

  final SystemControl control;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return _GateFrame(
      icon: Icons.construction_rounded,
      color: const Color(0xffb54708),
      title: S.t('PharmSpecio is under maintenance', 'PharmSpecio iko kwenye matengenezo'),
      message: control.message.isNotEmpty
          ? control.message
          : S.t(
              'We are fixing something important. Your data is safe. This screen opens by itself when we finish.',
              'Tunarekebisha jambo muhimu. Data yako iko salama. Skrini hii itafunguka yenyewe tukimaliza.',
            ),
      authService: authService,
    );
  }
}

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    required this.control,
    required this.profile,
    required this.authService,
    super.key,
  });

  final SystemControl control;
  final UserProfile profile;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final installed = SystemControlService.instance.installedVersion;
    final need = control.minVersion.isEmpty ? 'build ${control.minBuild}' : control.minVersion;
    return _GateFrame(
      icon: Icons.system_update_alt_rounded,
      color: const Color(0xff0f766e),
      title: S.t('Update required', 'Update inahitajika'),
      message: S.t(
        'This version ($installed) can no longer be used. Install version $need or newer to continue.',
        'Toleo hili ($installed) haliwezi kutumika tena. Weka toleo $need au jipya zaidi ili kuendelea.',
      ),
      authService: authService,
      action: kIsWeb
          ? FilledButton.icon(
              onPressed: () => launchUrl(Uri.base, webOnlyWindowName: '_self'),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(S.t('Reload to update', 'Pakia upya kupata toleo jipya')),
            )
          : null,
      child: kIsWeb ? null : SizedBox(height: 420, child: AppUpdateScreen(profile: profile)),
    );
  }
}
