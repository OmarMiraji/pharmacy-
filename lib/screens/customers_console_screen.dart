import 'package:flutter/material.dart';

import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import 'staff_account_dialogs.dart';

class CustomersConsoleScreen extends StatelessWidget {
  const CustomersConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final users = UserManagementService();
    return StreamBuilder<List<PharmacyRecord>>(
      stream: PharmacyService().watchPharmacies(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return StreamBuilder<List<UserProfile>>(
          stream: users.watchUsers(),
          builder: (context, userSnap) {
            final shops = snapshot.data!;
            final staff = userSnap.data ?? const <UserProfile>[];
            final groups = <String, List<PharmacyRecord>>{};
            for (final shop in shops) {
              final key = (shop.ownerEmail ?? '').trim().toLowerCase();
              final id = key.isEmpty ? 'unassigned' : key;
              groups.putIfAbsent(id, () => []).add(shop);
            }
            final keys = groups.keys.toList()..sort();
            if (keys.isEmpty) {
              return Text(S.t('No customers yet. Create a shop with an owner email.', 'Bado hakuna wateja. Tengeneza duka na email ya mmiliki.'));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('Customers', 'Wateja'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
                const SizedBox(height: 6),
                Text(
                  S.t('A customer is the owner. Edit shops, add logins, or delete a shop from here.', 'Mteja ni mmiliki. Hariri duka, ongeza login, au futa duka hapa.'),
                  style: const TextStyle(color: Color(0xff68807d), height: 1.45),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      for (final key in keys)
                        Card(
                          child: ExpansionTile(
                            title: Text(
                              key == 'unassigned' ? S.t('No owner email', 'Hakuna email ya mmiliki') : key,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink),
                            ),
                            subtitle: Text('${groups[key]!.length} ${S.t('shop(s)', 'duka')}'),
                            children: [
                              for (final shop in groups[key]!)
                                ListTile(
                                  title: Text(shop.name),
                                  subtitle: Text(
                                    '${shop.phone ?? '—'} · ${shop.address ?? '—'} · ${SubscriptionService.licenseFromPharmacy(shop).status} · ${staff.where((user) => user.pharmacyId == shop.id).length} ${S.t('logins', 'login')}',
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: S.t('Edit', 'Hariri'),
                                        onPressed: () => showEditShopDialog(context, shop),
                                        icon: const Icon(Icons.edit_outlined, color: Color(0xff0f766e)),
                                      ),
                                      IconButton(
                                        tooltip: S.t('Add staff', 'Ongeza staff'),
                                        onPressed: () => showCreateStaffDialog(
                                          context,
                                          service: users,
                                          canManageSuperAdmin: true,
                                          presetPharmacyId: shop.id,
                                        ),
                                        icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xff0f766e)),
                                      ),
                                      IconButton(
                                        tooltip: S.t('Delete shop', 'Futa duka'),
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (dialogContext) => AlertDialog(
                                              title: Text(S.t('Delete shop?', 'Futa duka?')),
                                              content: Text(S.t(
                                                'This removes the ${shop.name} shop record. Staff logins stay until you delete them from Users.',
                                                'Hii inaondoa rekodi ya duka ${shop.name}. Login za staff zinabaki hadi uzifute kwenye Watumiaji.',
                                              )),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
                                                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete', 'Futa'))),
                                              ],
                                            ),
                                          );
                                          if (ok == true) await PharmacyService().deletePharmacy(shop.id);
                                        },
                                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
