import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/models.dart';
import 'package:phyimacy/backend/selling_units.dart';

void main() {
  Medicine tablet({required int selling, int minSale = 5, int pack = 1}) {
    return Medicine(
      id: 'm1',
      name: 'Paracetamol',
      sku: 'PARA',
      categoryId: 'c1',
      unit: 'Tablet',
      purchasePriceMinor: 200,
      sellingPriceMinor: selling,
      quantityOnHand: 40,
      reorderLevel: 5,
      requiresPrescription: false,
      isActive: true,
      packSize: pack,
      minSaleQty: minSale,
    );
  }

  test('400 is the price of 5 tablets, so 10 tablets cost 800', () {
    final medicine = tablet(selling: 400);
    expect(medicine.saleLotSize, 5);
    expect(medicine.priceForTablets(5), 400);
    expect(medicine.priceForTablets(10), 800);
    expect(medicine.sellUnits.single.id, 'lot');
    expect(medicine.sellUnits.single.toBase, 5);
    expect(medicine.sellUnits.single.unitPriceMinor, 400);
  });

  test('buying price of 5 tablets becomes cost per tablet', () {
    expect(
      BaseUnits.costPerStockUnit(unit: 'Tablet', purchasePriceMinor: 200, minSaleQty: 5),
      40,
    );
  });
}
