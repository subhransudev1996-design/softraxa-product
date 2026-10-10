import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/invoices/bill_layout.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';
import 'package:softraxa_inventory/features/returns/exchange.dart';

const kurtaLine = ExchangeReturnLine(
  productId: 'kurta',
  name: 'Kurta',
  qty: 1,
  shownQty: 1,
  qtyLabel: '1',
  rate: 500,
  paid: 450,
);

void main() {
  test('a returned line: rate, discount and price paid', () {
    expect(kurtaLine.gross, 500);
    expect(kurtaLine.discount, 50);
    const box = ExchangeReturnLine(
      productId: 'pen',
      name: 'Pens',
      qty: 10,
      shownQty: 1,
      qtyLabel: '1 Box',
      rate: 95,
      paid: 95,
    );
    expect(box.discount, 0);
    // Per piece: the lowest when a product came back on two lines.
    expect(
      exchangeOldPrices([
        kurtaLine,
        box,
        const ExchangeReturnLine(
          productId: 'kurta',
          name: 'Kurta',
          qty: 2,
          shownQty: 2,
          qtyLabel: '2',
          rate: 500,
          paid: 800,
        ),
      ]),
      {'kurta': 400, 'pen': 9.5},
    );
  });

  test('what the customer pays or gets back', () {
    expect(exchangeDifference(credit: 450, newTotal: 600), (
      label: 'Customer pays',
      amount: 150.0,
    ));
    expect(exchangeDifference(credit: 450, newTotal: 400), (
      label: 'Give back',
      amount: 50.0,
    ));
    expect(exchangeDifference(credit: 450, newTotal: 450), (
      label: 'Even exchange',
      amount: 0.0,
    ));
  });

  test('bill age line', () {
    expect(
      billAgeText(DateTime(2026, 10, 9), 3, 7),
      'Bought 09 Oct 2026 · 3 days ago · returns within 7 days',
    );
    expect(billAgeText(null, 0, 0), 'today');
  });

  test('the same product comes in at the price paid; others at today\'s', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cart = c.read(cartProvider.notifier);
    cart.replaceAll(const CartState(exchangePrices: {'kurta': 450}));
    cart.addProduct({'id': 'kurta', 'name': 'Kurta', 'selling_price': 500});
    cart.addProduct({'id': 'shirt', 'name': 'Shirt', 'selling_price': 700});
    final lines = c.read(cartProvider).lines;
    expect(lines[0].price, 450);
    expect(lines[0].priceSource, 'exchange');
    expect(priceSourceLabel(lines[0].priceSource), 'Paid before');
    // Today's price is still there to pick.
    expect(lines[0].priceOptions, [('exchange', 450.0), ('retail', 500.0)]);
    expect(lines[0].reductionFromDefault, 0);
    expect(lines[1].price, 700);
    expect(lines[1].exchangePrice, isNull);
    // A new bill afterwards has no old prices.
    cart.clear();
    cart.addProduct({'id': 'kurta', 'name': 'Kurta', 'selling_price': 500});
    expect(c.read(cartProvider).lines.single.price, 500);
  });

  test('an exchange bill prints what came back and where the credit went', () {
    final bill = BillLayout(
      business: const {},
      invoice: const {
        'invoice_type': 'non_gst',
        'total': 600,
        'paid_amount': 600,
        'payment_mode': 'cash',
        'invoice_payments': [
          {
            'amount': 450,
            'payment_mode': 'other',
            'note': 'Exchange credit from SR-00002',
          },
        ],
      },
      items: const [],
      exchange: const {
        'result': {
          'return_value': 450,
          'applied_to_original': 0,
          'credit_used': 450,
          'refund': 0,
          'advance': 0,
        },
        'original': {'invoice_no': 'INV/26-27/0056'},
        'sale_returns': {
          'return_no': 'SR-00002',
          'sale_return_items': [
            {'product_name': 'Kurta', 'quantity': 1, 'line_total': 450},
          ],
        },
      },
    );
    // The credit by name, the rest in cash.
    expect(bill.payments, [('Exchange credit', 450.0), ('Cash', 150.0)]);
    final ex = bill.exchange!;
    expect(ex.originalNo, 'INV/26-27/0056');
    expect(ex.returnNo, 'SR-00002');
    expect(ex.returned, [('Kurta', 1.0, 450.0)]);
    expect(ex.rows, [('Return value', 450.0), ('Used on this bill', 450.0)]);
  });
}
