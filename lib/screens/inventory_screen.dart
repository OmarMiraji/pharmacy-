import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/inventory_service.dart';
import '../backend/inventory_tracking_service.dart';
import '../backend/medicine_service.dart';
import '../backend/models.dart';
import '../backend/user_profile.dart';
import '../backend/expiry_priority.dart';
import '../theme/brand.dart';
import '../l10n/app_locale.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({required this.profile, this.embedded = false, super.key});

  final UserProfile profile;
  final bool embedded;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  DateTime _day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year && _day.month == now.month && _day.day == now.day;
  }

  String get _dayLabel {
    if (_isToday) return S.t('Today', 'Leo');
    return '${_day.day.toString().padLeft(2, '0')}/${_day.month.toString().padLeft(2, '0')}/${_day.year}';
  }

  void _shiftDay(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'Inventory day',
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Medicine>>(
      stream: MedicineService().watchMedicines(),
      builder: (context, medicineSnapshot) {
        if (medicineSnapshot.hasError) return Center(child: Text('Could not load stock: ${medicineSnapshot.error}'));
        if (!medicineSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final medicines = medicineSnapshot.data!;
        return StreamBuilder<List<MedicineBatch>>(
          stream: MedicineService().watchAllBatches(),
          builder: (context, batchSnapshot) {
            final batches = batchSnapshot.data ?? const <MedicineBatch>[];
            return StreamBuilder<DailyInventoryTrack>(
              stream: InventoryTrackingService().watchDay(day: _day, medicines: medicines),
              builder: (context, trackSnapshot) {
                if (trackSnapshot.hasError) {
                  return FutureBuilder<DailyInventoryTrack>(
                    future: InventoryTrackingService().loadDay(day: _day, medicines: medicines),
                    builder: (context, fallback) {
                      if (!fallback.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _body(medicines, batches, fallback.data!);
                    },
                  );
                }
                if (!trackSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                return _body(medicines, batches, trackSnapshot.data!);
              },
            );
          },
        );
      },
    );
  }

  Widget _body(List<Medicine> medicines, List<MedicineBatch> batches, DailyInventoryTrack track) {
    return SingleChildScrollView(
      padding: widget.embedded ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chrome(),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _metric(S.t('On hand now', 'Ipo sasa'), '${track.stockUnits}', S.t('${medicines.length} products', 'Bidhaa ${medicines.length}'), Icons.inventory_2_outlined, const Color(0xffdff7ee))),
            const SizedBox(width: 12),
            Expanded(child: _metric(S.t('Received this day', 'Zilizopokelewa leo'), '${track.unitsIn}', S.t('Stock in from purchases', 'Stock kutoka manunuzi'), Icons.move_to_inbox_rounded, const Color(0xffe8f1ff))),
            const SizedBox(width: 12),
            Expanded(child: _metric(S.t('Sold this day', 'Zilizouzwa leo'), '${track.saleLedgerUnits}', S.t('Stock out from completed sales', 'Stock iliyotoka kwa mauzo'), Icons.point_of_sale_rounded, const Color(0xffffeadf))),
            const SizedBox(width: 12),
            Expanded(child: _metric(S.t('Expired removed', 'Zilizoisha ziliondolewa'), '${track.expiryUnits}', S.t('Written off after expiry', 'Ziliondolewa baada ya kuisha'), Icons.event_busy_rounded, const Color(0xffffeadf))),
          ]),
          if (!track.salesMatchLedger) ...[
            const SizedBox(height: 12),
            _mismatchBanner(track),
          ],
          const SizedBox(height: 14),
          _dayTable(track),
          const SizedBox(height: 14),
          _stockList(medicines, batches),
          const SizedBox(height: 14),
          _ledger(track),
        ],
      ),
    );
  }

  Widget _chrome() {
    final dates = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(onPressed: () => _shiftDay(-1), icon: const Icon(Icons.chevron_left_rounded)),
        const SizedBox(width: 8),
        FilledButton.icon(onPressed: _pickDay, icon: const Icon(Icons.calendar_today_rounded, size: 18), label: Text(_dayLabel)),
        const SizedBox(width: 8),
        IconButton.outlined(
          onPressed: _isToday ? null : () => _shiftDay(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        if (!_isToday) ...[
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => setState(() => _day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)), child: Text(S.t('Today', 'Leo'))),
        ],
      ],
    );
    if (widget.embedded) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Stock in and out for $_dayLabel', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
            ),
            dates,
          ],
        ),
      );
    }
    return Container(
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
            child: const Icon(Icons.inventory_2_outlined, color: PhyimacyBrand.teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('Inventory tracking', 'Ufuatiliaji wa stock'), style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink, height: 1.1)),
                const SizedBox(height: 4),
                Text(S.t('Live stock, units received, and units sold for $_dayLabel.', 'Stock ya sasa, zilizopokelewa, na zilizouzwa tarehe $_dayLabel.'), style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 13)),
              ],
            ),
          ),
          dates,
        ],
      ),
    );
  }

  Widget _mismatchBanner(DailyInventoryTrack track) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xfffff0d7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xffb45309)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sales receipts recorded ${track.saleReceiptUnits} units sold. Stock ledger recorded ${track.saleLedgerUnits} units sold. Check this day before closing.',
              style: GoogleFonts.inter(color: const Color(0xffb45309), fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String note, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, size: 20, color: PhyimacyBrand.teal),
          ),
          const SizedBox(height: 14),
          Text(label, style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          const SizedBox(height: 4),
          Text(note, style: GoogleFonts.inter(color: const Color(0xff879895), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _panel({required String title, required IconData icon, required Widget child, Widget? trailing}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: const Color(0x14073B3A),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 10),
              Icon(icon, color: PhyimacyBrand.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
        ),
      ),
    );
  }

  Widget _dayTable(DailyInventoryTrack track) {
    final active = track.rows.where((row) => row.unitsIn > 0 || row.unitsOut > 0 || row.medicine.quantityOnHand > 0).toList();
    return _panel(
      title: 'Stock vs sales this day',
      icon: Icons.fact_check_outlined,
      trailing: Text(
        track.salesMatchLedger ? 'Sales and stock match' : 'Review differences',
        style: GoogleFonts.inter(
          color: track.salesMatchLedger ? PhyimacyBrand.teal : const Color(0xffb45309),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      child: active.isEmpty
          ? Text('No stock movement for this day yet.', style: GoogleFonts.inter(color: PhyimacyBrand.muted))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 980),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(PhyimacyBrand.cream),
                  headingTextStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink, fontSize: 12),
                  dataTextStyle: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 13),
                  columns: const [
                    DataColumn(label: Text('Medicine')),
                    DataColumn(label: Text('On hand')),
                    DataColumn(label: Text('Received')),
                    DataColumn(label: Text('Sold')),
                    DataColumn(label: Text('Expired')),
                    DataColumn(label: Text('Sale receipts')),
                    DataColumn(label: Text('Net')),
                    DataColumn(label: Text('Check')),
                  ],
                  rows: active.map((row) {
                    final low = row.medicine.quantityOnHand <= row.medicine.reorderLevel;
                    return DataRow(
                      cells: [
                        DataCell(Text(row.medicine.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff143230)))),
                        DataCell(Text('${row.medicine.quantityOnHand} ${row.medicine.unit}', style: TextStyle(fontWeight: FontWeight.w700, color: low ? const Color(0xffb45309) : PhyimacyBrand.ink))),
                        DataCell(Text('${row.unitsIn}')),
                        DataCell(Text('${row.saleLedgerUnits}')),
                        DataCell(Text('${row.expiryUnits}')),
                        DataCell(Text('${row.saleReceiptUnits}')),
                        DataCell(Text('${row.net >= 0 ? '+' : ''}${row.net}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(
                          Text(
                            row.ledgerMatchesSales ? 'Matched' : 'Mismatch',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: row.ledgerMatchesSales ? PhyimacyBrand.teal : const Color(0xffb45309),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  Widget _stockList(List<Medicine> medicines, List<MedicineBatch> batches) {
    final nearest = <String, DateTime>{};
    for (final batch in batches) {
      if (batch.quantityOnHand <= 0) continue;
      final date = batch.expiryDate.toDate();
      final current = nearest[batch.medicineId];
      if (current == null || ExpiryPriority.compare(date, current) < 0) {
        nearest[batch.medicineId] = date;
      }
    }
    final ordered = [...medicines]..sort((a, b) {
      final byExpiry = ExpiryPriority.compare(nearest[a.id], nearest[b.id]);
      if (byExpiry != 0) return byExpiry;
      return a.name.compareTo(b.name);
    });
    return _panel(
      title: 'Current stock',
      icon: Icons.medication_outlined,
      child: medicines.isEmpty
          ? Text('Add a medicine first, then receive its stock here.', style: GoogleFonts.inter(color: PhyimacyBrand.muted))
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ordered.length,
              itemBuilder: (context, index) {
                final medicine = ordered[index];
                final isLow = medicine.quantityOnHand <= medicine.reorderLevel;
                final statusExpiry = nearest[medicine.id];
                final expired = statusExpiry != null && ExpiryPriority.isExpired(statusExpiry);
                final urgent = statusExpiry != null && ExpiryPriority.isUrgent(statusExpiry);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: statusExpiry != null ? ExpiryPriority.tint(statusExpiry) : (isLow ? const Color(0xfffff0d7) : const Color(0xffdff7ee)),
                    child: Icon(
                      expired ? Icons.event_busy_rounded : (urgent ? Icons.priority_high_rounded : Icons.medication_outlined),
                      color: expired || urgent || isLow ? const Color(0xffc2410c) : PhyimacyBrand.teal,
                    ),
                  ),
                  title: Text(medicine.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [
                      '${medicine.sku}  •  ${medicine.stockLabel()} on hand',
                      if (statusExpiry != null) ExpiryPriority.label(statusExpiry),
                    ].join('  •  '),
                  ),
                  trailing: Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (expired)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xffffeadf), borderRadius: BorderRadius.circular(20)),
                          child: const Text('Expired', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xffc2410c))),
                        )
                      else if (urgent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xfffff0d7), borderRadius: BorderRadius.circular(20)),
                          child: const Text('Sell first', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xffc2410c))),
                        ),
                      if (widget.profile.can('inventory.adjust'))
                        FilledButton.tonalIcon(onPressed: () => _showReceiveDialog(context, medicine), icon: const Icon(Icons.add, size: 17), label: const Text('Receive'))
                      else
                        Text(isLow ? 'Low stock' : 'Available'),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _ledger(DailyInventoryTrack track) {
    return _panel(
      title: 'Movement log',
      icon: Icons.history_rounded,
      trailing: Text('${track.movements.length} entries', style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      child: track.movements.isEmpty
          ? Text('No in or out records for this day.', style: GoogleFonts.inter(color: PhyimacyBrand.muted))
          : Column(
              children: track.movements.take(40).map((entry) {
                final expired = entry.type == 'expiry';
                final out = entry.type == 'sale' || expired || entry.quantityChange < 0;
                final time = entry.createdAt;
                final stamp = time == null
                    ? ''
                    : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: out ? const Color(0xffffeadf) : const Color(0xffdff7ee),
                    child: Icon(
                      expired ? Icons.event_busy_rounded : (out ? Icons.south_west_rounded : Icons.north_east_rounded),
                      color: out ? const Color(0xffc2410c) : PhyimacyBrand.teal,
                      size: 18,
                    ),
                  ),
                  title: Text(entry.medicineName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [
                      expired ? 'Expired write-off' : (out ? 'Sold' : (entry.type == 'sale_void' ? 'Returned' : 'Received')),
                      if (entry.batchNumber != null && entry.batchNumber!.isNotEmpty) 'Batch ${entry.batchNumber}',
                      if (stamp.isNotEmpty) stamp,
                    ].join('  •  '),
                  ),
                  trailing: Text(
                    '${out ? '-' : '+'}${entry.units}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: out ? const Color(0xffc2410c) : PhyimacyBrand.teal, fontSize: 16),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Future<void> _showReceiveDialog(BuildContext context, Medicine medicine) async {
    final formKey = GlobalKey<FormState>();
    final batch = TextEditingController();
    final quantity = TextEditingController();
    final cost = TextEditingController();
    DateTime expiry = DateTime.now().add(const Duration(days: 365));
    final service = InventoryService();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.move_to_inbox_rounded, color: PhyimacyBrand.teal),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Receive ${medicine.name}', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
                      IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Stock on hand and the daily in/out log update together.', style: TextStyle(color: Color(0xff68807d), height: 1.4)),
                    const SizedBox(height: 22),
                    TextFormField(controller: batch, decoration: const InputDecoration(labelText: 'Batch number', prefixIcon: Icon(Icons.qr_code_2_rounded)), validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextFormField(controller: quantity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: medicine.sellsLoose ? 'Packs received' : 'Quantity', prefixIcon: const Icon(Icons.inventory_2_outlined)), validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a whole number' : null)),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit cost (TZS)', prefixIcon: Icon(Icons.payments_outlined)), validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a whole number' : null)),
                    ]),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available_outlined, color: PhyimacyBrand.teal),
                      title: const Text('Expiry date'),
                      subtitle: Text('${expiry.day}/${expiry.month}/${expiry.year}'),
                      onTap: () async {
                        final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: expiry);
                        if (picked != null) setState(() => expiry = picked);
                      },
                    ),
                    const SizedBox(height: 15),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final user = AuthService().currentUser;
                          if (user == null) return;
                          await service.receiveBatch(medicineId: medicine.id, batchNumber: batch.text, expiryDate: Timestamp.fromDate(expiry), quantity: int.parse(quantity.text), unitCostMinor: int.parse(cost.text), createdBy: user.uid);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Receive stock'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    batch.dispose();
    quantity.dispose();
    cost.dispose();
  }
}
