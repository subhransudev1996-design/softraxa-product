import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/products/alternatives.dart';

void main() {
  test('stock is the product\'s own, or its active variants\' together', () {
    expect(altStock({'current_stock': 7}), 7);
    expect(
      altStock({
        'has_variants': true,
        'current_stock': 0,
        'product_variants': [
          {'current_stock': 2, 'is_active': true},
          {'current_stock': 3},
          {'current_stock': 9, 'is_active': false},
        ],
      }),
      5,
    );
    expect(
      altStock({'has_variants': true, 'current_stock': 4, 'product_variants': []}),
      4,
    );
  });
}
