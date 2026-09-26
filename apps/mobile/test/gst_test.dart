import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/gst.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';

void main() {
  group('Bill discount and GST at checkout', () {
    CartLine phone() => CartLine(
      key: 'p1:',
      productId: 'p1',
      name: 'Phone',
      price: 118,
      gstRate: 18,
    );

    test('without a bill discount the included GST is the line tax', () {
      expect(CartState(lines: [phone()]).billTaxTotal, closeTo(18, 0.001));
    });

    test('a bill discount reduces the included GST in proportion', () {
      // ₹118 incl. 18% less ₹18 → ₹100 = 84.75 + 15.25 GST (as 0040 saves it).
      final cart = CartState(lines: [phone()], billDiscount: 18);
      expect(cart.total, 100);
      expect(cart.billTaxTotal, closeTo(15.25, 0.01));
      expect(cart.taxTotal, closeTo(18, 0.001)); // still sent per line
    });
  });

  group('GST state helpers', () {
    test('state comes from the first two GSTIN digits', () {
      expect(stateFromGstin('27AAPFU0939F1ZV'), '27');
      expect(stateFromGstin(' 29ABCDE1234F1Z5'), '29');
    });

    test('invalid or short GSTINs give no state', () {
      expect(stateFromGstin(''), isNull);
      expect(stateFromGstin('2'), isNull);
      expect(stateFromGstin('25ABCDE1234F1Z5'), isNull); // 25 merged into 26
      expect(stateFromGstin('AB123'), isNull);
    });

    test('labels', () {
      expect(gstStateLabel('27'), '27 - Maharashtra');
      expect(gstStateLabel(''), '');
      expect(gstStateLabel(null), '');
    });
  });

  group('GSTIN validation (mirrors public.is_valid_gstin)', () {
    test('valid check digits', () {
      expect(isValidGstin('27AAPFU0939F1ZV'), isTrue);
      expect(isValidGstin('29AAPFU0939F1ZR'), isTrue);
      expect(isValidGstin(' 27aapfu0939f1zv '), isTrue); // trimmed, any case
    });

    test('wrong check digit, state or length', () {
      expect(isValidGstin('27AAPFU0939F1ZX'), isFalse);
      expect(isValidGstin('25AAPFU0939F1ZV'), isFalse); // no state 25
      expect(isValidGstin('27AAPFU0939F1Z'), isFalse);
      expect(isValidGstin(''), isFalse);
    });

    test('field errors: empty is fine, length and typos are explained', () {
      expect(gstinError(''), isNull);
      expect(gstinError('27AAPFU0939F1ZV'), isNull);
      expect(gstinError('27AAPFU'), contains('15 characters'));
      expect(gstinError('27AAPFU0939F1ZX'), contains('not valid'));
    });
  });

  group('GST split', () {
    test('intra-state lines sum CGST and SGST', () {
      final s = gstSplit([
        {'tax_amount': 18, 'cgst_amount': 9, 'sgst_amount': 9, 'igst_amount': 0},
        {'tax_amount': 5, 'cgst_amount': 2.5, 'sgst_amount': 2.5, 'igst_amount': 0},
      ]);
      expect(s.cgst, 11.5);
      expect(s.sgst, 11.5);
      expect(s.igst, 0);
    });

    test('inter-state lines are all IGST', () {
      final s = gstSplit([
        {'tax_amount': 18, 'cgst_amount': 0, 'sgst_amount': 0, 'igst_amount': 18},
      ]);
      expect(s.igst, 18);
      expect(s.cgst + s.sgst, 0);
    });

    test('lines saved before the split existed count as CGST + SGST', () {
      final s = gstSplit([
        {'tax_amount': 18},
      ]);
      expect(s.cgst, 9);
      expect(s.sgst, 9);
      expect(s.igst, 0);
    });

    test('a fully discounted line keeps its zero split', () {
      // Bill discount can take a line's tax to 0 (migration 0040); that must
      // not fall back to "tax_amount / 2".
      final s = gstSplit([
        {'tax_amount': 18, 'cgst_amount': 0, 'sgst_amount': 0, 'igst_amount': 0},
      ]);
      expect(s.cgst + s.sgst + s.igst, 0);
    });

    test('taxable total sums the after-discount taxable values', () {
      expect(
        gstTaxableTotal([
          {'taxable_value': 84.75},
          {'taxable_value': 100},
        ]),
        184.75,
      );
    });

    test('breakup rows: half rate for CGST/SGST, full rate for IGST', () {
      final rows = gstBreakupRows([
        {'gst_rate': 18, 'tax_amount': 18, 'cgst_amount': 9, 'sgst_amount': 9, 'igst_amount': 0},
        {'gst_rate': 12, 'tax_amount': 12, 'cgst_amount': 0, 'sgst_amount': 0, 'igst_amount': 12},
        {'gst_rate': 0, 'tax_amount': 0},
      ]);
      expect(rows, [
        ('CGST 9%', 9.0),
        ('SGST 9%', 9.0),
        ('IGST 12%', 12.0),
      ]);
    });
  });
}
