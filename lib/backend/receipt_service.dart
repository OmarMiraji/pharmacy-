import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
  });

  final String receiptNumber;
  final String soldBy;
  final String paymentMethod;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final DateTime createdAt;
  final List<ReceiptLineItem> items;

  String get paymentLabel => paymentMethod.trim().isEmpty ? 'Unknown' : paymentMethod;

  List<String> get lines {
    final formattedDate = '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    final list = <String>[
      'PHYIMACY',
      'Receipt: $receiptNumber',
      'Date: $formattedDate',
      'Seller: $soldBy',
      'Payment: $paymentLabel',
      '---',
      ...items.map((item) => '${item.name} x${item.quantity}  TZS ${item.totalMinor}'),
      '---',
      'Subtotal: TZS $subtotalMinor',
      'Discount: TZS $discountMinor',
      'Total: TZS $totalMinor',
      'Thank you for shopping with PHYIMACY',
    ];
    return list;
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
  Future<void> printReceipt(
    ReceiptSummary receipt, {
    PrinterSettings settings = const PrinterSettings(),
    BuildContext? context,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80, 250 + (receipt.items.length * 18), marginAll: 8),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('PHYIMACY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 8),
              pw.Text('Receipt: ${receipt.receiptNumber}'),
              pw.Text('Date: ${receipt.createdAt.day.toString().padLeft(2, '0')}/${receipt.createdAt.month.toString().padLeft(2, '0')}/${receipt.createdAt.year} ${receipt.createdAt.hour.toString().padLeft(2, '0')}:${receipt.createdAt.minute.toString().padLeft(2, '0')}'),
              pw.Text('Seller: ${receipt.soldBy}'),
              pw.Text('Payment: ${receipt.paymentLabel}'),
              pw.Divider(),
              ...receipt.items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${item.name} x${item.quantity}'),
                        pw.Text('TZS ${item.totalMinor}'),
                      ],
                    ),
                  )),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal'),
                  pw.Text('TZS ${receipt.subtotalMinor}'),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Discount'),
                  pw.Text('TZS ${receipt.discountMinor}'),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('TZS ${receipt.totalMinor}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text('Thank you for shopping with PHYIMACY'),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    final info = await Printing.info();
    if (!info.canPrint) {
      return;
    }

    if (settings.selectedPrinterUrl.isNotEmpty && context != null) {
      final printer = await Printing.listPrinters().then((printers) => printers.firstWhere(
            (item) => item.url == settings.selectedPrinterUrl || item.name == settings.selectedPrinterName,
            orElse: () => printers.firstWhere((item) => item.isDefault, orElse: () => printers.first),
          ));
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (format) async => bytes,
        name: 'Phyimacy receipt ${receipt.receiptNumber}',
      );
      return;
    }

    await Printing.layoutPdf(
      name: 'Phyimacy receipt ${receipt.receiptNumber}',
      onLayout: (PdfPageFormat format) async => bytes,
      usePrinterSettings: settings.defaultPrinterName.isNotEmpty,
    );
  }
}
