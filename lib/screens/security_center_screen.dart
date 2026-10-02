import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../backend/payment_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/outgoing_email_card.dart';

class SecurityCenterScreen extends StatelessWidget {
  const SecurityCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PharmacyRecord>>(
      stream: PharmacyService().watchPharmacies(),
      builder: (context, shopSnap) {
        return StreamBuilder<List<LicensePayment>>(
          stream: PaymentService().watch(),
          builder: (context, paySnap) {
            final shops = shopSnap.data ?? const <PharmacyRecord>[];
            final payments = paySnap.data ?? const <LicensePayment>[];
            var locked = 0, expired = 0;
            for (final shop in shops) {
              final license = SubscriptionService.licenseFromPharmacy(shop);
              if (license.isBlocked) locked++;
              if (license.hasExpired) expired++;
            }
            final pending = payments.where((row) => row.status == 'pending').length;
            return ListView(
              children: [
                Text(S.t('Security center', 'Kituo cha usalama'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: const OutgoingEmailCard(),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _pill(S.t('Firebase Auth', 'Firebase Auth'), S.t('Healthy', 'Sawa')),
                    _pill(S.t('Firestore', 'Firestore'), S.t('Connected', 'Imeunganishwa')),
                    _pill(S.t('Security rules', 'Sheria'), S.t('Deployed', 'Zimewekwa')),
                    _pill(S.t('Locked shops', 'Maduka yaliyofungwa'), '$locked'),
                    _pill(S.t('Expired licenses', 'Leseni zilizoisha'), '$expired'),
                    _pill(S.t('Pending payments', 'Malipo yanayosubiri'), '$pending'),
                  ],
                ),
                const SizedBox(height: 18),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? '—';
                    return Text(S.t('This console version: $version', 'Toleo la console hii: $version'));
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff68807d))),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
        ],
      ),
    );
  }
}
