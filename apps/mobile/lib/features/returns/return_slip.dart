import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../invoices/bill_layout.dart';
import '../invoices/invoice_pdf.dart' show pdfGstSummaryTable;
import '../invoices/thermal_printer.dart' show posGstSummary;

/// The sales return slip handed to the customer, like the shop's own:
/// the shop, "SALES RETURN", the return no., the customer and the bill it
/// came from; each item with its quantity, price and total; the discount
/// the bill had given; the net returned; how it was refunded; the GST
/// summary; who made it and when.
///
/// [saleReturn] is a sale_returns row with `sale_return_items(*,
/// invoice_items(...))`, `invoices(...)`, `customers(name)` and
/// `profiles(full_name)` embedded (saleReturnDetailProvider).

class ReturnSlipLine {
  const ReturnSlipLine({
    required this.name,
    required this.qty,
    required this.unit,
    required this.price,
    required this.gross,
    required this.total,
  });

  final String name;
  final double qty;

  /// The pack when a whole number of packs came back, else ''.
  final String unit;

  /// The price on the bill, per [unit] (or per piece), GST included.
  final double price;
  final double gross;

  /// What this line was worth back, after the bill's discounts.
  final double total;
}

class ReturnSlip {
  ReturnSlip({required this.business, required this.saleReturn});

  final Map<String, dynamic> business;
  final Map<String, dynamic> saleReturn;

  List<Map<String, dynamic>> get _items => List<Map<String, dynamic>>.from(
    saleReturn['sale_return_items'] as List? ?? const [],
  );

  Map<String, dynamic> get _invoice =>
      Map<String, dynamic>.from(saleReturn['invoices'] as Map? ?? const {});

  bool get _gstBill => _invoice['invoice_type'] == 'gst';

  String get returnNo => saleReturn['return_no'] as String? ?? '';
  String get creditNoteNo => saleReturn['credit_note_no'] as String? ?? '';
  String get billNo => _invoice['invoice_no'] as String? ?? '';
  String get customer =>
      ((saleReturn['customers'] as Map?)?['name'] as String?) ??
      (_invoice['customer_name'] as String? ?? '');
  String get user =>
      ((saleReturn['profiles'] as Map?)?['full_name'] as String? ?? '').trim();
  String get reason => (saleReturn['notes'] as String? ?? '').trim();

  late final List<ReturnSlipLine> lines = [for (final it in _items) _line(it)];

  ReturnSlipLine _line(Map<String, dynamic> it) {
    final q = toDouble(it['quantity']);
    final total = toDouble(it['line_total']);
    final billLine = it['invoice_items'] as Map?;
    if (billLine == null || q <= 0) {
      // Older returns don't name their bill line: the value back is all
      // that's known.
      final each = q > 0 ? total / q : 0.0;
      return ReturnSlipLine(
        name: it['product_name'] as String? ?? '',
        qty: q,
        unit: '',
        price: each,
        gross: total,
        total: total,
      );
    }
    // The bill line's price per piece, GST included, before discounts.
    final incl = _gstBill ? 1 + toDouble(billLine['gst_rate']) / 100 : 1;
    final perPiece = toDouble(billLine['unit_price']) * incl;
    final factor = toDouble(billLine['alt_factor']);
    final wholePacks =
        billLine['sold_as_pack'] == true &&
        factor > 0 &&
        (q / factor - (q / factor).roundToDouble()).abs() < 1e-6;
    final shownQty = wholePacks ? q / factor : q;
    final price = wholePacks ? perPiece * factor : perPiece;
    final gross = (shownQty * price * 100).roundToDouble() / 100;
    final variant = (billLine['variant_name'] as String? ?? '').trim();
    final name = it['product_name'] as String? ?? '';
    return ReturnSlipLine(
      name: variant.isEmpty ? name : '$name ($variant)',
      qty: shownQty,
      unit: wholePacks ? billLine['alt_unit_name'] as String? ?? '' : '',
      price: (price * 100).roundToDouble() / 100,
      // A rounding paisa never shows as a discount.
      gross: gross < total ? total : gross,
      total: total,
    );
  }

  double get totalQty => lines.fold(0.0, (s, l) => s + l.qty);
  double get gross => lines.fold(0.0, (s, l) => s + l.gross);
  double get net => toDouble(saleReturn['total']);
  double get discount {
    final d = gross - net;
    return d > 0.005 ? d : 0;
  }

