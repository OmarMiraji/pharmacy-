import 'dart:async';
import 'dart:convert';

import '../platform/local_store.dart';

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

  Map<String, Object> toJson() {
    return {
      'defaultPrinterName': defaultPrinterName,
      'selectedPrinterName': selectedPrinterName,
      'selectedPrinterUrl': selectedPrinterUrl,
      'receiptPaperWidthMm': receiptPaperWidthMm,
      'autoPrintAfterSale': autoPrintAfterSale,
      'paperMode': paperMode,
    };
  }

  factory PrinterSettings.fromJson(Map<String, dynamic> json) {
    final mode = (json['paperMode'] as String?)?.trim() ?? '';
    return PrinterSettings(
      defaultPrinterName: json['defaultPrinterName'] as String? ?? '',
      selectedPrinterName: json['selectedPrinterName'] as String? ?? '',
      selectedPrinterUrl: json['selectedPrinterUrl'] as String? ?? '',
      receiptPaperWidthMm: (json['receiptPaperWidthMm'] as num?)?.toInt() ?? 80,
      autoPrintAfterSale: json['autoPrintAfterSale'] == true,
      paperMode: mode.isEmpty ? 'thermal' : mode,
    );
  }
}

class PrinterSettingsStore {
  PrinterSettingsStore._();

  static final instance = PrinterSettingsStore._();

  PrinterSettings _settings = const PrinterSettings();

  PrinterSettings get current => _settings;

  Future<void> load() async {
    try {
      final raw = await LocalStore.read(_fileName);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _settings = PrinterSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
  }

  void set(PrinterSettings settings) {
    _settings = settings;
    unawaited(save());
  }

  Future<void> save() async {
    try {
      await LocalStore.write(_fileName, jsonEncode(_settings.toJson()));
    } catch (_) {}
  }

  static const _fileName = 'printer_settings.json';

  void update(PrinterSettings Function(PrinterSettings current) updater) {
    set(updater(_settings));
  }
}
