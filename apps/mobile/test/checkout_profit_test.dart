import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';

void main() {
  test('Non-GST bill keeps the whole amount; GST bill takes the tax off', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // 7 kg at ₹36 (price includes 18% GST), cost ₹32 a kg.
    c.read(cartProvider.notifier).addProduct({
      'id': 'p1',
      'name': 'Sugar',
      'selling_price': 36,
      'purchase_price': 32,
      'gst_rate': 18,
      'current_stock': 100,
      'units': {'short_name': 'kg', 'allow_decimal': true},
    }, addQty: 7);
    final cart = c.read(cartProvider);
    expect(cart.profitFor(gst: false), closeTo(252 - 224, 0.01));
    expect(cart.profitFor(gst: true), closeTo(252 / 1.18 - 224, 0.01));
  });
}
