import 'package:flutter/material.dart';

import '../backend/app_update_service.dart';

Future<void> applyPhyimacyUpdate(BuildContext context, AppRelease release) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Install update'),
        content: Text(
          'Phyimacy ${release.version} will download from GitHub, be verified, then this app will close and reopen. You do not unzip anything.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update now')),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return;

  final progress = ValueNotifier<(double, String)>((0, 'Starting...'));
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Installing update'),
          content: ValueListenableBuilder<(double, String)>(
            valueListenable: progress,
            builder: (context, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: value.$1 <= 0.04 ? null : value.$1),
                  const SizedBox(height: 14),
                  Text(value.$2),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  try {
    await AppUpdateService().installAndRestart(
      release: release,
      onProgress: (fraction, label) => progress.value = (fraction, label),
    );
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }
}
