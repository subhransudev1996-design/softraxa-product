import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/customers/customer_statement.dart';

Map<String, dynamic> bill(String no, String date, num total, num paid,
        {bool cancelled = false}) =>
    {
      'invoice_no': no,
      'invoice_date': date,
      'total': total,
      'paid_amount': paid,
      'due_amount': total - paid,
      'is_cancelled': cancelled,
      'invoice_type': 'non_gst',
    };

void main() {
  final invoices = [
    bill('B1', '2026-07-10T10:00:00', 500, 0), // old, still owing
    bill('B2', '2026-10-02T10:00:00', 300, 100),
    bill('B3', '2026-10-03T10:00:00', 200, 200),
    bill('B4', '2026-10-04T10:00:00', 999, 0, cancelled: true),
  ];
  final entries = [
    {
      'kind': 'payment',
      'date': '2026-10-05T10:00:00',
      'credit': 150,
      'data': {'payment_date': '2026-10-05T10:00:00', 'amount': 150, 'payment_mode': 'upi'},
    },
    {
      'kind': 'payment',
      'date': '2026-10-05T11:00:00',
      'credit': null, // reversed
      'data': {'payment_date': '2026-10-05T11:00:00', 'amount': 80, 'payment_mode': 'cash'},
    },
  ];

  test('October: bills and payments in the period; unpaid bills from any date', () {
    final s = buildCustomerStatement(
      customer: {'due_amount': 700, 'advance_amount': 0},
      invoices: invoices,
      entries: entries,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 6),
    );
    expect(s.bills.map((b) => b['invoice_no']), ['B2', 'B3']);
    expect(s.billed, 500);
    expect(s.payments.length, 1);
    expect(s.received, 150);
    expect(s.unpaid.map((b) => b['invoice_no']), ['B1', 'B2']);
    expect(s.earlierDue, 0);
    expect(s.netPayable, 700);
  });

  test('due on bills older than the loaded ones shows as earlier balance', () {
    final s = buildCustomerStatement(
      customer: {'due_amount': 1000, 'advance_amount': 100},
      invoices: invoices,
      entries: const [],
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 6),
    );
    expect(s.earlierDue, 300); // 1000 - (500 + 200)
    expect(s.netPayable, 900);
  });

  test('the PDF builds', () async {
    final s = buildCustomerStatement(
      customer: {'due_amount': 700, 'advance_amount': 0},
      invoices: invoices,
      entries: entries,
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 6),
    );
    final bytes = await buildStatementPdf(
      business: {'name': 'Shop', 'upi_id': 'shop@upi'},
      customer: {'name': 'Ramesh', 'phone': '9000012301'},
      s: s,
    );
    expect(bytes.length, greaterThan(1000));
  });
}
