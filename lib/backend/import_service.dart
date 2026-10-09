import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

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
    this.allowHalfBlister = false,
    this.stockAs = 'tablets',
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
  final bool allowHalfBlister;
  final String stockAs;
}

class MedicineImportValidationResult {
  const MedicineImportValidationResult({
    required this.validRows,
    required this.invalidRows,
  });

  final List<MedicineImportRow> validRows;
  final List<MedicineImportInvalidRow> invalidRows;
}

class MedicineImportParseResult {
  const MedicineImportParseResult({
    required this.displayText,
    required this.result,
  });

  final String displayText;
  final MedicineImportValidationResult result;
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
    'allow_half_blister',
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

  static MedicineImportParseResult parseBytes(List<int> bytes, {String fileName = ''}) {
    if (bytes.isEmpty) {
      return const MedicineImportParseResult(
        displayText: '',
        result: MedicineImportValidationResult(validRows: [], invalidRows: []),
      );
    }
    final name = fileName.toLowerCase();
    if (_looksLikeSpreadsheet(bytes, name)) {
      try {
        final table = _rowsFromSpreadsheet(Uint8List.fromList(bytes));
        final csv = _tableToCsv(table);
        return MedicineImportParseResult(displayText: csv, result: validateTable(table));
      } catch (error) {
        return MedicineImportParseResult(
          displayText: '',
          result: MedicineImportValidationResult(
            validRows: const [],
            invalidRows: [
              MedicineImportInvalidRow(
                rowNumber: 1,
                data: const {},
                errors: [
                  'Could not read this Excel file. Save it as .xlsx or .csv and try again.',
                ],
              ),
            ],
          ),
        );
      }
    }
    final csv = utf8.decode(bytes, allowMalformed: true).replaceAll('\uFEFF', '');
    return MedicineImportParseResult(displayText: csv, result: validateCsv(csv));
  }

  static MedicineImportValidationResult validateCsv(String csv) {
    return validateTable(_csvToTable(csv));
  }

