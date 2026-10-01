import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'report_service.dart';

class ReportExportService {
  static String money(int value) {
    final sign = value < 0 ? '-' : '';
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '$sign$buffer';
  }

  static String tzs(int value) => 'TZS ${money(value)}';

  static String dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  static String fileStamp(DateTime from, DateTime to) {
    return '${from.year}${from.month.toString().padLeft(2, '0')}${from.day.toString().padLeft(2, '0')}-'
        '${to.year}${to.month.toString().padLeft(2, '0')}${to.day.toString().padLeft(2, '0')}';
  }

  Future<Uint8List> buildPdf({
    required DetailedReport report,
    required String pharmacyName,
    required String rangeLabel,
  }) async {
    final doc = pw.Document(title: 'PharmSpecio report — $pharmacyName', author: 'PharmSpecio');
    final forest = PdfColor.fromInt(0xFF073B3A);
    final teal = PdfColor.fromInt(0xFF0F766E);
    final ink = PdfColor.fromInt(0xFF143230);
    final muted = PdfColor.fromInt(0xFF5B736F);
    final cream = PdfColor.fromInt(0xFFF7F4EC);
    final gold = PdfColor.fromInt(0xFFE8C47A);
    final line = PdfColor.fromInt(0xFFD7E5E1);
    final white = PdfColor.fromInt(0xFFFFFFFF);
    pw.ImageProvider? logo;
    try {
      logo = await imageFromAssetBundle('assets/brand/pharmspecio.png');
    } catch (_) {}

    final now = DateTime.now();
    final printedAt =
        '${dateLabel(now)}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    pw.Widget kpi(String label, String value, String note) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: pw.BoxDecoration(
            color: cream,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border(left: pw.BorderSide(color: gold, width: 3)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(), style: pw.TextStyle(color: teal, fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6)),
              pw.SizedBox(height: 6),
              pw.Text(value, style: pw.TextStyle(color: ink, fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(note, style: pw.TextStyle(color: muted, fontSize: 8)),
            ],
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
        header: (context) {
          return pw.Column(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: pw.BoxDecoration(color: forest, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null) ...[
                      pw.Container(
                        width: 36,
                        height: 36,
                        decoration: pw.BoxDecoration(color: white, shape: pw.BoxShape.circle),
                        child: pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Image(logo, fit: pw.BoxFit.contain),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('PHARMSPECIO', style: pw.TextStyle(color: gold, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1.8)),
                          pw.SizedBox(height: 2),
                          pw.Text(pharmacyName, style: pw.TextStyle(color: white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Pharmacy management report', style: pw.TextStyle(color: PdfColor.fromInt(0xFFB7D4CF), fontSize: 9)),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('PERIOD', style: pw.TextStyle(color: gold, fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
                        pw.SizedBox(height: 2),
                        pw.Text(rangeLabel, style: pw.TextStyle(color: white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Confidential', style: pw.TextStyle(color: PdfColor.fromInt(0xFFB7D4CF), fontSize: 8)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
            ],
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('PharmSpecio  ·  Printed $printedAt', style: pw.TextStyle(color: muted, fontSize: 8)),
                pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(color: muted, fontSize: 8)),
              ],
            ),
          );
        },
        build: (context) => [
          pw.Row(
            children: [
              kpi('Sales revenue', tzs(report.salesTotalMinor), '${report.salesCount} completed sales'),
              pw.SizedBox(width: 8),
              kpi('Purchases', tzs(report.purchasesTotalMinor), '${report.purchasesCount} purchase records'),
              pw.SizedBox(width: 8),
              kpi('Gross profit', tzs(report.grossProfitMinor), 'Revenue minus stock cost'),
              pw.SizedBox(width: 8),
              kpi('Stock on hand', money(report.stockUnits), '${report.lowStockCount} items need reorder'),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Medicine performance', style: pw.TextStyle(color: ink, fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Text('${report.medicinePerformance.length} medicines', style: pw.TextStyle(color: muted, fontSize: 9)),
            ],
          ),
          pw.SizedBox(height: 8),
          if (report.medicinePerformance.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(color: cream, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Text('No medicine sales in this period.', style: pw.TextStyle(color: muted, fontSize: 10)),
            )
          else
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: line, width: 0.4),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3.2),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(1.4),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: teal),
                  children: [
                    _th('Medicine', white),
                    _th('Units', white, align: pw.Alignment.centerRight),
                    _th('Revenue', white, align: pw.Alignment.centerRight),
                    _th('Cost', white, align: pw.Alignment.centerRight),
                    _th('Profit', white, align: pw.Alignment.centerRight),
                  ],
                ),
                for (var i = 0; i < report.medicinePerformance.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: i.isEven ? white : cream),
                    children: [
                      _td(report.medicinePerformance[i].medicineName, ink, bold: true),
                      _td(money(report.medicinePerformance[i].unitsSold), muted, align: pw.Alignment.centerRight),
                      _td(money(report.medicinePerformance[i].revenueMinor), muted, align: pw.Alignment.centerRight),
                      _td(money(report.medicinePerformance[i].costMinor), muted, align: pw.Alignment.centerRight),
                      _td(money(report.medicinePerformance[i].grossProfitMinor), ink, align: pw.Alignment.centerRight, bold: true),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _th(String text, PdfColor color, {pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: pw.TextStyle(color: color, fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ),
    );
  }

  pw.Widget _td(String text, PdfColor color, {pw.Alignment align = pw.Alignment.centerLeft, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: pw.TextStyle(color: color, fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
  }

  String buildCsv(DetailedReport report, {required String pharmacyName, required String rangeLabel}) {
    final lines = <String>[
      _csv(['Phyimacy report']),
      _csv(['Pharmacy', pharmacyName]),
      _csv(['Period', rangeLabel]),
      _csv(['Sales revenue (TZS)', money(report.salesTotalMinor)]),
      _csv(['Completed sales', '${report.salesCount}']),
      _csv(['Purchases (TZS)', money(report.purchasesTotalMinor)]),
      _csv(['Purchase records', '${report.purchasesCount}']),
      _csv(['Gross profit (TZS)', money(report.grossProfitMinor)]),
      _csv(['Stock units', '${report.stockUnits}']),
      _csv(['Low stock items', '${report.lowStockCount}']),
      '',
      _csv(['Medicine', 'Units', 'Revenue (TZS)', 'Cost (TZS)', 'Profit (TZS)']),
      ...report.medicinePerformance.map(
        (row) => _csv([
          row.medicineName,
          '${row.unitsSold}',
          money(row.revenueMinor),
          money(row.costMinor),
          money(row.grossProfitMinor),
        ]),
      ),
    ];
    return lines.join('\r\n');
  }

  String _csv(List<String> cells) {
    return cells.map((cell) {
      final needsQuotes = cell.contains(',') || cell.contains('"') || cell.contains('\n');
      final escaped = cell.replaceAll('"', '""');
      return needsQuotes ? '"$escaped"' : escaped;
    }).join(',');
  }

  Future<void> printReport({
    required DetailedReport report,
    required String pharmacyName,
    required String rangeLabel,
  }) async {
    final bytes = await buildPdf(report: report, pharmacyName: pharmacyName, rangeLabel: rangeLabel);
    await Printing.layoutPdf(
      name: 'PharmSpecio report $rangeLabel',
      format: PdfPageFormat.a4,
      usePrinterSettings: false,
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

  Future<String?> savePdf({
    required DetailedReport report,
    required String pharmacyName,
    required String rangeLabel,
  }) async {
    final bytes = await buildPdf(report: report, pharmacyName: pharmacyName, rangeLabel: rangeLabel);
    final name = 'phyimacy-report-${fileStamp(report.range.start, report.range.end)}.pdf';
    return _saveBytes(fileName: name, extension: 'pdf', bytes: bytes);
  }

  Future<String?> saveCsv({
    required DetailedReport report,
    required String pharmacyName,
    required String rangeLabel,
  }) async {
    final csv = buildCsv(report, pharmacyName: pharmacyName, rangeLabel: rangeLabel);
    final name = 'phyimacy-report-${fileStamp(report.range.start, report.range.end)}.csv';
    return _saveBytes(fileName: name, extension: 'csv', bytes: Uint8List.fromList(utf8.encode(csv)));
  }

  Future<String?> _saveBytes({
    required String fileName,
    required String extension,
    required Uint8List bytes,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save pharmacy report',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path.endsWith('.$extension') ? path : '$path.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
