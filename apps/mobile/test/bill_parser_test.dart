import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/purchases/bill_reader/bill_parser.dart';

/// Lays out a bill as a PDF would: each entry is a row of (x, text) cells
/// at 10 pt, words split on spaces 2.5 pt apart (a space), cells where
/// they're put.
List<BillWord> layout(
  List<List<(double, String)>> rows, {
  int page = 0,
  double top = 0,
}) {
  final out = <BillWord>[];
  for (var r = 0; r < rows.length; r++) {
    final y = top + r * 14.0;
    for (final (x0, text) in rows[r]) {
      var x = x0;
      for (final w in text.split(' ')) {
        if (w.isEmpty) continue;
        final width = w.length * 5.0;
        out.add(BillWord(w, x, y, x + width, y + 10, page: page));
        x += width + 2.5;
      }
    }
  }
  return out;
}

void main() {
  tallyExcelBillTest();
  test('numbers as bills print them', () {
    expect(billNumber('1,23,456.50'), 123456.5);
    expect(billNumber('₹ 550.00'), 550);
    expect(billNumber('Rs. 12.5'), 12.5);
    expect(billNumber('(10.00)'), -10);
    expect(billNumber('Pcs'), isNull);
    final q = billQty('10 Pcs')!;
    expect((q.qty, q.unit), (10.0, 'Pcs'));
    final s = billQty('10+2')!;
    expect((s.qty, s.free), (10.0, 2.0));
    expect(billQty('12.000')!.qty, 12);
  });

  test('header words name their columns', () {
    expect(columnFor('Description of Goods'), BillCol.name);
    expect(columnFor('HSN/SAC'), BillCol.hsn);
    expect(columnFor('Disc.%'), BillCol.disc);
    expect(columnFor('Amount(₹)'), BillCol.amount);
    expect(columnFor('Price/ Unit'), BillCol.rate);
    expect(columnFor('CGST Rate'), BillCol.gstPart);
    expect(columnFor('CGST Amount'), BillCol.taxAmt);
    expect(columnFor('Taxable Value'), BillCol.taxable);
    expect(columnFor('Batch'), BillCol.ignore);
  });

  test('a Tally-style bill: boxed invoice no., qty with unit, tax rows', () {
    final words = layout([
      [(200, 'Tax Invoice')],
      [(20, 'GUPTA TRADERS')],
      [
        (20, 'GSTIN/UIN: 27ABCDE1234F1Z5'),
        (300, 'Invoice No.'),
        (420, 'Dated'),
      ],
      [(300, 'GT/245'), (420, '8-Oct-26')],
      [(20, 'Buyer: Sharma General Store GSTIN 27AAAAA0000A1Z5')],
      [
        (10, 'Sl No.'),
        (50, 'Description of Goods'),
        (200, 'HSN/SAC'),
        (260, 'Quantity'),
        (330, 'Rate'),
        (380, 'per'),
        (420, 'Disc. %'),
        (480, 'Amount'),
      ],
      [
        (10, '1'),
        (50, 'AMUL GHEE 1LTR TIN'),
        (200, '0405'),
        (260, '10 Pcs'),
        (330, '550.00'),
        (380, 'Pcs'),
        (480, '5,500.00'),
      ],
      [
        (10, '2'),
        (50, 'TATA SALT 1KG'),
        (200, '2501'),
        (260, '50 Pcs'),
        (330, '24.00'),
        (380, 'Pcs'),
        (420, '5'),
        (480, '1,140.00'),
      ],
      [(50, 'Output CGST'), (330, '9'), (380, '%'), (480, '597.60')],
      [(50, 'Output SGST'), (330, '9'), (380, '%'), (480, '597.60')],
      [(50, 'Total'), (260, '60 Pcs'), (480, '₹ 7,835.20')],
    ]);
    final bill = parseBill(words, ownGstin: '27AAAAA0000A1Z5');
    expect(bill.foundHeader, isTrue);
    expect(bill.billNo, 'GT/245');
    expect(bill.date, DateTime(2026, 10, 8));
    expect(bill.gstins, ['27ABCDE1234F1Z5']);
    expect(bill.supplierName, 'GUPTA TRADERS');
    expect(bill.total, 7835.20);
    expect(bill.lines, hasLength(2));
    final ghee = bill.lines[0];
    expect(ghee.name, 'AMUL GHEE 1LTR TIN');
    expect(ghee.hsn, '0405');
    expect((ghee.qty, ghee.unit, ghee.rate), (10.0, 'Pcs', 550.0));
    expect(ghee.value, 5500);
    expect(ghee.agrees, isTrue);
    final salt = bill.lines[1];
    expect(salt.discPct, 5);
    expect(salt.value, closeTo(1140, 0.01));
    expect(salt.agrees, isTrue);
    // No GST column, but 18% takes the lines to the bill's total.
    expect(salt.gstRate, 18);
  });

  test(
    'a pharma-style bill: free qty, batch, MRP, GST % and amount with tax',
    () {
      final words = layout([
        [(20, 'MEDI DISTRIBUTORS')],
        [(20, 'Bill No: MD-1029'), (300, 'Date: 05/10/2026')],
        [
          (10, 'Qty'),
          (40, 'Free'),
          (70, 'Product'),
          (200, 'Batch'),
          (250, 'Exp'),
          (290, 'MRP'),
          (330, 'Rate'),
          (380, 'Dis%'),
          (420, 'GST%'),
          (470, 'Amount'),
        ],
        [
          (10, '10'),
          (40, '2'),
          (70, 'DOLO 650 TAB'),
          (200, 'B123'),
          (250, '12/27'),
          (290, '33.60'),
          (330, '24.00'),
          (380, '10'),
          (420, '12'),
          (470, '241.92'),
        ],
        [(70, 'Grand Total'), (470, '241.92')],
      ]);
      final bill = parseBill(words);
      expect(bill.billNo, 'MD-1029');
      expect(bill.date, DateTime(2026, 10, 5));
      final l = bill.lines.single;
      expect(l.name, 'DOLO 650 TAB');
      expect(
        (l.qty, l.free, l.mrp, l.gstRate, l.discPct),
        (10.0, 2.0, 33.6, 12.0, 10.0),
      );
      // 10 × 24 less 10% = 216, + 12% GST = 241.92: the amount includes GST.
      expect(l.value, closeTo(216, 0.01));
      expect(l.agrees, isTrue);
      expect(l.stockQty, 12);
      expect(l.unitCost, closeTo(18, 0.01));
    },
  );

  test('two-level GST header (CGST over Rate | Amount) and a wrapped name', () {
    final words = layout([
      [(20, 'SUPER WHOLESALE')],
      [(20, 'Invoice No: SW/88 Date: 2026-10-01')],
      [
        (10, '#'),
        (40, 'Item'),
        (200, 'Qty'),
        (240, 'Rate'),
        (290, 'Taxable'),
        (350, 'CGST'),
        (430, 'SGST'),
        (510, 'Total'),
      ],
      [
        (290, 'Value'),
        (340, 'Rate'),
        (380, 'Amount'),
        (420, 'Rate'),
        (460, 'Amount'),
      ],
      [
        (10, '1'),
        (40, 'Surf Excel Easy Wash'),
        (200, '20'),
        (240, '95.00'),
        (290, '1900.00'),
        (340, '9%'),
        (380, '171.00'),
        (420, '9%'),
        (460, '171.00'),
        (510, '2242.00'),
      ],
      [(40, 'Detergent 1kg')],
      [
        (10, '2'),
        (40, 'Vim Bar 300g'),
        (200, '30'),
        (240, '20.00'),
        (290, '600.00'),
        (340, '2.5%'),
        (380, '15.00'),
        (420, '2.5%'),
        (460, '15.00'),
        (510, '630.00'),
      ],
      [(40, 'Total'), (510, '2872.00')],
    ]);
    final bill = parseBill(words);
    expect(bill.lines, hasLength(2));
    expect(bill.lines[0].name, 'Surf Excel Easy Wash Detergent 1kg');
    expect(bill.lines[0].gstRate, 18);
    expect(bill.lines[0].value, 1900);
    expect(bill.lines[0].agrees, isTrue);
    expect(bill.lines[1].gstRate, 5);
    expect(bill.total, 2872);
    expect(bill.date, DateTime(2026, 10, 1));
  });

  test('a second page with no header goes on in the same columns', () {
    final page1 = layout([
      [(20, 'GUPTA TRADERS')],
      [
        (10, 'S.No'),
        (40, 'Particulars'),
        (200, 'Qty'),
        (250, 'Rate'),
        (300, 'Amount'),
      ],
      [
        (10, '1'),
        (40, 'Parle G 250g'),
        (200, '24'),
        (250, '20.00'),
        (300, '480.00'),
      ],
    ]);
    final page2 = layout([
      [
        (10, '2'),
        (40, 'Good Day 200g'),
        (200, '12'),
        (250, '30.00'),
        (300, '360.00'),
      ],
      [(40, 'Grand Total'), (300, '840.00')],
    ], page: 1);
    final bill = parseBill([...page1, ...page2]);
    expect(bill.lines.map((l) => l.name), ['Parle G 250g', 'Good Day 200g']);
    expect(bill.total, 840);
  });

  test("a line whose numbers don't agree is marked for checking", () {
    final words = layout([
      [(10, 'Description'), (200, 'Qty'), (250, 'Rate'), (300, 'Amount')],
      [(10, 'Maggi 70g'), (200, '10'), (250, '14.00'), (300, '150.00')],
    ]);
    final l = parseBill(words).lines.single;
    expect(l.agrees, isFalse);
    expect(l.value, 150);
  });

  test('no known header: rows whose qty × rate = amount', () {
    final words = layout([
      [(20, 'RAJ AGENCIES')],
      [
        (10, '1'),
        (30, 'Colgate 100g'),
        (200, '12'),
        (250, '45.00'),
        (300, '540.00'),
      ],
      [
        (10, '2'),
        (30, 'Dettol Soap'),
        (200, '6'),
        (250, '38.00'),
        (290, '5'),
        (300, '216.60'),
      ],
      [(30, 'Phone 98765 43210 total due 12 pcs')],
    ]);
    final bill = parseBill(words);
    expect(bill.foundHeader, isFalse);
    expect(bill.lines.map((l) => l.name), ['Colgate 100g', 'Dettol Soap']);
    expect(bill.lines[1].discPct, 5);
  });

  test('a sheet (Excel/CSV) reads like a PDF', () {
    final words = sheetWords([
      ['Item Name', 'HSN', 'Qty', 'Unit', 'Rate', 'GST %', 'Amount'],
      ['Fortune Oil 1L', '1512', '12', 'Pcs', '150', '5', '1890'],
      ['Aashirvaad Atta 5kg', '1101', '5', 'Bag', '260', '0', '1300'],
    ]);
    final bill = parseBill(words);
    expect(bill.lines, hasLength(2));
    expect(bill.lines[0].value, 1800); // 1890 includes 5% GST
    expect(bill.lines[0].agrees, isTrue);
    expect(bill.lines[1].unit, 'Bag');
    expect(bill.lines[1].value, 1300);
  });

  test("the shop's own column choice wins", () {
    final words = sheetWords([
      ['Item', 'Qty', 'Value', 'Net'],
      ['Lux Soap', '10', '30', '300'],
    ]);
    final plain = parseBill(words);
    // "Value" and "Net"… "Value" reads as the amount.
    expect(plain.columns.map((c) => c.role), [
      BillCol.name,
      BillCol.qty,
      BillCol.amount,
      BillCol.ignore,
    ]);
    final fixed = parseBill(
      words,
      overrides: {'value': BillCol.rate, 'net': BillCol.amount},
    );
    final l = fixed.lines.single;
    expect((l.rate, l.amount, l.agrees), (30.0, 300.0, true));
  });
}

