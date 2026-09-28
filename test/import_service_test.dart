import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/import_service.dart';

void main() {
  test('import validator accepts form-matching rows and rejects missing name', () {
    const csv = '''sku,medicine_name,category,unit,pack_size,buying_price,selling_price,reorder_level,opening_quantity,expiry_date,batch_number
MED-001,Amoxicillin 500mg,Antibiotics,Tablet,20,1500,2000,10,40,2027-12-31,B-001
BAD-ROW,,Antibiotics,Tablet,20,1500,2000,10,40,2027-12-31,B-002
''';

    final result = MedicineImportService.validateCsv(csv);

    expect(result.validRows.length, 1);
    expect(result.validRows.first.packSize, 20);
    expect(result.validRows.first.unit, 'Tablet');
    expect(result.invalidRows.length, 1);
    expect(result.invalidRows.first.errors, contains('medicine_name'));
  });

  test('template uses the same fields as Add medicine', () {
    final csv = MedicineImportService.generateTemplateCsv();

    expect(csv, contains('sku'));
    expect(csv, contains('medicine_name'));
    expect(csv, contains('category'));
    expect(csv, contains('unit'));
    expect(csv, contains('pack_size'));
    expect(csv, contains('buying_price'));
    expect(csv, contains('selling_price'));
    expect(csv, isNot(contains('strength')));
    expect(csv, isNot(contains('supplier_name')));
    expect(csv, isNot(contains('buying_price_minor')));
  });
}
