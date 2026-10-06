import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/formatters.dart';

void main() {
  test('small weights and volumes read in g / ml', () {
    expect(cartQtyLabel(0.1, 'kg'), '100 g');
    expect(cartQtyLabel(0.25, 'kg'), '250 g');
    expect(cartQtyLabel(0.2, 'L'), '200 ml');
  });

  test('a kilo or more stays in kg; pieces are a bare number', () {
    expect(cartQtyLabel(1, 'kg'), '1 kg');
    expect(cartQtyLabel(1.5, 'kg'), '1.5 kg');
    expect(cartQtyLabel(3, 'pcs'), '3');
    expect(cartQtyLabel(2, ''), '2');
    expect(cartQtyLabel(0.5, 'm'), '0.5 m');
  });
}
