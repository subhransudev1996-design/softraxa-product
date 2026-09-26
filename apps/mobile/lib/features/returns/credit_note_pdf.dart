import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../../core/gst.dart';

/// Default PDF fonts have no ₹ glyph, so amounts use "Rs." instead.
String _rs(num? v) =>
    'Rs. ${NumberFormat('#,##,##0.00', 'en_IN').format(v ?? 0)}';

/// GST credit note for a sale return on a tax invoice (D40, PD26): linked to
/// the original invoice, with the tax reversed per line.
///
/// [saleReturn] is a sale_returns row with `sale_return_items(*)` and
/// `invoices(invoice_no, invoice_date, customer_name)` embedded.
/// Works for purchase-return debit notes too via [isDebitNote].
class CreditNotePdf {
  CreditNotePdf({
    required this.business,
    required this.saleReturn,
    this.isDebitNote = false,
  });

  final Map<String, dynamic> business;
  final Map<String, dynamic> saleReturn;
  final bool isDebitNote;

  List<Map<String, dynamic>> get _items => List<Map<String, dynamic>>.from(
    saleReturn[isDebitNote ? 'purchase_return_items' : 'sale_return_items']
            as List? ??
        const [],
  );

  Map<String, dynamic> get _original => Map<String, dynamic>.from(
    saleReturn[isDebitNote ? 'purchases' : 'invoices'] as Map? ?? const {},
  );

  Future<pw.Document> build() async {
    final doc = pw.Document();
    final items = _items;
    final original = _original;
    final noteNo =
        saleReturn[isDebitNote ? 'debit_note_no' : 'credit_note_no'] as String? ?? '';
    final partyGstin =
        saleReturn[isDebitNote ? 'supplier_gstin' : 'customer_gstin'] as String? ?? '';
    final party = saleReturn[isDebitNote ? 'suppliers' : 'customers'] as Map?;
    final partyName =
        (party?['name'] as String?) ??
        (original['customer_name'] as String?) ??
        '';
    final state = gstStateLabel(
      saleReturn[isDebitNote ? 'supplier_state' : 'place_of_supply'] as String?,
    );
    final originalNo = original[isDebitNote ? 'bill_no' : 'invoice_no'] as String? ?? '';
    final originalDate = original[isDebitNote ? 'purchase_date' : 'invoice_date'];
    final split = gstSplit(items);
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    const small = pw.TextStyle(fontSize: 9);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    business['name'] as String? ?? '',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  if ((business['address'] as String? ?? '').isNotEmpty)
                    pw.Text(business['address'] as String, style: small),
                  if ((business['gst_number'] as String? ?? '').isNotEmpty)
                    pw.Text(
                      'GSTIN: ${business['gst_number']}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    isDebitNote ? 'DEBIT NOTE' : 'CREDIT NOTE',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('No: $noteNo', style: bold),
                  pw.Text('Date: ${dateStr(saleReturn['return_date'])}', style: small),
                  if (state.isNotEmpty)
                    pw.Text(
                      '${isDebitNote ? 'Supplier state' : 'Place of supply'}: $state',
                      style: small,
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.Text(
            isDebitNote ? 'Supplier:' : 'Customer:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (partyName.isNotEmpty) pw.Text(partyName),
          if (partyGstin.isNotEmpty)
            pw.Text(
              'GSTIN: $partyGstin',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          if (originalNo.isNotEmpty)
            pw.Text(
              '${isDebitNote ? 'Against supplier bill' : 'Against invoice'} '
              '$originalNo${originalDate == null ? '' : ' dated ${dateStr(originalDate)}'}',
              style: small,
            ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              for (var i = 3; i < 10; i++) i: pw.Alignment.centerRight,
            },
            headers: [
              '#', 'Item', 'HSN', 'Qty', 'Taxable', 'GST%', 'CGST', 'SGST', 'IGST', 'Total',
            ],
            data: [
              for (var i = 0; i < items.length; i++)
                [
                  '${i + 1}',
                  items[i]['product_name'] as String? ?? '',
                  items[i]['hsn_code'] as String? ?? '',
                  qtyUnit(items[i]['quantity'] as num?, items[i]['unit_name'] as String?),
                  toDouble(items[i]['taxable_value']).toStringAsFixed(2),
                  '${qty(items[i]['gst_rate'] as num?)}%',
                  toDouble(items[i]['cgst_amount']).toStringAsFixed(2),
                  toDouble(items[i]['sgst_amount']).toStringAsFixed(2),
                  toDouble(items[i]['igst_amount']).toStringAsFixed(2),
                  toDouble(items[i]['line_total']).toStringAsFixed(2),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  children: [
                    _totRow('Taxable value', _rs(gstTaxableTotal(items))),
                    if (split.cgst != 0) _totRow('CGST', _rs(split.cgst)),
                    if (split.sgst != 0) _totRow('SGST', _rs(split.sgst)),
                    if (split.igst != 0) _totRow('IGST', _rs(split.igst)),
                    pw.Divider(),
                    _totRow(
                      isDebitNote ? 'TOTAL DEBIT' : 'TOTAL CREDIT',
                      _rs(saleReturn['total'] as num?),
                      bold: true,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((saleReturn['notes'] as String? ?? '').isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Reason: ${saleReturn['notes']}', style: small),
          ],
          pw.SizedBox(height: 32),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                children: [
                  pw.Container(
                    width: 120,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide()),
                    ),
                  ),
                  pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return doc;
  }

  pw.Widget _totRow(String label, String value, {bool bold = false, double size = 9}) {
    final style = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }
}
