import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/returns/return_lines.dart';

// One bill: 1 Box of 10 at ₹95 (₹9.50 a piece) + 3 loose at ₹10.
final box = <String, dynamic>{
  'id': 'L1',
  'product_id': 'P',
  'quantity': 10,
  'line_total': 95,
  'sold_as_pack': true,
  'alt_factor': 10,
  'alt_unit_name': 'Box',
  'unit_name': 'pcs',
};
final loose = <String, dynamic>{
  'id': 'L2',
  'product_id': 'P',
  'quantity': 3,
  'line_total': 30,
  'sold_as_pack': false,
  'unit_name': 'pcs',
};

void main() {
  test('each line is worth its own price, not the average', () {
    expect(returnUnitValue(box), 9.5);
    expect(returnUnitValue(loose), 10);
    expect(returnRowValue(10, box, 1), 95);
    expect(returnRowValue(1, loose, 1), 10);
    // A ₹12.50 bill discount on ₹125: 10% off everything returned.
    expect(returnRowValue(10, box, 0.9), 85.5);
  });

  test('box lines read in boxes', () {
    expect(linePackSize(box), 10);
    expect(linePackSize(loose), isNull);
    expect(returnQtyLabel(10, box), '1 Box');
    expect(returnQtyLabel(13, {...box, 'quantity': 20}), '1 Box + 3 pcs');
    expect(returnQtyLabel(4, box), '4 pcs');
    expect(returnQtyLabel(2, loose), '2');
  });

  test('what is left: per line, and never past the product on the bill', () {
    final lines = [box, loose];
    final none = ReturnedSoFar.fromRows(const []);
    expect(maxReturnableFrom(box, lines, none), 10);
    expect(maxReturnableFrom(loose, lines, none), 3);

    final some = ReturnedSoFar.fromRows([
      {'product_id': 'P', 'quantity': 1, 'invoice_item_id': 'L2'},
    ]);
    expect(maxReturnableFrom(loose, lines, some), 2);
    expect(maxReturnableFrom(box, lines, some), 10);

    // An older return (no line recorded) of 12 pieces: only 1 left overall.
    final old = ReturnedSoFar.fromRows([
      {'product_id': 'P', 'quantity': 12},
    ]);
    expect(maxReturnableFrom(box, lines, old), 1);
    expect(maxReturnableFrom(loose, lines, old), 1);
  });
}
