import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/invoices/bill_layout.dart';

void main() {
  test('amount in words, Indian system', () {
    expect(
      rupeesInWords(3586),
      'Rupees Three Thousand Five Hundred Eighty-Six Only',
    );
    expect(rupeesInWords(0), 'Rupees Zero Only');
    expect(rupeesInWords(100), 'Rupees One Hundred Only');
    expect(rupeesInWords(125000), 'Rupees One Lakh Twenty-Five Thousand Only');
    expect(
      rupeesInWords(23456789.5),
      'Rupees Two Crore Thirty-Four Lakh Fifty-Six Thousand Seven Hundred '
      'Eighty-Nine and Fifty Paise Only',
    );
    expect(rupeesInWords(19.05), 'Rupees Nineteen and Five Paise Only');
  });

  test('terms: one per line, blank lines dropped', () {
    expect(billTerms('  Exchange in 7 days \n\n No cash refund\n'), [
      'Exchange in 7 days',
      'No cash refund',
    ]);
    expect(billTerms(null), isEmpty);
  });

  // The photographed bill: a saree at 3,490 less 349 and a nighty at 350
  // less 35, both 5% GST, intra-state.
  Map<String, dynamic> line(
    String name,
    double rate,
    double disc,
    double total, {
    String sku = '',
    String size = '',
  }) => {
    'product_name': name,
    'variant_name': size,
    'products': {'sku': sku},
    'quantity': 1,
    'unit_name': 'pcs',
    'unit_price': rate / 1.05,
    'discount_amount': disc / 1.05,
    'gst_rate': 5,
    'line_total': total,
    'taxable_value': total / 1.05,
    'cgst_amount': total / 1.05 * 0.025,
    'sgst_amount': total / 1.05 * 0.025,
    'igst_amount': 0,
  };

  final invoice = {
    'invoice_type': 'gst',
    'total': 3456.0,
    'discount_amount': 0,
    'round_off': 0,
    'paid_amount': 3456.0,
    'payment_mode': 'upi',
    'due_amount': 0,
    'invoice_payments': <Map<String, dynamic>>[],
  };

  test('lines, totals and GST summary', () {
    final bill = BillLayout(
      business: {'bill_show_sku': true, 'bill_footer': ' Visit again '},
      invoice: invoice,
      items: [
        line('Handloom Saree', 3490, 349, 3141, sku: 'MAFB061807'),
        line('Cotton Nighty', 350, 35, 315, size: 'Free size'),
      ],
    );
    final saree = bill.lines.first;
    expect(saree.sku, 'MAFB061807');
    expect(saree.rate, 3490);
    expect(saree.amount, 3490);
    expect(saree.discount, 349);
    expect(saree.total, 3141);
    expect(bill.lines.last.size, 'Free size');
    expect(bill.totalQty, 2);
    expect(bill.totalAmount, 3840);
    expect(bill.totalLineDiscount, 384);
    expect(bill.linesTotal, 3456);
    expect(bill.payments, [('UPI', 3456.0)]);
    expect(bill.footer, 'Visit again');

    final gst = bill.gstSummary.single;
    expect(gst.rate, 5);
    expect(gst.taxable, closeTo(3291.43, 0.01));
    expect(gst.cgst, closeTo(82.29, 0.01));
    expect(gst.totalTax, closeTo(164.57, 0.01));
    expect(bill.gstIsInterState, isFalse);
  });

  test(
    'stock no. only when the shop prints it; no GST summary off GST bills',
    () {
      final bill = BillLayout(
        business: const {},
        invoice: {...invoice, 'invoice_type': 'non_gst'},
        items: [line('Saree', 100, 0, 100, sku: 'S1')],
      );
      expect(bill.lines.single.sku, '');
      expect(bill.gstSummary, isEmpty);
    },
  );
}
