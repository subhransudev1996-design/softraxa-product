import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/reports/gst_export.dart';

/// Shaped like get_gstr1 / get_gstr3b / get_purchase_register (0040) for the
/// staging example in supabase/tests/r1_gst_returns.sql.
GstReturnData _sample() => GstReturnData(
  gstr1: {
    'b2b': [
      {
        'gstin': '29AAPFU0939F1ZR', 'receiver_name': 'Karnataka Traders',
        'invoice_no': 'INV-00001', 'invoice_date': '2026-09-05',
        'invoice_value': 236, 'place_of_supply': '29', 'reverse_charge': 'N',
        'invoice_type': 'Regular B2B', 'gst_rate': 18, 'taxable_value': 200,
        'igst_amount': 36, 'cgst_amount': 0, 'sgst_amount': 0, 'cess_amount': 0,
      },
    ],
    'b2cl': <Map<String, dynamic>>[],
    'b2cs': [
      {
        'type': 'OE', 'place_of_supply': '27', 'gst_rate': 18,
        'taxable_value': 84.75, 'igst_amount': 0, 'cgst_amount': 7.63,
        'sgst_amount': 7.62, 'cess_amount': 0,
      },
    ],
    'cdnr': [
      {
        'gstin': '29AAPFU0939F1ZR', 'receiver_name': 'Karnataka Traders',
        'note_no': 'CN/26-27/00001', 'note_date': '2026-09-06', 'note_type': 'C',
        'place_of_supply': '29', 'reverse_charge': 'N',
        'note_supply_type': 'Regular B2B', 'note_value': 118,
        'invoice_no': 'INV-00001', 'invoice_date': '2026-09-05', 'gst_rate': 18,
        'taxable_value': 100, 'igst_amount': 18, 'cgst_amount': 0,
        'sgst_amount': 0, 'cess_amount': 0,
      },
    ],
    'cdnur': <Map<String, dynamic>>[],
    'hsn': [
      {
        'supply': 'B2B', 'hsn_code': '8517', 'description': 'Phone', 'uqc': 'PCS',
        'quantity': 1, 'total_value': 118, 'gst_rate': 18, 'taxable_value': 100,
        'igst_amount': 18, 'cgst_amount': 0, 'sgst_amount': 0, 'cess_amount': 0,
      },
      {
        'supply': 'B2C', 'hsn_code': '8517', 'description': 'Phone', 'uqc': 'PCS',
        'quantity': 1, 'total_value': 100, 'gst_rate': 18, 'taxable_value': 84.75,
        'igst_amount': 0, 'cgst_amount': 7.63, 'sgst_amount': 7.62, 'cess_amount': 0,
      },
    ],
    'docs': [
      {
        'nature': 'Invoices for outward supply', 'from_no': 'INV-00001',
        'to_no': 'INV-00002', 'total': 2, 'cancelled': 0,
      },
      {'nature': 'Credit notes', 'from_no': null, 'to_no': null, 'total': 0, 'cancelled': 0},
    ],
    'warnings': {'lines_without_hsn': 0, 'invalid_customer_gstins': 1, 'invoices_without_state': 0},
  },
  gstr3b: {
    'outward_taxable': {
      'taxable_value': 184.75, 'igst_amount': 18, 'cgst_amount': 7.63, 'sgst_amount': 7.62,
    },
    'outward_nil_exempt': {'taxable_value': 0},
    'inter_state_unregistered': <Map<String, dynamic>>[],
    'itc_available': {'igst_amount': 5, 'cgst_amount': 10, 'sgst_amount': 10},
    'tax_on_unregistered_purchases': 0,
  },
  purchaseRegister: [
    {
      'doc_type': 'Purchase', 'doc_date': '2026-09-02', 'doc_no': 'PUR-00001',
      'supplier_bill_no': 'S-9', 'supplier_name': 'Distributor',
      'supplier_gstin': '27AAPFU0939F1ZV', 'supplier_state': '27', 'gst_rate': 18,
      'taxable_value': 111.11, 'igst_amount': 0, 'cgst_amount': 10,
      'sgst_amount': 10, 'bill_total': 131.11,
    },
  ],
);

void main() {
  group('GstReturnData', () {
    test('counts documents, not per-rate rows', () {
      final d = _sample();
      expect(d.documentCount('b2b'), 1);
      expect(d.documentCount('cdnr'), 1);
      expect(d.documentCount('b2cl'), 0);
    });

    test('net payable is output minus input tax credit per head', () {
      final net = _sample().netPayable;
      expect(net.igst, 13);
      expect(net.cgst, closeTo(-2.37, 0.001));
      expect(net.sgst, closeTo(-2.38, 0.001));
    });

    test('warnings are counted', () {
      expect(_sample().warningCount, 1);
    });
  });

  group('portal formats', () {
    test('dates as dd-MMM-yyyy', () {
      expect(gstDate('2026-09-05'), '05-Sep-2026');
      expect(gstDate(null), '');
    });

    test('place of supply as code-State', () {
      expect(gstPos('29'), '29-Karnataka');
      expect(gstPos(''), '');
    });
  });

  test('workbook has every section with the portal headers', () {
    final bytes = buildGstWorkbook(
      data: _sample(),
      businessName: 'Test Shop',
      gstin: '27AAPFU0939F1ZV',
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 30),
    );
    final book = Excel.decodeBytes(bytes);
    expect(
      book.tables.keys,
      containsAll([
        'Summary', 'b2b', 'b2cl', 'b2cs', 'cdnr', 'cdnur', 'hsn(b2b)',
        'hsn(b2c)', 'docs', 'GSTR-3B', 'Purchase register',
      ]),
    );
    expect(book.tables.keys, isNot(contains('Sheet1')));

    final b2b = book.tables['b2b']!;
    expect(b2b.rows.first.first?.value.toString(), 'GSTIN/UIN of Recipient');
    expect(b2b.rows[1][5]?.value.toString(), '29-Karnataka');
    expect(b2b.rows[1][3]?.value.toString(), '05-Sep-2026');

    // Only document series that were issued are listed.
    expect(book.tables['docs']!.rows.length, 2);
  });
}
