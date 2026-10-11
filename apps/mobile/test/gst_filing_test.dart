import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/reports/gst_export.dart';
import 'package:softraxa_inventory/features/reports/gst_filing.dart';

GstReturnData sample() => GstReturnData(
  gstr1: {
    'b2b': [
      {
        'gstin': '29aapfu0939f1zr',
        'receiver_name': 'Karnataka Traders',
        'invoice_no': 'INV/26-27/0002',
        'invoice_date': '2026-09-05',
        'invoice_value': 286.0,
        'place_of_supply': '29',
        'inter': true,
        'gst_rate': 18,
        'taxable_value': 200,
        'igst_amount': 36,
        'cgst_amount': 0,
        'sgst_amount': 0,
        'cess_amount': 0,
      },
      {
        'gstin': '29aapfu0939f1zr',
        'invoice_no': 'INV/26-27/0002',
        'invoice_date': '2026-09-05',
        'invoice_value': 286.0,
        'place_of_supply': '29',
        'inter': true,
        'gst_rate': 5,
        'taxable_value': 47.62,
        'igst_amount': 2.38,
        'cgst_amount': 0,
        'sgst_amount': 0,
      },
    ],
    'b2cl': [],
    'b2cs': [
      {
        'type': 'OE',
        'place_of_supply': '27',
        'supply_type': 'INTRA',
        'gst_rate': 18,
        'taxable_value': 50.004,
        'igst_amount': 0,
        'cgst_amount': 4.5,
        'sgst_amount': 4.5,
      },
      {
        'type': 'OE',
        'place_of_supply': '27',
        'supply_type': 'INTRA',
        'gst_rate': 5,
        'taxable_value': 0,
      },
    ],
    'cdnr': [
      {
        'gstin': '29AAPFU0939F1ZR',
        'note_no': 'CN/26-27/00001',
        'note_date': '2026-09-06',
        'note_type': 'C',
        'note_value': 118,
        'place_of_supply': '29',
        'inter': true,
        'gst_rate': 18,
        'taxable_value': 100,
        'igst_amount': 18,
      },
    ],
    'cdnur': [],
    'nil': [
      {
        'supply_type': 'INTRAB2C',
        'nil_amount': 150,
        'exempt_amount': 0,
        'non_gst_amount': 0,
      },
      {
        'supply_type': 'INTRB2B',
        'nil_amount': 0,
        'exempt_amount': 0,
        'non_gst_amount': 0,
      },
    ],
    'hsn': [
      {
        'supply': 'B2C',
        'hsn_code': '1006',
        'description': 'Basmati Rice Premium Long Grain 5kg Bag',
        'uqc': 'KGS',
        'quantity': 3,
        'gst_rate': 0,
        'taxable_value': 150,
      },
      {
        'supply': 'B2B',
        'hsn_code': '998713',
        'description': 'Repair',
        'uqc': 'NA',
        'quantity': 2,
        'gst_rate': 18,
        'taxable_value': 100,
        'cgst_amount': 9,
        'sgst_amount': 9,
      },
      {
        'supply': 'B2C',
        'hsn_code': '',
        'quantity': 1,
        'gst_rate': 18,
        'taxable_value': 10,
      },
    ],
    'docs': [
      {
        'doc_num': 1,
        'series': 'INV/26-27/',
        'from_no': 'INV/26-27/0001',
        'to_no': 'INV/26-27/0009',
        'total': 9,
        'cancelled': 1,
      },
      {
        'doc_num': 1,
        'series': 'CM/26-27/',
        'from_no': 'CM/26-27/0001',
        'to_no': 'CM/26-27/0002',
        'total': 2,
        'cancelled': 0,
      },
      {
        'doc_num': 5,
        'series': 'CN/26-27/',
        'from_no': 'CN/26-27/00001',
        'to_no': 'CN/26-27/00001',
        'total': 1,
        'cancelled': 0,
      },
    ],
  },
  gstr3b: const {},
  purchaseRegister: const [],
);

