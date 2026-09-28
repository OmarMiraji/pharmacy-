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
    final doc = pw.Document();
    final teal = PdfColor.fromInt(0xFF0F766E);
    final ink = PdfColor.fromInt(0xFF143230);
    final muted = PdfColor.fromInt(0xFF5B736F);
    final cream = PdfColor.fromInt(0xFFF7F4EC);
    final gold = PdfColor.fromInt(0xFFE8C47A);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(width: 6, height: 28, color: gold),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PHARMSPECIO', style: pw.TextStyle(color: teal, fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 1.4)),
                      pw.SizedBox(height: 2),
                      pw.Text(pharmacyName, style: pw.TextStyle(color: ink, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.Text('Pharmacy report', style: pw.TextStyle(color: muted, fontSize: 11)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColor.fromInt(0xFFD7E5E1)),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated ${dateLabel(DateTime.now())}', style: pw.TextStyle(color: muted, fontSize: 9)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(color: muted, fontSize: 9)),
          ],
        ),
        build: (context) => [
          pw.Text('Period: $rangeLabel', style: pw.TextStyle(color: ink, fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _pdfMetric('Sales revenue', tzs(report.salesTotalMinor), '${report.salesCount} sales', teal, cream),
              pw.SizedBox(width: 8),
              _pdfMetric('Purchases', tzs(report.purchasesTotalMinor), '${report.purchasesCount} records', teal, cream),
              pw.SizedBox(width: 8),
              _pdfMetric('Gross profit', tzs(report.grossProfitMinor), 'After stock cost', teal, cream),
              pw.SizedBox(width: 8),
              _pdfMetric('Stock units', money(report.stockUnits), '${report.lowStockCount} need attention', teal, cream),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Medicine performance', style: pw.TextStyle(color: ink, fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (report.medicinePerformance.isEmpty)
            pw.Text('No medicine activity in this period.', style: pw.TextStyle(color: muted, fontSize: 11))
          else
            pw.TableHelper.fromTextArray(
              headerDecoration: pw.BoxDecoration(color: cream),
              headerStyle: pw.TextStyle(color: ink, fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(color: muted, fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              headers: const ['Medicine', 'Units', 'Revenue (TZS)', 'Cost (TZS)', 'Profit (TZS)'],
              data: report.medicinePerformance
                  .map(
                    (row) => [
                      row.medicineName,
                      money(row.unitsSold),
                      money(row.revenueMinor),
                      money(row.costMinor),
                      money(row.grossProfitMinor),
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfMetric(String label, String value, String note, PdfColor teal, PdfColor cream) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: cream,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(color: teal, fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 2),
            pw.Text(note, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
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
    await Printing.layoutPdf(onLayout: (_) async => bytes);
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
