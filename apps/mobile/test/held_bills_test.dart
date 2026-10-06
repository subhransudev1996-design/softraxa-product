import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';
import 'package:softraxa_inventory/features/pos/held_bills.dart';

Map<String, dynamic> product(String id, String name, num price) => {
  'id': id,
  'name': name,
  'selling_price': price,
  'purchase_price': price * 0.8,
  'gst_rate': 0,
  'current_stock': 50,
  'units': {'short_name': 'pcs', 'allow_decimal': false},
};

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('hold clears the counter; taking it back gives the same bill', () {
    final cart = c.read(cartProvider.notifier);
    cart.addProduct(product('a', 'Milk', 28), addQty: 2);
    cart.addProduct(product('b', 'Bread', 45));
    final before = c.read(cartProvider);

    c.read(heldBillsProvider.notifier).hold(before);
    cart.clear();
    expect(c.read(cartProvider).lines, isEmpty);

    final held = c.read(heldBillsProvider);
    expect(held.single.label, 'Milk + 1 more');
    expect(held.single.cart.total, 101);

    final back = c.read(heldBillsProvider.notifier).take(held.single.id)!;
    cart.restore(back.cart);
    expect(c.read(cartProvider).total, 101);
    expect(c.read(cartProvider).lines.map((l) => l.qty), [2, 1]);
    expect(c.read(heldBillsProvider), isEmpty);
  });

  test('an empty counter is never held; ids stay unique', () {
    final held = c.read(heldBillsProvider.notifier);
    held.hold(const CartState());
    expect(c.read(heldBillsProvider), isEmpty);
    c.read(cartProvider.notifier).addProduct(product('a', 'Milk', 28));
    held.hold(c.read(cartProvider));
    held.hold(c.read(cartProvider));
    final ids = c.read(heldBillsProvider).map((h) => h.id).toSet();
    expect(ids.length, 2);
    expect(held.take(999), isNull);
  });
}
