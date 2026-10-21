import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:softraxa_inventory/features/invoices/invoice_pdf.dart';

Map<String, dynamic> _line(int i) => {
  'product_name': 'Handloom Saree design $i with a long descriptive name',
  'variant_name': 'Free size',
  'products': {'sku': 'MAFB0618$i'},
  'hsn_code': '5208',
  'quantity': 1,
  'unit_name': 'pcs',
  'unit_price': 3490 / 1.05,
  'discount_amount': 349 / 1.05,
  'gst_rate': 5,
  'line_total': 3141.0,
  'taxable_value': 3141 / 1.05,
  'cgst_amount': 3141 / 1.05 * 0.025,
  'sgst_amount': 3141 / 1.05 * 0.025,
  'igst_amount': 0,
};

InvoicePdf samplePdf(int lines) => InvoicePdf(
  business: {
    'name': 'Sharma Saree Centre',
    'address': 'Main Road, Puri',
    'phone': '9000000000',
    'gst_number': '21AAPFU0939F1ZV',
    'tax_preference': 'gst',
    'upi_id': 'sharma@upi',
    'bill_show_sku': true,
    'bill_terms': 'Exchange within 7 days\nNo cash refund',
    'bill_footer': 'Thank you! Visit again.',
  },
  invoice: {
    'invoice_no': 'INV/26-27/0101',
    'invoice_date': '2026-10-21T10:00:00Z',
    'invoice_type': 'gst',
    'customer_name': 'Ramesh Kumar',
    'customer_phone': '9876543210',
    'total': 3141.0 * lines,
    'discount_amount': 0,
    'round_off': 0,
    'paid_amount': 1000.0,
    'payment_mode': 'cash',
    'due_amount': 3141.0 * lines - 1000,
    'invoice_payments': <Map<String, dynamic>>[],
  },
  items: [for (var i = 0; i < lines; i++) _line(i)],
);

/// Page sizes in the PDF, as "width x height" in points.
List<String> _pages(List<int> bytes) =>
    RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
    ).allMatches(latin1.decode(bytes)).map((m) {
      String r(String v) => double.parse(v).round().toString();
      return '${r(m[1]!)}x${r(m[2]!)}';
    }).toList();

void main() {
  final a4 =
      '${PdfPageFormat.a4.width.round()}x${PdfPageFormat.a4.height.round()}';
  final a5 =
      '${PdfPageFormat.a5.width.round()}x${PdfPageFormat.a5.height.round()}';

  test('A4 bill stays on A4 paper', () async {
    final pages = _pages(await (await samplePdf(3).buildA4()).save());
    expect(pages, [a4]);
  });

  test('A5 bill is on A5 paper, everything on it', () async {
    final pages = _pages(await (await samplePdf(3).buildA5()).save());
    expect(pages, [a5]);
  });

  test('a long A5 bill flows onto more A5 pages', () async {
    final pages = _pages(await (await samplePdf(40).buildA5()).save());
    expect(pages.length, greaterThan(1));
    expect(pages.toSet(), {a5});
  });
}
