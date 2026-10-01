import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/subscription_service.dart';
import '../backend/user_management_service.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import 'accounts_admin_screen.dart';
import 'password_security.dart';
import 'staff_account_dialogs.dart';

class SupportDirectoryScreen extends StatefulWidget {
  const SupportDirectoryScreen({required this.profile, this.initialTab = 0, super.key});

  final UserProfile profile;
  final int initialTab;

  @override
  State<SupportDirectoryScreen> createState() => _SupportDirectoryScreenState();
}

class _SupportDirectoryScreenState extends State<SupportDirectoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _shopSearch = TextEditingController();
  final _userSearch = TextEditingController();
  Timer? _debounce;
  String _shopQuery = '';
  String _userQuery = '';
  String? _userShopFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _shopSearch.dispose();
    _userSearch.dispose();
    super.dispose();
  }

  void _onSearch(void Function() apply) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(apply);
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = UserManagementService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.t('Manage every shop and login from here. Edit details, add staff, set passwords, or remove a profile.', 'Simamia kila duka na login hapa. Hariri taarifa, ongeza staff, weka nenosiri, au futa wasifu.'),
          style: const TextStyle(color: Color(0xff68807d), height: 1.4),
        ),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabs,
          labelColor: PhyimacyBrand.teal,
          indicatorColor: PhyimacyBrand.teal,
          tabs: [
            Tab(text: S.t('Shops', 'Maduka')),
            Tab(text: S.t('Users', 'Watumiaji')),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ShopsPane(
                profile: widget.profile,
                search: _shopSearch,
                query: _shopQuery,
                onQuery: (value) => _onSearch(() => _shopQuery = value.trim().toLowerCase()),
                users: users,
              ),
              _UsersPane(
                profile: widget.profile,
                search: _userSearch,
                query: _userQuery,
                shopFilter: _userShopFilter,
                onQuery: (value) => _onSearch(() => _userQuery = value.trim().toLowerCase()),
                onShopFilter: (value) => setState(() => _userShopFilter = value),
                users: users,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShopsPane extends StatelessWidget {
  const _ShopsPane({
    required this.profile,
    required this.search,
    required this.query,
    required this.onQuery,
    required this.users,
  });

  final UserProfile profile;
  final TextEditingController search;
  final String query;
  final ValueChanged<String> onQuery;
  final UserManagementService users;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ExpansionTile(
          initiallyExpanded: false,
          title: Text(S.t('Create a new shop + admin', 'Unda duka jipya + admin'), style: const TextStyle(fontWeight: FontWeight.w800)),
          children: [AccountsAdminScreen(profile: profile)],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: search,
          onChanged: onQuery,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: S.t('Search shop name or owner email', 'Tafuta jina la duka au email ya mmiliki'),
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<PharmacyRecord>>(
          stream: PharmacyService().watchPharmacies(),
          builder: (context, shopSnap) {
            return StreamBuilder<List<UserProfile>>(
              stream: users.watchUsers(),
              builder: (context, userSnap) {
                if (shopSnap.hasError) return Text('${shopSnap.error}');
                if (!shopSnap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                final shops = shopSnap.data!.where((shop) {
                  if (query.isEmpty) return true;
                  return shop.name.toLowerCase().contains(query) || (shop.ownerEmail ?? '').toLowerCase().contains(query);
                }).toList();
                final staff = userSnap.data ?? const <UserProfile>[];
                if (shops.isEmpty) {
                  return Text(S.t('No shops match that search.', 'Hakuna duka linalofanana na utafutaji.'));
                }
                return Column(
                  children: [
                    for (final shop in shops)
                      _ShopCard(
                        shop: shop,
                        profile: profile,
                        staff: staff.where((user) => user.pharmacyId == shop.id && !user.isSuperAdmin).toList(),
                        users: users,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.shop,
    required this.profile,
    required this.staff,
    required this.users,
  });

  final PharmacyRecord shop;
  final UserProfile profile;
  final List<UserProfile> staff;
  final UserManagementService users;

  @override
  Widget build(BuildContext context) {
    final license = SubscriptionService.licenseFromPharmacy(shop);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${shop.ownerEmail ?? S.t('No owner email', 'Hakuna email ya mmiliki')}  •  ${staff.length} ${S.t('logins', 'login')}  •  ${license.status}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((shop.phone ?? '').trim().isNotEmpty) Text('${S.t('Phone', 'Simu')}: ${shop.phone}'),
                if ((shop.address ?? '').trim().isNotEmpty) Text('${S.t('Address', 'Anwani')}: ${shop.address}'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => showEditShopDialog(context, shop),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(S.t('Edit shop', 'Hariri duka')),
                    ),
                    FilledButton.icon(
                      onPressed: () => showCreateStaffDialog(
                        context,
                        service: users,
                        canManageSuperAdmin: true,
                        presetPharmacyId: shop.id,
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text(S.t('Add staff', 'Ongeza staff')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(S.t('Delete shop?', 'Futa duka?')),
                            content: Text(
                              S.t(
                                'This removes the ${shop.name} shop record. Staff logins stay until you delete them from Users.',
                                'Hii inaondoa rekodi ya duka ${shop.name}. Login za staff zinabaki hadi uzifute kwenye Watumiaji.',
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(S.t('Cancel', 'Ghairi'))),
                              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(S.t('Delete', 'Futa'))),
                            ],
                          ),
                        );
                        if (ok == true) await PharmacyService().deletePharmacy(shop.id);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xffb42318)),
                      label: Text(S.t('Delete shop', 'Futa duka'), style: const TextStyle(color: Color(0xffb42318))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (staff.isEmpty)
                  Text(S.t('No logins linked to this shop yet.', 'Bado hakuna login zilizounganishwa na duka hili.'))
                else
                  for (final user in staff)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(user.displayName.isEmpty ? user.email : user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${user.email}  •  ${user.role}  •  ${user.isActive ? S.t('Active', 'Hai') : S.t('Disabled', 'Imefungwa')}'),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: S.t('Edit', 'Hariri'),
                            onPressed: () => showEditStaffDialog(context, service: users, user: user, canManageSuperAdmin: true),
                            icon: const Icon(Icons.tune_rounded, color: Color(0xff0f766e)),
                          ),
                          IconButton(
                            tooltip: S.t('Password', 'Nenosiri'),
                            onPressed: () => showManagedPasswordDialog(context, user),
                            icon: const Icon(Icons.password_rounded, color: Color(0xff0f766e)),
                          ),
                          IconButton(
                            tooltip: S.t('Delete', 'Futa'),
                            onPressed: () => confirmDeleteStaffProfile(context, users, user),
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
    );
  }
}

class _UsersPane extends StatelessWidget {
  const _UsersPane({
    required this.profile,
    required this.search,
    required this.query,
    required this.shopFilter,
    required this.onQuery,
    required this.onShopFilter,
    required this.users,
  });

  final UserProfile profile;
  final TextEditingController search;
  final String query;
  final String? shopFilter;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onShopFilter;
  final UserManagementService users;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                onChanged: onQuery,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: S.t('Search name, email, or shop', 'Tafuta jina, email, au duka'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => showCreateStaffDialog(context, service: users, canManageSuperAdmin: true),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(S.t('Add user', 'Ongeza mtumiaji')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<List<PharmacyRecord>>(
            stream: PharmacyService().watchPharmacies(),
            builder: (context, shopSnap) {
              final shops = shopSnap.data ?? const <PharmacyRecord>[];
              final names = {for (final shop in shops) shop.id: shop.name};
              return Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: shopFilter,
                    decoration: InputDecoration(labelText: S.t('Filter by shop', 'Chuja kwa duka')),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(S.t('All shops', 'Maduka yote'))),
                      DropdownMenuItem<String?>(value: '', child: Text(S.t('Unlinked logins', 'Login zisizo na duka'))),
                      for (final shop in shops) DropdownMenuItem<String?>(value: shop.id, child: Text(shop.name)),
                    ],
                    onChanged: onShopFilter,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<List<UserProfile>>(
                      stream: users.watchUsers(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Text('${snapshot.error}');
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        final list = snapshot.data!.where((user) {
                          final shopId = (user.pharmacyId ?? '').trim();
                          if (shopFilter != null) {
                            if (shopFilter == '') {
                              if (shopId.isNotEmpty) return false;
                            } else if (shopId != shopFilter) {
                              return false;
                            }
                          }
                          if (query.isEmpty) return true;
                          final shopName = names[shopId] ?? '';
                          return user.displayName.toLowerCase().contains(query) ||
                              user.email.toLowerCase().contains(query) ||
                              shopName.toLowerCase().contains(query);
                        }).toList();
                        if (list.isEmpty) {
                          return Center(child: Text(S.t('No users match.', 'Hakuna watumiaji wanaofanana.')));
                        }
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final user = list[index];
                            final shopName = names[user.pharmacyId ?? ''] ??
                                ((user.pharmacyId ?? '').trim().isEmpty
                                    ? S.t('No shop linked', 'Hakuna duka')
                                    : S.t('Unknown shop', 'Duka halijulikani'));
                            return ListTile(
                              title: Text(user.displayName.isEmpty ? user.email : user.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text('${user.email}  •  ${user.role}  •  $shopName  •  ${user.isActive ? S.t('Active', 'Hai') : S.t('Disabled', 'Imefungwa')}'),
                              trailing: Wrap(
                                children: [
                                  IconButton(
                                    tooltip: S.t('Edit', 'Hariri'),
                                    onPressed: () => showEditStaffDialog(context, service: users, user: user, canManageSuperAdmin: true),
                                    icon: const Icon(Icons.tune_rounded, color: Color(0xff0f766e)),
                                  ),
                                  IconButton(
                                    tooltip: S.t('Password', 'Nenosiri'),
                                    onPressed: () => showManagedPasswordDialog(context, user),
                                    icon: const Icon(Icons.password_rounded, color: Color(0xff0f766e)),
                                  ),
                                  IconButton(
                                    tooltip: user.isActive ? S.t('Disable', 'Funga') : S.t('Enable', 'Fungua'),
                                    onPressed: () => users.updateAccess(
                                      userId: user.id,
                                      role: user.role == 'super_admin' ? 'admin' : user.role,
                                      permissions: user.permissions,
                                      isActive: !user.isActive,
                                    ),
                                    icon: Icon(user.isActive ? Icons.person_off_outlined : Icons.person_outline_rounded, color: PhyimacyBrand.teal),
                                  ),
                                  IconButton(
                                    tooltip: S.t('Delete', 'Futa'),
                                    onPressed: () => confirmDeleteStaffProfile(context, users, user),
                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
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
