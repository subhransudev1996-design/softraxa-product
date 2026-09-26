import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/customers/customer_providers.dart';
import 'package:softraxa_inventory/features/customers/receive_payment_dialog.dart';

void main() {
  group('Receive payment request', () {
    test('oldest-first sends no bill list', () {
      const r = PaymentRequest(amount: 1700, mode: 'cash', note: '');
      expect(r.toParams('c1'), {
        'p_customer_id': 'c1',
        'p_amount': 1700.0,
        'p_mode': 'cash',
        'p_note': '',
      });
    });

    test('chosen bills are sent in the order picked', () {
      const r = PaymentRequest(
        amount: 100,
        mode: 'upi',
        note: 'part',
        invoiceIds: ['b4', 'b2'],
      );
      expect(r.toParams('c1')['p_invoice_ids'], ['b4', 'b2']);
    });

    test('an empty choice falls back to oldest first', () {
      const r = PaymentRequest(amount: 100, mode: 'cash', note: '', invoiceIds: []);
      expect(r.toParams('c1').containsKey('p_invoice_ids'), isFalse);
    });
  });

  test('preview parsing (spec D26 example: 1,700 over 1,000 + 500)', () {
    final p = parsePaymentPreview({
      'allocations': [
        {'invoice_no': 'INV-1', 'due': 1000, 'apply': 1000},
        {'invoice_no': 'INV-2', 'due': 500, 'apply': 500},
      ],
      'applied': 1500,
      'advance': 200,
    });
    expect(p.allocations.map((a) => a.invoiceNo), ['INV-1', 'INV-2']);
    expect(p.allocations.first.apply, 1000);
    expect(p.advance, 200);
  });

  test('advance history labels', () {
    expect(advanceKindLabel('payment_excess'), 'Paid in advance');
    expect(advanceKindLabel('applied'), 'Used on a bill');
    expect(advanceKindLabel('refund'), 'Refunded');
    expect(advanceKindLabel(null), 'Advance');
  });
}
