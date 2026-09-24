import 'dart:convert';

class MedicineImportRow {
  const MedicineImportRow({
    required this.sku,
    required this.medicineName,
    required this.category,
    required this.strength,
    required this.form,
    required this.unit,
    required this.packSize,
    required this.supplierName,
    required this.buyingPriceMinor,
    required this.sellingPriceMinor,
    required this.reorderLevel,
    required this.quantityOnHand,
    required this.expiryDate,
    required this.batchNumber,
  });

  final String sku;
  final String medicineName;
  final String category;
  final String strength;
  final String form;
  final String unit;
  final String packSize;
  final String supplierName;
  final int buyingPriceMinor;
  final int sellingPriceMinor;
  final int reorderLevel;
  final int quantityOnHand;
  final String expiryDate;
  final String batchNumber;
}

class MedicineImportValidationResult {
  const MedicineImportValidationResult({
    required this.validRows,
    required this.invalidRows,
  });

  final List<MedicineImportRow> validRows;
  final List<MedicineImportInvalidRow> invalidRows;
}

class MedicineImportInvalidRow {
  const MedicineImportInvalidRow({
    required this.rowNumber,
    required this.data,
    required this.errors,
  });

  final int rowNumber;
  final Map<String, String> data;
  final List<String> errors;
}

class MedicineImportService {
  static const List<String> requiredHeaders = [
    'sku',
    'medicine_name',
    'category',
    'strength',
    'form',
    'unit',
    'pack_size',
    'supplier_name',
    'buying_price_minor',
    'selling_price_minor',
    'reorder_level',
    'quantity_on_hand',
    'expiry_date',
    'batch_number',
  ];

  static String generateTemplateCsv() {
    final header = requiredHeaders.join(',');
    final exampleRow = [
      'MED-001',
      'Amoxicillin 500mg',
      'Antibiotics',
      '500mg',
      'Capsule',
      'box',
      '30',
      'Alpha Pharma',
      '1500',
      '2000',
      '20',
      '100',
      '2027-12-31',
      'B-001',
    ].join(',');
    return '$header\n$exampleRow';
  }

  static MedicineImportValidationResult validateCsv(String csv) {
    final lines = const LineSplitter().convert(csv.trim());
    if (lines.isEmpty) {
      return const MedicineImportValidationResult(validRows: [], invalidRows: []);
    }

    final headerLine = lines.first;
    final headers = _parseCsvLine(headerLine);
    final missing = requiredHeaders.where((name) => !headers.map((header) => header.trim().toLowerCase()).contains(name)).toList();
    if (missing.isNotEmpty) {
      return MedicineImportValidationResult(
        validRows: const [],
        invalidRows: [
          MedicineImportInvalidRow(
            rowNumber: 1,
            data: const {},
            errors: ['Missing required columns: ${missing.join(', ')}'],
          ),
        ],
      );
    }

    final validRows = <MedicineImportRow>[];
    final invalidRows = <MedicineImportInvalidRow>[];

    for (var i = 1; i < lines.length; i++) {
      final row = _parseCsvLine(lines[i]);
      if (row.isEmpty || row.every((value) => value.trim().isEmpty)) {
        continue;
      }

      final data = <String, String>{
        for (var index = 0; index < headers.length; index++)
          headers[index].trim().toLowerCase(): row.length > index ? row[index].trim() : '',
      };

      final errors = <String>[];
      final sku = data['sku'] ?? '';
      final medicineName = data['medicine_name'] ?? '';
      final category = data['category'] ?? '';
      final strength = data['strength'] ?? '';
      final form = data['form'] ?? '';
      final unit = data['unit'] ?? '';
      final packSize = data['pack_size'] ?? '';
      final supplierName = data['supplier_name'] ?? '';
      final buyingPriceText = data['buying_price_minor'] ?? '';
      final sellingPriceText = data['selling_price_minor'] ?? '';
      final reorderText = data['reorder_level'] ?? '';
      final quantityText = data['quantity_on_hand'] ?? '';
      final expiryDate = data['expiry_date'] ?? '';
      final batchNumber = data['batch_number'] ?? '';

      if (sku.isEmpty) errors.add('sku');
      if (medicineName.isEmpty) errors.add('medicine_name');
      if (category.isEmpty) errors.add('category');
      if (strength.isEmpty) errors.add('strength');
      if (form.isEmpty) errors.add('form');
      if (unit.isEmpty) errors.add('unit');
      if (packSize.isEmpty) errors.add('pack_size');
      if (supplierName.isEmpty) errors.add('supplier_name');
      if (buyingPriceText.isEmpty) errors.add('buying_price_minor');
      if (sellingPriceText.isEmpty) errors.add('selling_price_minor');
      if (reorderText.isEmpty) errors.add('reorder_level');
      if (quantityText.isEmpty) errors.add('quantity_on_hand');
      if (expiryDate.isEmpty) errors.add('expiry_date');
      if (batchNumber.isEmpty) errors.add('batch_number');

      final buyingPrice = int.tryParse(buyingPriceText);
      final sellingPrice = int.tryParse(sellingPriceText);
      final reorderLevel = int.tryParse(reorderText);
      final quantityOnHand = int.tryParse(quantityText);

      if (buyingPriceText.isNotEmpty && buyingPrice == null) errors.add('buying_price_minor must be a number');
      if (sellingPriceText.isNotEmpty && sellingPrice == null) errors.add('selling_price_minor must be a number');
      if (reorderText.isNotEmpty && reorderLevel == null) errors.add('reorder_level must be a number');
      if (quantityText.isNotEmpty && quantityOnHand == null) errors.add('quantity_on_hand must be a number');

      if (buyingPrice != null && buyingPrice < 0) errors.add('buying_price_minor cannot be negative');
      if (sellingPrice != null && sellingPrice < 0) errors.add('selling_price_minor cannot be negative');
      if (reorderLevel != null && reorderLevel < 0) errors.add('reorder_level cannot be negative');
      if (quantityOnHand != null && quantityOnHand < 0) errors.add('quantity_on_hand cannot be negative');
      if (buyingPrice != null && sellingPrice != null && sellingPrice < buyingPrice) errors.add('selling_price_minor must be greater than or equal to buying_price_minor');

      try {
        if (expiryDate.isNotEmpty) {
          DateTime.parse(expiryDate);
        }
      } catch (_) {
        errors.add('expiry_date must use YYYY-MM-DD format');
      }

      if (errors.isEmpty) {
        validRows.add(MedicineImportRow(
          sku: sku,
          medicineName: medicineName,
          category: category,
          strength: strength,
          form: form,
          unit: unit,
          packSize: packSize,
          supplierName: supplierName,
          buyingPriceMinor: buyingPrice ?? 0,
          sellingPriceMinor: sellingPrice ?? 0,
          reorderLevel: reorderLevel ?? 0,
          quantityOnHand: quantityOnHand ?? 0,
          expiryDate: expiryDate,
          batchNumber: batchNumber,
        ));
      } else {
        invalidRows.add(MedicineImportInvalidRow(
          rowNumber: i + 1,
          data: data,
          errors: errors,
        ));
      }
    }

    return MedicineImportValidationResult(validRows: validRows, invalidRows: invalidRows);
  }

  static List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }
}