  static MedicineImportValidationResult validateTable(List<List<String>> table) {
    if (table.isEmpty) {
      return const MedicineImportValidationResult(validRows: [], invalidRows: []);
    }

    var headerAt = 0;
    for (var i = 0; i < table.length && i < 8; i++) {
      final cells = table[i].map(_normHeader).toList();
      if (cells.contains('sku') && (cells.contains('medicine_name') || cells.contains('name'))) {
        headerAt = i;
        break;
      }
    }

    final headers = table[headerAt].map(_normHeader).toList();
    final missing = requiredHeaders.where((name) => !_headerPresent(headers, name)).toList();
    if (missing.isNotEmpty) {
      return MedicineImportValidationResult(
        validRows: const [],
        invalidRows: [
          MedicineImportInvalidRow(
            rowNumber: headerAt + 1,
            data: const {},
            errors: ['Missing required columns: ${missing.join(', ')}'],
          ),
        ],
      );
    }

    final validRows = <MedicineImportRow>[];
    final invalidRows = <MedicineImportInvalidRow>[];

    for (var i = headerAt + 1; i < table.length; i++) {
      final row = table[i];
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
      var expiryDate = _normalizeDate(_col(data, ['expiry_date']));
      final batchNumber = _col(data, ['batch_number']);
      final stripText = _col(data, ['strip_size']);
      final boxText = _col(data, ['box_size']);
      final rxText = _col(data, ['requires_prescription']);
      final minSaleText = _col(data, ['min_sale_qty']);
      final stockAsRaw = _col(data, ['stock_as']).toLowerCase();
      final halfText = _col(data, ['allow_half_blister']).toLowerCase();

      if (sku.isEmpty) errors.add('sku');
      if (medicineName.isEmpty) errors.add('medicine_name');
      if (category.isEmpty) errors.add('category');
      if (unit.isEmpty) errors.add('unit');
      if (buyingText.isEmpty) errors.add('buying_price');
      if (sellingText.isEmpty) errors.add('selling_price');
      if (reorderText.isEmpty) errors.add('reorder_level');

      final parsedPack = packText.isEmpty ? 1 : _parseInt(packText);
      final packSize = (parsedPack == null || parsedPack < 1) ? 1 : parsedPack;
      final buyingPrice = _parseMoney(buyingText);
      final sellingPrice = _parseMoney(sellingText);
      final reorderLevel = _parseInt(reorderText);
      final openingQuantity = openingText.isEmpty ? 0 : _parseInt(openingText);
      final stripSize = stripText.isEmpty ? 0 : _parseInt(stripText);
      final boxSize = boxText.isEmpty ? 0 : _parseInt(boxText);
      final minSaleQty = minSaleText.isEmpty ? 0 : _parseInt(minSaleText);
      final pieceType = unit.toLowerCase() == 'tablet' || unit.toLowerCase() == 'capsule';
      final asBlister = stockAsRaw == 'blister' || stockAsRaw == 'blisters' || stockAsRaw == 'blista';
      final asPack = stockAsRaw == 'pack' || stockAsRaw == 'packs';
      final asOne = stockAsRaw == 'one' || stockAsRaw == 'tablet';
      final stockAs = asBlister
          ? 'blisters'
          : asPack
              ? 'packs'
              : asOne
                  ? 'one'
                  : 'tablets';
      final openingAsTablets = pieceType && !asPack && !asBlister;
      final allowHalf = halfText == '1' || halfText == 'yes' || halfText == 'true';

      if (parsedPack != null && parsedPack < 0) {
        errors.add('pack_size cannot be negative');
      }
      if (!openingAsTablets &&
          pieceType &&
          (openingQuantity ?? 0) > 0 &&
          packSize < 2) {
        errors.add('pack_size is required (2 or more) when stock_as is packs');
      }
      if (buyingText.isNotEmpty && buyingPrice == null) errors.add('buying_price must be a TZS number');
      if (sellingText.isNotEmpty && sellingPrice == null) errors.add('selling_price must be a TZS number');
      if (reorderText.isNotEmpty && reorderLevel == null) errors.add('reorder_level must be a whole number');
      if (openingText.isNotEmpty && openingQuantity == null) errors.add('opening_quantity must be a whole number');
      if (asBlister && (stripSize ?? 0) < 2) errors.add('strip_size must be 2 or more when stock_as is blisters');
      if (allowHalf && asBlister && (stripSize ?? 0) % 2 != 0) {
        errors.add('strip_size must be an even number when allow_half_blister is yes');
      }
      if (stripText.isNotEmpty && stripSize == null) errors.add('strip_size must be a whole number');
      if (boxText.isNotEmpty && boxSize == null) errors.add('box_size must be a whole number');
      if (minSaleText.isNotEmpty && minSaleQty == null) errors.add('min_sale_qty must be a whole number');
      if (buyingPrice != null && buyingPrice < 0) errors.add('buying_price cannot be negative');
      if (sellingPrice != null && sellingPrice < 0) errors.add('selling_price cannot be negative');
      if (reorderLevel != null && reorderLevel < 0) errors.add('reorder_level cannot be negative');
      if (openingQuantity != null && openingQuantity < 0) errors.add('opening_quantity cannot be negative');
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
          packSize: asBlister ? 1 : packSize,
          stripSize: asBlister ? (stripSize ?? 0) : (stripSize ?? 0),
          boxSize: boxSize ?? 0,
          buyingPriceMinor: buyingPrice ?? 0,
          sellingPriceMinor: sellingPrice ?? 0,
          reorderLevel: reorderLevel ?? 0,
          openingQuantity: openingQuantity ?? 0,
          expiryDate: expiryDate,
          batchNumber: batchNumber,
          requiresPrescription: rxText == '1' || rxText.toLowerCase() == 'yes' || rxText.toLowerCase() == 'true',
          minSaleQty: asOne ? 1 : (minSaleQty ?? 0),
          openingAsTablets: openingAsTablets,
          allowHalfBlister: asBlister && allowHalf,
          stockAs: stockAs,
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
      'medicine_name': ['medicine_name', 'name'],
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

  static String _normHeader(String raw) {
    return raw.trim().toLowerCase().replaceAll('\uFEFF', '').replaceAll(RegExp(r'[\s\-]+'), '_');
  }

  static int? _parseInt(String raw) {
    final cleaned = raw.trim().replaceAll(',', '').replaceAll(' ', '');
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned)?.round();
  }

  static int? _parseMoney(String raw) {
    return _parseInt(raw.replaceAll(RegExp(r'[^\d.\-]'), ''));
  }

  static String _normalizeDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final iso = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})');
    final isoMatch = iso.firstMatch(text);
    if (isoMatch != null) {
      final y = isoMatch.group(1)!;
      final m = isoMatch.group(2)!.padLeft(2, '0');
      final d = isoMatch.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }
    final serial = num.tryParse(text.replaceAll(',', ''));
    if (serial != null && serial >= 20000 && serial < 80000) {
      final date = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (serial * 86400000).round()));
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '${date.year}-$m-$d';
    }
    return text;
  }

  static bool _looksLikeSpreadsheet(List<int> bytes, String fileName) {
    if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls') || fileName.endsWith('.xlsm')) {
      return true;
    }
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) return true;
    if (bytes.length >= 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
      return true;
    }
    return false;
  }

  static List<List<String>> _rowsFromSpreadsheet(Uint8List bytes) {
    return _XlsxReader.read(bytes);
  }

  static List<List<String>> _csvToTable(String csv) {
    final text = csv.replaceAll('\uFEFF', '').trim();
    if (text.isEmpty) return const [];
    return [
      for (final line in const LineSplitter().convert(text)) _parseCsvLine(line),
    ];
  }

  static String _tableToCsv(List<List<String>> table) {
    return table.map((row) => row.map(_csvEscape).join(',')).join('\n');
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
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

class _XlsxReader {
  static List<List<String>> read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = _sharedStrings(archive);
    ArchiveFile? sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    sheetFile ??= archive.files.cast<ArchiveFile?>().firstWhere(
          (file) => file != null && file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml'),
          orElse: () => null,
        );
    if (sheetFile == null) {
      throw StateError('The Excel file has no worksheet.');
    }
    final document = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final rows = <List<String>>[];
    for (final row in document.findAllElements('row')) {
      final cells = <int, String>{};
      var maxIndex = -1;
      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final index = _columnIndex(ref);
        if (index < 0) continue;
        maxIndex = index > maxIndex ? index : maxIndex;
        cells[index] = _cellValue(cell, shared);
      }
      if (maxIndex < 0) {
        rows.add(const []);
        continue;
      }
      rows.add([for (var i = 0; i <= maxIndex; i++) cells[i] ?? '']);
    }
    if (rows.isEmpty) {
      throw StateError('The Excel sheet is empty.');
    }
    return rows;
  }

  static List<String> _sharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    final document = XmlDocument.parse(utf8.decode(file.content as List<int>));
    return [
      for (final si in document.findAllElements('si')) si.innerText,
    ];
  }

  static String _cellValue(XmlElement cell, List<String> shared) {
    final type = cell.getAttribute('t') ?? '';
    if (type == 's') {
      final index = int.tryParse(cell.getElement('v')?.innerText ?? '');
      if (index == null || index < 0 || index >= shared.length) return '';
      return shared[index].trim();
    }
    if (type == 'inlineStr') {
      return (cell.getElement('is')?.innerText ?? '').trim();
    }
    final raw = (cell.getElement('v')?.innerText ?? '').trim();
    if (raw.isEmpty) return '';
    final number = num.tryParse(raw);
    if (number != null && number == number.roundToDouble()) {
      return number.round().toString();
    }
    return raw;
  }

  static int _columnIndex(String ref) {
    final letters = StringBuffer();
    for (var i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        letters.writeCharCode(code);
      } else if (code >= 97 && code <= 122) {
        letters.writeCharCode(code - 32);
      } else {
        break;
      }
    }
    if (letters.isEmpty) return -1;
    var index = 0;
    for (var i = 0; i < letters.length; i++) {
      index = index * 26 + (letters.toString().codeUnitAt(i) - 64);
    }
    return index - 1;
  }
}