/// A Tally bill turned from PDF into Excel: a sheet per page, the bill
/// printed in copies, IMEIs under each phone, GST only in the tax rows, and
/// a tax summary with a "Total" of its own. (Made-up names and numbers.)
void tallyExcelBillTest() {
  test('a Tally bill saved as Excel: pages, copies, IMEIs, implied GST', () {
    List<List<String>> top(String copy) => [
      ['TAX INVOICE ($copy)\nIRN : abc\nAck Date : 25-Aug-26', 'e-Invoice'],
    ];
    final page1 = [
      [
        'Demo Mobiles Pvt. Ltd - (2024-26)\nPlot No- 1',
        '',
        '',
        '',
        '',
        '',
        'Invoice No.\nDM/2627/8/77',
        '',
        'e-Way Bill No.\n861700000000',
        '',
        'Dated\n25-Aug-26',
      ],
      ['GSTIN/UIN: 21AAAAA1111A1Z1'],
      ['Buyer (Bill to)'],
      ['GSTIN/UIN', '', ': 21BBBBB2222B1Z2'],
      [
        'Sl\nNo.',
        'Description of Goods',
        '',
        'HSN/SAC',
        'Quantity',
        '',
        '',
        'Rate',
        '',
        'per',
        'Disc. %',
        'Amount',
      ],
      [
        '1',
        'Demo Phone 8GB+256GB Black',
        '',
        '85171300',
        '1 Pcs',
        '',
        '',
        '31728.81',
        '',
        'Pcs',
        '',
        '31728.81',
      ],
      ['', '350846500000011'],
      [
        '2',
        'Demo Phone 8GB+128GB White',
        '',
        '85171300',
        '1 Pcs',
        '',
        '',
        '28474.58',
        '',
        'Pcs',
        '',
        '28474.58',
      ],
      ['', '350846500000022'],
      ['', '', '', '', '', '', '', '', '', '', '', '60203.39'],
      ['', 'CGST', '', '', '', '', '', '', '', '', '', '5418.3'],
      ['', 'SGST', '', '', '', '', '', '', '', '', '', '5418.3'],
      ['continued to page number  2'],
    ];
    final page2 = [
      [
        'Sl\nNo.',
        'Description of Goods',
        '',
        '',
        '',
        'HSN/SAC',
        '',
        'Quantity',
        '',
        '',
        '',
        '',
        'Rate',
        '',
        'per',
        'Disc. %',
        '',
        'Amount',
      ],
      [
        '',
        'Round Off',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '0.01',
      ],
      [
        '',
        'Total',
        '',
        '',
        '',
        '',
        '',
        '2 Pcs',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '71040',
      ],
      [
        'HSN/SAC',
        '',
        '',
        'Taxable\nValue',
        '',
        '',
        'CGST',
        '',
        '',
        '',
        '',
        '',
        '',
        'SGST/UTGST',
        '',
        '',
        '',
        '',
        'Total\nTax Amount',
      ],
      [
        'Total',
        '',
        '',
        '60203.39',
        '',
        '',
        '',
        '',
        '',
        '',
        '5418.3',
        '',
        '',
        '',
        '',
        '5418.3',
        '',
        '',
        '10836.6',
      ],
    ];
    final sheets = [
      for (final copy in [
        'ORIGINAL FOR RECIPIENT',
        'DUPLICATE FOR TRANSPORTER',
        'TRIPLICATE FOR SUPPLIER',
      ]) ...[top(copy), page1, page2],
    ];
    final words = [
      for (final (i, s) in sheets.indexed) ...sheetWords(s, page: i),
    ];
    final bill = parseBill(words, ownGstin: '21BBBBB2222B1Z2');
    expect(bill.lines.map((l) => l.name), [
      'Demo Phone 8GB+256GB Black',
      'Demo Phone 8GB+128GB White',
    ]);
    expect(bill.lines.map((l) => l.serials), [
      ['350846500000011'],
      ['350846500000022'],
    ]);
    expect(bill.lines.map((l) => l.value), [31728.81, 28474.58]);
    expect(bill.lines.every((l) => l.agrees), isTrue);
    expect(bill.lines.map((l) => l.gstRate), [18, 18]);
    expect(bill.billNo, 'DM/2627/8/77');
    expect(bill.date, DateTime(2026, 8, 25));
    expect(bill.gstins.first, '21AAAAA1111A1Z1');
    expect(bill.supplierName, 'Demo Mobiles Pvt. Ltd');
    expect(bill.total, 71040);
  });
}
