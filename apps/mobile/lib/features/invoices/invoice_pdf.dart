import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../../core/gst.dart';

/// Default PDF fonts have no ₹ glyph, so amounts use "Rs." instead.
String _rs(num? v) =>
    'Rs. ${NumberFormat('#,##,##0.00', 'en_IN').format(v ?? 0)}';

/// Builds invoice PDFs (PRD 7.8): A4 and thermal (80mm) layouts.
/// GST invoices show HSN and a tax summary; non-GST/cash memos don't.
class InvoicePdf {
  InvoicePdf({
    required this.business,
    required this.invoice,
    required this.items,
  });

  final Map<String, dynamic> business;
  final Map<String, dynamic> invoice;
  final List<Map<String, dynamic>> items;

  bool get isGst => invoice['invoice_type'] == 'gst';
  bool get isEstimate => invoice['invoice_type'] == 'estimate';

  /// Individual payment rows (split bills have more than one) — falls back
  /// to a single blended "Paid (mode)" line when there's 0 or 1 row.
  List<Map<String, dynamic>> get _payments => List<Map<String, dynamic>>.from(
    invoice['invoice_payments'] as List? ?? [],
  );

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
          _ => 'INVOICE',
        };

  // ---------------- A4 ----------------

  Future<pw.Document> buildA4() async {
    final doc = pw.Document();
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          // header
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    business['name'] as String? ?? '',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ((business['address'] as String? ?? '').isNotEmpty)
                    pw.Text(
                      business['address'] as String,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if ((business['phone'] as String? ?? '').isNotEmpty)
                    pw.Text(
                      'Phone: ${business['phone']}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (showsShopGstin)
                    pw.Text(
                      'GSTIN: ${business['gst_number']}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
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
                  pw.Text('No: ${invoice['invoice_no']}', style: bold),
                  pw.Text(
                    'Date: ${dateTimeStr(invoice['invoice_date'])}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (isGst && _placeOfSupply.isNotEmpty)
                    pw.Text(
                      _placeOfSupply,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          // customer
          if ((invoice['customer_name'] as String? ?? '').isNotEmpty) ...[
            pw.Text(
              'Bill To:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(invoice['customer_name'] as String),
            if (isGst && _customerGstin.isNotEmpty)
              pw.Text(
                'GSTIN: $_customerGstin',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            if ((invoice['customer_phone'] as String? ?? '').isNotEmpty)
              pw.Text(
                'Phone: ${invoice['customer_phone']}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            pw.SizedBox(height: 8),
          ],
          // items table
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
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              for (var i = 2; i < 8; i++) i: pw.Alignment.centerRight,
            },
            headers: [
              '#',
              'Item',
              if (isGst) 'HSN',
              'Qty',
              'Rate',
              if (isGst) 'GST%',
              'Disc',
              'Amount',
            ],
            data: [
              for (var i = 0; i < items.length; i++)
                [
                  '${i + 1}',
                  _itemName(items[i]),
                  if (isGst) items[i]['hsn_code'] as String? ?? '',
                  qtyUnit(
                    items[i]['quantity'] as num?,
                    items[i]['unit_name'] as String?,
                  ),
                  (toDouble(items[i]['unit_price']) * _inclFactor(items[i]))
                      .toStringAsFixed(2),
                  if (isGst) '${qty(items[i]['gst_rate'] as num?)}%',
                  toDouble(items[i]['discount_amount']) > 0
                      ? (toDouble(items[i]['discount_amount']) *
                                _inclFactor(items[i]))
                            .toStringAsFixed(2)
                      : '-',
                  toDouble(items[i]['line_total']).toStringAsFixed(2),
                ],
            ],
          ),
          pw.SizedBox(height: 10),
          // totals
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  children: [
                    _totRow(
                      'Subtotal',
                      _rs(
                        toDouble(invoice['subtotal']) +
                            toDouble(invoice['tax_amount']),
                      ),
                    ),
                    if (toDouble(invoice['discount_amount']) > 0)
                      _totRow(
                        'Discount',
                        '- ${_rs(invoice['discount_amount'] as num?)}',
                      ),
                    if (isGst) ...[
                      _totRow('Taxable value', _rs(gstTaxableTotal(items))),
                      ..._gstBreakup(),
                    ],
                    if (toDouble(invoice['round_off']) != 0)
                      _totRow('Round off', _rs(invoice['round_off'] as num?)),
                    pw.Divider(),
                    _totRow(
                      'TOTAL',
                      _rs(invoice['total'] as num?),
                      bold: true,
                      size: 12,
                    ),
                    if (!isEstimate) ...[
                      if (_payments.length > 1)
                        for (final p in _payments)
                          _totRow(
                            'Paid (${p['payment_mode']})',
                            _rs(p['amount'] as num?),
                          )
                      else
                        _totRow(
                          'Paid (${invoice['payment_mode']})',
                          _rs(invoice['paid_amount'] as num?),
                        ),
                      if (toDouble(invoice['credit_amount']) > 0)
                        _totRow(
                          'Returns credit',
                          _rs(invoice['credit_amount'] as num?),
                        ),
                      if (toDouble(invoice['due_amount']) > 0)
                        _totRow(
                          'Balance Due',
                          _rs(invoice['due_amount'] as num?),
                          bold: true,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (_upiLink != null)
                _upiQr(84)
              else
                pw.Text(
                  'Thank you for your business!',
                  style: const pw.TextStyle(fontSize: 9),
                ),
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

  // ---------------- Thermal (80mm / 58mm) ----------------

  Future<pw.Document> buildThermal({double widthMm = 80}) async {
    final doc = pw.Document();
    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );
    const small = pw.TextStyle(fontSize: 8);
    final smallBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                business['name'] as String? ?? '',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            if ((business['address'] as String? ?? '').isNotEmpty)
              pw.Center(
                child: pw.Text(
                  business['address'] as String,
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              ),
            if ((business['phone'] as String? ?? '').isNotEmpty)
              pw.Center(
                child: pw.Text('Ph: ${business['phone']}', style: small),
              ),
            if (showsShopGstin)
              pw.Center(
                child: pw.Text(
                  'GSTIN: ${business['gst_number']}',
                  style: smallBold,
                ),
              ),
            pw.Center(child: pw.Text('--- $title ---', style: smallBold)),
            if (isComposition)
              pw.Center(
                child: pw.Text(
                  compositionDeclaration,
                  style: small,
                  textAlign: pw.TextAlign.center,
                ),
              ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('${invoice['invoice_no']}', style: smallBold),
                pw.Text(dateTimeStr(invoice['invoice_date']), style: small),
              ],
            ),
            if ((invoice['customer_name'] as String? ?? '').isNotEmpty)
              pw.Text('Customer: ${invoice['customer_name']}', style: small),
            if (isGst && _customerGstin.isNotEmpty)
              pw.Text('GSTIN: $_customerGstin', style: small),
            if (isGst && _placeOfSupply.isNotEmpty)
              pw.Text(_placeOfSupply, style: small),
            pw.Divider(height: 6, borderStyle: pw.BorderStyle.dashed),
            for (final it in items) ...[
              pw.Text(_itemName(it), style: smallBold),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${qtyUnit(it['quantity'] as num?, it['unit_name'] as String?)}'
                    ' x ${(toDouble(it['unit_price']) * _inclFactor(it)).toStringAsFixed(2)}',
                    style: small,
                  ),
                  pw.Text(
                    toDouble(it['line_total']).toStringAsFixed(2),
                    style: small,
                  ),
                ],
              ),
            ],
            pw.Divider(height: 6, borderStyle: pw.BorderStyle.dashed),
            _tRow(
              'Subtotal',
              (toDouble(invoice['subtotal']) + toDouble(invoice['tax_amount']))
                  .toStringAsFixed(2),
              small,
            ),
            if (toDouble(invoice['discount_amount']) > 0)
              _tRow(
                'Discount',
                '-${toDouble(invoice['discount_amount']).toStringAsFixed(2)}',
                small,
              ),
            if (isGst && toDouble(invoice['tax_amount']) > 0) ...[
              _tRow(
                'Taxable value',
                gstTaxableTotal(items).toStringAsFixed(2),
                small,
              ),
              for (final (label, amount) in gstBreakupRows(items))
                _tRow('Incl. $label', amount.toStringAsFixed(2), small),
            ],
            if (toDouble(invoice['round_off']) != 0)
              _tRow(
                'Round off',
                toDouble(invoice['round_off']).toStringAsFixed(2),
                small,
              ),
            _tRow(
              'TOTAL',
              toDouble(invoice['total']).toStringAsFixed(2),
              pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            if (!isEstimate) ...[
              if (_payments.length > 1)
                for (final p in _payments)
                  _tRow(
                    'Paid (${p['payment_mode']})',
                    toDouble(p['amount']).toStringAsFixed(2),
                    small,
                  )
              else
                _tRow(
                  'Paid (${invoice['payment_mode']})',
                  toDouble(invoice['paid_amount']).toStringAsFixed(2),
                  small,
                ),
              if (toDouble(invoice['due_amount']) > 0)
                _tRow(
                  'DUE',
                  toDouble(invoice['due_amount']).toStringAsFixed(2),
                  smallBold,
                ),
            ],
            if (_upiLink != null) ...[
              pw.SizedBox(height: 6),
              pw.Center(child: _upiQr(widthMm >= 70 ? 90 : 70)),
            ],
            pw.SizedBox(height: 6),
            pw.Center(child: pw.Text('Thank you! Visit again.', style: small)),
          ],
        ),
      ),
    );
    return doc;
  }

  // ---------------- helpers ----------------

  String _itemName(Map<String, dynamic> it) {
    final variant = it['variant_name'] as String? ?? '';
    final serial = it['serial_no'] as String? ?? '';
    var name = it['product_name'] as String? ?? '';
    if (variant.isNotEmpty) name = '$name ($variant)';
    if (serial.isNotEmpty) name = '$name\nS/N: $serial';
    return name;
  }

  /// unit_price is stored tax-exclusive; display inclusive rate on the bill.
  double _inclFactor(Map<String, dynamic> it) =>
      isGst ? 1 + toDouble(it['gst_rate']) / 100 : 1;

  List<pw.Widget> _gstBreakup() => [
    for (final (label, amount) in gstBreakupRows(items))
      _totRow('$label (incl.)', _rs(amount)),
  ];

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
