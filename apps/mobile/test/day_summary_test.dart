import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/dashboard/day_summary.dart';

void main() {
  final s = summarizeDay(
    day: DateTime(2026, 10, 6),
    invoices: [
      {'total': 500, 'due_amount': 0, 'customer_id': null},
      {'total': 300, 'due_amount': 200, 'customer_id': 'c1'},
    ],
    counterPayments: [
      {'amount': 500, 'payment_mode': 'cash'},
      {'amount': 100, 'payment_mode': 'upi'},
    ],
    khataReceipts: [
      {'amount': 250, 'payment_mode': 'cash'},
    ],
    returns: [
      {'refund_amount': 40},
    ],
    expenses: [
      {'amount': 60},
    ],
    profit: 95,
  );

  test('sales, credit, money by mode, old dues, refunds, expenses', () {
    expect(s.bills, 2);
    expect(s.sales, 800);
    expect(s.creditGiven, 200);
    expect(s.received, {'cash': 750, 'upi': 100});
    expect(s.totalReceived, 850);
    expect(s.khataCollected, 250);
    expect(s.refunds, 40);
    expect(s.expenses, 60);
  });

  test('the WhatsApp text has the day and the totals', () {
    final m = daySummaryMessage(s, 'Sharma General Store');
    expect(m, contains('*Sharma General Store*'));
    expect(m, contains('Bills: 2'));
    expect(m, contains('800.00'));
    expect(m, contains('old dues collected'));
    expect(m, contains('Profit'));
  });

  test('no profit line for staff who may not see it', () {
    final staff = summarizeDay(
      day: DateTime(2026, 10, 6),
      invoices: const [],
      counterPayments: const [],
      khataReceipts: const [],
      returns: const [],
      expenses: const [],
    );
    expect(daySummaryMessage(staff, 'Shop'), isNot(contains('Profit')));
  });
}