  /// How the value went back: cash/UPI now, the rest to the customer.
  List<(String, double)> get refunds {
    final refunded = toDouble(saleReturn['refund_amount']);
    final rest = net - refunded;
    return [
      if (refunded > 0)
        ('Refund (${paymentModeLabel(saleReturn['refund_mode'])})', refunded),
      if (rest > 0.005) ('Credit to customer', rest),
    ];
  }

  List<GstSummaryRow> get gst => _gstBill ? gstSummaryRows(_items) : const [];

  bool get showsGstin =>
      business['tax_preference'] != 'non_gst' &&
      (business['gst_number'] as String? ?? '').trim().isNotEmpty;
}

String _s(Object? v) => (v as String? ?? '').trim();
String _n(num v) => billMoney(v);
String _qtyText(ReturnSlipLine l) =>
    l.unit.isEmpty ? qty(l.qty) : qtyUnit(l.qty, l.unit);

// ---------------- 80 mm PDF ----------------

Future<pw.Document> buildReturnSlipPdf(
  ReturnSlip slip, {
  Uint8List? logo,
}) async {
  final business = slip.business;
  final r = slip.saleReturn;
  final doc = pw.Document();
  const small = pw.TextStyle(fontSize: 7.5);
  final smallBold = pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold);
  pw.Widget centered(String text, pw.TextStyle style) => pw.Center(
    child: pw.Text(text, style: style, textAlign: pw.TextAlign.center),
  );
  pw.Widget row(String a, String b, pw.TextStyle style) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(a, style: style),
      pw.Text(b, style: style),
    ],
  );
  // Qty | Price | Total
  const flex = [2, 3, 3];
  pw.Widget cols(List<String> c, pw.TextStyle style) => pw.Row(
    children: [
      for (var i = 0; i < c.length; i++)
        pw.Expanded(
          flex: flex[i],
          child: pw.Text(c[i], style: style, textAlign: pw.TextAlign.right),
        ),
    ],
  );

  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 4 * PdfPageFormat.mm,
      ),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Center(
              child: pw.Image(
                pw.MemoryImage(logo),
                height: 40,
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
          pw.SizedBox(height: 3),
          centered('SALES RETURN', smallBold),
          if (slip.showsGstin)
            centered('GSTIN: ${business['gst_number']}', smallBold),
          pw.SizedBox(height: 4),
          row(
            'Return No: ${slip.returnNo}',
            dateStr(r['return_date']),
            smallBold,
          ),
          if (slip.customer.isNotEmpty)
            pw.Text('Name: ${slip.customer}', style: small),
          if (slip.billNo.isNotEmpty)
            pw.Text('Against bill: ${slip.billNo}', style: small),
          if (slip.creditNoteNo.isNotEmpty)
            pw.Text('Credit note: ${slip.creditNoteNo}', style: small),
          pw.Divider(height: 6),
          pw.Text('Item Name', style: smallBold),
          cols(['Qty', 'Price', 'Total'], smallBold),
          pw.Divider(height: 6),
          for (final l in slip.lines) ...[
            pw.Text(l.name, style: small),
            cols([_qtyText(l), _n(l.price), _n(l.gross)], small),
            pw.SizedBox(height: 2),
          ],
          pw.Divider(height: 6),
          row('Total: ${qty(slip.totalQty)}', _n(slip.gross), smallBold),
          if (slip.discount > 0) row('Discount', _n(slip.discount), small),
          pw.Divider(height: 6),
          row(
            'Net Return Amount',
            _n(slip.net),
            pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(rupeesInWords(slip.net), style: small),
          if (slip.refunds.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            for (final (label, amount) in slip.refunds)
              row(label, _n(amount), small),
          ],
          if (slip.gst.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('GST Summary', style: smallBold),
            pw.SizedBox(height: 2),
            pdfGstSummaryTable(slip.gst, fontSize: 6.5),
          ],
          if (slip.reason.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Reason: ${slip.reason}', style: small),
          ],
          pw.SizedBox(height: 6),
          row(
            slip.user.isEmpty ? '' : 'User: ${slip.user}',
            'Time: ${timeOf(r['return_date'])}',
            small,
          ),
        ],
      ),
    ),
  );
  return doc;
}

