import 'package:flutter_test/flutter_test.dart';
import 'package:dukania/features/invoices/bill_layout.dart';

void main() {
  test('amount in words, Indian system', () {
    expect(
      rupeesInWords(3586),
      'Rupees Three Thousand Five Hundred Eighty-Six Only',
    );
    expect(rupeesInWords(0), 'Rupees Zero Only');
    expect(rupeesInWords(100), 'Rupees One Hundred Only');
    expect(rupeesInWords(125000), 'Rupees One Lakh Twenty-Five Thousand Only');
    expect(
      rupeesInWords(23456789.5),
      'Rupees Two Crore Thirty-Four Lakh Fifty-Six Thousand Seven Hundred '
      'Eighty-Nine and Fifty Paise Only',
    );
    expect(rupeesInWords(19.05), 'Rupees Nineteen and Five Paise Only');
  });

  test('terms: one per line, blank lines dropped', () {
    expect(billTerms('  Exchange in 7 days \n\n No cash refund\n'), [
      'Exchange in 7 days',
      'No cash refund',
    ]);
    expect(billTerms(null), isEmpty);
  });

  // The photographed bill: a saree at 3,490 less 349 and a nighty at 350
  // less 35, both 5% GST, intra-state.
  Map<String, dynamic> line(
    String name,
    double rate,
    double disc,
    double total, {
    String sku = '',
    String size = '',
  }) => {
    'product_name': name,
    'variant_name': size,
    'products': {'sku': sku},
    'quantity': 1,
    'unit_name': 'pcs',
    'unit_price': rate / 1.05,
    'discount_amount': disc / 1.05,
    'gst_rate': 5,
    'line_total': total,
    'taxable_value': total / 1.05,
    'cgst_amount': total / 1.05 * 0.025,
    'sgst_amount': total / 1.05 * 0.025,
    'igst_amount': 0,
  };

  final invoice = {
    'invoice_type': 'gst',
    'total': 3456.0,
    'discount_amount': 0,
    'round_off': 0,
    'paid_amount': 3456.0,
    'payment_mode': 'upi',
    'due_amount': 0,
    'invoice_payments': <Map<String, dynamic>>[],
  };

  test('lines, totals and GST summary', () {
    final bill = BillLayout(
      business: {'bill_show_sku': true, 'bill_footer': ' Visit again '},
      invoice: invoice,
      items: [
        line('Handloom Saree', 3490, 349, 3141, sku: 'MAFB061807'),
        line('Cotton Nighty', 350, 35, 315, size: 'Free size'),
      ],
    );
    final saree = bill.lines.first;
    expect(saree.sku, 'MAFB061807');
    expect(saree.rate, 3490);
    expect(saree.amount, 3490);
    expect(saree.discount, 349);
    expect(saree.total, 3141);
    expect(bill.lines.last.size, 'Free size');
    expect(bill.totalQty, 2);
    expect(bill.totalAmount, 3840);
    expect(bill.totalLineDiscount, 384);
    expect(bill.linesTotal, 3456);
    expect(bill.payments, [('UPI', 3456.0)]);
    expect(bill.footer, [(text: 'Visit again', bold: false)]);

    final gst = bill.gstSummary.single;
    expect(gst.rate, 5);
    expect(gst.taxable, closeTo(3291.43, 0.01));
    expect(gst.cgst, closeTo(82.29, 0.01));
    expect(gst.totalTax, closeTo(164.57, 0.01));
    expect(bill.gstIsInterState, isFalse);
  });

  test(
    'stock no. only when the shop prints it; no GST summary off GST bills',
    () {
      final bill = BillLayout(
        business: const {},
        invoice: {...invoice, 'invoice_type': 'non_gst'},
        items: [line('Saree', 100, 0, 100, sku: 'S1')],
      );
      expect(bill.lines.single.sku, '');
      expect(bill.gstSummary, isEmpty);
    },
  );

  test('bottom note: one line each, *starred* lines bold, blanks dropped', () {
    expect(
      billNoteLines(
        '*BUSINESS HOURS - 9 AM TO 10 PM*\n\n  Last Tuesday closed \n**\n*Exchange: 12 noon to 4 pm*',
      ),
      [
        (text: 'BUSINESS HOURS - 9 AM TO 10 PM', bold: true),
        (text: 'Last Tuesday closed', bold: false),
        (text: '**', bold: false),
        (text: 'Exchange: 12 noon to 4 pm', bold: true),
      ],
    );
    expect(billNoteLines(null), isEmpty);
  });

  // A bookshop bill (0094): Penguin book MRP 250 with its 10% regular
  // discount and the Privilege card's 10% on what is left; a second item
  // the card doesn't cover; a scratch coupon of 20.
  Map<String, dynamic> bookBill({bool withType = true, double card = 22.5}) => {
    'invoice_type': 'non_gst',
    'total': 282.0,
    'discount_amount': 20,
    'offer_amount': 20,
    'offer_name': 'Scratch & Win',
    'offer_code': 'SC-0001',
    'round_off': -0.5,
    'paid_amount': 282.0,
    'payment_mode': 'cash',
    'due_amount': 0,
    'invoice_payments': <Map<String, dynamic>>[],
    'discount_card_no': '2017-1234-1234-0007',
    'discount_card_type': 'Privilege',
    'discount_card_pct': 10,
    'discount_card_amount': card,
    if (withType)
      'discount_cards': {
        'discount_card_types': {
          'applies_to': 'only',
          'category_ids': ['books'],
        },
      },
  };
  final bookItems = [
    {
      'product_id': 'p1',
      'product_name': 'The Guide',
      'products': {
        'category_id': 'books',
        'publisher': 'Penguin',
        'author': 'R. K. Narayan',
      },
      'quantity': 1,
      'unit_name': 'pcs',
      'unit_price': 250,
      'discount_amount': 47.5,
      'gst_rate': 0,
      'line_total': 202.5,
      'mrp': 250,
    },
    {
      'product_id': 'p2',
      'product_name': 'Notebook',
      'products': {'category_id': 'stationery'},
      'quantity': 1,
      'unit_name': 'pcs',
      'unit_price': 100,
      'discount_amount': 0,
      'gst_rate': 0,
      'line_total': 100,
      'mrp': 120,
    },
  ];

  test('book bill: card discount on its own row, coupon, you saved', () {
    final bill = BillLayout(
      business: const {},
      invoice: bookBill(),
      items: bookItems,
    );
    expect(bill.cardSplit, isTrue);
    expect(bill.lines.first.discount, 25);
    expect(bill.lines.first.cardDiscount, 22.5);
    expect(bill.lines.first.total, 225);
    expect(bill.lines.first.publisher, 'Penguin');
    expect(bill.lines.first.author, 'R. K. Narayan');
    expect(bill.lines.last.cardDiscount, 0);
    expect(bill.anyPublisher, isTrue);
    expect(bill.linesTotal, 325);
    expect(bill.adjustments, [
      ('Less card discount (Privilege 10%)', -22.5),
      ('Less coupon SC-0001', -20.0),
      ('Round off', -0.5),
    ]);
    // 325 - 22.5 - 20 - 0.5 = the net amount.
    expect(
      bill.linesTotal + bill.adjustments.fold(0.0, (s, a) => s + a.$2),
      bill.netAmount,
    );
    expect(bill.cardTopLine, 'Privilege card: 2017-1234-1234-0007');
    // MRP 250 + 120 against 282 paid.
    expect(bill.youSaved, 88);
  });

  test('book bill without the card type: split only when it adds up', () {
    final ok = BillLayout(
      business: const {},
      invoice: bookBill(withType: false),
      items: [bookItems.first],
    );
    expect(ok.cardSplit, isTrue);
    final off = BillLayout(
      business: const {},
      invoice: bookBill(withType: false, card: 50),
      items: bookItems,
    );
    expect(off.cardSplit, isFalse);
    expect(off.lines.first.discount, 47.5);
    expect(off.adjustments.first.$1, 'Less coupon SC-0001');
  });
}
