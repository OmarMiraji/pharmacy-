import 'package:flutter/material.dart';

import '../backend/announcement_service.dart';
import '../backend/audit_log_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key});

  @override
  State<AnnouncementsAdminScreen> createState() => _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    await AnnouncementService().publish(title: _title.text, body: _body.text);
    await AuditLogService().record(action: 'ANNOUNCEMENT_PUBLISHED', detail: _title.text.trim());
    _title.clear();
    _body.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.t('Announcements', 'Matangazo'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        Text(S.t('Shown to shops inside PharmSpecio.', 'Yataonekana ndani ya maduka ya PharmSpecio.'), style: const TextStyle(color: Color(0xff68807d))),
        const SizedBox(height: 16),
        TextField(controller: _title, decoration: InputDecoration(labelText: S.t('Title', 'Kichwa'))),
        const SizedBox(height: 10),
        TextField(controller: _body, maxLines: 3, decoration: InputDecoration(labelText: S.t('Message', 'Ujumbe'))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _publish, child: Text(S.t('Publish', 'Chapisha'))),
        const SizedBox(height: 18),
        Expanded(
          child: StreamBuilder<List<Announcement>>(
            stream: AnnouncementService().watchAll(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!;
              if (rows.isEmpty) return Text(S.t('No announcements yet.', 'Bado hakuna matangazo.'));
              return ListView(
                children: [
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        title: Text(row.title, style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                        subtitle: Text(row.body),
                        trailing: Wrap(
                          children: [
                            Switch(
                              value: row.isActive,
                              onChanged: (value) => AnnouncementService().setActive(row.id, value),
                            ),
                            IconButton(
                              tooltip: S.t('Delete', 'Futa'),
                              onPressed: () async {
                                await AnnouncementService().delete(row.id);
                                await AuditLogService().record(action: 'ANNOUNCEMENT_DELETED', detail: row.title);
                              },
                              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
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
    );
  }
}
