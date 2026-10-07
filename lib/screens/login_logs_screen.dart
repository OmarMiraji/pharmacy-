import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/login_log_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

class LoginLogsScreen extends StatelessWidget {
  const LoginLogsScreen({this.pharmacyId, super.key});

  /// When set, only this shop is shown. Super admin leaves this empty to see everyone.
  final String? pharmacyId;

  String _when(DateTime? value) {
    if (value == null) return '—';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/${value.year}  $hour:$minute';
  }

  String _role(String role) {
    return switch (role.trim().toLowerCase()) {
      'super_admin' => S.t('Super admin', 'Super admin'),
      'admin' => S.t('Admin', 'Admin'),
      'pharmacist' => S.t('Pharmacist', 'Mfamasia'),
      'cashier' => S.t('Cashier', 'Keshia'),
      'storekeeper' => S.t('Storekeeper', 'Mhifadhi'),
      '' => '—',
      _ => role,
    };
  }

  @override
  Widget build(BuildContext context) {
    final shopOnly = (pharmacyId ?? '').trim().isNotEmpty;
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shopOnly
                  ? S.t(
                      'Date and time each person in this shop signed in and signed out.',
                      'Tarehe na saa kila mtu wa duka hili alipoingia na kutoka.',
                    )
                  : S.t(
                      'Every sign-in and sign-out in PharmSpecio. Use this to see who was in the system.',
                      'Kila kuingia na kutoka kwenye PharmSpecio. Hapa unaona nani alikuwa ndani ya mfumo.',
                    ),
              style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.45),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 560,
              child: StreamBuilder<List<LoginEvent>>(
                stream: LoginLogService().watch(pharmacyId: shopOnly ? pharmacyId : null),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      S.t('Could not load login times. Publish the latest Firestore rules, then sign in again.', 'Imeshindwa kupakia muda wa kuingia. Chapisha rules mpya za Firestore, kisha ingia tena.'),
                      style: GoogleFonts.inter(color: const Color(0xffb42318), height: 1.4),
                    );
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return Text(
                      S.t('No sign-in records yet. They appear after the next login and logout.', 'Bado hakuna kumbukumbu. Zitaonekana baada ya kuingia na kutoka ijayo.'),
                      style: GoogleFonts.inter(color: PhyimacyBrand.muted, height: 1.4),
                    );
                  }
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xffedf2f2)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            color: PhyimacyBrand.forest,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: Row(
                            children: [
                              _head(S.t('When', 'Lini'), 18),
                              _head(S.t('Name', 'Jina'), 18),
                              _head(S.t('Email', 'Barua pepe'), 22),
                              if (!shopOnly) _head(S.t('Shop', 'Duka'), 16),
                              _head(S.t('Role', 'Cheo'), 12),
                              _head(S.t('Action', 'Kitendo'), 14),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final signedIn = row.isLogin;
                              final name = row.actorName.trim().isEmpty ? row.actorEmail : row.actorName.trim();
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                color: index.isOdd ? const Color(0xfff7f4ec) : Colors.white,
                                child: Row(
                                  children: [
                                    _value(_when(row.createdAt), 18, strong: true),
                                    _value(name, 18, strong: true),
                                    _value(row.actorEmail.trim().isEmpty ? '—' : row.actorEmail, 22),
                                    if (!shopOnly) _value(row.pharmacyName.trim().isEmpty ? '—' : row.pharmacyName, 16),
                                    _value(_role(row.role), 12),
                                    Expanded(
                                      flex: 14,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: (signedIn ? PhyimacyBrand.teal : const Color(0xffb45309)).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            signedIn ? S.t('Signed in', 'Aliingia') : S.t('Signed out', 'Alitoka'),
                                            style: TextStyle(
                                              color: signedIn ? PhyimacyBrand.teal : const Color(0xffb45309),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _head(String label, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(color: PhyimacyBrand.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }

  Widget _value(String text, int flex, {bool strong = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: strong ? PhyimacyBrand.ink : PhyimacyBrand.muted,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}
