import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/returns/exchange.dart';
import 'package:softraxa_inventory/features/returns/held_goods_screen.dart';

void main() {
  group('Exchange credit (D29 examples)', () {
    test('fully paid original: the whole return is credit', () {
      expect(estimateExchangeCredit(returnValue: 1000, originalDue: 0), 1000);
    });

    test('original still owes 400: only 600 is left for the replacement', () {
      expect(estimateExchangeCredit(returnValue: 1000, originalDue: 400), 600);
    });

    test('return smaller than the old due leaves no credit', () {
      expect(estimateExchangeCredit(returnValue: 300, originalDue: 400), 0);
    });
  });

  test('bill discount share (PD26): ₹18 off a ₹118 bill', () {
    final f = invoiceDiscountFactor({
      'discount_amount': 18,
      'invoice_items': [
        {'line_total': 118},
      ],
    });
    expect(f * 118, closeTo(100, 0.001));
    expect(invoiceDiscountFactor({'invoice_items': []}), 1);
  });

  test('condition split label (D28 example)', () {
    expect(
      conditionSplitLabel({'sellable': 1, 'inspection': 1, 'scrap': 1}),
      '1 sellable, 1 needs inspection, 1 scrap',
    );
  });

  test('exchange summary uses the server figures', () {
    final s = exchangeSummary({
      'return_no': 'SR-00007',
      'return_value': 1000,
      'invoice_no': 'INV-00042',
      'applied_to_original': 400,
      'credit_used': 600,
      'refund': 0,
      'advance': 0,
    });
    expect(s, contains('SR-00007'));
    expect(s, contains('INV-00042'));
    expect(s, contains('cleared the old bill'));
    expect(s, isNot(contains('refund')));
  });

  group('Held goods moves (PD29)', () {
    test('returns staff reclassify but cannot release or write off', () {
      final moves = heldGoodsMoves('inspection', canStock: false, canReturns: true)
          .map((m) => m.$1);
      expect(moves, containsAll(['damaged', 'scrap']));
      expect(moves, isNot(contains('sellable')));
      expect(moves, isNot(contains('disposed')));
    });

    test('stock staff release and write off damaged goods', () {
      final moves = heldGoodsMoves('damaged', canStock: true, canReturns: false)
          .map((m) => m.$1);
      expect(moves, ['sellable', 'disposed']);
    });
  });
}
