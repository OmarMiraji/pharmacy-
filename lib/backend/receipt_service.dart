import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'printer_settings.dart';

class ReceiptLineItem {
  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.totalMinor,
  });

  final String name;
  final int quantity;
  final int unitPriceMinor;
  final int totalMinor;
}

class ReceiptShop {
  const ReceiptShop({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.cashier = '',
  });

  final String name;
  final String phone;
  final String address;
  final String cashier;

  String get displayName {
    final value = name.trim();
    return value.isEmpty ? 'PharmSpecio' : value;
  }
}

class ReceiptSummary {
  const ReceiptSummary({
    required this.receiptNumber,
    required this.soldBy,
    required this.paymentMethod,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.createdAt,
    required this.items,
    this.shop = const ReceiptShop(),
  });

  final String receiptNumber;
  final String soldBy;
  final String paymentMethod;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final DateTime createdAt;
  final List<ReceiptLineItem> items;
  final ReceiptShop shop;

  String get paymentLabel => paymentMethod.trim().isEmpty ? 'Unknown' : paymentMethod;

  String get cashierLabel {
    final named = shop.cashier.trim();
    if (named.isNotEmpty) return named;
    final seller = soldBy.trim();
    return seller.isEmpty ? 'Cashier' : seller;
  }

  ReceiptSummary copyWith({ReceiptShop? shop}) {
    return ReceiptSummary(
      receiptNumber: receiptNumber,
      soldBy: soldBy,
      paymentMethod: paymentMethod,
      subtotalMinor: subtotalMinor,
      discountMinor: discountMinor,
      totalMinor: totalMinor,
      createdAt: createdAt,
      items: items,
      shop: shop ?? this.shop,
    );
  }

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

  String get formattedDate {
    final day = createdAt.day.toString().padLeft(2, '0');
    final month = createdAt.month.toString().padLeft(2, '0');
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$day/$month/${createdAt.year}  $hour:$minute';
  }

  List<String> get lines {
    return <String>[
      shop.displayName,
      'PHARMSPECIO',
      'Receipt: $receiptNumber',
      'Date: $formattedDate',
      if (shop.address.trim().isNotEmpty) shop.address.trim(),
      if (shop.phone.trim().isNotEmpty) shop.phone.trim(),
      'Printed by: $cashierLabel',
      'Payment: $paymentLabel',
      '---',
      ...items.map((item) => '${item.name} x${item.quantity}  ${tzs(item.totalMinor)}'),
      '---',
      'Subtotal: ${tzs(subtotalMinor)}',
      'Discount: ${tzs(discountMinor)}',
      'Total: ${tzs(totalMinor)}',
      'Thank you for shopping with ${shop.displayName}',
    ];
  }

  static ReceiptSummary fromFirestore(Map<String, dynamic> data, {required List<ReceiptLineItem> items}) {
    final price = data['totalMinor'] as num? ?? 0;
    final subtotal = data['subtotalMinor'] as num? ?? 0;
    final discount = data['discountMinor'] as num? ?? 0;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return ReceiptSummary(
      receiptNumber: (data['receiptNumber'] ?? 'R-UNKNOWN').toString(),
      soldBy: (data['soldBy'] ?? 'Unknown').toString(),
      paymentMethod: (data['paymentMethod'] ?? 'cash').toString(),
      subtotalMinor: subtotal.toInt(),
      discountMinor: discount.toInt(),
      totalMinor: price.toInt(),
      createdAt: createdAt,
      items: items,
    );
  }
}

class ReceiptService {
  static const _forest = 0xFF073B3A;
  static const _teal = 0xFF0F766E;
  static const _ink = 0xFF143230;
  static const _muted = 0xFF5B736F;
  static const _cream = 0xFFF7F4EC;
  static const _gold = 0xFFE8C47A;
  static const _line = 0xFFD7E5E1;
  static const _white = 0xFFFFFFFF;

  bool usesA4(PrinterSettings settings) => settings.paperMode != 'thermal';

  Future<Uint8List> buildPdf(
    ReceiptSummary receipt, {
    PrinterSettings settings = const PrinterSettings(),
  }) async {
    pw.ImageProvider? logo;
    try {
      logo = await imageFromAssetBundle('assets/brand/pharmspecio.png');
    } catch (_) {}
    pw.Font? regular;
    pw.Font? bold;
    try {
      regular = pw.Font.ttf(await rootBundle.load('google_fonts/Inter-Regular.ttf'));
      bold = pw.Font.ttf(await rootBundle.load('google_fonts/Inter-Bold.ttf'));
    } catch (_) {}
    final doc = pw.Document(
      title: '${receipt.shop.displayName} ${receipt.receiptNumber}',
      author: 'PharmSpecio',
      theme: regular != null && bold != null ? pw.ThemeData.withFont(base: regular, bold: bold) : null,
    );
    if (usesA4(settings)) {
      doc.addPage(_a4Page(receipt, logo));
    } else {
      doc.addPage(_thermalPage(receipt, settings));
    }
    return doc.save();
  }

