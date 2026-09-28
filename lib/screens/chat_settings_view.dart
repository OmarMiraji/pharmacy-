import 'package:flutter/material.dart';

import '../backend/chat_settings.dart';
import '../backend/user_profile.dart';

class ChatSettingsView extends StatefulWidget {
  const ChatSettingsView({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<ChatSettingsView> createState() => _ChatSettingsViewState();
}

class _ChatSettingsViewState extends State<ChatSettingsView> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  bool get _canManage => widget.profile.can('settings.manage') || widget.profile.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await ChatSettingsService().load();
    if (!mounted) return;
    _url.text = settings.apiUrl;
    _key.text = settings.apiKey;
    _model.text = settings.model;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ChatSettingsService().save(
        ChatAssistantSettings(apiUrl: _url.text, apiKey: _key.text, model: _model.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assistant connection saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Text('Shop assistant', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        const Text(
          'Staff can tap the chat icon and ask about stock, expiry, and how to use Phyimacy. Leave the address empty to answer from this shop only. Paste your API address if you want replies from your own assistant.',
          style: TextStyle(color: Color(0xff68807d), height: 1.4),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _url,
          enabled: _canManage,
          decoration: const InputDecoration(
            labelText: 'API address',
            hintText: 'https://your-api.example.com/v1/chat/completions',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          enabled: _canManage,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'API key (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          enabled: _canManage,
          decoration: const InputDecoration(labelText: 'Model name (optional)', hintText: 'gpt-4o-mini'),
        ),
        const SizedBox(height: 18),
        if (_canManage)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save assistant'),
            ),
          )
        else
          const Text('Ask a shop administrator to change the assistant connection.'),
      ],
    );
  }
}
