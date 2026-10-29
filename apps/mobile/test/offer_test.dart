import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dukania/features/offers/offer.dart';
import 'package:dukania/features/pos/cart.dart';
import 'package:dukania/features/pos/pos_providers.dart';

Map<String, dynamic> _product(double price) => {
  'id': 'p$price',
  'name': 'Item $price',
  'selling_price': price,
  'gst_rate': 0,
};

const _scratch50 = AppliedOffer(
  offerId: 'o1',
  name: 'Scratch & Win',
  amount: 50,
  minBill: 200,
  needsCustomer: true,
);
const _diwali = AppliedOffer(
  offerId: 'o2',
  name: 'Diwali',
  code: 'DIWALI10',
  kind: 'percent',
  percent: 10,
  maxDiscount: 100,
);

void main() {
  test(
    'an amount offer: its amount, never more than the bill, none under the minimum',
    () {
      expect(_scratch50.discountOn(500), 50);
      expect(_scratch50.discountOn(199), 0);
      const big = AppliedOffer(offerId: 'o', name: 'Voucher', amount: 100);
      expect(big.discountOn(60), 60);
    },
  );

  test('a % offer: rounded to the paisa, at most its cap', () {
    expect(_diwali.discountOn(555), 55.5);
    expect(_diwali.discountOn(2000), 100);
    expect(_diwali.label, 'Diwali 10%');
  });

  test(
    'from the server: the chosen prize, a code\'s own value, or the single amount',
    () {
      final json = {
        'offer_id': 'o1',
        'name': 'Scratch',
        'kind': 'amount',
        'amounts': [20, 50, 100],
        'min_bill': 200,
        'needs_customer': true,
      };
      expect(AppliedOffer.fromJson(json, amount: 100).amount, 100);
      expect(AppliedOffer.fromJson({...json, 'code_amount': 20}).amount, 20);
      expect(
        AppliedOffer.fromJson({
          ...json,
          'amounts': [75],
        }).amount,
        75,
      );
      expect(AppliedOffer.fromJson(json).needsCustomer, isTrue);
    },
  );

  group('in the cart', () {
    late ProviderContainer c;
    CartNotifier cart() => c.read(cartProvider.notifier);
    CartState state() => c.read(cartProvider);
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('comes off the bill after the typed bill discount', () {
      cart().addProduct(_product(1000));
      cart().setBillDiscount(100);
      cart().setOffer(_diwali);
      expect(state().manualBillDiscountAmount, 100);
      expect(state().offerAmount, 90); // 10% of 900
      expect(state().billDiscountAmount, 190);
      expect(state().total, 810);
    });

    test('a cashier with no discount rights can give it, nothing more', () {
      cart().addProduct(_product(500));
      cart().setOffer(_scratch50);
      const noRights = (unlimited: false, canEditPrices: false, limitPct: 0.0);
      expect(state().countedReduction, 0);
      expect(pricingProblem(state(), noRights), isNull);
      cart().setBillDiscount(20);
      expect(pricingProblem(state(), noRights), isNotNull);
    });

    test(
      'the bill sends the offer, code and amount; the discount includes it',
      () {
        cart().addProduct(_product(500));
        cart().setOffer(_diwali);
        final p = buildInvoicePayload(
          cart: state(),
          invoiceType: 'non_gst',
          paidAmount: 450,
          paymentMode: 'cash',
        );
        expect(p['offer_id'], 'o2');
        expect(p['offer_code'], 'DIWALI10');
        expect(p['offer_amount'], 50);
        expect(p['discount_amount'], 50);
        cart().setOffer(null);
        expect(
          buildInvoicePayload(
            cart: state(),
            invoiceType: 'non_gst',
            paidAmount: 500,
            paymentMode: 'cash',
          ).containsKey('offer_id'),
          isFalse,
        );
      },
    );
  });

  test('a saved bill gives back its offer as what it gave', () {
    final o = offerOnSavedBill({
      'offer_id': 'o1',
      'offer_name': 'Scratch & Win',
      'offer_code': 'SC-0001',
      'offer_amount': 50,
    })!;
    expect(o.amount, 50);
    expect(o.code, 'SC-0001');
    expect(o.discountOn(500), 50);
    expect(offerOnSavedBill({'offer_id': null}), isNull);
  });
}
