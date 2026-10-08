import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/stock/pack_qty_input.dart';

void main() {
  test('full packs times pack size plus loose units', () {
    expect(packQtyTotal('30', '', 50), 1500);
    expect(packQtyTotal('30', '5', 50), 1505);
    expect(packQtyTotal('', '7', 50), 7);
    expect(packQtyTotal('2.5', '', 10), 25);
  });

  test('nothing typed or not a number gives null', () {
    expect(packQtyTotal('', '', 50), isNull);
    expect(packQtyTotal(' ', ' ', 50), isNull);
    expect(packQtyTotal('abc', '', 50), isNull);
    expect(packQtyTotal('-1', '', 50), isNull);
  });
}
