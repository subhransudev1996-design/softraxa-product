import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../../core/gst.dart';
import 'bill_layout.dart';

/// Default PDF fonts have no ₹ glyph, so amounts use "Rs." instead.
String _rs(num? v) =>
    'Rs. ${NumberFormat('#,##,##0.00', 'en_IN').format(v ?? 0)}';

/// 3,490.00 — table cells, where "Rs." would only crowd the columns.
String _n(num v) => billMoney(v);

/// Builds invoice PDFs (PRD 7.8): A4 and thermal (80mm) layouts, laid out
/// like a shop's sales invoice (bill_layout.dart): stock no., rate, amount,
/// discount and total per line; amount in words; payment details; GST
/// summary by rate; the shop's terms & conditions (migration 0076).
class InvoicePdf {
  InvoicePdf({
    required this.business,
    required this.invoice,
    required this.items,
    this.logo,
    Map<String, dynamic>? exchange,
  }) : bill = BillLayout(
         business: business,
         invoice: invoice,
         items: items,
         exchange: exchange,
       );

  final Map<String, dynamic> business;
  final Map<String, dynamic> invoice;
  final List<Map<String, dynamic>> items;

  /// The shop's logo (loadBillLogo), printed at the top when there is one.
  final Uint8List? logo;
  final BillLayout bill;

  bool get isGst => bill.isGst;
  bool get isEstimate => bill.isEstimate;

