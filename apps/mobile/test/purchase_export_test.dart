import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/purchases/purchase_export.dart';

void main() {
  final purchases = [
    {
      'purchase_no': 'PUR-00002',
      'bill_no': 'SW-118',
      'supplier_name': 'Sharma Wholesale',
      'purchase_date': '2026-10-05',
      'subtotal': 1944,
      'discount_amount': 0,
      'tax_amount': 0,
      'extra_charges': 0,
      'total': 1944,
      'paid_amount': 0,
      'due_amount': 1944,
      'payment_status': 'unpaid',
      'payment_mode': 'credit',
      'notes': '',
      'purchase_items': [
        {'product_name': 'Amul Butter 100 g', 'quantity': 24, 'unit_price': 52, 'discount_amount': 0, 'gst_rate': 0, 'tax_amount': 0, 'line_total': 1248},
        {'product_name': 'Amul Paneer 200 g', 'quantity': 12, 'unit_price': 58, 'discount_amount': 0, 'gst_rate': 0, 'tax_amount': 0, 'line_total': 696},
      ],
    },
    {
      'purchase_no': 'PUR-00001',
      'bill_no': '',
      'supplier_name': 'Rakesh',
      'purchase_date': '2026-10-02',
      'subtotal': 500,
      'total': 500,
      'paid_amount': 300,
      'due_amount': 200,
      'payment_status': 'partial',
      'payment_mode': 'cash',
      'purchase_items': [
        {'product_name': 'Sugar (loose)', 'quantity': 12.5, 'unit_price': 40, 'line_total': 500},
      ],
    },
  ];

  Excel open() => Excel.decodeBytes(
    buildPurchasesWorkbook(purchases: purchases, businessName: 'pinku', period: 'This month'),
  );
  String cell(Sheet s, int row, int col) =>
      s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value.toString();

  test('one row per purchase, credit labelled as Credit, and a total row', () {
    final s = open()['Purchases'];
    expect(cell(s, 0, 0), 'pinku');
    expect(cell(s, 2, 0), 'Purchase #');
    expect(cell(s, 3, 0), 'PUR-00002');
    expect(cell(s, 3, 2), 'Sharma Wholesale');
    expect(cell(s, 3, 11), 'Credit');
    expect(cell(s, 4, 11), 'Partial');
    expect(cell(s, 5, 0), 'Total (2)');
    expect(double.parse(cell(s, 5, 8)), 2444);
    expect(double.parse(cell(s, 5, 9)), 300);
    expect(double.parse(cell(s, 5, 10)), 2144);
  });

  test('items sheet lists every item with its purchase', () {
    final x = open();
    final s = x['Items'];
    expect(s.maxRows, 4);
    expect(cell(s, 1, 3), 'Amul Butter 100 g');
    expect(cell(s, 3, 0), 'PUR-00001');
    expect(double.parse(cell(s, 3, 4)), 12.5);
    expect(x.tables.keys, isNot(contains('Sheet1')));
  });
}
