import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/formatters.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';

/// Cigarettes: one piece ₹10, a Box of 10 at ₹95 (migration 0061).
Map<String, dynamic> cigarette({double? packPrice = 95}) => {
  'id': 'c1',
  'name': 'Gold Flake',
  'selling_price': 10,
  'purchase_price': 8,
  'mrp': 10,
  'gst_rate': 0,
  'current_stock': 100,
  'secondary_unit_name': 'Box',
  'conversion_factor': 10,
  'pack_price': packPrice,
  'units': {'short_name': 'pcs', 'allow_decimal': false},
};

void main() {
  late ProviderContainer c;
  CartNotifier cart() => c.read(cartProvider.notifier);
  CartState state() => c.read(cartProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('a box and loose pieces are separate lines at their own prices', () {
    cart().addProduct(cigarette(), asPack: true);
    cart().addProduct(cigarette(), addQty: 3);
    final box = state().lines.firstWhere((l) => l.isPack);
    final loose = state().lines.firstWhere((l) => !l.isPack);
    expect(box.price, 95);
    expect(box.qty, 1);
    expect(box.unitName, 'Box');
    expect(box.baseQty, 10);
    expect(box.priceSource, 'retail');
    expect(loose.price, 10);
    expect(loose.qty, 3);
    expect(state().total, 125);
    expect(state().priceReduction, 0);
    expect(cart().qtyInCart('c1', null), 13);
    // Profit uses the box's cost: 10 × ₹8 for ₹95.
    expect(state().estimatedProfit, closeTo(125 - 13 * 8, 0.001));
  });

  test('adding a box again adds to the box line', () {
    cart().addProduct(cigarette(), asPack: true);
    cart().addProduct(cigarette(), asPack: true);
    expect(state().lines.single.qty, 2);
    expect(state().total, 190);
  });

  test('the bill sends the box as 10 pieces at ₹9.50, flagged as a pack', () {
    cart().addProduct(cigarette(), asPack: true, addQty: 2);
    final item =
        (buildInvoicePayload(
                  cart: state(),
                  invoiceType: 'non_gst',
                  paidAmount: 190,
                  paymentMode: 'cash',
                )['items']
                as List)
            .single;
    expect(item['quantity'], 20);
    expect(item['unit_name'], 'pcs');
    expect(item['unit_price'], 9.5);
    expect(item['cost_price'], 8);
    expect(item['line_total'], 190);
    expect(item['pack'], true);
  });

  test('a saved box line reloads as a box for editing', () {
    final line = invoiceItemsToCartLines([
      {
        'id': 'i1',
        'product_id': 'c1',
        'product_name': 'Gold Flake',
        'quantity': 20,
        'unit_name': 'pcs',
        'unit_price': 9.5,
        'list_price': 9.5,
        'cost_price': 8,
        'gst_rate': 0,
        'line_total': 190,
        'sold_as_pack': true,
        'alt_unit_name': 'Box',
        'alt_factor': 10,
        'products': {'current_stock': 50},
      },
    ]).single;
    expect(line.isPack, true);
    expect(line.qty, 2);
    expect(line.price, 95);
    expect(line.retailPrice, 95);
    expect(line.unitName, 'Box');
    expect(line.availableStock, 5);
  });

  test('a customer price only applies to boxes when it is cheaper', () {
    cart().applyCustomerPricing({'c1:': 9.8}, wholesale: false);
    cart().addProduct(cigarette(), asPack: true);
    expect(state().lines.single.price, 95); // 10 × 9.80 = 98 > 95
    cart().applyCustomerPricing({'c1:': 9}, wholesale: false);
    expect(state().lines.single.price, 90); // 10 × 9 = 90 < 95
  });

  test('no pack price: a box is just 10 pieces at the piece price', () {
    expect(packOf(cigarette(packPrice: null), null), isNull);
    expect(packOf(cigarette(), {'id': 'v1'}), isNull); // not for variants
  });

  test('saved bill lines read as sold', () {
    final b = billedQty({
      'quantity': 20,
      'unit_name': 'pcs',
      'sold_as_pack': true,
      'alt_unit_name': 'Box',
      'alt_factor': 10,
    });
    expect((b.qty, b.unit, b.per), (2.0, 'Box', 10.0));
    final l = billedQty({
      'quantity': 20,
      'unit_name': 'pcs',
      'alt_unit_name': 'Box',
      'alt_factor': 10,
    });
    expect((l.qty, l.unit, l.per), (20.0, 'pcs', 1.0));
  });
}
