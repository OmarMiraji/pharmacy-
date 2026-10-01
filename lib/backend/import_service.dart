import 'dart:convert';

class MedicineImportRow {
  const MedicineImportRow({
    required this.sku,
    required this.medicineName,
    required this.category,
    required this.unit,
    required this.packSize,
    required this.stripSize,
    required this.boxSize,
    required this.buyingPriceMinor,
    required this.sellingPriceMinor,
    required this.reorderLevel,
    required this.openingQuantity,
    required this.expiryDate,
    required this.batchNumber,
    required this.requiresPrescription,
    this.minSaleQty = 0,
    this.openingAsTablets = true,
  });

  final String sku;
  final String medicineName;
  final String category;
  final String unit;
  final int packSize;
  final int stripSize;
  final int boxSize;
  final int buyingPriceMinor;
  final int sellingPriceMinor;
  final int reorderLevel;
  final int openingQuantity;
  final String expiryDate;
  final String batchNumber;
  final bool requiresPrescription;
  final int minSaleQty;
  final bool openingAsTablets;
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
    'unit',
    'buying_price',
    'selling_price',
    'reorder_level',
  ];

  static const List<String> optionalHeaders = [
    'stock_as',
    'pack_size',
    'min_sale_qty',
    'strip_size',
    'box_size',
    'opening_quantity',
    'expiry_date',
    'batch_number',
  ];

  static const List<String> templateHeaders = [
    ...requiredHeaders,
    ...optionalHeaders,
  ];

  static String generateTemplateCsv() {
    return '${templateHeaders.join(',')}\n';
  }

  static MedicineImportValidationResult validateCsv(String csv) {
    final lines = const LineSplitter().convert(csv.trim());
    if (lines.isEmpty) {
      return const MedicineImportValidationResult(validRows: [], invalidRows: []);
    }

    final headers = _parseCsvLine(lines.first).map((header) => header.trim().toLowerCase()).toList();
    final missing = requiredHeaders.where((name) => !_headerPresent(headers, name)).toList();
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
          headers[index]: row.length > index ? row[index].trim() : '',
      };

      final errors = <String>[];
      final sku = _col(data, ['sku']);
      final medicineName = _col(data, ['medicine_name', 'name']);
      final category = _col(data, ['category']);
      final unit = _col(data, ['unit', 'form']);
      final packText = _col(data, ['pack_size']);
      final buyingText = _col(data, ['buying_price', 'buying_price_minor', 'purchase_price']);
      final sellingText = _col(data, ['selling_price', 'selling_price_minor']);
      final reorderText = _col(data, ['reorder_level']);
      final openingText = _col(data, ['opening_quantity', 'quantity_on_hand']);
      final expiryDate = _col(data, ['expiry_date']);
      final batchNumber = _col(data, ['batch_number']);
      final stripText = _col(data, ['strip_size']);
      final boxText = _col(data, ['box_size']);
      final rxText = _col(data, ['requires_prescription']);
      final minSaleText = _col(data, ['min_sale_qty']);
      final stockAs = _col(data, ['stock_as']).toLowerCase();

      if (sku.isEmpty) errors.add('sku');
      if (medicineName.isEmpty) errors.add('medicine_name');
      if (category.isEmpty) errors.add('category');
      if (unit.isEmpty) errors.add('unit');
      if (buyingText.isEmpty) errors.add('buying_price');
      if (sellingText.isEmpty) errors.add('selling_price');
      if (reorderText.isEmpty) errors.add('reorder_level');

      final packSize = packText.isEmpty ? 1 : int.tryParse(packText);
      final buyingPrice = int.tryParse(buyingText);
      final sellingPrice = int.tryParse(sellingText);
      final reorderLevel = int.tryParse(reorderText);
      final openingQuantity = openingText.isEmpty ? 0 : int.tryParse(openingText);
      final stripSize = stripText.isEmpty ? 0 : int.tryParse(stripText);
      final boxSize = boxText.isEmpty ? 0 : int.tryParse(boxText);
      final minSaleQty = minSaleText.isEmpty ? 0 : int.tryParse(minSaleText);
      final pieceType = unit.toLowerCase() == 'tablet' || unit.toLowerCase() == 'capsule';
      final openingAsTablets = pieceType && stockAs != 'packs' && stockAs != 'pack';

      if (packText.isNotEmpty && (packSize == null || packSize < 1)) errors.add('pack_size must be 1 or more');
      if (!openingAsTablets && pieceType && (openingQuantity ?? 0) > 0 && (packSize == null || packSize < 2)) {
        errors.add('pack_size is required (2 or more) when stock_as is packs');
      }
      if (buyingText.isNotEmpty && buyingPrice == null) errors.add('buying_price must be a whole TZS number');
      if (sellingText.isNotEmpty && sellingPrice == null) errors.add('selling_price must be a whole TZS number');
      if (reorderText.isNotEmpty && reorderLevel == null) errors.add('reorder_level must be a whole number');
      if (openingText.isNotEmpty && openingQuantity == null) errors.add('opening_quantity must be a whole number');
      if (stripText.isNotEmpty && stripSize == null) errors.add('strip_size must be a whole number');
      if (boxText.isNotEmpty && boxSize == null) errors.add('box_size must be a whole number');
      if (minSaleText.isNotEmpty && minSaleQty == null) errors.add('min_sale_qty must be a whole number');
      if (buyingPrice != null && buyingPrice < 0) errors.add('buying_price cannot be negative');
      if (sellingPrice != null && sellingPrice < 0) errors.add('selling_price cannot be negative');
      if (reorderLevel != null && reorderLevel < 0) errors.add('reorder_level cannot be negative');
      if (openingQuantity != null && openingQuantity < 0) errors.add('opening_quantity cannot be negative');
      if ((openingQuantity ?? 0) > 0 && expiryDate.isEmpty) {
        errors.add('expiry_date is required when opening_quantity is greater than 0');
      }
      if (expiryDate.isNotEmpty) {
        try {
          DateTime.parse(expiryDate);
        } catch (_) {
          errors.add('expiry_date must use YYYY-MM-DD');
        }
      }

      if (errors.isEmpty) {
        validRows.add(MedicineImportRow(
          sku: sku,
          medicineName: medicineName,
          category: category,
          unit: unit,
          packSize: packSize ?? 1,
          stripSize: stripSize ?? 0,
          boxSize: boxSize ?? 0,
          buyingPriceMinor: buyingPrice ?? 0,
          sellingPriceMinor: sellingPrice ?? 0,
          reorderLevel: reorderLevel ?? 0,
          openingQuantity: openingQuantity ?? 0,
          expiryDate: expiryDate,
          batchNumber: batchNumber,
          requiresPrescription: rxText == '1' || rxText.toLowerCase() == 'yes' || rxText.toLowerCase() == 'true',
          minSaleQty: minSaleQty ?? 0,
          openingAsTablets: openingAsTablets,
        ));
      } else {
        invalidRows.add(MedicineImportInvalidRow(rowNumber: i + 1, data: data, errors: errors));
      }
    }

    return MedicineImportValidationResult(validRows: validRows, invalidRows: invalidRows);
  }

  static bool _headerPresent(List<String> headers, String name) {
    const aliases = {
      'buying_price': ['buying_price', 'buying_price_minor', 'purchase_price'],
      'selling_price': ['selling_price', 'selling_price_minor'],
      'unit': ['unit', 'form'],
    };
    final names = aliases[name] ?? [name];
    return names.any(headers.contains);
  }

  static String _col(Map<String, String> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
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
