import 'package:flutter/material.dart';

import '../backend/audit_log_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

class AuditLogsScreen extends StatelessWidget {
  const AuditLogsScreen({super.key});

  String _fmt(DateTime? value) {
    if (value == null) return '—';
    return '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.t('Audit logs', 'Kumbukumbu za vitendo'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        Text(
          S.t('Append-only. Super Admin cannot edit or delete these records from the app.', 'Huwezi kuhariri au kufuta. Zinarekodi nani alifanya nini na lini.'),
          style: const TextStyle(color: Color(0xff68807d), height: 1.45),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<AuditEntry>>(
            stream: AuditLogService().watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('${snapshot.error}');
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return Text(S.t('No audit events yet. Grant, lock, extend, and payments will appear here.', 'Bado hakuna vitendo. Grant, lock, extend, na malipo yataonekana hapa.'));
              }
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      title: Text(row.action, style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                      subtitle: Text(
                        [
                          _fmt(row.createdAt),
                          if (row.actorEmail.isNotEmpty) row.actorEmail,
                          if ((row.pharmacyName ?? '').trim().isNotEmpty) row.pharmacyName,
                          if ((row.detail ?? '').trim().isNotEmpty) row.detail,
                        ].whereType<String>().join(' · '),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
