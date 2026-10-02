import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/purchase_service.dart';
import '../backend/tanzania_phone.dart';
import '../backend/user_profile.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({required this.profile, this.embedded = false, super.key});

  final UserProfile profile;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final service = PurchaseService();
    return Padding(
      padding: embedded ? EdgeInsets.zero : const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: StreamBuilder<List<SupplierOption>>(
        stream: service.watchSuppliers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Could not load suppliers: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final suppliers = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!embedded) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: Row(
                    children: [
                      Container(width: 4, height: 36, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
                      const SizedBox(width: 14),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: const Color(0xffdff7ee), borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.local_shipping_outlined, color: PhyimacyBrand.teal),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Suppliers', style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink, height: 1.1)),
                            const SizedBox(height: 4),
                            Text('People and companies that send stock into this pharmacy.', style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (profile.can('suppliers.manage'))
                        FilledButton.icon(
                          onPressed: () => _showSupplierDialog(context, service),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Add supplier'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: suppliers.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(color: const Color(0xffdff7ee), borderRadius: BorderRadius.circular(22)),
                                child: const Icon(Icons.local_shipping_outlined, size: 32, color: PhyimacyBrand.teal),
                              ),
                              const SizedBox(height: 16),
                              Text('No suppliers yet', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
                              const SizedBox(height: 8),
                              const Text('Add a supplier, then receive purchases against their name.', style: TextStyle(color: Color(0xff68807d))),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: suppliers.length,
                          separatorBuilder: (_, index) => const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) {
                            final supplier = suppliers[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xffdff7ee),
                                child: Text(
                                  supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : 'S',
                                  style: const TextStyle(color: PhyimacyBrand.teal, fontWeight: FontWeight.w800),
                                ),
                              ),
                              title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xff143230))),
                              subtitle: Text(
                                supplier.phone?.isNotEmpty == true ? supplier.phone! : 'No phone number added',
                                style: GoogleFonts.inter(color: PhyimacyBrand.muted),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showSupplierDialog(BuildContext context, PurchaseService service) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Add supplier'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Supplier name', hintText: 'Example: Mzigo Pharma')),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: S.t('Phone (optional)', 'Simu (si lazima)'),
                  hintText: TanzaniaPhone.hint,
                  helperText: S.t('Tanzania mobile, e.g. 0712345678', 'Simu ya Tanzania, mfano 0712345678'),
                  errorText: TanzaniaPhone.validate(phone.text),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: TanzaniaPhone.validate(phone.text) == null
                ? () async {
              final supplierName = name.text.trim();
              if (supplierName.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Supplier name is required.')));
                return;
              }
              await service.createSupplier(name: supplierName, phone: TanzaniaPhone.normalize(phone.text), email: email.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
      ),
    );
    name.dispose();
    phone.dispose();
    email.dispose();
  }
}