  Future<void> printReceipt(
    ReceiptSummary receipt, {
    PrinterSettings settings = const PrinterSettings(),
    BuildContext? context,
  }) async {
    final bytes = await buildPdf(receipt, settings: settings);
    final info = await Printing.info();
    if (!info.canPrint) {
      return;
    }

    final previewOnly = settings.paperMode == 'pdf';
    if (!previewOnly && settings.selectedPrinterUrl.isNotEmpty && context != null) {
      final printers = await Printing.listPrinters();
      if (printers.isNotEmpty) {
        final printer = printers.firstWhere(
          (item) => item.url == settings.selectedPrinterUrl || item.name == settings.selectedPrinterName,
          orElse: () => printers.firstWhere((item) => item.isDefault, orElse: () => printers.first),
        );
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (format) async => bytes,
          name: 'PharmSpecio receipt ${receipt.receiptNumber}',
          format: usesA4(settings) ? PdfPageFormat.a4 : _thermalFormat(receipt, settings),
          dynamicLayout: false,
        );
        return;
      }
    }

    await Printing.layoutPdf(
      name: 'PharmSpecio receipt ${receipt.receiptNumber}',
      format: usesA4(settings) ? PdfPageFormat.a4 : _thermalFormat(receipt, settings),
      onLayout: (PdfPageFormat format) async => bytes,
      dynamicLayout: false,
    );
  }

  PdfPageFormat _thermalFormat(ReceiptSummary receipt, PrinterSettings settings) {
    final paperMm = settings.receiptPaperWidthMm < 58 ? 80.0 : settings.receiptPaperWidthMm.toDouble();
    final widthMm = paperMm.clamp(58.0, 80.0);
    final extras = (receipt.shop.address.trim().isEmpty ? 0 : 8) + (receipt.shop.phone.trim().isEmpty ? 0 : 6);
    final heightMm = 132 + extras + (receipt.items.length * 16);
    return PdfPageFormat(widthMm * PdfPageFormat.mm, heightMm * PdfPageFormat.mm);
  }

  pw.Page _thermalPage(ReceiptSummary receipt, PrinterSettings settings) {
    const black = PdfColors.black;
    final paperMm = settings.receiptPaperWidthMm < 58 ? 80.0 : settings.receiptPaperWidthMm.toDouble().clamp(58.0, 80.0);
    final leftMm = paperMm >= 72 ? 3.0 : 2.0;
    final rightMm = paperMm >= 72 ? 16.0 : 10.0;
    final base = pw.TextStyle(fontSize: 8, color: black, fontWeight: pw.FontWeight.bold, height: 1.15);
    final strong = pw.TextStyle(fontSize: 9, color: black, fontWeight: pw.FontWeight.bold, height: 1.15);
    return pw.Page(
      pageFormat: _thermalFormat(receipt, settings),
      margin: pw.EdgeInsets.fromLTRB(leftMm * PdfPageFormat.mm, 4 * PdfPageFormat.mm, rightMm * PdfPageFormat.mm, 10 * PdfPageFormat.mm),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text('PHARMSPECIO', style: pw.TextStyle(color: black, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8))),
            pw.SizedBox(height: 2),
            pw.Text(receipt.shop.displayName, textAlign: pw.TextAlign.center, style: pw.TextStyle(color: black, fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if (receipt.shop.address.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(receipt.shop.address.trim(), textAlign: pw.TextAlign.center, style: base),
            ],
            if (receipt.shop.phone.trim().isNotEmpty)
              pw.Text(receipt.shop.phone.trim(), textAlign: pw.TextAlign.center, style: base),
            _rule(black, thick: true),
            pw.Center(child: pw.Text('SALES RECEIPT', style: pw.TextStyle(color: black, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6))),
            _rule(black),
            _pair('Receipt', receipt.receiptNumber, base, strong),
            _pair('Date', receipt.formattedDate, base, strong),
            _pair('By', receipt.cashierLabel, base, strong),
            _pair('Pay', receipt.paymentLabel.toUpperCase(), base, strong),
            _rule(black),
            for (final item in receipt.items) ...[
              pw.Text(item.name, maxLines: 2, style: strong),
              pw.SizedBox(height: 1),
              _pair('${item.quantity} x ${ReceiptSummary.money(item.unitPriceMinor)}', ReceiptSummary.tzs(item.totalMinor), base, strong),
            ],
            _rule(black),
            _pair('Subtotal', ReceiptSummary.tzs(receipt.subtotalMinor), base, strong),
            _pair('Discount', ReceiptSummary.tzs(receipt.discountMinor), base, strong),
            _rule(black, thick: true),
            _pair('TOTAL', ReceiptSummary.tzs(receipt.totalMinor), pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: black), pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: black)),
            _rule(black, thick: true),
            pw.SizedBox(height: 4),
            pw.Text('Thank you', textAlign: pw.TextAlign.center, style: base),
            pw.Text(receipt.shop.displayName, textAlign: pw.TextAlign.center, style: strong),
            pw.SizedBox(height: 6),
          ],
        );
      },
    );
  }

  pw.Widget _rule(PdfColor color, {bool thick = false}) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      height: thick ? 1.4 : 0.8,
      color: color,
    );
  }

  pw.Widget _pair(String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 4, child: pw.Text(label, style: labelStyle)),
          pw.SizedBox(width: 6),
          pw.Expanded(flex: 6, child: pw.Text(value, textAlign: pw.TextAlign.right, maxLines: 2, style: valueStyle)),
        ],
      ),
    );
  }

  pw.MultiPage _a4Page(ReceiptSummary receipt, pw.ImageProvider? logo) {
    final forest = PdfColor.fromInt(_forest);
    final teal = PdfColor.fromInt(_teal);
    final ink = PdfColor.fromInt(_ink);
    final muted = PdfColor.fromInt(_muted);
    final cream = PdfColor.fromInt(_cream);
    final gold = PdfColor.fromInt(_gold);
    final white = PdfColor.fromInt(_white);
    final line = PdfColor.fromInt(_line);
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 28),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: pw.BoxDecoration(color: forest, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Container(
                  width: 42,
                  height: 42,
                  decoration: pw.BoxDecoration(color: white, shape: pw.BoxShape.circle),
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PHARMSPECIO', style: pw.TextStyle(color: gold, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1.8)),
                    pw.SizedBox(height: 3),
                    pw.Text(receipt.shop.displayName, style: pw.TextStyle(color: white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    if (receipt.shop.address.trim().isNotEmpty)
                      pw.Text(receipt.shop.address.trim(), style: pw.TextStyle(color: PdfColor.fromInt(0xFFB7D4CF), fontSize: 9)),
                    if (receipt.shop.phone.trim().isNotEmpty)
                      pw.Text(receipt.shop.phone.trim(), style: pw.TextStyle(color: PdfColor.fromInt(0xFFB7D4CF), fontSize: 9)),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C4A48), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('SALES RECEIPT', style: pw.TextStyle(color: gold, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                    pw.SizedBox(height: 4),
                    pw.Text(receipt.receiptNumber, style: pw.TextStyle(color: white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(receipt.formattedDate, style: pw.TextStyle(color: PdfColor.fromInt(0xFFD7E5E1), fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            _infoTile('Printed by', receipt.cashierLabel, cream, teal, ink),
            pw.SizedBox(width: 10),
            _infoTile('Payment', receipt.paymentLabel.toUpperCase(), cream, teal, ink),
            pw.SizedBox(width: 10),
            _infoTile('Items', '${receipt.items.length}', cream, teal, ink),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: forest),
              children: [
                _th('Medicine', white),
                _th('Qty', white, align: pw.Alignment.centerRight),
                _th('Unit price', white, align: pw.Alignment.centerRight),
                _th('Amount', white, align: pw.Alignment.centerRight),
              ],
            ),
            for (var i = 0; i < receipt.items.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: i.isEven ? white : cream),
                children: [
                  _td(receipt.items[i].name, ink, bold: true),
                  _td('${receipt.items[i].quantity}', ink, align: pw.Alignment.centerRight),
                  _td(ReceiptSummary.tzs(receipt.items[i].unitPriceMinor), muted, align: pw.Alignment.centerRight),
                  _td(ReceiptSummary.tzs(receipt.items[i].totalMinor), ink, align: pw.Alignment.centerRight, bold: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Container(
              width: 240,
              padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: pw.BoxDecoration(
                color: cream,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  _moneyRow('Subtotal', ReceiptSummary.tzs(receipt.subtotalMinor), ink, false),
                  pw.SizedBox(height: 4),
                  _moneyRow('Discount', ReceiptSummary.tzs(receipt.discountMinor), ink, false),
                  pw.SizedBox(height: 6),
                  pw.Container(height: 0.6, color: line),
                  pw.SizedBox(height: 6),
                  _moneyRow('Total', ReceiptSummary.tzs(receipt.totalMinor), forest, true),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 28),
        pw.Center(child: pw.Text('Thank you for choosing ${receipt.shop.displayName}', style: pw.TextStyle(color: ink, fontSize: 11, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('This receipt was issued by PharmSpecio. Keep it for your records.', style: pw.TextStyle(color: muted, fontSize: 9))),
      ],
    );
  }

  pw.Widget _infoTile(String label, String value, PdfColor fill, PdfColor labelColor, PdfColor valueColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: pw.BoxDecoration(color: fill, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label.toUpperCase(), style: pw.TextStyle(color: labelColor, fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.6)),
            pw.SizedBox(height: 3),
            pw.Text(value, style: pw.TextStyle(color: valueColor, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
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
        child: pw.Text(text, style: pw.TextStyle(color: color, fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ),
    );
  }

  pw.Widget _moneyRow(String label, String value, PdfColor color, bool emphasis) {
    final size = emphasis ? 11.0 : 8.5;
    return pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: pw.TextStyle(color: color, fontSize: size, fontWeight: pw.FontWeight.bold))),
        pw.Text(value, style: pw.TextStyle(color: color, fontSize: size, fontWeight: emphasis ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }
}
