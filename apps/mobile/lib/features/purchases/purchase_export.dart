import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../core/formatters.dart';

/// Payment status as the app shows it: the DB's 'unpaid' is "Credit".
String purchaseStatusLabel(String? s) => switch (s) {
  'paid' => 'Paid',
  'partial' => 'Partial',
  'unpaid' => 'Credit',
  _ => s ?? '',
};

/// The Purchases download: one sheet with a row per purchase (and a total
/// row), one with a row per item bought — what an accountant or the owner
/// needs to check supplier bills in Excel.
Uint8List buildPurchasesWorkbook({
  required List<Map<String, dynamic>> purchases,
  required String businessName,
  required String period,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  CellValue t(Object? v) => TextCellValue('${v ?? ''}');
  CellValue n(Object? v) => DoubleCellValue(toDouble(v));

  final list = excel['Purchases'];
  list.appendRow([t(businessName), t('Purchases'), t(period)]);
  list.appendRow([t('')]); // an empty list adds no row
  list.appendRow([
    for (final h in const [
      'Purchase #',
      'Supplier bill no',
      'Supplier',
      'Date',
      'Subtotal',
      'Discount',
      'GST',
      'Extra charges',
      'Total',
      'Paid',
      'Due',
      'Status',
      'Payment mode',
      'Note',
    ])
      t(h),
  ]);
  double total = 0, paid = 0, due = 0;
  for (final p in purchases) {
    total += toDouble(p['total']);
    paid += toDouble(p['paid_amount']);
    due += toDouble(p['due_amount']);
    list.appendRow([
      t(p['purchase_no']),
      t(p['bill_no']),
      t(p['supplier_name']),
      t(dateStr(p['purchase_date'])),
      n(p['subtotal']),
      n(p['discount_amount']),
      n(p['tax_amount']),
      n(p['extra_charges']),
      n(p['total']),
      n(p['paid_amount']),
      n(p['due_amount']),
      t(purchaseStatusLabel(p['payment_status'] as String?)),
      t(p['payment_mode']),
      t(p['notes']),
    ]);
  }
  list.appendRow([
    t('Total (${purchases.length})'),
    t(''),
    t(''),
    t(''),
    t(''),
    t(''),
    t(''),
    t(''),
    n(total),
    n(paid),
    n(due),
  ]);

  final items = excel['Items'];
  items.appendRow([
    for (final h in const [
      'Purchase #',
      'Date',
      'Supplier',
      'Product',
      'Qty',
      'Rate',
      'Discount',
      'GST %',
      'GST',
      'Amount',
    ])
      t(h),
  ]);
  for (final p in purchases) {
    for (final it in List<Map<String, dynamic>>.from(
      p['purchase_items'] as List? ?? const [],
    )) {
      items.appendRow([
        t(p['purchase_no']),
        t(dateStr(p['purchase_date'])),
        t(p['supplier_name']),
        t(it['product_name']),
        n(it['quantity']),
        n(it['unit_price']),
        n(it['discount_amount']),
        n(it['gst_rate']),
        n(it['tax_amount']),
        n(it['line_total']),
      ]);
    }
  }

  excel.setDefaultSheet('Purchases');
  if (defaultSheet != null && defaultSheet != 'Purchases') {
    excel.delete(defaultSheet);
  }
  return Uint8List.fromList(excel.encode()!);
}
