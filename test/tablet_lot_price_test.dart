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

  test('one tablet at a time uses the price of a single tablet', () {
    final medicine = tablet(selling: 80, minSale: 1);
    expect(medicine.effectiveMinSaleQty, 1);
    expect(medicine.sellsPricedLots, isFalse);
    expect(medicine.sellUnits.single.id, 'base');
    expect(medicine.priceForTablets(1), 80);
    expect(medicine.priceForTablets(3), 240);
  });

  test('one tablet from a pack can be sold by itself', () {
    final medicine = tablet(selling: 1000, minSale: 1, pack: 10);
    expect(medicine.piecePriceMinor, 100);
    expect(medicine.minSellCountFor(medicine.sellUnits.first, 10), 1);
    expect(medicine.sellUnits.map((unit) => unit.id), containsAll(['base', 'pack']));
  });

  test('a blister price can also sell half a blister', () {
    final medicine = tablet(selling: 1000, minSale: 1).copyWith(quantityOnHand: 20);
    final blister = Medicine(
      id: medicine.id,
      name: medicine.name,
      sku: medicine.sku,
      categoryId: medicine.categoryId,
      unit: medicine.unit,
      purchasePriceMinor: 800,
      sellingPriceMinor: 1000,
      quantityOnHand: 20,
      reorderLevel: medicine.reorderLevel,
      requiresPrescription: false,
      isActive: true,
      packSize: 1,
      stripSize: 10,
      allowHalfBlister: true,
      minSaleQty: 1,
    );
    expect(blister.pricedByBlister, isTrue);
    expect(blister.piecePriceMinor, 100);
    expect(blister.sellUnits.map((unit) => unit.id), ['strip', 'half']);
    expect(blister.sellUnits.last.toBase, 5);
    expect(blister.sellUnits.last.unitPriceMinor, 500);
    expect(
      BaseUnits.costPerStockUnit(unit: 'Tablet', purchasePriceMinor: 800, stripSize: 10),
      80,
    );
  });

  test('buying price of 5 tablets becomes cost per tablet', () {
    expect(
      BaseUnits.costPerStockUnit(unit: 'Tablet', purchasePriceMinor: 200, minSaleQty: 5),
      40,
    );
  });
}