/// "05:00 PM" from a timestamp.
String timeOf(Object? v) {
  final s = dateTimeStr(v);
  final comma = s.lastIndexOf(', ');
  return comma < 0 ? s : s.substring(comma + 2);
}

// ---------------- Bluetooth printer ----------------

Future<List<int>> buildReturnSlipTicket(
  ReturnSlip slip, {
  img.Image? logo,
}) async {
  final business = slip.business;
  final r = slip.saleReturn;
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm80, profile);
  const center = PosStyles(align: PosAlign.center);
  const right = PosStyles(align: PosAlign.right);
  const bold = PosStyles(bold: true);
  var bytes = <int>[];

  void line(String a, String b, {bool strong = false}) {
    bytes += generator.row([
      PosColumn(
        text: a,
        width: 7,
        styles: PosStyles(bold: strong),
      ),
      PosColumn(
        text: b,
        width: 5,
        styles: PosStyles(align: PosAlign.right, bold: strong),
      ),
    ]);
  }

  List<PosColumn> cols(List<String> c, {bool b = false}) => [
    PosColumn(
      text: c[0],
      width: 3,
      styles: PosStyles(bold: b),
    ),
    PosColumn(
      text: c[1],
      width: 4,
      styles: PosStyles(align: PosAlign.right, bold: b),
    ),
    PosColumn(
      text: c[2],
      width: 5,
      styles: PosStyles(align: PosAlign.right, bold: b),
    ),
  ];

  if (logo != null) bytes += generator.imageRaster(logo);
  bytes += generator.text(
    _s(business['name']),
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
    ),
  );
  if (_s(business['address']).isNotEmpty) {
    bytes += generator.text(_s(business['address']), styles: center);
  }
  if (_s(business['phone']).isNotEmpty) {
    bytes += generator.text('Ph: ${_s(business['phone'])}', styles: center);
  }
  bytes += generator.text('SALES RETURN', styles: center.copyWith(bold: true));
  if (slip.showsGstin) {
    bytes += generator.text(
      'GSTIN: ${_s(business['gst_number'])}',
      styles: center.copyWith(bold: true),
    );
  }
  bytes += generator.hr();
  line('Return No: ${slip.returnNo}', dateStr(r['return_date']), strong: true);
  if (slip.customer.isNotEmpty) {
    bytes += generator.text('Name: ${slip.customer}');
  }
  if (slip.billNo.isNotEmpty) {
    bytes += generator.text('Against bill: ${slip.billNo}');
  }
  if (slip.creditNoteNo.isNotEmpty) {
    bytes += generator.text('Credit note: ${slip.creditNoteNo}');
  }
  bytes += generator.hr();
  bytes += generator.text('Item Name', styles: bold);
  bytes += generator.row(cols(['Qty', 'Price', 'Total'], b: true));
  bytes += generator.hr();
  for (final l in slip.lines) {
    bytes += generator.text(l.name);
    bytes += generator.row(cols([_qtyText(l), _n(l.price), _n(l.gross)]));
  }
  bytes += generator.hr();
  line('Total: ${qty(slip.totalQty)}', _n(slip.gross), strong: true);
  if (slip.discount > 0) line('Discount', _n(slip.discount));
  bytes += generator.row([
    PosColumn(
      text: 'Net Return',
      width: 7,
      styles: const PosStyles(bold: true, height: PosTextSize.size2),
    ),
    PosColumn(
      text: _n(slip.net),
      width: 5,
      styles: const PosStyles(
        align: PosAlign.right,
        bold: true,
        height: PosTextSize.size2,
      ),
    ),
  ]);
  bytes += generator.text(rupeesInWords(slip.net));
  for (final (label, amount) in slip.refunds) {
    line(label, _n(amount));
  }
  bytes += posGstSummary(generator, slip.gst);
  if (slip.reason.isNotEmpty) {
    bytes += generator.hr();
    bytes += generator.text('Reason: ${slip.reason}');
  }
  bytes += generator.hr();
  bytes += generator.row([
    PosColumn(text: slip.user.isEmpty ? '' : 'User: ${slip.user}', width: 6),
    PosColumn(
      text: 'Time: ${timeOf(r['return_date'])}',
      width: 6,
      styles: right,
    ),
  ]);
  bytes += generator.feed(2);
  bytes += generator.cut();
  return bytes;
}
