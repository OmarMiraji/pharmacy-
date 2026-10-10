import 'package:flutter/material.dart';

import '../backend/auth_service.dart';
import '../backend/medicine_service.dart';
import '../backend/medicine_match.dart';
import '../backend/models.dart';
import '../backend/purchase_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/app_notice.dart';

Future<void> showReceivePurchaseDialog(BuildContext context, PurchaseService service) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ReceivePurchaseForm(service: service),
  );
}

class _ReceivePurchaseForm extends StatefulWidget {
  const _ReceivePurchaseForm({required this.service});

  final PurchaseService service;

  @override
  State<_ReceivePurchaseForm> createState() => _ReceivePurchaseFormState();
}

class _ReceivePurchaseFormState extends State<_ReceivePurchaseForm> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _newName = TextEditingController();
  final _newPrice = TextEditingController();
  final _batch = TextEditingController();
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _invoice = TextEditingController();
  String? _supplierId;
  Medicine? _selected;
  var _addingNew = false;
  var _busy = false;
  DateTime _expiry = DateTime.now().add(const Duration(days: 365));

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    _newPrice.dispose();
    _batch.dispose();
    _quantity.dispose();
    _cost.dispose();
    _invoice.dispose();
    super.dispose();
  }

  List<Medicine> _matches(List<Medicine> medicines) {
    final q = _search.text.trim().toLowerCase();
    final source = q.isEmpty
        ? medicines
        : medicines.where((item) => item.name.toLowerCase().contains(q) || item.sku.toLowerCase().contains(q));
    return source.take(8).toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = AuthService().currentUser;
    final amount = int.tryParse(_quantity.text);
    final unitCost = int.tryParse(_cost.text);
    if (user == null || amount == null || unitCost == null || amount <= 0 || unitCost < 0) return;
    if (!_addingNew && _selected == null) {
      showAppNotice(context, S.t('Select a medicine or tap New', 'Chagua dawa au bofya Mpya'), kind: AppNoticeKind.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final existing = _selected ??
          await MedicineService().findExistingByName(
            _addingNew ? _newName.text : _search.text,
          );
      var medicineId = existing?.id ?? '';
      final before = existing?.quantityOnHand ?? 0;
      final label = existing?.name ?? _newName.text.trim();
      if (_addingNew || medicineId.isEmpty) {
        final name = _newName.text.trim();
        final price = int.tryParse(_newPrice.text.trim()) ?? 0;
        if (name.isEmpty && medicineId.isEmpty) {
          throw StateError(S.t('Enter the medicine name', 'Weka jina la dawa'));
        }
        if (medicineId.isEmpty) {
          medicineId = await MedicineService().createQuickMedicine(
            name: name,
            sellingPriceMinor: price,
            createdBy: user.uid,
          );
        }
      }
      await widget.service.receivePurchase(
        supplierId: _supplierId ?? '',
        medicineId: medicineId,
        batchNumber: _batch.text,
        expiryDate: _expiry,
        quantity: amount,
        unitCostMinor: unitCost,
        createdBy: user.uid,
        invoiceNumber: _invoice.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final after = before + amount;
      showAppNotice(context, '$label: $before → $after');
    } catch (error) {
      if (mounted) showAppNotice(context, friendlyActionError(error), kind: AppNoticeKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, {Widget? prefix, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xfff7fbfa),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 540,
        child: StreamBuilder<List<SupplierOption>>(
          stream: widget.service.watchSuppliers(),
          builder: (context, supplierSnapshot) {
            final suppliers = supplierSnapshot.data ?? const <SupplierOption>[];
            return StreamBuilder<List<Medicine>>(
              stream: MedicineService().watchMedicines(),
              builder: (context, medicineSnapshot) {
                final medicines = MedicineMatch.unique(medicineSnapshot.data ?? const <Medicine>[]);
                return Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(S.t('Receive stock', 'Pokea stock'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PhyimacyBrand.ink)),
                        const SizedBox(height: 6),
                        Text(
                          S.t(
                            'Search an existing medicine, or tap New. A later expiry is a separate batch; sales sell the nearest date first.',
                            'Tafuta dawa iliyopo, au bofya Mpya. Tarehe tofauti ya kuisha ni batch mpya; mauzo yanatoa ile inayoisha kwanza.',
                          ),
                          style: const TextStyle(color: Color(0xff68807d), height: 1.35, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        if (suppliers.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            initialValue: suppliers.any((item) => item.id == _supplierId) ? _supplierId : '',
                            decoration: _field(S.t('Supplier (optional)', 'Msambazaji (si lazima)')),
                            items: [
                              DropdownMenuItem(value: '', child: Text(S.t('No supplier', 'Bila msambazaji'))),
                              for (final supplier in suppliers) DropdownMenuItem(value: supplier.id, child: Text(supplier.name)),
                            ],
                            onChanged: (value) => setState(() => _supplierId = value ?? ''),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!_addingNew) ...[
                          TextField(
                            controller: _search,
                            onChanged: (_) {
                              final exact = MedicineMatch.findIn(medicines, _search.text);
                              setState(() => _selected = exact);
                            },
                            decoration: _field(
                              S.t('Search medicine', 'Tafuta dawa'),
                              prefix: const Icon(Icons.search_rounded),
                              suffix: TextButton(
                                onPressed: () {
                                  final exact = MedicineMatch.findIn(medicines, _search.text);
                                  if (exact != null) {
                                    setState(() {
                                      _addingNew = false;
                                      _selected = exact;
                                      _search.text = exact.name;
                                    });
                                    showAppNotice(context, S.t('Already in catalogue. Receive adds to this stock.', 'Tayari ipo. Pokea inaongeza kwenye stock hii.'), kind: AppNoticeKind.info);
                                    return;
                                  }
                                  setState(() {
                                    _addingNew = true;
                                    _selected = null;
                                    _newName.text = _search.text.trim();
                                  });
                                },
                                child: Text(S.t('New', 'Mpya')),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_selected != null)
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xffdff7ee),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: PhyimacyBrand.teal),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_selected!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                        Text(
                                          S.t('On hand now: ${_selected!.stockLabel()}', 'Ipo sasa: ${_selected!.stockLabel()}'),
                                          style: const TextStyle(color: Color(0xff68807d), fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: S.t('Change', 'Badilisha'),
                                    onPressed: () => setState(() => _selected = null),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            )
                          else
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: Material(
                                color: const Color(0xfff7fbfa),
                                borderRadius: BorderRadius.circular(14),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    for (final medicine in _matches(medicines))
                                      InkWell(
                                        onTap: () => setState(() {
                                          _selected = medicine;
                                          _search.text = medicine.name;
                                        }),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(medicine.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                              Text(
                                                '${medicine.sku}  •  ${medicine.stockLabel()} on hand',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Color(0xff68807d), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (_matches(medicines).isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          S.t('No match. Tap New to add this medicine.', 'Hakuna inayofanana. Bofya Mpya kuiongeza.'),
                                          style: const TextStyle(color: Color(0xff68807d), fontSize: 13),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ] else ...[
                          TextField(controller: _newName, decoration: _field(S.t('New medicine name', 'Jina la dawa mpya'))),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _newPrice,
                            keyboardType: TextInputType.number,
                            decoration: _field(S.t('Selling price (TZS)', 'Bei ya kuuza (TZS)')),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _addingNew = false),
                              child: Text(S.t('Choose existing medicine', 'Chagua dawa iliyopo')),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(controller: _invoice, decoration: _field(S.t('Invoice (optional)', 'Ankara (si lazima)'))),
                        const SizedBox(height: 10),
                        TextField(controller: _batch, decoration: _field(S.t('Batch number (optional)', 'Namba ya batch (si lazima)'))),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _quantity,
                                keyboardType: TextInputType.number,
                                decoration: _field(S.t('Quantity', 'Idadi')),
                                validator: (value) => (int.tryParse(value ?? '') ?? 0) <= 0 ? S.t('Required', 'Inahitajika') : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _cost,
                                keyboardType: TextInputType.number,
                                decoration: _field(S.t('Unit cost (TZS)', 'Gharama (TZS)')),
                                validator: (value) => int.tryParse(value ?? '') == null ? S.t('Required', 'Inahitajika') : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(S.t('Expiry date', 'Tarehe ya kuisha')),
                          subtitle: Text('${_expiry.day}/${_expiry.month}/${_expiry.year}'),
                          trailing: const Icon(Icons.calendar_month_outlined, color: PhyimacyBrand.teal),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 3650)),
                              initialDate: _expiry,
                            );
                            if (picked != null) setState(() => _expiry = picked);
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(S.t('Cancel', 'Ghairi'))),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(_busy ? S.t('Saving...', 'Inahifadhi...') : S.t('Receive stock', 'Pokea stock')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
