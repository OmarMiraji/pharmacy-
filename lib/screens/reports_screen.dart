import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/report_export_service.dart';
import '../backend/report_service.dart';
import '../backend/tenant_context.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';

enum _ReportPeriod { thisMonth, lastMonth, thisYear, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from;
  late DateTime _to;
  late int _year;
  int? _month;
  _ReportPeriod _period = _ReportPeriod.thisMonth;
  late Future<DetailedReport> _reportFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _applyThisMonth(reload: false);
    _reportFuture = ReportService().loadDetailedReport(from: _from, to: _to);
  }

  List<int> get _years {
    final now = DateTime.now().year;
    return [for (var year = 2024; year <= now + 1; year++) year];
  }

  void _reload() {
    setState(() {
      _reportFuture = ReportService().loadDetailedReport(from: _from, to: _to);
    });
  }

  void _setRange(DateTime from, DateTime to) {
    _from = DateTime(from.year, from.month, from.day);
    _to = DateTime(to.year, to.month, to.day);
  }

  void _applyThisMonth({bool reload = true}) {
    final now = DateTime.now();
    _period = _ReportPeriod.thisMonth;
    _year = now.year;
    _month = now.month;
    _setRange(DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
    if (reload) _reload();
  }

  void _applyLastMonth() {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, 0);
    _period = _ReportPeriod.lastMonth;
    _year = last.year;
    _month = last.month;
    _setRange(DateTime(last.year, last.month, 1), last);
    _reload();
  }

  void _applyThisYear() {
    final now = DateTime.now();
    _period = _ReportPeriod.thisYear;
    _year = now.year;
    _month = null;
    _setRange(DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
    _reload();
  }

  void _applyYear(int year) {
    _year = year;
    if (_month == null) {
      _period = year == DateTime.now().year ? _ReportPeriod.thisYear : _ReportPeriod.custom;
      _setRange(DateTime(year, 1, 1), DateTime(year, 12, 31));
    } else {
      _period = _ReportPeriod.custom;
      _setRange(DateTime(year, _month!, 1), DateTime(year, _month! + 1, 0));
    }
    _reload();
  }

  void _applyMonth(int? month) {
    _month = month;
    if (month == null) {
      _period = _year == DateTime.now().year ? _ReportPeriod.thisYear : _ReportPeriod.custom;
      _setRange(DateTime(_year, 1, 1), DateTime(_year, 12, 31));
    } else {
      _period = _ReportPeriod.custom;
      _setRange(DateTime(_year, month, 1), DateTime(_year, month + 1, 0));
    }
    _reload();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _from : _to,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
              helpText: isStart ? S.t('From date', 'Kuanzia') : S.t('To date', 'Mpaka'),
    );
    if (picked == null || !mounted) return;
    _period = _ReportPeriod.custom;
    if (isStart) {
      _from = DateTime(picked.year, picked.month, picked.day);
      if (_from.isAfter(_to)) _to = _from;
    } else {
      _to = DateTime(picked.year, picked.month, picked.day);
      if (_to.isBefore(_from)) _from = _to;
    }
    _year = _from.year;
    _month = _from.year == _to.year && _from.month == _to.month ? _from.month : null;
    _reload();
  }

  String _rangeLabel() {
    if (_period == _ReportPeriod.thisMonth) {
      return S.t(
        'This month · ${ReportExportService.dateLabel(_from)} – ${ReportExportService.dateLabel(_to)}',
        'Mwezi huu · ${ReportExportService.dateLabel(_from)} – ${ReportExportService.dateLabel(_to)}',
      );
    }
    if (_period == _ReportPeriod.lastMonth) {
      return S.t(
        'Last month · ${ReportExportService.dateLabel(_from)} – ${ReportExportService.dateLabel(_to)}',
        'Mwezi uliopita · ${ReportExportService.dateLabel(_from)} – ${ReportExportService.dateLabel(_to)}',
      );
    }
    if (_period == _ReportPeriod.thisYear) return S.t('This year · $_year', 'Mwaka huu · $_year');
    if (_month != null) return '${S.monthName(_month!)} $_year';
    return '${ReportExportService.dateLabel(_from)} – ${ReportExportService.dateLabel(_to)}';
  }

  Future<void> _runExport(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(DetailedReport report) {
    return _runExport(() async {
      await ReportExportService().printReport(
        report: report,
        pharmacyName: TenantContext.instance.pharmacyName ?? 'Pharmacy',
        rangeLabel: _rangeLabel(),
      );
    });
  }

  Future<void> _downloadPdf(DetailedReport report) {
    return _runExport(() async {
      final path = await ReportExportService().savePdf(
        report: report,
        pharmacyName: TenantContext.instance.pharmacyName ?? 'Pharmacy',
        rangeLabel: _rangeLabel(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report saved to $path')));
    });
  }

  Future<void> _exportCsv(DetailedReport report) {
    return _runExport(() async {
      final path = await ReportExportService().saveCsv(
        report: report,
        pharmacyName: TenantContext.instance.pharmacyName ?? 'Pharmacy',
        rangeLabel: _rangeLabel(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Spreadsheet saved to $path')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        return FutureBuilder<DetailedReport>(
      future: _reportFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load reports: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final report = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(report),
              const SizedBox(height: 14),
              _filters(),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _metric(S.t('Sales revenue', 'Mapato ya mauzo'), ReportExportService.tzs(report.salesTotalMinor), S.t('${report.salesCount} completed sales', 'Mauzo ${report.salesCount} yamekamilika'), Icons.trending_up_rounded, const Color(0xffdff7ee))),
                const SizedBox(width: 12),
                Expanded(child: _metric(S.t('Purchases', 'Manunuzi'), ReportExportService.tzs(report.purchasesTotalMinor), S.t('${report.purchasesCount} purchase records', 'Rekodi ${report.purchasesCount} za ununuzi'), Icons.shopping_cart_outlined, const Color(0xffffeadf))),
                const SizedBox(width: 12),
                Expanded(child: _metric(S.t('Gross profit', 'Faida ghafi'), ReportExportService.tzs(report.grossProfitMinor), S.t('Net margin after stock cost', 'Faida baada ya gharama ya stock'), Icons.paid_rounded, const Color(0xffe8f1ff))),
                const SizedBox(width: 12),
                Expanded(child: _metric(S.t('Stock units', 'Vipande vya stock'), ReportExportService.money(report.stockUnits), S.t('${report.lowStockCount} products need attention', 'Bidhaa ${report.lowStockCount} zinahitaji uangalizi'), Icons.inventory_2_outlined, const Color(0xfffff0d7))),
              ]),
              const SizedBox(height: 14),
              _table(report),
            ],
          ),
        );
      },
    );
      },
    );
  }

  Widget _header(DetailedReport report) {
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
            child: const Icon(Icons.insights_rounded, color: PhyimacyBrand.teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('Reports & insights', 'Ripoti na uchambuzi'), style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink, height: 1.1)),
                const SizedBox(height: 4),
                Text(_rangeLabel(), style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 13)),
              ],
            ),
          ),
          _ActionChip(icon: Icons.print_outlined, label: S.t('Print', 'Chapisha'), onPressed: _busy ? null : () => _print(report)),
          const SizedBox(width: 8),
          _ActionChip(icon: Icons.download_outlined, label: S.t('Download', 'Pakua'), filled: true, onPressed: _busy ? null : () => _downloadPdf(report)),
          const SizedBox(width: 8),
          _ActionChip(icon: Icons.table_view_outlined, label: S.t('Export', 'Tuma'), onPressed: _busy ? null : () => _exportCsv(report)),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 10),
              Text(S.t('Choose period', 'Chagua kipindi'), style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PeriodChip(label: S.t('This month', 'Mwezi huu'), selected: _period == _ReportPeriod.thisMonth, onTap: _applyThisMonth),
              _PeriodChip(label: S.t('Last month', 'Mwezi uliopita'), selected: _period == _ReportPeriod.lastMonth, onTap: _applyLastMonth),
              _PeriodChip(label: S.t('This year', 'Mwaka huu'), selected: _period == _ReportPeriod.thisYear, onTap: _applyThisYear),
              _PeriodChip(label: S.t('Custom dates', 'Tarehe maalum'), selected: _period == _ReportPeriod.custom, onTap: () => setState(() => _period = _ReportPeriod.custom)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('report-year-$_year'),
                  initialValue: _year,
                  decoration: InputDecoration(labelText: S.t('Year', 'Mwaka'), prefixIcon: const Icon(Icons.calendar_month_outlined)),
                  items: _years.map((year) => DropdownMenuItem(value: year, child: Text('$year'))).toList(),
                  onChanged: (year) {
                    if (year == null) return;
                    _applyYear(year);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('report-month-$_month'),
                  initialValue: _month,
                  decoration: InputDecoration(labelText: S.t('Month', 'Mwezi'), prefixIcon: const Icon(Icons.event_outlined)),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(S.t('All months', 'Miezi yote'))),
                    ...List.generate(12, (index) => DropdownMenuItem<int?>(value: index + 1, child: Text(S.monthName(index + 1)))),
                  ],
                  onChanged: _applyMonth,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _DateTile(label: S.t('From date', 'Kuanzia'), value: ReportExportService.dateLabel(_from), onTap: () => _pickDate(isStart: true))),
              const SizedBox(width: 12),
              Expanded(child: _DateTile(label: S.t('To date', 'Mpaka'), value: ReportExportService.dateLabel(_to), onTap: () => _pickDate(isStart: false))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, String note, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          const SizedBox(height: 5),
          Text(note, style: GoogleFonts.inter(color: const Color(0xff879895), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _table(DetailedReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x14073B3A), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: PhyimacyBrand.gold, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 10),
              const Icon(Icons.bar_chart_rounded, color: PhyimacyBrand.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(S.t('Medicine performance', 'Utendaji wa dawa'), style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: PhyimacyBrand.ink))),
              Text(S.t('${report.medicinePerformance.length} medicines', 'Dawa ${report.medicinePerformance.length}'), style: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          if (report.medicinePerformance.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(S.t('No medicine activity in this selected range.', 'Hakuna mauzo ya dawa kwenye kipindi hiki.'), style: GoogleFonts.inter(color: PhyimacyBrand.muted))),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 760),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(PhyimacyBrand.cream),
                  columnSpacing: 28,
                  headingTextStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, color: PhyimacyBrand.ink, fontSize: 12),
                  dataTextStyle: GoogleFonts.inter(color: PhyimacyBrand.muted, fontSize: 13),
                  columns: [
                    DataColumn(label: Text(S.t('Medicine', 'Dawa'))),
                    DataColumn(label: Text(S.t('Units', 'Vipande'))),
                    DataColumn(label: Text(S.t('Revenue', 'Mapato'))),
                    DataColumn(label: Text(S.t('Cost', 'Gharama'))),
                    DataColumn(label: Text(S.t('Profit', 'Faida'))),
                  ],
                  rows: report.medicinePerformance
                      .map(
                        (row) => DataRow(
                          cells: [
                            DataCell(Text(row.medicineName, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff143230)))),
                            DataCell(Text(ReportExportService.money(row.unitsSold))),
                            DataCell(Text(ReportExportService.tzs(row.revenueMinor))),
                            DataCell(Text(ReportExportService.tzs(row.costMinor))),
                            DataCell(Text(ReportExportService.tzs(row.grossProfitMinor), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff0f766e)))),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onPressed, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
    }
    return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PhyimacyBrand.teal : PhyimacyBrand.cream,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected ? Colors.white : PhyimacyBrand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.date_range_rounded),
        ),
        child: Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
      ),
    );
  }
}
