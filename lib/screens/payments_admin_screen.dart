import 'package:flutter/material.dart';

import '../backend/audit_log_service.dart';
import '../backend/pharmacy.dart';
import '../backend/pharmacy_service.dart';
import '../backend/payment_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

class PaymentsAdminScreen extends StatefulWidget {
  const PaymentsAdminScreen({super.key});

  @override
  State<PaymentsAdminScreen> createState() => _PaymentsAdminScreenState();
}

class _PaymentsAdminScreenState extends State<PaymentsAdminScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _email = TextEditingController();
  String _method = 'M-Pesa';
  String? _pharmacyId;
  String _pharmacyName = '';

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _create(List<PharmacyRecord> shops) async {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if ((_pharmacyId ?? '').isEmpty || amount <= 0 || _reference.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('Choose a shop, amount, and payment reference.', 'Chagua duka, kiasi, na namba ya malipo.'))));
      return;
    }
    await PaymentService().create(
      pharmacyId: _pharmacyId!,
      pharmacyName: _pharmacyName,
      customerEmail: _email.text,
      amountTzs: amount,
      method: _method,
      reference: _reference.text,
    );
    await AuditLogService().record(action: 'PAYMENT_RECORDED', pharmacyId: _pharmacyId, pharmacyName: _pharmacyName, detail: '$_method $_reference $amount TZS');
    _amount.clear();
    _reference.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('Payment recorded as pending.', 'Malipo yamehifadhiwa kama pending.'))));
  }

  Future<void> _setStatus(LicensePayment payment, String status) async {
    await PaymentService().setStatus(payment.id, status);
    await AuditLogService().record(
      action: 'PAYMENT_${status.toUpperCase()}',
      pharmacyId: payment.pharmacyId,
      pharmacyName: payment.pharmacyName,
      detail: payment.reference,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.t('Payments', 'Malipo'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xff183b3b))),
        const SizedBox(height: 6),
        Text(
          S.t('Record a manual payment, then verify it before granting a license. Shop users cannot change Verified.', 'Rekodi malipo ya mkono, kisha thibitisha kabla ya kutoa leseni. Duka haliwezi kubadilisha Verified.'),
          style: const TextStyle(color: Color(0xff68807d), height: 1.45),
        ),
        const SizedBox(height: 16),
        StreamBuilder<List<PharmacyRecord>>(
          stream: PharmacyService().watchPharmacies(),
          builder: (context, shopSnap) {
            final shops = shopSnap.data ?? const <PharmacyRecord>[];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String>(
                        initialValue: shops.any((shop) => shop.id == _pharmacyId) ? _pharmacyId : null,
                        decoration: InputDecoration(labelText: S.t('Pharmacy', 'Duka')),
                        items: [
                          for (final shop in shops)
                            DropdownMenuItem(value: shop.id, child: Text(shop.name)),
                        ],
                        onChanged: (value) {
                          final shop = shops.cast<PharmacyRecord?>().firstWhere((item) => item?.id == value, orElse: () => null);
                          setState(() {
                            _pharmacyId = value;
                            _pharmacyName = shop?.name ?? '';
                            if ((shop?.ownerEmail ?? '').isNotEmpty) _email.text = shop!.ownerEmail!;
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 160, child: TextField(controller: _email, decoration: InputDecoration(labelText: S.t('Customer email', 'Email ya mteja')))),
                    SizedBox(width: 140, child: TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount TZS'))),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        initialValue: _method,
                        decoration: InputDecoration(labelText: S.t('Method', 'Njia')),
                        items: const [
                          DropdownMenuItem(value: 'M-Pesa', child: Text('M-Pesa')),
                          DropdownMenuItem(value: 'Bank', child: Text('Bank')),
                          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        ],
                        onChanged: (value) => setState(() => _method = value ?? _method),
                      ),
                    ),
                    SizedBox(width: 180, child: TextField(controller: _reference, decoration: InputDecoration(labelText: S.t('Reference', 'Namba ya malipo')))),
                    FilledButton(onPressed: () => _create(shops), child: Text(S.t('Record pending', 'Rekodi pending'))),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<LicensePayment>>(
            stream: PaymentService().watch(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('${snapshot.error}');
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snapshot.data!;
              if (rows.isEmpty) return Text(S.t('No payments yet.', 'Bado hakuna malipo.'));
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      title: Text('${row.pharmacyName} · TZS ${row.amountTzs}', style: const TextStyle(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                      subtitle: Text('${row.status.toUpperCase()} · ${row.method} · ${row.reference} · ${row.customerEmail}'),
                      trailing: Wrap(
                        children: [
                          if (row.status == 'pending') ...[
                            TextButton(onPressed: () => _setStatus(row, 'verified'), child: Text(S.t('Verify', 'Thibitisha'))),
                            TextButton(onPressed: () => _setStatus(row, 'rejected'), child: Text(S.t('Reject', 'Kataa'))),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(right: 8, top: 12),
                              child: Text(row.verifiedBy ?? ''),
                            ),
                          IconButton(
                            tooltip: S.t('Delete', 'Futa'),
                            onPressed: () async {
                              await PaymentService().delete(row.id);
                              await AuditLogService().record(
                                action: 'PAYMENT_DELETED',
                                pharmacyId: row.pharmacyId,
                                pharmacyName: row.pharmacyName,
                                detail: row.reference,
                              );
                            },
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xffb42318)),
                          ),
                        ],
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
