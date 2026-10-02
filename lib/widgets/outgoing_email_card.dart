import 'package:flutter/material.dart';

import '../backend/transactional_email_service.dart';
import '../l10n/app_locale.dart';

class OutgoingEmailCard extends StatefulWidget {
  const OutgoingEmailCard({super.key});

  static Future<void> showDialogBox(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('Outgoing email (Gmail)', 'Email za kutuma (Gmail)')),
        content: const SizedBox(width: 460, child: OutgoingEmailCard()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(S.t('Close', 'Funga'))),
        ],
      ),
    );
  }

  @override
  State<OutgoingEmailCard> createState() => _OutgoingEmailCardState();
}

class _OutgoingEmailCardState extends State<OutgoingEmailCard> {
  final _gmail = TextEditingController(text: 'aboulonso85@gmail.com');
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _saved = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    TransactionalEmailService().loadSmtp().then((smtp) {
      if (!mounted || smtp == null) return;
      _gmail.text = smtp['user'] ?? _gmail.text;
      setState(() {
        _saved = true;
        _status = S.t(
          'Already saved. Emails will be sent from ${smtp['user']}.',
          'Tayari imewekwa. Barua zitatoka ${smtp['user']}.',
        );
      });
    });
  }

  @override
  void dispose() {
    _gmail.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await TransactionalEmailService().saveSmtp(gmail: _gmail.text, appPassword: _password.text);
      _password.clear();
      if (!mounted) return;
      setState(() {
        _saved = true;
        _status = S.t(
          'Saved. Welcome emails will be sent from ${_gmail.text.trim()}.',
          'Imehifadhiwa. Email za karibu zitatoka ${_gmail.text.trim()}.',
        );
      });
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xff0f766e),
          content: Text(S.t('Email settings saved.', 'Mipangilio ya email imehifadhiwa.')),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.t(
            'Use the Gmail that has the App password. Login omar@gmail.com is only for signing in to PharmSpecio.',
            'Tumia Gmail yenye App password. Login omar@gmail.com ni kuingia app tu.',
          ),
          style: const TextStyle(color: Color(0xff68807d), height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _gmail,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: S.t('Gmail address', 'Email ya Gmail')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: _hide,
          decoration: InputDecoration(
            labelText: S.t('App password (16 characters)', 'App password (herufi 16)'),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hide = !_hide),
              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: Icon(_saved && !_busy ? Icons.check_circle_outline : Icons.save_outlined),
          label: Text(
            _busy
                ? S.t('Saving…', 'Inahifadhi…')
                : _saved
                    ? S.t('Saved', 'Imehifadhiwa')
                    : S.t('Save email settings', 'Hifadhi email'),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xffdff7ee),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xff0f766e)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Color(0xff0f766e), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_status!, style: const TextStyle(color: Color(0xff183b3b), height: 1.35, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
