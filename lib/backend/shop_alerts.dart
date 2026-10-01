import 'expiry_priority.dart';
import 'models.dart';

enum ShopAlertKind { expired, expiringSoon }

class ShopAlert {
  const ShopAlert({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.expiry,
    required this.quantity,
  });

  final String id;
  final ShopAlertKind kind;
  final String title;
  final String body;
  final DateTime expiry;
  final int quantity;
}

class ShopAlerts {
  static List<ShopAlert> fromStock(List<Medicine> medicines, List<MedicineBatch> batches) {
    final byMedicine = <String, List<MedicineBatch>>{};
    for (final batch in batches) {
      byMedicine.putIfAbsent(batch.medicineId, () => []).add(batch);
    }

    final alerts = <ShopAlert>[];
    for (final medicine in medicines) {
      final dated = <({DateTime expiry, int quantity, String? batchId, String? batchNumber})>[];
      final medBatches = byMedicine[medicine.id] ?? const <MedicineBatch>[];
      for (final batch in medBatches) {
        if (batch.quantityOnHand <= 0) continue;
        dated.add((
          expiry: batch.expiryDate.toDate(),
          quantity: batch.quantityOnHand,
          batchId: batch.id,
          batchNumber: batch.batchNumber,
        ));
      }
      if (dated.isEmpty && medicine.quantityOnHand > 0 && medicine.expiryDate != null) {
        dated.add((
          expiry: medicine.expiryDate!.toDate(),
          quantity: medicine.quantityOnHand,
          batchId: null,
          batchNumber: null,
        ));
      }

      for (final line in dated) {
        final days = ExpiryPriority.daysLeft(line.expiry);
        if (ExpiryPriority.isExpired(line.expiry)) {
          alerts.add(
            ShopAlert(
              id: 'expired:${medicine.id}:${line.batchId ?? 'item'}',
              kind: ShopAlertKind.expired,
              title: medicine.name,
              body: 'Expired · ${ExpiryPriority.format(line.expiry)} · ${line.quantity} ${medicine.unit}',
              expiry: line.expiry,
              quantity: line.quantity,
            ),
          );
        } else if (ExpiryPriority.isNotifySoon(line.expiry)) {
          alerts.add(
            ShopAlert(
              id: 'soon:${medicine.id}:${line.batchId ?? 'item'}',
              kind: ShopAlertKind.expiringSoon,
              title: medicine.name,
              body: days <= 0 ? 'Expires today' : 'Expires in $days days',
              expiry: line.expiry,
              quantity: line.quantity,
            ),
          );
        }
      }
    }

    alerts.sort((a, b) {
      if (a.kind != b.kind) {
        return a.kind == ShopAlertKind.expired ? -1 : 1;
      }
      return a.expiry.compareTo(b.expiry);
    });
    return alerts;
  }
}
