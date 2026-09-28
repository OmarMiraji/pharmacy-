import 'expiry_priority.dart';
import 'models.dart';

class ExpiredStockLine {
  const ExpiredStockLine({
    required this.medicineId,
    required this.medicineName,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.expiry,
    this.batchId,
    this.batchNumber,
  });

  final String medicineId;
  final String medicineName;
  final String sku;
  final String unit;
  final int quantity;
  final DateTime expiry;
  final String? batchId;
  final String? batchNumber;

  String get key => '${batchId ?? medicineId}:${expiry.millisecondsSinceEpoch}:$quantity';
}

class ExpiryStock {
  static List<ExpiredStockLine> expiredLines(List<Medicine> medicines, List<MedicineBatch> batches) {
    final lines = <ExpiredStockLine>[];
    final byMedicine = <String, List<MedicineBatch>>{};
    for (final batch in batches) {
      byMedicine.putIfAbsent(batch.medicineId, () => []).add(batch);
    }

    for (final medicine in medicines) {
      final medBatches = [...(byMedicine[medicine.id] ?? const <MedicineBatch>[])]
        ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      var sellable = 0;
      var shownExpired = 0;
      MedicineBatch? earliestExpired;

      for (final batch in medBatches) {
        final expiry = batch.expiryDate.toDate();
        if (ExpiryPriority.isExpired(expiry)) {
          earliestExpired ??= batch;
          if (batch.quantityOnHand > 0) {
            lines.add(
              ExpiredStockLine(
                medicineId: medicine.id,
                medicineName: medicine.name,
                sku: medicine.sku,
                unit: medicine.unit,
                quantity: batch.quantityOnHand,
                expiry: expiry,
                batchId: batch.id,
                batchNumber: batch.batchNumber,
              ),
            );
            shownExpired += batch.quantityOnHand;
          }
        } else if (batch.quantityOnHand > 0) {
          sellable += batch.quantityOnHand;
        }
      }

      final leftover = medicine.quantityOnHand - sellable - shownExpired;
      if (leftover > 0 && earliestExpired != null && sellable == 0) {
        lines.add(
          ExpiredStockLine(
            medicineId: medicine.id,
            medicineName: medicine.name,
            sku: medicine.sku,
            unit: medicine.unit,
            quantity: leftover,
            expiry: earliestExpired.expiryDate.toDate(),
            batchId: earliestExpired.id,
            batchNumber: earliestExpired.batchNumber,
          ),
        );
      } else if (medBatches.isEmpty && leftover > 0 && medicine.expiryDate != null) {
        final expiry = medicine.expiryDate!.toDate();
        if (ExpiryPriority.isExpired(expiry)) {
          lines.add(
            ExpiredStockLine(
              medicineId: medicine.id,
              medicineName: medicine.name,
              sku: medicine.sku,
              unit: medicine.unit,
              quantity: leftover,
              expiry: expiry,
            ),
          );
        }
      }
    }

    lines.sort((a, b) => a.expiry.compareTo(b.expiry));
    return lines;
  }

  static int productsWithoutExpiry(List<Medicine> medicines, List<MedicineBatch> batches) {
    final dated = {for (final batch in batches) batch.medicineId};
    return medicines.where((medicine) => medicine.quantityOnHand > 0 && !dated.contains(medicine.id)).length;
  }
}
