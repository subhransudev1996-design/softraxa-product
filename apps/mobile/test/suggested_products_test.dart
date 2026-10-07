import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/products/suggested_products_screen.dart';

void main() {
  test('every ticked product needs a selling price above zero', () {
    expect(suggestedItemsPayload(['a'], {}, {}), isNull);
    expect(suggestedItemsPayload(['a'], {'a': ''}, {}), isNull);
    expect(suggestedItemsPayload(['a'], {'a': '0'}, {}), isNull);
    expect(suggestedItemsPayload(['a', 'b'], {'a': '10'}, {}), isNull);
  });

  test('sends price, and stock only when it is above zero', () {
    final items = suggestedItemsPayload(
      ['a', 'b', 'c'],
      {'a': '12.5', 'b': ' 40 ', 'c': '7'},
      {'a': '3', 'b': '', 'c': '0'},
    )!;
    expect(items, [
      {'master_id': 'a', 'selling_price': 12.5, 'opening_stock': 3.0},
      {'master_id': 'b', 'selling_price': 40.0},
      {'master_id': 'c', 'selling_price': 7.0},
    ]);
  });
}
