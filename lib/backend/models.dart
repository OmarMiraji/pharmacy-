import 'package:cloud_firestore/cloud_firestore.dart';

import 'expiry_priority.dart';
import 'selling_units.dart';

class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.sku,
    required this.categoryId,
    required this.unit,
    required this.purchasePriceMinor,
    required this.sellingPriceMinor,
    required this.quantityOnHand,
    required this.reorderLevel,
    required this.requiresPrescription,
    required this.isActive,
    this.genericName,
    this.barcode,
    this.supplierId,
    this.expiryDate,
    this.packSize = 1,
    this.stripSize = 0,
    this.boxSize = 0,
    this.allowLooseSale = false,
    this.minSaleQty = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? genericName;
  final String sku;
  final String? barcode;
  final String categoryId;
  final String? supplierId;
  final String unit;
  final int purchasePriceMinor;
  final int sellingPriceMinor;
  final int quantityOnHand;
  final int reorderLevel;
  final bool requiresPrescription;
  final bool isActive;
  final Timestamp? expiryDate;
  final int packSize;
  final int stripSize;
  final int boxSize;
  final bool allowLooseSale;
  final int minSaleQty;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  String get baseLabel => BaseUnits.normalize(unit);

  bool get tracksBaseUnits => piecesPerPack > 1 || stripSize > 1 || boxSize > 1;

  bool get sellsLoose => tracksBaseUnits;

  bool get canSellPiecesByType {
    const pieceTypes = {'Tablet', 'Capsule', 'Piece', 'Sachet'};
    return pieceTypes.contains(baseLabel);
  }

  int get piecesPerPack => packSize < 1 ? 1 : packSize;

  int get effectiveMinSaleQty {
    if (minSaleQty > 0) return minSaleQty;
    if (canSellPiecesByType && piecesPerPack > 1) return 5;
    return 1;
  }

  int minSellCountFor(SellUnit unit, int availableBase) {
    if (unit.toBase != 1) return 1;
    final min = effectiveMinSaleQty;
    if (availableBase > 0 && availableBase < min) return availableBase;
    return min;
  }

  int get piecePriceMinor {
    if (piecesPerPack <= 1) return sellingPriceMinor;
    return (sellingPriceMinor / piecesPerPack).round().clamp(0, sellingPriceMinor);
  }

  List<SellUnit> get sellUnits {
    final units = <SellUnit>[];
    final piece = piecePriceMinor;
    units.add(
      SellUnit(
        id: 'base',
        label: baseLabel,
        toBase: 1,
        unitPriceMinor: piecesPerPack <= 1 ? sellingPriceMinor : piece,
        baseLabel: baseLabel,
      ),
    );
    if (stripSize > 1) {
      units.add(
        SellUnit(
          id: 'strip',
          label: 'Strip',
          toBase: stripSize,
          unitPriceMinor: piece * stripSize,
          baseLabel: baseLabel,
        ),
      );
    }
    if (piecesPerPack > 1) {
      units.add(
        SellUnit(
          id: 'pack',
          label: 'Pack',
          toBase: piecesPerPack,
          unitPriceMinor: sellingPriceMinor,
          baseLabel: baseLabel,
        ),
      );
    }
    if (boxSize > 1) {
      units.add(
        SellUnit(
          id: 'box',
          label: 'Box',
          toBase: boxSize,
          unitPriceMinor: piece * boxSize,
          baseLabel: baseLabel,
        ),
      );
    }
    return units;
  }

  String stockLabel([int? qty]) {
    final count = qty ?? quantityOnHand;
    if (!tracksBaseUnits) return '$count $baseLabel${count == 1 ? '' : 's'}';
    final packs = piecesPerPack > 1 ? count ~/ piecesPerPack : 0;
    final rest = piecesPerPack > 1 ? count % piecesPerPack : count;
    final baseWord = count == 1 ? baseLabel : '${baseLabel}s';
    if (packs > 0 && rest > 0) return '$count $baseWord ($packs pack + $rest)';
    if (packs > 0) return '$count $baseWord ($packs pack)';
    return '$count $baseWord';
  }

  factory Medicine.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Medicine(
      id: doc.id,
      name: data['name'] as String? ?? '',
      genericName: data['genericName'] as String?,
      sku: data['sku'] as String? ?? '',
      barcode: data['barcode'] as String?,
      categoryId: data['categoryId'] as String? ?? '',
      supplierId: data['supplierId'] as String?,
      unit: data['unit'] as String? ?? 'unit',
      purchasePriceMinor: (data['purchasePriceMinor'] as num?)?.toInt() ?? 0,
      sellingPriceMinor: (data['sellingPriceMinor'] as num?)?.toInt() ?? 0,
      quantityOnHand: (data['quantityOnHand'] as num?)?.toInt() ?? 0,
      reorderLevel: (data['reorderLevel'] as num?)?.toInt() ?? 0,
      requiresPrescription: data['requiresPrescription'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true,
      expiryDate: () {
        final parsed = ExpiryPriority.parseAny(data['expiryDate']);
        return parsed == null ? null : Timestamp.fromDate(parsed);
      }(),
      packSize: () {
        final raw = (data['packSize'] as num?)?.toInt() ?? 1;
        return raw < 1 ? 1 : raw;
      }(),
      stripSize: (data['stripSize'] as num?)?.toInt() ?? 0,
      boxSize: (data['boxSize'] as num?)?.toInt() ?? 0,
      allowLooseSale: data['allowLooseSale'] == true,
      minSaleQty: (data['minSaleQty'] as num?)?.toInt() ?? 0,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Medicine copyWith({int? quantityOnHand}) {
    return Medicine(
      id: id,
      name: name,
      genericName: genericName,
      sku: sku,
      barcode: barcode,
      categoryId: categoryId,
      supplierId: supplierId,
      unit: unit,
      purchasePriceMinor: purchasePriceMinor,
      sellingPriceMinor: sellingPriceMinor,
      quantityOnHand: quantityOnHand ?? this.quantityOnHand,
      reorderLevel: reorderLevel,
      requiresPrescription: requiresPrescription,
      isActive: isActive,
      expiryDate: expiryDate,
      packSize: packSize,
      stripSize: stripSize,
      boxSize: boxSize,
      allowLooseSale: allowLooseSale,
      minSaleQty: minSaleQty,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'genericName': genericName,
        'sku': sku,
        'barcode': barcode,
        'categoryId': categoryId,
        'supplierId': supplierId,
        'unit': unit,
        'purchasePriceMinor': purchasePriceMinor,
        'sellingPriceMinor': sellingPriceMinor,
        'quantityOnHand': quantityOnHand,
        'reorderLevel': reorderLevel,
        'requiresPrescription': requiresPrescription,
        'isActive': isActive,
        if (expiryDate != null) 'expiryDate': expiryDate,
        'packSize': packSize,
        'stripSize': stripSize,
        'boxSize': boxSize,
        'allowLooseSale': allowLooseSale,
        'minSaleQty': minSaleQty,
      };
}

class MedicineBatch {
  const MedicineBatch({
    required this.id,
    required this.medicineId,
    required this.batchNumber,
    required this.expiryDate,
    required this.quantityOnHand,
    required this.unitCostMinor,
    required this.isActive,
    this.sellingPriceMinor,
    this.supplierId,
    this.purchaseId,
  });

  final String id;
  final String medicineId;
  final String batchNumber;
  final Timestamp expiryDate;
  final int quantityOnHand;
  final int unitCostMinor;
  final int? sellingPriceMinor;
  final String? supplierId;
  final String? purchaseId;
  final bool isActive;

  factory MedicineBatch.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return MedicineBatch(
      id: doc.id,
      medicineId: data['medicineId'] as String? ?? '',
      batchNumber: data['batchNumber'] as String? ?? '',
      expiryDate: Timestamp.fromDate(ExpiryPriority.parseAny(data['expiryDate']) ?? DateTime.now()),
      quantityOnHand: (data['quantityOnHand'] as num?)?.toInt() ?? 0,
      unitCostMinor: (data['unitCostMinor'] as num?)?.toInt() ?? 0,
      sellingPriceMinor: (data['sellingPriceMinor'] as num?)?.toInt(),
      supplierId: data['supplierId'] as String?,
      purchaseId: data['purchaseId'] as String?,
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'medicineId': medicineId,
        'batchNumber': batchNumber,
        'expiryDate': expiryDate,
        'quantityOnHand': quantityOnHand,
        'unitCostMinor': unitCostMinor,
        'sellingPriceMinor': sellingPriceMinor,
        'supplierId': supplierId,
        'purchaseId': purchaseId,
        'isActive': isActive,
      };
}
