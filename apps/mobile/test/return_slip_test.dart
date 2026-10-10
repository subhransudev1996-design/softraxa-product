import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/returns/return_slip.dart';

/// A sale-return row as saleReturnDetailProvider loads it: [lines] are
/// (name, qty, bill price with GST, value back).
Map<String, dynamic> saleReturn(
  List<(String, double, double, double)> lines, {
  double refund = 0,
  String type = 'gst',
}) {
  final total = lines.fold(0.0, (s, l) => s + l.$4);
  return {
    'return_no': 'SR-00001',
    'return_date': '2026-10-09T11:30:42Z',
    'total': total,
    'refund_amount': refund,
    'refund_mode': 'cash',
    'notes': '',
    'invoices': {'invoice_no': 'INV/26-27/0056', 'invoice_type': type},
    'customers': {'name': 'K'},
    'profiles': {'full_name': 'Shirish'},
    'sale_return_items': [
      for (final l in lines)
        {
          'product_name': l.$1,
          'quantity': l.$2,
          'gst_rate': 5,
          'line_total': l.$4,
          'taxable_value': l.$4 / 1.05,
          'cgst_amount': l.$4 / 1.05 * 0.025,
          'sgst_amount': l.$4 / 1.05 * 0.025,
          'igst_amount': 0,
          'invoice_items': {
            'unit_price': type == 'gst' ? l.$3 / 1.05 : l.$3,
            'gst_rate': 5,
          },
        },
    ],
  };
}

void main() {
  test('the photographed return: price, discount, net', () {
    // 3,930 at bill prices; the bill's discounts bring it to 3,550.
    final slip = ReturnSlip(
      business: const {'gst_number': '21ABCDE1234F1Z5'},
      saleReturn: saleReturn([
        ('Cotton Nighty', 1, 450, 405),
        ('Saaya', 1, 130, 130),
        ('South Cotton Saree', 1, 3350, 3015),
      ], refund: 3550),
    );
    expect(slip.lines.map((l) => l.price), [450, 130, 3350]);
    expect(slip.totalQty, 3);
    expect(slip.gross, 3930);
    expect(slip.discount, 380);
    expect(slip.net, 3550);
    expect(slip.refunds, [('Refund (Cash)', 3550.0)]);
    expect(slip.user, 'Shirish');
    expect(slip.gst.single.taxable, closeTo(3380.95, 0.01));
    expect(slip.showsGstin, isTrue);
  });

  test('part refunded, the rest to the customer; no GST off GST bills', () {
    final slip = ReturnSlip(
      business: const {},
      saleReturn: saleReturn([('Pen', 2, 10, 20)], refund: 5, type: 'non_gst'),
    );
    expect(slip.lines.single.price, 10);
    expect(slip.discount, 0);
    expect(slip.refunds, [
      ('Refund (Cash)', 5.0),
      ('Credit to customer', 15.0),
    ]);
    expect(slip.gst, isEmpty);
  });

  test('a whole box back shows as a box at the box price', () {
    final row = saleReturn([('Pens', 10, 9.5, 95)], type: 'non_gst');
    final item = (row['sale_return_items'] as List).single as Map;
    item['invoice_items'] = {
      'unit_price': 9.5,
      'gst_rate': 0,
      'sold_as_pack': true,
      'alt_factor': 10,
      'alt_unit_name': 'Box',
    };
    final l = ReturnSlip(business: const {}, saleReturn: row).lines.single;
    expect(l.qty, 1);
    expect(l.unit, 'Box');
    expect(l.price, 95);
    expect(l.gross, 95);
  });

  test('older returns without their bill line show the value back', () {
    final row = saleReturn([('Pen', 2, 10, 18)]);
    ((row['sale_return_items'] as List).single as Map).remove('invoice_items');
    final slip = ReturnSlip(business: const {}, saleReturn: row);
    expect(slip.lines.single.price, 9);
    expect(slip.discount, 0);
  });

  test('time of day', () {
    expect(timeOf('2026-10-09T11:30:42Z'), isNotEmpty);
    expect(timeOf('2026-10-09T11:30:42Z'), contains(':'));
  });
}
