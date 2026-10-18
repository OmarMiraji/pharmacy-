import 'package:cloud_firestore/cloud_firestore.dart';

import '../backend/expiry_stock.dart';
import '../backend/firestore_collections.dart';
import '../backend/models.dart';
import '../backend/sales_service.dart';
import '../backend/shop_alerts.dart';
import '../backend/tenant_context.dart';

class MobileDayPoint {
  const MobileDayPoint({required this.day, required this.revenueMinor});

  final DateTime day;
  final int revenueMinor;
}

class MobileSaleRow {
  const MobileSaleRow({
    required this.receiptNumber,
    required this.totalMinor,
    required this.paymentMethod,
    required this.createdAt,
    required this.itemLabel,
  });

  final String receiptNumber;
  final int totalMinor;
  final String paymentMethod;
  final DateTime createdAt;
  final String itemLabel;
}

class MobileStockRow {
  const MobileStockRow({
    required this.name,
    required this.quantity,
    required this.reorderLevel,
    required this.unit,
  });

  final String name;
  final int quantity;
  final int reorderLevel;
  final String unit;
}

class MobileShopSnapshot {
  const MobileShopSnapshot({
    required this.stockItems,
    required this.lowStockCount,
    required this.todaySalesCount,
    required this.todaySalesMinor,
    required this.weekSalesMinor,
    required this.expiredCount,
    required this.soonCount,
    required this.week,
    required this.recentSales,
    required this.lowStock,
    required this.alerts,
  });

  final int stockItems;
  final int lowStockCount;
  final int todaySalesCount;
  final int todaySalesMinor;
  final int weekSalesMinor;
  final int expiredCount;
  final int soonCount;
  final List<MobileDayPoint> week;
  final List<MobileSaleRow> recentSales;
  final List<MobileStockRow> lowStock;
  final List<ShopAlert> alerts;

  static const empty = MobileShopSnapshot(
    stockItems: 0,
    lowStockCount: 0,
    todaySalesCount: 0,
    todaySalesMinor: 0,
    weekSalesMinor: 0,
    expiredCount: 0,
    soonCount: 0,
    week: [],
    recentSales: [],
    lowStock: [],
    alerts: [],
  );
}

class MobileShopData {
  Future<MobileShopSnapshot> load({required bool includeMoney}) async {
    final tenant = TenantContext.instance;
    if ((tenant.pharmacyId ?? '').trim().isEmpty) return MobileShopSnapshot.empty;
    final firestore = FirebaseFirestore.instance;
    try {
      Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadDocs(String collection) async {
        try {
          return (await tenant.scoped(firestore.collection(collection)).get()).docs;
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied') return const [];
          rethrow;
        }
      }

      final medicineDocs = await loadDocs(FirestoreCollections.medicines);
      final batchDocs = await loadDocs(FirestoreCollections.medicineBatches);
      final salesDocs = includeMoney
          ? await SalesService().fetchSaleDocsSince(
              SalesService.dashboardSalesSince(),
            )
          : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      final medicines = medicineDocs.map(Medicine.fromFirestore).where((item) => item.isActive).toList();
      final batches = batchDocs.map(MedicineBatch.fromFirestore).toList();
      final lowStock = medicines.where((item) => item.quantityOnHand <= item.reorderLevel).toList()
        ..sort((a, b) => a.quantityOnHand.compareTo(b.quantityOnHand));

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final liveSales = salesDocs.where((doc) {
        final status = (doc.data()['status'] as String?) ?? 'completed';
        return status != 'voided' && status != 'refunded';
      }).toList();

      bool onDay(QueryDocumentSnapshot<Map<String, dynamic>> doc, DateTime start, DateTime end) {
        final value = doc.data()['createdAt'];
        final createdAt = value is Timestamp ? value.toDate() : null;
        return createdAt != null && !createdAt.isBefore(start) && createdAt.isBefore(end);
      }

      final todaySales = liveSales.where((doc) => onDay(doc, todayStart, todayEnd)).toList();
      final todaySalesMinor = todaySales.fold<int>(0, (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0));

      final week = <MobileDayPoint>[];
      var weekSalesMinor = 0;
      for (var offset = 6; offset >= 0; offset--) {
        final dayStart = todayStart.subtract(Duration(days: offset));
        final nextDay = dayStart.add(const Duration(days: 1));
        final revenue = liveSales.where((doc) => onDay(doc, dayStart, nextDay)).fold<int>(
              0,
              (total, doc) => total + ((doc.data()['totalMinor'] as num?)?.toInt() ?? 0),
            );
        weekSalesMinor += revenue;
        week.add(MobileDayPoint(day: dayStart, revenueMinor: revenue));
      }

      liveSales.sort((a, b) {
        final left = a.data()['createdAt'];
        final right = b.data()['createdAt'];
        final leftDate = left is Timestamp ? left.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate = right is Timestamp ? right.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

      final recentSales = <MobileSaleRow>[];
      for (final doc in liveSales.take(24)) {
        final data = doc.data();
        final createdAt = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : DateTime.now();
        final names = ((data['itemNames'] as List?) ?? const []).whereType<String>().where((name) => name.trim().isNotEmpty).toList();
        recentSales.add(
          MobileSaleRow(
            receiptNumber: (data['receiptNumber'] as String?) ?? 'Receipt',
            totalMinor: (data['totalMinor'] as num?)?.toInt() ?? 0,
            paymentMethod: (data['paymentMethod'] as String?) ?? 'cash',
            createdAt: createdAt,
            itemLabel: names.take(2).join(', '),
          ),
        );
      }

      final alerts = ShopAlerts.fromStock(medicines, batches);
      return MobileShopSnapshot(
        stockItems: medicines.length,
        lowStockCount: lowStock.length,
        todaySalesCount: todaySales.length,
        todaySalesMinor: todaySalesMinor,
        weekSalesMinor: weekSalesMinor,
        expiredCount: ExpiryStock.expiredLines(medicines, batches).length,
        soonCount: alerts.where((alert) => alert.kind == ShopAlertKind.expiringSoon).length,
        week: week,
        recentSales: recentSales,
        lowStock: lowStock
            .take(20)
            .map(
              (item) => MobileStockRow(
                name: item.name,
                quantity: item.quantityOnHand,
                reorderLevel: item.reorderLevel,
                unit: item.unit,
              ),
            )
            .toList(),
        alerts: alerts.take(20).toList(),
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return MobileShopSnapshot.empty;
      rethrow;
    }
  }
}
