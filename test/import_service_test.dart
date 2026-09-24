import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/import_service.dart';

void main() {
  test('import validator accepts valid medicine rows and rejects missing required values', () {
    const csv = '''sku,medicine_name,category,strength,form,unit,pack_size,supplier_name,buying_price_minor,selling_price_minor,reorder_level,quantity_on_hand,expiry_date,batch_number
MED-001,Amoxicillin 500mg,Antibiotics,500mg,Capsule,box,30,Alpha Pharma,1500,2000,20,100,2027-12-31,B-001
BAD-ROW,,Antibiotics,500mg,Capsule,box,30,Alpha Pharma,1500,2000,20,100,2027-12-31,B-002
''';

    final result = MedicineImportService.validateCsv(csv);

    expect(result.validRows.length, 1);
    expect(result.invalidRows.length, 1);
    expect(result.invalidRows.first.errors, contains('medicine_name'));
  });

  test('template generator includes all required medicine columns', () {
    final csv = MedicineImportService.generateTemplateCsv();

    expect(csv, contains('sku'));
    expect(csv, contains('medicine_name'));
    expect(csv, contains('category'));
    expect(csv, contains('supplier_name'));
    expect(csv, contains('buying_price_minor'));
    expect(csv, contains('selling_price_minor'));
    expect(csv, contains('expiry_date'));
  });
}