  /// UPI "scan to pay" link for the balance due (setup wizard, 0047).
  /// Null when the shop has no UPI ID or nothing is left to pay.
  String? get _upiLink {
    final upi = (business['upi_id'] as String? ?? '').trim();
    final due = toDouble(invoice['due_amount']);
    if (upi.isEmpty || isEstimate || due <= 0) return null;
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upi,
        'pn': business['name'] as String? ?? '',
        'am': due.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Bill ${invoice['invoice_no'] ?? ''}',
      },
    ).toString();
  }

  pw.Widget _upiQr(double size) => pw.Column(
    children: [
      pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: _upiLink!,
        width: size,
        height: size,
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'Scan to pay ${_rs(invoice['due_amount'] as num?)} by UPI',
        style: const pw.TextStyle(fontSize: 8),
      ),
      pw.Text(
        business['upi_id'] as String,
        style: const pw.TextStyle(fontSize: 7),
      ),
    ],
  );

  /// Composition shops can't charge GST: their bills are bills of supply
  /// carrying the composition declaration (migration 0048).
  bool get isComposition => business['tax_preference'] == 'composition';

  /// Bill of supply: a composition shop's bill, or a GST shop's bill of
  /// exempt goods only (every line at 0%).
  bool get isBillOfSupply =>
      !isEstimate &&
      invoice['invoice_type'] != 'cash_memo' &&
      (isComposition ||
          (isGst &&
              items.isNotEmpty &&
              items.every((it) => toDouble(it['gst_rate']) == 0)));

  /// The shop's GSTIN is printed on tax invoices and on a composition
  /// shop's bills of supply.
  bool get showsShopGstin =>
      (isGst || isComposition) &&
      (business['gst_number'] as String? ?? '').isNotEmpty;

  static const compositionDeclaration =
      'Composition taxable person, not eligible to collect tax on supplies';

  String get title => isBillOfSupply
      ? 'BILL OF SUPPLY'
      : switch (invoice['invoice_type']) {
          'gst' => 'TAX INVOICE',
          'cash_memo' => 'CASH MEMO',
          'estimate' => 'ESTIMATE / QUOTATION',
          'opening' => 'OPENING BALANCE',
          _ => 'SALES INVOICE',
        };

  String _s(Object? v) => (v as String? ?? '').trim();
  bool get _anySize => bill.lines.any((l) => l.size.isNotEmpty);
  bool get _anyDiscount => bill.lines.any((l) => l.discount > 0);
  bool get _anySku => bill.lines.any((l) => l.sku.isNotEmpty);

  // ---------------- A4 ----------------

  Future<pw.Document> buildA4() async {
    final doc = pw.Document();
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    const small = pw.TextStyle(fontSize: 9);
    final smallBold = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final email = _s(business['email']);

    // Item table columns, each only when some line needs it.
    final headers = <String>[
      '#',
      if (_anySku) 'Stock No',
      'Item',
      if (_anySize) 'Size',
      if (isGst) 'HSN',
      'Qty',
      'Rate',
      'Amount',
      if (_anyDiscount) 'Disc',
      if (isGst) 'GST%',
      'Total',
    ];
    final firstNumber = headers.indexOf('Qty');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          // header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) ...[
                pw.Image(pw.MemoryImage(logo!), width: 64, height: 64),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _s(business['name']),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (_s(business['address']).isNotEmpty)
                      pw.Text(_s(business['address']), style: small),
                    if (_s(business['phone']).isNotEmpty || email.isNotEmpty)
                      pw.Text(
                        [
                          if (_s(business['phone']).isNotEmpty)
                            'Ph: ${_s(business['phone'])}',
                          if (email.isNotEmpty) email,
                        ].join('   '),
                        style: small,
                      ),
                    if (showsShopGstin)
                      pw.Text(
                        'GSTIN: ${business['gst_number']}',
                        style: smallBold,
                      ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (isComposition)
                    pw.SizedBox(
                      width: 190,
                      child: pw.Text(
                        compositionDeclaration,
                        style: const pw.TextStyle(fontSize: 8),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  pw.SizedBox(height: 4),
                  pw.Text('Bill No: ${invoice['invoice_no']}', style: bold),
                  pw.Text(dateTimeStr(invoice['invoice_date']), style: small),
                  if (isGst && _placeOfSupply.isNotEmpty)
                    pw.Text(_placeOfSupply, style: small),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          // customer
          if (_s(invoice['customer_name']).isNotEmpty ||
              _s(invoice['customer_phone']).isNotEmpty) ...[
            pw.Text('Bill To:', style: smallBold),
            if (_s(invoice['customer_name']).isNotEmpty)
              pw.Text(_s(invoice['customer_name'])),
            if (isGst && _customerGstin.isNotEmpty)
              pw.Text('GSTIN: $_customerGstin', style: smallBold),
            if (_s(invoice['customer_phone']).isNotEmpty)
              pw.Text('Mob: ${invoice['customer_phone']}', style: small),
            pw.SizedBox(height: 8),
          ],
          // items
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              for (var i = 0; i < headers.length; i++)
                i: i >= firstNumber
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
            },
            headers: headers,
            data: [
              for (var i = 0; i < bill.lines.length; i++)
                () {
                  final l = bill.lines[i];
                  final it = items[i];
                  return [
                    '${i + 1}',
                    if (_anySku) l.sku,
                    l.name,
                    if (_anySize) l.size,
                    if (isGst) it['hsn_code'] as String? ?? '',
                    qtyUnit(l.qty, l.unit),
                    _n(l.rate),
                    _n(l.amount),
                    if (_anyDiscount) l.discount > 0 ? _n(l.discount) : '-',
                    if (isGst) '${qty(it['gst_rate'] as num?)}%',
                    _n(l.total),
                  ];
                }(),
              // Totals row, like the shop's own bill.
              [
                '',
                if (_anySku) '',
                'Total',
                if (_anySize) '',
                if (isGst) '',
                qty(bill.totalQty),
                '',
                _n(bill.totalAmount),
                if (_anyDiscount) _n(bill.totalLineDiscount),
                if (isGst) '',
                _n(bill.linesTotal),
              ],
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // amount in words + payments
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Amount in words:', style: smallBold),
                    pw.Text(bill.amountInWords, style: small),
                    if (bill.payments.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Text('Payment details:', style: smallBold),
                      for (final (mode, amount) in bill.payments)
                        pw.Text('$mode: ${_rs(amount)}', style: small),
                    ],
                    ..._exchangeBlock(small, smallBold),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              // totals
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  children: [
                    if (bill.billDiscount > 0)
                      _totRow('Bill discount', '- ${_rs(bill.billDiscount)}'),
                    if (bill.roundOff != 0)
                      _totRow('Round off', _rs(bill.roundOff)),
                    pw.Divider(),
                    _totRow(
                      'NET AMOUNT',
                      _rs(bill.netAmount),
                      bold: true,
                      size: 12,
                    ),
                    if (bill.due > 0)
                      _totRow('Balance Due', _rs(bill.due), bold: true),
                  ],
                ),
              ),
            ],
          ),
          if (bill.gstSummary.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('GST Summary', style: smallBold),
            pw.SizedBox(height: 4),
            _gstTable(fontSize: 9),
          ],
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (_upiLink != null) _upiQr(84),
                    ..._termsBlock(fontSize: 8.5),
                    if (bill.footer.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(bill.footer, style: small),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Column(
                children: [
                  pw.SizedBox(height: 24),
                  pw.Container(
                    width: 120,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide()),
                    ),
                  ),
                  pw.Text(
                    'Authorised Signatory',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return doc;
  }

  // ---------------- Thermal (80mm) ----------------

  Future<pw.Document> buildThermal({double widthMm = 80}) async {
    final doc = pw.Document();
    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );
    const small = pw.TextStyle(fontSize: 7.5);
    final smallBold = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
    );
    final email = _s(business['email']);
    final dash = pw.Divider(height: 6, borderStyle: pw.BorderStyle.dashed);

    // Size | Qty | Rate | Amount | Disc | Total, each where it's needed.
    // Qty is short; the money columns need the room.
    final flex = [if (_anySize) 3, 2, 3, 3, if (_anyDiscount) 3, 3];
    pw.Widget cols(List<String> cells, pw.TextStyle style) => pw.Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Expanded(
            flex: flex[i],
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(left: 3),
              child: pw.Text(
                cells[i],
                style: style,
                textAlign: i == 0 && _anySize
                    ? pw.TextAlign.left
                    : pw.TextAlign.right,
              ),
            ),
          ),
      ],
    );

    pw.Widget centered(String text, pw.TextStyle style) => pw.Center(
      child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
    );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logo != null)
              pw.Center(
                child: pw.Image(
                  pw.MemoryImage(logo!),
                  height: 44,
                  fit: pw.BoxFit.contain,
                ),
              ),
            centered(
              _s(business['name']),
              pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            if (_s(business['address']).isNotEmpty)
              centered(_s(business['address']), small),
            if (_s(business['phone']).isNotEmpty)
              centered('Ph: ${business['phone']}', small),
            if (email.isNotEmpty) centered(email, small),
            pw.SizedBox(height: 3),
            centered(title, smallBold),
            if (showsShopGstin)
              centered('GSTIN: ${business['gst_number']}', smallBold),
            if (isComposition) centered(compositionDeclaration, small),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill No: ${invoice['invoice_no']}', style: smallBold),
                pw.Text(dateTimeStr(invoice['invoice_date']), style: small),
              ],
            ),
            if (_s(invoice['customer_name']).isNotEmpty ||
                _s(invoice['customer_phone']).isNotEmpty)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Cust: ${_s(invoice['customer_name'])}',
                    style: small,
                  ),
                  if (_s(invoice['customer_phone']).isNotEmpty)
                    pw.Text('Mob: ${invoice['customer_phone']}', style: small),
                ],
              ),
            if (isGst && _customerGstin.isNotEmpty)
              pw.Text('GSTIN: $_customerGstin', style: small),
            if (isGst && _placeOfSupply.isNotEmpty)
              pw.Text(_placeOfSupply, style: small),
            pw.Divider(height: 6),
            // table header
            pw.Text(
              _anySku ? 'Stock No   Item Description' : 'Item',
              style: smallBold,
            ),
            cols([
              if (_anySize) 'Size',
              'Qty',
              'Rate',
              'Amount',
              if (_anyDiscount) 'Disc',
              'Total',
            ], smallBold),
            pw.Divider(height: 6),
            for (final l in bill.lines) ...[
              pw.Text(
                l.sku.isEmpty ? l.name : '${l.sku}   ${l.name}',
                style: small,
              ),
              cols([
                if (_anySize) l.size,
                l.isPack ? qtyUnit(l.qty, l.unit) : qty(l.qty),
                _n(l.rate),
                _n(l.amount),
                if (_anyDiscount) l.discount > 0 ? _n(l.discount) : '0.00',
                _n(l.total),
              ], small),
              pw.SizedBox(height: 2),
            ],
            pw.Divider(height: 6),
            cols([
              if (_anySize) 'Total',
              qty(bill.totalQty),
              '',
              _n(bill.totalAmount),
              if (_anyDiscount) _n(bill.totalLineDiscount),
              _n(bill.linesTotal),
            ], smallBold),
            pw.Divider(height: 6),
            if (bill.billDiscount > 0)
              _tRow('Bill discount', '-${_n(bill.billDiscount)}', small),
            if (bill.roundOff != 0)
              _tRow('Round off', _n(bill.roundOff), small),
            _tRow(
              'Net Bill Amount',
              _n(bill.netAmount),
              pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Amount In Words:', style: smallBold),
                  pw.Text(bill.amountInWords, style: small),
                ],
              ),
            ),
            if (bill.payments.isNotEmpty || bill.due > 0) ...[
              pw.SizedBox(height: 4),
              pw.Text('Payment Details', style: smallBold),
              for (final (mode, amount) in bill.payments)
                _tRow(mode, _n(amount), small),
              if (bill.due > 0) _tRow('DUE', _n(bill.due), smallBold),
            ],
            ..._exchangeBlock(small, smallBold),
            if (bill.gstSummary.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('GST Summary', style: smallBold),
              pw.SizedBox(height: 2),
              _gstTable(fontSize: 6.5),
            ],
            if (_upiLink != null) ...[
              pw.SizedBox(height: 6),
              pw.Center(child: _upiQr(widthMm >= 70 ? 90 : 70)),
            ],
            if (bill.terms.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              dash,
              ..._termsBlock(fontSize: 7),
            ],
            if (bill.footer.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              centered(bill.footer, small),
            ],
          ],
        ),
      ),
    );
    return doc;
  }

  // ---------------- helpers ----------------

  pw.Widget _gstTable({required double fontSize}) =>
      pdfGstSummaryTable(bill.gstSummary, fontSize: fontSize);

  /// An exchange bill: what came back, from which bill, where the credit
  /// went.
  List<pw.Widget> _exchangeBlock(pw.TextStyle style, pw.TextStyle boldStyle) {
    final ex = bill.exchange;
    if (ex == null) return const [];
    return [
      pw.SizedBox(height: 6),
      pw.Text(
        'Exchange against ${ex.originalNo}'
        '${ex.returnNo.isEmpty ? '' : ' (return ${ex.returnNo})'}',
        style: boldStyle,
      ),
      for (final (name, q, value) in ex.returned)
        _tRow('$name x ${qty(q)}', _n(value), style),
      for (final (label, amount) in ex.rows) _tRow(label, _n(amount), style),
    ];
  }

  /// "Terms & Conditions:" and the shop's terms, numbered.
  List<pw.Widget> _termsBlock({required double fontSize}) {
    if (bill.terms.isEmpty) return const [];
    final style = pw.TextStyle(fontSize: fontSize);
    return [
      pw.SizedBox(height: 4),
      pw.Text(
        'Terms & Conditions:',
        style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold),
      ),
      for (var i = 0; i < bill.terms.length; i++)
        pw.Text('${i + 1}. ${bill.terms[i]}', style: style),
    ];
  }

  /// The customer's GSTIN as it was when billed (migration 0040).
  String get _customerGstin => invoice['customer_gstin'] as String? ?? '';

  /// "Place of supply: 27 - Maharashtra", or '' when not recorded.
  String get _placeOfSupply {
    final label = gstStateLabel(invoice['place_of_supply'] as String?);
    return label.isEmpty ? '' : 'Place of supply: $label';
  }

  pw.Widget _totRow(
    String label,
    String value, {
    bool bold = false,
    double size = 9,
  }) {
    final style = pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  pw.Widget _tRow(String label, String value, pw.TextStyle style) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: style),
      pw.Text(value, style: style),
    ],
  );
}

