import 'package:cloud_firestore/cloud_firestore.dart';

import 'tenant_context.dart';

class StockLedger {
  static String businessDate([DateTime? now]) {
    final date = now ?? DateTime.now();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static DateTime startOfDay(DateTime day) => DateTime(day.year, day.month, day.day);

  static DateTime endOfDay(DateTime day) => DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

  static Map<String, dynamic> movement({
    required String medicineId,
    required String type,
    required int quantityChange,
    required String createdBy,
    String? medicineName,
    String? referenceId,
    String? batchId,
    String? batchNumber,
    Object? createdAt,
  }) {
    final units = quantityChange.abs();
    return TenantContext.instance.withTenant({
      'medicineId': medicineId,
      'medicineName': medicineName,
      'type': type,
      'direction': quantityChange < 0 ? 'out' : 'in',
      'quantityChange': quantityChange,
      'units': units,
      'businessDate': businessDate(),
      'referenceId': referenceId,
      'batchId': batchId,
      'batchNumber': batchNumber,
      'createdBy': createdBy,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    });
  }
}
