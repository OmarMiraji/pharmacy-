import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../backend/inventory_service.dart';
import '../backend/models.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

enum _ExpiryMode { fullDate, monthYear, yearOnly }

/// Add units to shelf stock. New qty goes to a **new batch** (or an explicit batch no.)
/// without changing catalog prices or expiry on existing batches.
Future<void> showIncreaseStockDialog(
  BuildContext context, {
  required Medicine medicine,
  InventoryService? inventoryService,
}) async {
  final service = inventoryService ?? InventoryService();
  final formKey = GlobalKey<FormState>();
  final batchNumber = TextEditingController();
  final quantity = TextEditingController();
  final buyingPrice = TextEditingController(
    text: medicine.purchasePriceMinor > 0
        ? '${medicine.purchasePriceMinor}'
        : '',
  );
  final sellingPrice = TextEditingController(
    text: medicine.sellingPriceMinor > 0
        ? '${medicine.sellingPriceMinor}'
        : '',
  );

  var expiryMode = _ExpiryMode.fullDate;
  var expiryDate = DateTime.now().add(const Duration(days: 365));
  var expiryYear = expiryDate.year;
  var expiryMonth = expiryDate.month;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        String expirySummary() {
          switch (expiryMode) {
            case _ExpiryMode.fullDate:
              return '${expiryDate.day.toString().padLeft(2, '0')}/'
                  '${expiryDate.month.toString().padLeft(2, '0')}/'
                  '${expiryDate.year}';
            case _ExpiryMode.monthYear:
              return '${_monthLabel(expiryMonth)} $expiryYear';
            case _ExpiryMode.yearOnly:
              return '$expiryYear';
          }
        }

        DateTime resolvedExpiry() {
          switch (expiryMode) {
            case _ExpiryMode.fullDate:
              return DateTime(
                expiryDate.year,
                expiryDate.month,
                expiryDate.day,
              );
            case _ExpiryMode.monthYear:
              return DateTime(expiryYear, expiryMonth + 1, 0);
            case _ExpiryMode.yearOnly:
              return DateTime(expiryYear, 12, 31);
          }
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22073B3A),
                  blurRadius: 28,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xffdff7ee),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.add_box_outlined,
                                color: PhyimacyBrand.teal,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    S.t(
                                      'Increase stock',
                                      'Ongeza stock',
                                    ),
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: PhyimacyBrand.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    medicine.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: PhyimacyBrand.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          S.t(
                            'New units get the prices and expiry you enter here. Stock already on the shelf keeps its own batch details.',
                            'Vipimo vipya vitachukua bei na muda wa kuisha unaoweka hapa. Stock iliyokuwepo haibadilishwi.',
                          ),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xff68807d),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          S.t(
                            'On hand now: ${medicine.stockLabel()}',
                            'Stock sasa: ${medicine.stockLabel()}',
                          ),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: PhyimacyBrand.teal,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: batchNumber,
                          decoration: InputDecoration(
                            labelText: S.t(
                              'Batch / lot (optional)',
                              'Batch (si lazima)',
                            ),
                            hintText: S.t(
                              'Leave empty for a new batch',
                              'Acha tupu kwa batch mpya',
                            ),
                            prefixIcon: const Icon(Icons.qr_code_2_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: quantity,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: medicine.piecesPerPack > 1
                                      ? S.t('Packs to add', 'Pakiti kuongeza')
                                      : S.t('Quantity to add', 'Idadi kuongeza'),
                                  prefixIcon: const Icon(
                                    Icons.inventory_2_outlined,
                                  ),
                                ),
                                validator: (value) {
                                  final n = int.tryParse(value ?? '');
                                  if (n == null || n <= 0) {
                                    return S.t(
                                      'Enter a whole number',
                                      'Weka namba kamili',
                                    );
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: buyingPrice,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: S.t(
                                    'Buying price (TZS)',
                                    'Bei ya kununua (TZS)',
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.shopping_bag_outlined,
                                  ),
                                ),
                                validator: (value) {
                                  final n = int.tryParse(value ?? '');
                                  if (n == null || n < 0) {
                                    return S.t(
                                      'Enter a whole number',
                                      'Weka namba kamili',
                                    );
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: sellingPrice,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: S.t(
                                    'Selling price (TZS)',
                                    'Bei ya kuuza (TZS)',
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.sell_outlined,
                                  ),
                                ),
                                validator: (value) {
                                  final n = int.tryParse(value ?? '');
                                  if (n == null || n < 0) {
                                    return S.t(
                                      'Enter a whole number',
                                      'Weka namba kamili',
                                    );
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          S.t('Expiry', 'Muda wa kuisha').toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: PhyimacyBrand.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<_ExpiryMode>(
                          segments: [
                            ButtonSegment(
                              value: _ExpiryMode.fullDate,
                              label: Text(S.t('Day', 'Tarehe')),
                              icon: const Icon(Icons.calendar_today, size: 16),
                            ),
                            ButtonSegment(
                              value: _ExpiryMode.monthYear,
                              label: Text(S.t('Month', 'Mwezi')),
                              icon: const Icon(Icons.date_range, size: 16),
                            ),
                            ButtonSegment(
                              value: _ExpiryMode.yearOnly,
                              label: Text(S.t('Year', 'Mwaka')),
                              icon: const Icon(Icons.event, size: 16),
                            ),
                          ],
                          selected: {expiryMode},
                          onSelectionChanged: (set) {
                            setDialogState(() => expiryMode = set.first);
                          },
                        ),
                        const SizedBox(height: 10),
                        Material(
                          color: const Color(0xfff4faf8),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              if (expiryMode == _ExpiryMode.fullDate) {
                                final picked = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 3650),
                                  ),
                                  initialDate: expiryDate,
                                );
                                if (picked != null) {
                                  setDialogState(() => expiryDate = picked);
                                }
                                return;
                              }
                              if (expiryMode == _ExpiryMode.monthYear) {
                                await _pickMonthYear(
                                  context,
                                  initialYear: expiryYear,
                                  initialMonth: expiryMonth,
                                  onPicked: (y, m) {
                                    setDialogState(() {
                                      expiryYear = y;
                                      expiryMonth = m;
                                    });
                                  },
                                );
                                return;
                              }
                              await _pickYearOnly(
                                context,
                                initialYear: expiryYear,
                                onPicked: (y) {
                                  setDialogState(() => expiryYear = y);
                                },
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.event_available_outlined,
                                    color: PhyimacyBrand.teal,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          S.t(
                                            'Expiry date',
                                            'Tarehe ya kuisha',
                                          ),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            color: PhyimacyBrand.ink,
                                          ),
                                        ),
                                        Text(
                                          expirySummary(),
                                          style: GoogleFonts.inter(
                                            color: PhyimacyBrand.teal,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: PhyimacyBrand.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: Text(S.t('Cancel', 'Ghairi')),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final user = AuthService().currentUser;
                                if (user == null) return;
                                try {
                                  await service.receiveBatch(
                                    medicineId: medicine.id,
                                    batchNumber: batchNumber.text,
                                    expiryDate: Timestamp.fromDate(
                                      resolvedExpiry(),
                                    ),
                                    quantity: int.parse(quantity.text),
                                    unitCostMinor: int.parse(buyingPrice.text),
                                    sellingPriceMinor: int.parse(
                                      sellingPrice.text,
                                    ),
                                    createdBy: user.uid,
                                  );
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } catch (error) {
                                  if (!dialogContext.mounted) return;
                                  ScaffoldMessenger.of(dialogContext)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(error.toString()),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(S.t('Save', 'Hifadhi')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  batchNumber.dispose();
  quantity.dispose();
  buyingPrice.dispose();
  sellingPrice.dispose();
}

String _monthLabel(int month) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (month < 1 || month > 12) return '$month';
  return names[month - 1];
}

Future<void> _pickYearOnly(
  BuildContext context, {
  required int initialYear,
  required void Function(int year) onPicked,
}) async {
  final now = DateTime.now();
  final years = List.generate(12, (i) => now.year + i);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(S.t('Expiry year', 'Mwaka wa kuisha')),
      content: SizedBox(
        width: 280,
        height: 320,
        child: ListView.builder(
          itemCount: years.length,
          itemBuilder: (_, index) {
            final year = years[index];
            return ListTile(
              title: Text('$year'),
              trailing: year == initialYear
                  ? const Icon(Icons.check, color: PhyimacyBrand.teal)
                  : null,
              onTap: () {
                onPicked(year);
                Navigator.pop(ctx);
              },
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _pickMonthYear(
  BuildContext context, {
  required int initialYear,
  required int initialMonth,
  required void Function(int year, int month) onPicked,
}) async {
  var year = initialYear;
  var month = initialMonth;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(S.t('Expiry month', 'Mwezi na mwaka')),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: year,
                decoration: InputDecoration(
                  labelText: S.t('Year', 'Mwaka'),
                ),
                items: [
                  for (var y = DateTime.now().year;
                      y <= DateTime.now().year + 11;
                      y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => year = v);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var m = 1; m <= 12; m++)
                    ChoiceChip(
                      label: Text(_monthLabel(m)),
                      selected: month == m,
                      onSelected: (_) => setState(() => month = m),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('Cancel', 'Ghairi')),
          ),
          FilledButton(
            onPressed: () {
              onPicked(year, month);
              Navigator.pop(ctx);
            },
            child: Text(S.t('Done', 'Sawa')),
          ),
        ],
      ),
    ),
  );
}
