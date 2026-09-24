class PrinterSettings {
  const PrinterSettings({
    this.defaultPrinterName = '',
    this.selectedPrinterName = '',
    this.selectedPrinterUrl = '',
    this.receiptPaperWidthMm = 80,
    this.autoPrintAfterSale = false,
    this.paperMode = 'thermal',
  });

  final String defaultPrinterName;
  final String selectedPrinterName;
  final String selectedPrinterUrl;
  final int receiptPaperWidthMm;
  final bool autoPrintAfterSale;
  final String paperMode;

  PrinterSettings copyWith({
    String? defaultPrinterName,
    String? selectedPrinterName,
    String? selectedPrinterUrl,
    int? receiptPaperWidthMm,
    bool? autoPrintAfterSale,
    String? paperMode,
  }) {
    return PrinterSettings(
      defaultPrinterName: defaultPrinterName ?? this.defaultPrinterName,
      selectedPrinterName: selectedPrinterName ?? this.selectedPrinterName,
      selectedPrinterUrl: selectedPrinterUrl ?? this.selectedPrinterUrl,
      receiptPaperWidthMm: receiptPaperWidthMm ?? this.receiptPaperWidthMm,
      autoPrintAfterSale: autoPrintAfterSale ?? this.autoPrintAfterSale,
      paperMode: paperMode ?? this.paperMode,
    );
  }
}

class PrinterSettingsStore {
  PrinterSettingsStore._();

  static final instance = PrinterSettingsStore._();

  PrinterSettings _settings = const PrinterSettings();

  PrinterSettings get current => _settings;

  void set(PrinterSettings settings) {
    _settings = settings;
  }

  void update(PrinterSettings Function(PrinterSettings current) updater) {
    _settings = updater(_settings);
  }
}
