import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/discount_cards/discount_card.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';
import 'package:softraxa_inventory/features/pos/pos_providers.dart';

const _books = 'cat-books';
const _stationery = 'cat-stationery';

Map<String, dynamic> _product(String id, double price, String? category) => {
  'id': id,
  'name': id,
  'selling_price': price,
  'gst_rate': 0,
  'category_id': category,
};

const _gold = DiscountCard(
  id: 'card-1',
  cardNo: '2017 1234 1234 4109',
  typeName: 'Gold',
  pct: 10,
  appliesTo: 'only',
  categoryIds: {_books},
);

void main() {
  late ProviderContainer c;
  CartNotifier cart() => c.read(cartProvider.notifier);
  CartState state() => c.read(cartProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('a card covers only its categories; charges are never covered', () {
    expect(_gold.pctFor(productId: 'b', categoryId: _books), 10);
    expect(_gold.pctFor(productId: 'p', categoryId: _stationery), 0);
    expect(_gold.pctFor(productId: 'p', categoryId: null), 0);
    const student = DiscountCard(
      id: 'c2',
      cardNo: 'S1',
      typeName: 'Student',
      pct: 5,
      appliesTo: 'except',
      categoryIds: {_stationery},
    );
    expect(student.pctFor(productId: 'b', categoryId: _books), 5);
    expect(student.pctFor(productId: 'b', categoryId: null), 5);
    expect(student.pctFor(productId: 'p', categoryId: _stationery), 0);
    const all = DiscountCard(id: 'c3', cardNo: 'A', typeName: 'All', pct: 7);
    expect(all.pctFor(productId: '', categoryId: null), 0);
    expect(all.label, 'All 7%');
  });

  test('applying the card discounts covered lines, also ones added later', () {
    cart().addProduct(_product('book', 200, _books));
    cart().setCard(_gold);
    expect(state().lines.single.cardDiscountAmount, 20);
    expect(state().total, 180);

    cart().addProduct(_product('pen', 50, _stationery));
    cart().addProduct(_product('guide', 300, _books));
    final byId = {for (final l in state().lines) l.productId: l};
    expect(byId['pen']!.cardDiscountAmount, 0);
    expect(byId['guide']!.cardDiscountAmount, 30);
    expect(state().cardDiscountTotal, 50);
    expect(state().total, 200 + 50 + 300 - 50);
  });

  test('quantity changes keep the card; removing the card restores prices', () {
    cart().addProduct(_product('book', 200, _books));
    cart().setCard(_gold);
    cart().changeQty(state().lines.single, 3);
    expect(state().lines.single.cardDiscountAmount, 60);
    cart().setCard(null);
    expect(state().lines.single.cardDiscountAmount, 0);
    expect(state().total, 600);
  });

  test('the card comes off after a typed line discount', () {
    cart().addProduct(_product('book', 200, _books));
    cart().changeDiscount(state().lines.single, 20); // ₹20 typed
    cart().setCard(_gold);
    final l = state().lines.single;
    expect(l.manualDiscountAmount, 20);
    expect(l.cardDiscountAmount, 18); // 10% of 180
    expect(l.discountAmount, 38);
  });

  test('the card discount does not count towards a staff discount limit', () {
    cart().addProduct(_product('book', 200, _books));
    cart().setCard(_gold);
    expect(state().priceReduction, closeTo(20, 0.001));
    expect(state().countedReduction, 0);
    const noRights = (unlimited: false, canEditPrices: false, limitPct: 0.0);
    expect(pricingProblem(state(), noRights), isNull);

    // Anything beyond the card still needs rights.
    cart().changeDiscount(state().lines.single, 10);
    expect(state().countedReduction, greaterThan(0));
    expect(pricingProblem(state(), noRights), isNotNull);
  });

  test('the bill payload carries the card only when one is applied', () {
    cart().addProduct(_product('book', 200, _books));
    final plain = buildInvoicePayload(
      cart: state(),
      invoiceType: 'non_gst',
      paidAmount: 200,
      paymentMode: 'cash',
    );
    expect(plain.containsKey('discount_card_id'), isFalse);

    cart().setCard(_gold);
    final withCard = buildInvoicePayload(
      cart: state(),
      invoiceType: 'non_gst',
      paidAmount: 180,
      paymentMode: 'cash',
    );
    expect(withCard['discount_card_id'], 'card-1');
    final item = (withCard['items'] as List).single as Map;
    expect(item['discount_amount'], 20);
    expect(item['line_total'], 180);
  });

  test('clearing the bill drops the card', () {
    cart().setCard(_gold);
    cart().clear();
    expect(state().card, isNull);
  });
}
