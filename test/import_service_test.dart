import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/import_service.dart';

void main() {
  test('import validator accepts form-matching rows and rejects missing name', () {
    const csv = '''sku,medicine_name,category,unit,buying_price,selling_price,reorder_level,stock_as,opening_quantity,expiry_date,batch_number
MED-001,Amoxicillin 500mg,Antibiotics,Tablet,1500,2000,10,tablets,40,2027-12-31,B-001
BAD-ROW,,Antibiotics,Tablet,1500,2000,10,tablets,40,2027-12-31,B-002
''';

    final result = MedicineImportService.validateCsv(csv);

    expect(result.validRows.length, 1);
    expect(result.validRows.first.packSize, 1);
    expect(result.validRows.first.openingAsTablets, isTrue);
    expect(result.validRows.first.unit, 'Tablet');
    expect(result.invalidRows.length, 1);
    expect(result.invalidRows.first.errors, contains('medicine_name'));
  });

  test('accepts Excel-style headers and thousands separators', () {
    const csv = '''sku,medicine name,category,unit,buying_price,selling_price,reorder_level,opening_quantity,expiry_date
PH-001,Nivea Spray,Cosmetics,piece,"10,000.00","15,000.00",10,1,2026-07-03
''';
    final result = MedicineImportService.validateCsv(csv);
    expect(result.validRows.length, 1);
    expect(result.validRows.first.medicineName, 'Nivea Spray');
    expect(result.validRows.first.buyingPriceMinor, 10000);
    expect(result.validRows.first.sellingPriceMinor, 15000);
  });

  test('template uses the same fields as Add medicine and has no sample rows', () {
    final csv = MedicineImportService.generateTemplateCsv();

    expect(csv, contains('sku'));
    expect(csv, contains('medicine_name'));
    expect(csv, contains('category'));
    expect(csv, contains('unit'));
    expect(csv, contains('buying_price'));
    expect(csv, contains('selling_price'));
    expect(csv, contains('stock_as'));
    expect(csv, contains('min_sale_qty'));
    expect(csv, isNot(contains('MED-001')));
    expect(csv, isNot(contains('Amoxicillin')));
    expect(csv, isNot(contains('strength')));
    expect(csv, isNot(contains('supplier_name')));
    expect(csv, isNot(contains('buying_price_minor')));
  });
}
