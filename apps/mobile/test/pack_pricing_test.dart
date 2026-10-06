import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/products/pack_pricing.dart';

void main() {
  test('a 50 kg bag bought at 1600 costs 32 a kg', () {
    expect(perUnitPrice(1600, 50), 32);
    expect(priceText(perUnitPrice(1600, 50)), '32');
  });

  test('uneven splits round to paise', () {
    expect(perUnitPrice(1650, 45), 36.67);
    expect(priceText(perUnitPrice(1650, 45)), '36.67');
  });

  test('missing numbers give nothing', () {
    expect(perUnitPrice(null, 50), isNull);
    expect(perUnitPrice(1600, 0), isNull);
    expect(packPriceFor(32, null), isNull);
    expect(priceText(null), '');
  });

  test('per-kg back to a bag', () {
    expect(packPriceFor(32, 50), 1600);
  });

  test('margin on a bag', () {
    expect(packMarginText(1600, 1800, 'Bag'), 'Profit ₹200 a Bag (13%)');
    expect(
      packMarginText(1800, 1700, 'Bag'),
      'Loss ₹100 a Bag — selling below cost',
    );
    expect(packMarginText(null, 1800, 'Bag'), isNull);
  });
}
