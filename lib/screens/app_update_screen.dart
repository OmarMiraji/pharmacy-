import 'package:flutter/material.dart';

import '../backend/app_update_service.dart';
import '../backend/user_profile.dart';
import 'apply_app_update.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({required this.profile, super.key});

  final UserProfile profile;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  final _service = AppUpdateService();
  final _version = TextEditingController();
  final _build = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  final _github = TextEditingController();
  AppUpdateCheck? _check;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _version.dispose();
    _build.dispose();
    _url.dispose();
    _notes.dispose();
    _github.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final result = await _service.check();
      if (!mounted) return;
      _check = result;
      final latest = result.latest;
      if (widget.profile.isSuperAdmin && latest != null) {
        _version.text = latest.version;
        _build.text = latest.buildNumber.toString();
        _url.text = latest.downloadUrl;
        _notes.text = latest.notes;
        if (latest.githubRepo.isNotEmpty) _github.text = latest.githubRepo;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await _service.publish(
        version: _version.text,
        buildNumber: int.tryParse(_build.text.trim()) ?? 0,
        downloadUrl: _url.text,
        notes: _notes.text,
        githubRepo: _github.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GitHub repo saved. Pharmacies will install verified releases in-app.')),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final latest = check?.latest;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('App updates', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
          const SizedBox(height: 8),
          const Text(
            'One button installs the update. Phyimacy downloads the official GitHub zip, checks SHA-256, replaces this app, and reopens. Nobody unzips files by hand.',
            style: TextStyle(color: Color(0xff68807d)),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.computer_rounded, color: Color(0xff0f766e)),
                title: Text('Installed version ${check?.installedVersion ?? '-'}'),
                subtitle: Text('Build ${check?.installedBuild ?? 0}'),
                trailing: OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check for update'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (check?.updateAvailable == true && latest != null)
              Card(
                color: const Color(0xffe8f6f2),
                child: ListTile(
                  leading: const Icon(Icons.system_update_alt_rounded, color: Color(0xff0f766e)),
                  title: Text('New version ${latest.version} is available'),
                  subtitle: Text(
                    latest.canAutoInstall
                        ? (latest.notes.isEmpty ? 'Install now. The app will close and reopen by itself.' : latest.notes)
                        : 'This release is not a verified GitHub zip yet.',
                  ),
                  trailing: FilledButton(
                    onPressed: latest.canAutoInstall ? () => applyPhyimacyUpdate(context, latest) : null,
                    child: const Text('Update now'),
                  ),
                ),
              )
            else
              const ListTile(
                leading: Icon(Icons.check_circle_outline_rounded, color: Color(0xff0f766e)),
                title: Text('You are on the latest version available to this app.'),
              ),
          ],
          if (widget.profile.isSuperAdmin) ...[
            const SizedBox(height: 28),
            const Text('Publish / connect GitHub', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
            const SizedBox(height: 8),
            const Text(
              'Save owner/repo once. After each tag (v1.0.2), GitHub builds the zip. Pharmacies tap Update now — no browser unzip.',
              style: TextStyle(color: Color(0xff68807d)),
            ),
            const SizedBox(height: 12),
            TextField(controller: _github, decoration: const InputDecoration(labelText: 'GitHub repo, for example yourname/phyimacy')),
            const SizedBox(height: 10),
            TextField(controller: _version, decoration: const InputDecoration(labelText: 'Version fallback, for example 1.0.1')),
            const SizedBox(height: 10),
            TextField(controller: _build, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Build number fallback')),
            const SizedBox(height: 10),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'Manual download link (optional if GitHub is set)')),
            const SizedBox(height: 10),
            TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'What is new')),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: const Icon(Icons.publish_rounded),
              label: Text(_busy ? 'Saving...' : 'Save GitHub repo for all pharmacies'),
            ),
          ],
        ],
      ),
    );
  }
}