/// Rate | Taxable value | CGST | SGST | Total GST (or IGST), with totals.
pw.Widget pdfGstSummaryTable(
  List<GstSummaryRow> rows, {
  required double fontSize,
}) {
  final igst = rows.any((r) => r.igst != 0);
  final style = pw.TextStyle(fontSize: fontSize);
  final boldStyle = pw.TextStyle(
    fontSize: fontSize,
    fontWeight: pw.FontWeight.bold,
  );
  final headers = [
    'GST %',
    'Taxable',
    if (igst) 'IGST' else ...['CGST', 'SGST'],
    'Total GST',
  ];
  final sum = (
    taxable: rows.fold(0.0, (s, r) => s + r.taxable),
    cgst: rows.fold(0.0, (s, r) => s + r.cgst),
    sgst: rows.fold(0.0, (s, r) => s + r.sgst),
    igst: rows.fold(0.0, (s, r) => s + r.igst),
    tax: rows.fold(0.0, (s, r) => s + r.totalTax),
  );
  pw.Widget cell(String s, pw.TextStyle st, {bool left = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.Text(
      s,
      style: st,
      textAlign: left ? pw.TextAlign.left : pw.TextAlign.right,
    ),
  );
  return pw.Table(
    border: pw.TableBorder.all(width: 0.5),
    children: [
      pw.TableRow(
        children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i], boldStyle, left: i == 0),
        ],
      ),
      for (final r in rows)
        pw.TableRow(
          children: [
            cell('${qty(r.rate)}%', style, left: true),
            cell(_n(r.taxable), style),
            if (igst)
              cell(_n(r.igst), style)
            else ...[
              cell(_n(r.cgst), style),
              cell(_n(r.sgst), style),
            ],
            cell(_n(r.totalTax), style),
          ],
        ),
      if (rows.length > 1)
        pw.TableRow(
          children: [
            cell('Total', boldStyle, left: true),
            cell(_n(sum.taxable), boldStyle),
            if (igst)
              cell(_n(sum.igst), boldStyle)
            else ...[
              cell(_n(sum.cgst), boldStyle),
              cell(_n(sum.sgst), boldStyle),
            ],
            cell(_n(sum.tax), boldStyle),
          ],
        ),
    ],
  );
}
