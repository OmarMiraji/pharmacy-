import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/printer_settings.dart';

void main() {
  test('printer settings default to manual print and keep saved values', () {
    const settings = PrinterSettings();

    expect(settings.autoPrintAfterSale, isFalse);
    expect(settings.defaultPrinterName, isEmpty);
    expect(settings.selectedPrinterUrl, isEmpty);

    final updated = settings.copyWith(
      defaultPrinterName: 'Receipt Printer',
      selectedPrinterUrl: 'ipps://printer/receipt',
      selectedPrinterName: 'Receipt Printer',
      autoPrintAfterSale: true,
    );

    expect(updated.defaultPrinterName, 'Receipt Printer');
    expect(updated.selectedPrinterUrl, 'ipps://printer/receipt');
    expect(updated.selectedPrinterName, 'Receipt Printer');
    expect(updated.autoPrintAfterSale, isTrue);
  });
}
