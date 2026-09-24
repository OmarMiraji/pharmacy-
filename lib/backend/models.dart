import 'package:cloud_firestore/cloud_firestore.dart';

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
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

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
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
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
      expiryDate: data['expiryDate'] as Timestamp? ?? Timestamp.now(),
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
