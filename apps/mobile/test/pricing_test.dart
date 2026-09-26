import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';
import 'package:softraxa_inventory/features/pos/pos_providers.dart';

/// Spec D15 example: retail 100, wholesale 90 from 10 units, customer 95.
Map<String, dynamic> cable() => {
  'id': 'p1',
  'name': 'Cable',
  'selling_price': 100,
  'wholesale_price': 90,
  'wholesale_min_qty': 10,
  'gst_rate': 0,
};

void main() {
  late ProviderContainer c;
  CartNotifier cart() => c.read(cartProvider.notifier);
  CartLine line() => c.read(cartProvider).lines.single;

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('retail by default; wholesale once the tier is reached, and back', () {
    cart().addProduct(cable());
    expect(line().price, 100);
    expect(line().priceSource, 'retail');
    cart().changeQty(line(), 10);
    expect(line().price, 90);
    expect(line().priceSource, 'wholesale');
    cart().changeQty(line(), 9);
    expect(line().price, 100);
  });

  test('a customer\'s agreed price is the default (95, not the cheaper 90)', () {
    cart().applyCustomerPricing({'p1:': 95}, wholesale: false);
    cart().addProduct(cable(), addQty: 10);
    expect(line().price, 95);
    expect(line().priceSource, 'customer');
    expect(c.read(cartProvider).priceReduction, 0);
  });

  test('choosing wholesale by hand is a reduction from the default', () {
    cart().applyCustomerPricing({'p1:': 95}, wholesale: false);
    cart().addProduct(cable());
    cart().changePrice(line(), 90);
    expect(line().priceSource, 'wholesale');
    expect(line().priceIsDefault, isFalse);
    expect(c.read(cartProvider).priceReduction, closeTo(5, 0.001));
  });

  test('a manual price survives quantity and customer changes', () {
    cart().addProduct(cable());
    cart().changePrice(line(), 97);
    cart().changeQty(line(), 12);
    expect(line().price, 97);
    cart().applyCustomerPricing({'p1:': 95}, wholesale: false);
    expect(line().price, 97);
    expect(line().priceSource, 'negotiated');
  });

  test('a wholesale customer gets wholesale from the first unit', () {
    cart().applyCustomerPricing(const {}, wholesale: true);
    cart().addProduct(cable());
    expect(line().price, 90);
  });

  group('discount limit (PD07, spec 5% example)', () {
    const staff5 = (unlimited: false, canEditPrices: true, limitPct: 5.0);

    test('50 off 1,000 is allowed, 60 is not', () {
      cart().addProduct(cable(), addQty: 5); // 5 × 100 = 500 at retail
      cart().changeQty(line(), 5);
      cart().changeDiscount(line(), 25); // 5% of 500
      expect(pricingProblem(c.read(cartProvider), staff5), isNull);
      cart().changeDiscount(line(), 30);
      expect(pricingProblem(c.read(cartProvider), staff5), contains('limit is 5%'));
    });

    test('price change and bill discount count together', () {
      cart().addProduct(cable(), addQty: 5);
      cart().changePrice(line(), 98); // 10 off
      cart().setBillDiscount(20); // + 20 → 30 = 6%
      expect(pricingProblem(c.read(cartProvider), staff5), isNotNull);
    });

    test('no price permission: any reduction is refused; owner: unlimited', () {
      cart().addProduct(cable());
      cart().changeDiscount(line(), 1);
      expect(
        pricingProblem(c.read(cartProvider), (unlimited: false, canEditPrices: false, limitPct: 0)),
        contains('permission'),
      );
      expect(
        pricingProblem(c.read(cartProvider), (unlimited: true, canEditPrices: true, limitPct: 100)),
        isNull,
      );
    });
  });
}
