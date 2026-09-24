import 'package:flutter_test/flutter_test.dart';
import 'package:phyimacy/backend/receipt_service.dart';

void main() {
  test('receipt summary keeps the printed totals and payment details consistent', () {
    final receipt = ReceiptSummary(
      receiptNumber: 'R-123456',
      soldBy: 'user-1',
      paymentMethod: 'cash',
      subtotalMinor: 2500,
      discountMinor: 300,
      totalMinor: 2200,
      createdAt: DateTime(2026, 9, 19, 12, 30),
      items: const [
        ReceiptLineItem(name: 'Amoxicillin', quantity: 2, unitPriceMinor: 1000, totalMinor: 2000),
        ReceiptLineItem(name: 'Paracetamol', quantity: 1, unitPriceMinor: 500, totalMinor: 500),
      ],
    );

    expect(receipt.receiptNumber, 'R-123456');
    expect(receipt.totalMinor, 2200);
    expect(receipt.paymentMethod, 'cash');
    expect(receipt.items.length, 2);
    expect(receipt.items.first.name, 'Amoxicillin');
    expect(receipt.lines.any((line) => line.contains('R-123456')), isTrue);
  });
}
