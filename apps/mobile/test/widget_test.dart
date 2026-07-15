import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';
import 'package:softraxa_inventory/features/products/product_providers.dart'
    show parseWeightedBarcode;
import 'package:softraxa_inventory/features/reports/report_detail_screen.dart'
    show purchasesByDay, gstByRate, topN;
import 'package:softraxa_inventory/features/reports/report_charts.dart'
    show ChartPoint;
import 'package:softraxa_inventory/features/import/excel_import_screen.dart'
    show parseImportNum, normalizeImportHeader, gstRateError;
import 'package:softraxa_inventory/features/expenses/expenses_screen.dart'
    show expensePresetRange;

void main() {
  group('Cart totals', () {
    CartLine line({
      double price = 118,
      double qty = 1,
      double discount = 0,
      bool discountIsPercent = false,
      double gstRate = 18,
      double costPrice = 0,
    }) => CartLine(
      key: 'p1:',
      productId: 'p1',
      name: 'Test product',
      price: price,
      qty: qty,
      discount: discount,
      discountIsPercent: discountIsPercent,
      gstRate: gstRate,
      costPrice: costPrice,
    );

    test('GST is back-calculated from inclusive price', () {
      final l = line(price: 118, qty: 1, gstRate: 18);
      expect(l.gross, 118);
      expect(l.net, closeTo(100, 0.001));
      expect(l.tax, closeTo(18, 0.001));
    });

    test('line discount reduces gross before tax split', () {
      final l = line(price: 118, qty: 2, discount: 18, gstRate: 18);
      expect(l.gross, 218);
      expect(l.net, closeTo(218 / 1.18, 0.001));
    });

    test('line discount can be entered as a percent of qty*price', () {
      // 2 units @ ₹118, 10% off -> discountAmount = 23.6, gross = 212.4.
      final l = line(price: 118, qty: 2, discount: 10, discountIsPercent: true);
      expect(l.discountAmount, closeTo(23.6, 0.001));
      expect(l.gross, closeTo(212.4, 0.001));
    });

    test('₹ discount is unaffected by discountIsPercent being false', () {
      final l = line(price: 118, qty: 2, discount: 18);
      expect(l.discountAmount, 18);
    });

    test('cart totals include round off to whole rupees', () {
      final cart = CartState(lines: [line(price: 99.5)]);
      expect(cart.total, cart.grandBeforeRound + cart.roundOff);
      expect(cart.total, cart.total.roundToDouble());
    });

    test('bill discount can be entered as a percent of items gross', () {
      final cart = CartState(
        lines: [line(price: 100, qty: 2, gstRate: 0)], // itemsGross = 200
        billDiscount: 10,
        billDiscountIsPercent: true,
      );
      expect(cart.billDiscountAmount, closeTo(20, 0.001));
      expect(cart.grandBeforeRound, closeTo(180, 0.001));
    });

    test(
      '₹ bill discount is unaffected by billDiscountIsPercent being false',
      () {
        final cart = CartState(
          lines: [line(price: 100, qty: 2, gstRate: 0)],
          billDiscount: 15,
        );
        expect(cart.billDiscountAmount, 15);
      },
    );

    test('roundOffFor rounds up when the fraction is 50p or more', () {
      expect(roundOffFor(99.5), closeTo(0.5, 0.0001));
      expect(roundOffFor(99.6), closeTo(0.4, 0.0001));
    });

    test('roundOffFor rounds down when the fraction is under 50p', () {
      expect(roundOffFor(100.4), closeTo(-0.4, 0.0001));
      expect(roundOffFor(100.1), closeTo(-0.1, 0.0001));
    });

    test('roundOffFor is zero for an already-whole amount', () {
      expect(roundOffFor(250), 0);
    });

    test('fractional (loose) quantities keep GST math exact', () {
      // 1.19 kg of ₹42/kg sugar at 5% GST — kirana loose-goods case.
      final l = line(price: 42, qty: 1.19, gstRate: 5);
      expect(l.gross, closeTo(49.98, 0.001));
      expect(l.net, closeTo(49.98 / 1.05, 0.001));
      expect(l.tax, closeTo(49.98 - 49.98 / 1.05, 0.001));
      final cart = CartState(lines: [l]);
      expect(
        cart.total,
        cart.total.roundToDouble(),
      ); // round-off still lands whole
    });

    test('fractional quantities survive the invoice payload round trip', () {
      final cart = CartState(lines: [line(price: 42, qty: 0.5, gstRate: 0)]);
      final payload = buildInvoicePayload(
        cart: cart,
        invoiceType: 'non_gst',
        paidAmount: cart.total,
        paymentMode: 'cash',
      );
      final item = (payload['items'] as List).first as Map<String, dynamic>;
      expect(item['quantity'], 0.5);
      expect(item['line_total'], closeTo(21, 0.001));
    });

    test('invoice payload matches server total formula', () {
      final cart = CartState(
        lines: [
          line(price: 118, qty: 2, gstRate: 18),
          line(price: 50, qty: 1, gstRate: 0),
        ],
        billDiscount: 10,
      );
      final payload = buildInvoicePayload(
        cart: cart,
        invoiceType: 'gst',
        paidAmount: cart.total,
        paymentMode: 'cash',
      );
      final items = payload['items'] as List;
      // server: total = sum(qty*unit_price - line_disc) - bill_disc + sum(tax) + round
      double serverSubtotal = 0, serverTax = 0;
      for (final it in items.cast<Map<String, dynamic>>()) {
        serverSubtotal +=
            (it['quantity'] as num) * (it['unit_price'] as num) -
            (it['discount_amount'] as num);
        serverTax += it['tax_amount'] as num;
      }
      final serverTotal =
          serverSubtotal -
          (payload['discount_amount'] as num) +
          serverTax +
          (payload['round_off'] as num);
      expect(serverTotal, closeTo(cart.total, 0.05));
    });

    test('estimated profit nets out cost, GST and line discount', () {
      // ₹118 incl. 18% GST (net ₹100), cost ₹60 -> profit ₹40 per unit.
      final cart = CartState(
        lines: [line(price: 118, qty: 2, gstRate: 18, costPrice: 60)],
      );
      expect(cart.totalCost, 120);
      expect(
        cart.estimatedProfit,
        closeTo(200 - 120, 0.01),
      ); // net 200, cost 120
    });

    test('bill discount comes straight out of profit', () {
      final cart = CartState(
        lines: [line(price: 100, qty: 1, gstRate: 0, costPrice: 60)],
        billDiscount: 20,
      );
      // net = 100, bill discount ₹20, cost 60 -> profit 20.
      expect(cart.estimatedProfit, closeTo(20, 0.01));
    });

    test('profit can go negative when selling below cost', () {
      final cart = CartState(
        lines: [line(price: 50, qty: 1, gstRate: 0, costPrice: 80)],
      );
      expect(cart.estimatedProfit, closeTo(-30, 0.01));
    });
  });

  group('Sell by amount (loose goods)', () {
    test('₹50 of ₹42/kg sugar computes 1.190 kg', () {
      expect(qtyForAmount(50, 42), closeTo(1.190, 0.0005));
    });

    test('rounds to the 3 decimals the DB stores', () {
      expect(qtyForAmount(10, 3), 3.333);
    });

    test('guards zero/negative rate and amount', () {
      expect(qtyForAmount(50, 0), 0);
      expect(qtyForAmount(0, 42), 0);
      expect(qtyForAmount(-5, 42), 0);
    });

    test('computed qty × rate lands within a paisa of the asked amount', () {
      final q = qtyForAmount(50, 42);
      expect(q * 42, closeTo(50, 0.05));
    });
  });

  group('Secondary unit conversion', () {
    test('2 Bags at 50 kg/Bag = 100 kg base', () {
      expect(toBaseQty(2, 50), 100);
    });

    test('no factor means no conversion', () {
      expect(toBaseQty(2.5, null), 2.5);
    });

    test('rounds to 3 decimals (rod store: 1.5 Rods of 3.048 m)', () {
      expect(toBaseQty(1.5, 3.048), 4.572);
    });

    test(
      'bulk price round-trips: ₹2000/Bag ÷ 50 = ₹40/kg × 100 kg = 2 Bags worth',
      () {
        const bagPrice = 2000.0, factor = 50.0;
        final basePrice = bagPrice / factor;
        expect(basePrice * toBaseQty(2, factor), closeTo(2 * bagPrice, 0.001));
      },
    );
  });

  group('Weighted (scale-label) barcodes', () {
    test('parses 2P IIIII WWWWW C: item 12345, 485 g', () {
      final r = parseWeightedBarcode('2112345004853');
      expect(r, isNotNull);
      expect(r!.itemCode, '12345');
      expect(r.weightKg, closeTo(0.485, 0.0001));
    });

    test('parses a whole-kg weight: 1.5 kg', () {
      final r = parseWeightedBarcode('2012345015002');
      expect(r!.weightKg, closeTo(1.5, 0.0001));
    });

    test('rejects non-2-prefix EAN-13 (normal retail barcode)', () {
      expect(parseWeightedBarcode('8901234567890'), isNull);
    });

    test('rejects wrong lengths and non-numeric codes', () {
      expect(parseWeightedBarcode('212345'), isNull);
      expect(parseWeightedBarcode('2ABCDE0048531'), isNull);
    });

    test('rejects zero-weight labels', () {
      expect(parseWeightedBarcode('2112345000003'), isNull);
    });
  });

  group('Report charts — data helpers', () {
    test('topN sorts descending and caps to n', () {
      final points = <ChartPoint>[('A', 30), ('B', 90), ('C', 10), ('D', 50)];
      final top2 = topN(points, 2);
      expect(top2.map((p) => p.$1), ['B', 'D']);
    });

    test('topN returns everything when n exceeds length', () {
      final points = <ChartPoint>[('A', 1), ('B', 2)];
      expect(topN(points, 8).length, 2);
    });

    test('purchasesByDay sums same-day rows and sorts chronologically', () {
      final rows = [
        {'purchase_date': '2026-07-03', 'total': 100},
        {'purchase_date': '2026-07-01', 'total': 40},
        {'purchase_date': '2026-07-03', 'total': 20},
        {'purchase_date': '2026-07-02', 'total': 60},
      ];
      final points = purchasesByDay(rows);
      expect(points.length, 3);
      expect(points[0].$2, closeTo(40, 0.001)); // Jul 1
      expect(points[1].$2, closeTo(60, 0.001)); // Jul 2
      expect(points[2].$2, closeTo(120, 0.001)); // Jul 3 (100 + 20)
    });

    test('purchasesByDay ignores rows with an unparsable date', () {
      final rows = [
        {'purchase_date': null, 'total': 999},
        {'purchase_date': '2026-07-01', 'total': 40},
      ];
      expect(purchasesByDay(rows).length, 1);
    });

    test('gstByRate merges output/input across the union of rates', () {
      final output = [
        {'gst_rate': 18, 'tax_amount': 100},
        {'gst_rate': 5, 'tax_amount': 10},
      ];
      final input = [
        {'gst_rate': 18, 'tax_amount': 40},
        {'gst_rate': 12, 'tax_amount': 5},
      ];
      final r = gstByRate(output, input);
      // Union of rates 5, 12, 18 sorted ascending.
      expect(r.output.map((p) => p.$1), ['5%', '12%', '18%']);
      expect(r.output.map((p) => p.$2), [10, 0, 100]);
      expect(r.input.map((p) => p.$2), [0, 5, 40]);
    });

    test('gstByRate returns empty series for empty input', () {
      final r = gstByRate([], []);
      expect(r.output, isEmpty);
      expect(r.input, isEmpty);
    });
  });

  group('Purchase round off', () {
    // Mirrors purchase_form_screen.dart's _grandBeforeRound/_roundOff/_total:
    // subtotal + tax - discount + extra charges, then rounded to the rupee.
    double total({
      required double subtotal,
      double tax = 0,
      double discount = 0,
      double extra = 0,
    }) {
      final grandBeforeRound = subtotal + tax - discount + extra;
      return grandBeforeRound + roundOffFor(grandBeforeRound);
    }

    test('purchase total rounds to the nearest rupee after all charges', () {
      // 1000 + 180 tax - 50 discount + 20 extra = 1150.30 -> rounds to 1150.
      expect(total(subtotal: 1000, tax: 180.3, discount: 50, extra: 20), 1150);
    });

    test('round off can be negative when the total rounds down', () {
      const grandBeforeRound = 1150.2;
      expect(roundOffFor(grandBeforeRound), closeTo(-0.2, 0.0001));
      expect(total(subtotal: 1150.2), 1150);
    });
  });

  group('Purchase percent discount', () {
    // Mirrors purchase_form_screen.dart's _discountAmount getter: a percent
    // discount is resolved against (subtotal + tax), same base as the bill's
    // pre-discount goods value including GST.
    double discountAmount({
      required double subtotal,
      double tax = 0,
      required double raw,
      required bool isPercent,
    }) => isPercent ? (subtotal + tax) * raw / 100 : raw;

    test('percent discount resolves against subtotal + tax', () {
      // 1000 subtotal + 180 tax = 1180 base; 10% -> ₹118.
      final amt = discountAmount(
        subtotal: 1000,
        tax: 180,
        raw: 10,
        isPercent: true,
      );
      expect(amt, closeTo(118, 0.001));
    });

    test('₹ discount passes through unchanged regardless of base', () {
      final amt = discountAmount(
        subtotal: 1000,
        tax: 180,
        raw: 75,
        isPercent: false,
      );
      expect(amt, 75);
    });
  });

  group('Excel import — numeric parsing', () {
    test('parses plain numbers', () {
      expect(parseImportNum('28999'), 28999);
      expect(parseImportNum('18'), 18);
    });

    test('strips thousands separators', () {
      expect(parseImportNum('28,999'), 28999);
      expect(parseImportNum('1,00,000'), 100000); // Indian lakh grouping
    });

    test('strips currency symbol and stray percent sign', () {
      expect(parseImportNum('₹28999'), 28999);
      expect(parseImportNum('18%'), 18);
    });

    test('strips surrounding whitespace', () {
      expect(parseImportNum('  299 '), 299);
    });

    test('throws on genuinely non-numeric text', () {
      expect(() => parseImportNum('abc'), throwsFormatException);
    });
  });

  group('Excel import — header validation', () {
    test('normalizes case, whitespace and the required asterisk', () {
      expect(normalizeImportHeader('Name*'), normalizeImportHeader('  name '));
      expect(
        normalizeImportHeader('Selling Price*'),
        normalizeImportHeader('selling price'),
      );
    });

    test('different headers do not normalize to the same value', () {
      expect(
        normalizeImportHeader('GST %'),
        isNot(normalizeImportHeader('Opening Stock')),
      );
    });
  });

  group('Excel import — GST rate validation', () {
    test('accepts standard GST slabs with no error', () {
      for (final rate in [0.0, 5.0, 12.0, 18.0, 28.0]) {
        expect(gstRateError(rate), isNull);
      }
    });

    test('rejects out-of-range rates', () {
      expect(gstRateError(-1), isNotNull);
      expect(gstRateError(29), isNotNull);
    });

    test(
      'flags a fraction between 0 and 1 as a likely percent-format mistake',
      () {
        // A cell formatted as a percentage in Excel stores "18%" as 0.18.
        expect(gstRateError(0.18), isNotNull);
        expect(gstRateError(0.05), isNotNull);
      },
    );

    test('does not flag a legitimate whole-number-adjacent rate like 1', () {
      expect(gstRateError(1), isNull);
    });
  });

  group('POS split payments', () {
    test('sums real payment modes as collected', () {
      final r = resolveSplitPayments([('cash', 500), ('upi', 500)]);
      expect(r.collected, 1000);
      expect(r.realPayments, [('cash', 500.0), ('upi', 500.0)]);
      expect(r.mode, 'other');
    });

    test('a single real mode is sent as-is, not collapsed to other', () {
      final r = resolveSplitPayments([('cash', 300), ('cash', 200)]);
      expect(r.collected, 500);
      expect(r.mode, 'cash');
    });

    test('a credit row is excluded from collected and from realPayments', () {
      // ₹1000 bill: ₹500 cash + ₹500 credit -> only ₹500 actually collected.
      final r = resolveSplitPayments([('cash', 500), ('credit', 500)]);
      expect(r.collected, 500);
      expect(r.realPayments, [('cash', 500.0)]);
      expect(r.mode, 'cash');
    });

    test('a fully-credit split collects nothing and mode is credit', () {
      final r = resolveSplitPayments([('credit', 1000)]);
      expect(r.collected, 0);
      expect(r.realPayments, isEmpty);
      expect(r.mode, 'credit');
    });

    test('zero/blank amount rows are ignored', () {
      final r = resolveSplitPayments([('cash', 0), ('upi', 500)]);
      expect(r.collected, 500);
      expect(r.realPayments, [('upi', 500.0)]);
    });

    test('negative amounts are ignored, not subtracted', () {
      final r = resolveSplitPayments([('cash', -50), ('upi', 500)]);
      expect(r.collected, 500);
    });
  });

  group('Invoice edit — reconstructing cart lines', () {
    Map<String, dynamic> item({
      String id = 'item1',
      String productId = 'p1',
      String? variantId,
      double unitPrice = 100,
      double discountAmount = 0,
      double gstRate = 18,
      double quantity = 2,
      Map<String, dynamic>? products,
      Map<String, dynamic>? productVariants,
    }) => {
      'id': id,
      'product_id': productId,
      'variant_id': variantId,
      'product_name': 'Test product',
      'variant_name': '',
      'hsn_code': '',
      'unit_name': 'pcs',
      'unit_price': unitPrice,
      'discount_amount': discountAmount,
      'gst_rate': gstRate,
      'quantity': quantity,
      'mrp': 0,
      'cost_price': 60,
      'serial_no': '',
      'products': products,
      'product_variants': productVariants,
    };

    test(
      'GST-inclusive price is reconstructed from the stored pre-tax unit_price',
      () {
        // Stored unit_price 100 @ 18% GST -> inclusive price should be 118.
        final lines = invoiceItemsToCartLines([
          item(unitPrice: 100, gstRate: 18),
        ]);
        expect(lines.single.price, closeTo(118, 0.001));
      },
    );

    test(
      'line discount is reconstructed the same way, back to GST-inclusive',
      () {
        final lines = invoiceItemsToCartLines([
          item(unitPrice: 100, discountAmount: 10, gstRate: 18),
        ]);
        expect(lines.single.discount, closeTo(11.8, 0.001));
        expect(lines.single.discountIsPercent, false);
      },
    );

    test(
      'non-GST items (gst_rate 0) pass unit_price/discount through unchanged',
      () {
        final lines = invoiceItemsToCartLines([
          item(unitPrice: 100, discountAmount: 10, gstRate: 0),
        ]);
        expect(lines.single.price, 100);
        expect(lines.single.discount, 10);
      },
    );

    test(
      'trackSerial/allowDecimal/availableStock come from the embedded product row',
      () {
        final lines = invoiceItemsToCartLines([
          item(
            products: {
              'track_serial': true,
              'current_stock': 5,
              'units': {'allow_decimal': true},
            },
          ),
        ]);
        final l = lines.single;
        expect(l.trackSerial, true);
        expect(l.allowDecimal, true);
        expect(l.availableStock, 5);
      },
    );

    test(
      'a variant line reads current_stock from product_variants, not products',
      () {
        final lines = invoiceItemsToCartLines([
          item(
            variantId: 'v1',
            products: {'current_stock': 999},
            productVariants: {'current_stock': 3},
          ),
        ]);
        expect(lines.single.availableStock, 3);
      },
    );

    test(
      'each line gets a unique key from its own item id, even for the same product',
      () {
        final lines = invoiceItemsToCartLines([
          item(id: 'a', productId: 'p1'),
          item(id: 'b', productId: 'p1'),
        ]);
        expect(lines[0].key, isNot(lines[1].key));
      },
    );
  });

  group('Expense quick-filter presets', () {
    test('today spans midnight to the current moment', () {
      final now = DateTime(2026, 7, 8, 15, 30);
      final r = expensePresetRange('today', now);
      expect(r.from, DateTime(2026, 7, 8));
      expect(r.to, now);
    });

    test('this week starts on Monday', () {
      // 2026-07-08 is a Wednesday.
      final now = DateTime(2026, 7, 8, 15, 30);
      final r = expensePresetRange('this_week', now);
      expect(r.from, DateTime(2026, 7, 6));
      expect(r.to, now);
    });

    test('this week when today is itself Monday starts on the same day', () {
      final now = DateTime(2026, 7, 6, 9);
      final r = expensePresetRange('this_week', now);
      expect(r.from, DateTime(2026, 7, 6));
    });

    test('this month starts on the 1st', () {
      final now = DateTime(2026, 7, 8, 15, 30);
      final r = expensePresetRange('this_month', now);
      expect(r.from, DateTime(2026, 7, 1));
      expect(r.to, now);
    });

    test('last month spans the previous calendar month', () {
      final now = DateTime(2026, 7, 8);
      final r = expensePresetRange('last_month', now);
      expect(r.from, DateTime(2026, 6, 1));
      expect(r.to, DateTime(2026, 6, 30));
    });

    test('last month rolls back across a year boundary in January', () {
      final now = DateTime(2026, 1, 15);
      final r = expensePresetRange('last_month', now);
      expect(r.from, DateTime(2025, 12, 1));
      expect(r.to, DateTime(2025, 12, 31));
    });

    test('unknown preset throws', () {
      expect(
        () => expensePresetRange('bogus', DateTime(2026, 7, 8)),
        throwsArgumentError,
      );
    });
  });
}