void main() {
  test('GSTR-1 file in the portal format', () {
    final json = buildGstr1Json(
      sample(),
      gstin: '27aapfu0939f1zv',
      fp: '092026',
    );
    expect(json['gstin'], '27AAPFU0939F1ZV');
    expect(json['fp'], '092026');

    final b2b = json['b2b'] as List;
    expect(b2b, hasLength(1));
    expect(b2b[0]['ctin'], '29AAPFU0939F1ZR');
    final inv = (b2b[0]['inv'] as List).single as Map;
    expect(inv['inum'], 'INV/26-27/0002');
    expect(inv['idt'], '05-09-2026');
    expect(
      (inv['pos'], inv['rchrg'], inv['inv_typ'], inv['val']),
      ('29', 'N', 'R', 286.0),
    );
    final itms = inv['itms'] as List;
    expect(itms.map((i) => i['num']), [1, 2]);
    expect(itms[0]['itm_det'], {
      'txval': 200.0,
      'rt': 18.0,
      'iamt': 36.0,
      'csamt': 0.0,
    });

    // B2C small: intra-state, CGST/SGST, paisa-rounded; the empty row left out.
    expect(json['b2cs'], [
      {
        'sply_ty': 'INTRA',
        'rt': 18.0,
        'typ': 'OE',
        'pos': '27',
        'txval': 50.0,
        'camt': 4.5,
        'samt': 4.5,
        'csamt': 0.0,
      },
    ]);

    final note = ((json['cdnr'] as List).single['nt'] as List).single as Map;
    expect(
      (note['ntty'], note['nt_num'], note['nt_dt'], note['val']),
      ('C', 'CN/26-27/00001', '06-09-2026', 118.0),
    );

    // Table 8: only rows with something in them.
    expect(json['nil'], {
      'inv': [
        {
          'sply_ty': 'INTRAB2C',
          'nil_amt': 150.0,
          'expt_amt': 0.0,
          'ngsup_amt': 0.0,
        },
      ],
    });

    // Table 12, split from May 2025: services NA with no quantity, the
    // description cut to 30, rows without HSN left out.
    final hsn = json['hsn'] as Map;
    expect((hsn['hsn_b2b'] as List).single, {
      'num': 1,
      'hsn_sc': '998713',
      'desc': 'Repair',
      'uqc': 'NA',
      'qty': 0,
      'rt': 18.0,
      'txval': 100.0,
      'iamt': 0.0,
      'camt': 9.0,
      'samt': 9.0,
      'csamt': 0.0,
    });
    final rice = (hsn['hsn_b2c'] as List).single as Map;
    expect(rice['desc'], hasLength(30));
    expect((rice['uqc'], rice['qty']), ('KGS', 3.0));
    expect(hsnRowsWithoutCode(sample()), 1);

    // Table 13: invoices (two series) and credit notes.
    final det = (json['doc_issue'] as Map)['doc_det'] as List;
    expect(det.map((d) => d['doc_num']), [1, 5]);
    expect((det[0]['docs'] as List)[0], {
      'num': 1,
      'from': 'INV/26-27/0001',
      'to': 'INV/26-27/0009',
      'totnum': 9,
      'cancel': 1,
      'net_issue': 8,
    });
    expect(det[0]['docs'], hasLength(2));

    // The file is plain JSON.
    expect(jsonDecode(gstr1JsonText(json)), isA<Map>());
  });

  test('before May 2025 the HSN summary is one list; IFF has B2B only', () {
    final old = buildGstr1Json(sample(), gstin: 'X', fp: '042025');
    expect((old['hsn'] as Map).keys, ['data']);
    final iff = buildGstr1Json(
      sample(),
      gstin: 'X',
      fp: '072026',
      iffOnly: true,
    );
    expect(iff.keys.toSet(), {'gstin', 'fp', 'b2b', 'cdnr'});
  });

  group('GSTR-3B set-off', () {
    test('own credit first, cash for the rest', () {
      final r = gstSetOff(
        const TaxHeads(100, 50, 50),
        const TaxHeads(30, 20, 60),
      );
      // IGST 30 → IGST; CGST 20 → CGST; SGST 60 → SGST 50 + IGST 10.
      expect((r.cash.igst, r.cash.cgst, r.cash.sgst), (60.0, 30.0, 0.0));
      expect(r.carryForward.total, 0);
    });

    test('IGST credit covers CGST and SGST where their credit falls short', () {
      final r = gstSetOff(
        const TaxHeads(0, 100, 100),
        const TaxHeads(150, 80, 0),
      );
      // Shortfalls: CGST 20, SGST 100 → IGST credit 120 there, 30 left goes
      // to CGST before CGST credit (rule 88A), CGST credit 80 → 50 left over.
      expect(r.cash.total, 0);
      expect(r.carryForward.cgst, 30);
      expect(r.used.igst, 150);
    });

    test('CGST credit never pays SGST', () {
      final r = gstSetOff(const TaxHeads(0, 0, 100), const TaxHeads(0, 100, 0));
      expect(r.cash.sgst, 100);
      expect(r.carryForward.cgst, 100);
    });

    test('more credit notes than sales is no tax, not a refund', () {
      final r = gstSetOff(
        const TaxHeads(-50, -10, -10),
        const TaxHeads(5, 5, 5),
      );
      expect(r.cash.total, 0);
      expect(r.carryForward.total, 15);
    });
  });

  group('GSTR-2B', () {
    const twoB = '''
{"chksum":"x","data":{"gstin":"27AAPFU0939F1ZV","rtnprd":"092026","docdata":{
 "b2b":[{"ctin":"21AAECR3780P1Z1","trdnm":"RJS ENTERPRISES","inv":[
   {"inum":"RJSB/2627/8/362","dt":"25-08-2026","val":71040,"itcavl":"Y","items":[{"num":1,"rt":18,"txval":60203.39,"igst":0,"cgst":5418.3,"sgst":5418.3}]},
   {"inum":"RJSB/2627/8/400","dt":"28-08-2026","val":1180,"itcavl":"Y","items":[{"num":1,"rt":18,"txval":1000,"igst":0,"cgst":90,"sgst":90}]},
   {"inum":"RJSB/2627/8/401","dt":"29-08-2026","val":1180,"itcavl":"N","rsn":"P","items":[{"num":1,"rt":18,"txval":1000,"igst":180,"cgst":0,"sgst":0}]}]}],
 "cdnr":[{"ctin":"21AAECR3780P1Z1","trdnm":"RJS ENTERPRISES","nt":[{"ntnum":"CR-1","dt":"30-08-2026","val":118,"typ":"C","itcavl":"Y","items":[{"num":1,"rt":18,"txval":100,"igst":18,"cgst":0,"sgst":0}]}]}]
}}}''';

    test('reads invoices and notes from the portal file', () {
      final r = parseGstr2b(twoB);
      expect((r.gstin, r.period), ('27AAPFU0939F1ZV', '092026'));
      expect(r.docs, hasLength(4));
      final first = r.docs.first;
      expect(
        (first.number, first.date, first.tax),
        ('RJSB/2627/8/362', DateTime(2026, 8, 25), 10836.6),
      );
      expect(r.docs[2].itcAvailable, isFalse);
      expect(r.docs.last.noteType, 'C');
      expect(() => parseGstr2b('{"a":1}'), throwsA(isA<Gstr2bFormatError>()));
    });

    test('matches the purchase register bill by bill', () {
      final docs = parseGstr2b(twoB).docs;
      final register = [
        // Same bill written differently, split over two rates.
        {
          'doc_type': 'Purchase',
          'doc_no': 'PUR-1',
          'supplier_bill_no': 'rjsb-2627-08-0362',
          'supplier_gstin': '21AAECR3780P1Z1',
          'supplier_name': 'RJS',
          'cgst_amount': 5000,
          'sgst_amount': 5000,
          'igst_amount': 0,
        },
        {
          'doc_type': 'Purchase',
          'doc_no': 'PUR-1',
          'supplier_bill_no': 'rjsb-2627-08-0362',
          'supplier_gstin': '21AAECR3780P1Z1',
          'cgst_amount': 418.3,
          'sgst_amount': 418.3,
          'igst_amount': 0,
        },
        // Tax entered wrongly.
        {
          'doc_type': 'Purchase',
          'doc_no': 'PUR-2',
          'supplier_bill_no': 'RJSB/2627/8/400',
          'supplier_gstin': '21AAECR3780P1Z1',
          'cgst_amount': 50,
          'sgst_amount': 50,
        },
        // The supplier hasn't uploaded this one.
        {
          'doc_type': 'Purchase',
          'doc_no': 'PUR-3',
          'supplier_bill_no': 'GT/9',
          'supplier_gstin': '27ABCDE1234F1Z5',
          'cgst_amount': 9,
          'sgst_amount': 9,
        },
        // Unregistered supplier: no credit to match.
        {
          'doc_type': 'Purchase',
          'doc_no': 'PUR-4',
          'supplier_bill_no': '12',
          'supplier_gstin': '',
          'cgst_amount': 0,
        },
      ];
      final rows = matchGstr2b(docs, register);
      ItcMatch status(String bill) =>
          rows.firstWhere((r) => r.billNo == bill).status;
      expect(status('RJSB/2627/8/362'), ItcMatch.matched);
      expect(status('RJSB/2627/8/400'), ItcMatch.differs);
      expect(status('RJSB/2627/8/401'), ItcMatch.blocked);
      expect(status('GT/9'), ItcMatch.missingIn2b);
      expect(rows, hasLength(4));
      expect(
        normalizeBillNo('RJSB/2627/08/0362'),
        normalizeBillNo('rjsb 2627 8 362'),
      );
    });
  });
}
