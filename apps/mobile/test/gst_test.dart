import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/gst.dart';

void main() {
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
