import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/gst.dart';

/// What a printed bill shows, worked out once for every format — the A4
/// and 80 mm PDFs and the Bluetooth printer — so they always agree.
/// Laid out like a shop's sales invoice: each line with its stock no.,
/// rate, amount, discount and total; the totals; the amount in words; how
/// it was paid; the GST summary by rate; the shop's terms & conditions.

/// One item line. Money is GST-inclusive, as the customer pays it.
class BillLine {
  const BillLine({
    required this.name,
    required this.sku,
    required this.size,
    required this.qty,
    required this.unit,
    required this.rate,
    required this.amount,
    required this.discount,
    required this.total,
    this.isPack = false,
  });

  final String name;

  /// Sold by the pack (0061): [qty] and [rate] are per pack, [unit] the pack.
  final bool isPack;

  /// Stock no. — only when the shop prints it (bill_show_sku).
  final String sku;

  /// Size, colour or other variant ("Free size", "XL").
  final String size;
  final double qty;
  final String unit;
  final double rate;

  /// Quantity × rate, before the line's discount.
  final double amount;
  final double discount;
  final double total;
}

/// One GST rate's share of the bill: the GST summary table.
class GstSummaryRow {
  const GstSummaryRow({
    required this.rate,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });

  final double rate;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;

  double get totalTax => cgst + sgst + igst;
}

class BillLayout {
  BillLayout({
    required this.business,
    required this.invoice,
    required this.items,
    Map<String, dynamic>? exchange,
  }) : exchange = exchange == null ? null : BillExchange(exchange);

  final Map<String, dynamic> business;
  final Map<String, dynamic> invoice;
  final List<Map<String, dynamic>> items;

  /// When this bill was made in an exchange: what came back and how its
  /// credit was used (invoiceExchangeProvider). Null for ordinary bills.
  final BillExchange? exchange;

  bool get isGst => invoice['invoice_type'] == 'gst';
  bool get isEstimate => invoice['invoice_type'] == 'estimate';
  bool get showSku => business['bill_show_sku'] == true;

  /// unit_price is stored before GST on GST bills: the bill shows it with.
  double _incl(Map<String, dynamic> it) =>
      isGst ? 1 + toDouble(it['gst_rate']) / 100 : 1;

  late final List<BillLine> lines = [for (final it in items) _line(it)];

  BillLine _line(Map<String, dynamic> it) {
    final billed = billedQty(it);
    final rate = toDouble(it['unit_price']) * _incl(it) * billed.per;
    final discount = toDouble(it['discount_amount']) * _incl(it);
    final serial = (it['serial_no'] as String? ?? '').trim();
    var name = it['product_name'] as String? ?? '';
    if (serial.isNotEmpty) name = '$name (S/N $serial)';
    // Bulk unit as it was when billed (migration 0052): 100 kg = 2 Bag.
    final factor = toDouble(it['alt_factor']);
    final altUnit = it['alt_unit_name'] as String? ?? '';
    final isPack = it['sold_as_pack'] == true && factor > 0;
    if (isPack) {
      name =
          '$name (1 $altUnit = ${qtyUnit(factor, it['unit_name'] as String?)})';
    } else if (altUnit.isNotEmpty &&
        factor > 0 &&
        toDouble(it['quantity']) >= factor) {
      name = '$name (= ${qty(toDouble(it['quantity']) / factor)} $altUnit)';
    }
    return BillLine(
      name: name,
      isPack: isPack,
      // The variant's own code (KURTA-XL-RED), else the product's.
      sku: showSku
          ? [
              ((it['product_variants'] as Map?)?['sku'] as String? ?? '')
                  .trim(),
              ((it['products'] as Map?)?['sku'] as String? ?? '').trim(),
            ].firstWhere((s) => s.isNotEmpty, orElse: () => '')
          : '',
      size: (it['variant_name'] as String? ?? '').trim(),
      qty: billed.qty,
      unit: billed.unit,
      rate: _r2(rate),
      amount: _r2(billed.qty * rate),
      discount: _r2(discount),
      total: toDouble(it['line_total']),
    );
  }

  double get totalQty => lines.fold(0.0, (s, l) => s + l.qty);
  double get totalAmount => lines.fold(0.0, (s, l) => s + l.amount);
  double get totalLineDiscount => lines.fold(0.0, (s, l) => s + l.discount);
  double get linesTotal => lines.fold(0.0, (s, l) => s + l.total);
  double get billDiscount => toDouble(invoice['discount_amount']);
  double get roundOff => toDouble(invoice['round_off']);
  double get netAmount => toDouble(invoice['total']);

  /// "Rupees Three Thousand Five Hundred Eighty-Six Only".
  String get amountInWords => rupeesInWords(netAmount);

  /// How it was paid: each payment row (an exchange's credit by name),
  /// and whatever of the paid amount has no row, by the bill's mode.
  List<(String, double)> get payments {
    if (isEstimate) return const [];
    final rows = List<Map<String, dynamic>>.from(
      invoice['invoice_payments'] as List? ?? const [],
    );
    final paid = toDouble(invoice['paid_amount']);
    final inRows = rows.fold(0.0, (s, p) => s + toDouble(p['amount']));
    final list = [
      for (final p in rows)
        (
          p['sale_return_id'] != null ||
                  '${p['note'] ?? ''}'.startsWith('Exchange credit')
              ? 'Exchange credit'
              : paymentModeLabel(p['payment_mode']),
          toDouble(p['amount']),
        ),
      if (paid - inRows > 0.005)
        (paymentModeLabel(invoice['payment_mode']), _r2(paid - inRows)),
    ];
    final credit = toDouble(invoice['credit_amount']);
    return [...list, if (credit > 0) ('Credit note', credit)];
  }

  double get due => isEstimate ? 0 : toDouble(invoice['due_amount']);

  /// GST by rate, from each line's stored split (after any bill discount,
  /// migration 0040). Only for GST bills that charged GST.
  List<GstSummaryRow> get gstSummary =>
      isGst ? gstSummaryRows(items) : const [];

  bool get gstIsInterState => gstSummary.any((r) => r.igst != 0);

  /// The shop's terms & conditions, one per line, blank lines dropped.
  List<String> get terms => billTerms(business['bill_terms'] as String?);

  String get footer => (business['bill_footer'] as String? ?? '').trim();
}

/// GST by rate, from each line's stored split (after any bill discount,
/// migration 0040): bill lines or return lines alike. Lines at 0% are left
/// out, so a bill without GST gives no rows.
List<GstSummaryRow> gstSummaryRows(List<Map<String, dynamic>> lines) {
  final byRate = <double, List<Map<String, dynamic>>>{};
  for (final it in lines) {
    final rate = toDouble(it['gst_rate']);
    if (rate > 0) (byRate[rate] ??= []).add(it);
  }
  final rates = byRate.keys.toList()..sort();
  return [
    for (final r in rates)
      () {
        final split = gstSplit(byRate[r]!);
        return GstSummaryRow(
          rate: r,
          taxable: gstTaxableTotal(byRate[r]!),
          cgst: split.cgst,
          sgst: split.sgst,
          igst: split.igst,
        );
      }(),
  ];
}

/// The exchange a bill was made in, for printing on it: the bill and
/// return it came from, what came back, and where the credit went.
class BillExchange {
  BillExchange(Map<String, dynamic> row)
    : _result = Map<String, dynamic>.from(row['result'] as Map? ?? const {}),
      originalNo = ((row['original'] as Map?)?['invoice_no'] as String?) ?? '',
      returnNo = ((row['sale_returns'] as Map?)?['return_no'] as String?) ?? '',
      returned = [
        for (final it
            in (row['sale_returns'] as Map?)?['sale_return_items'] as List? ??
                const [])
          (
            [
              it['product_name'] as String? ?? '',
              if (((it['invoice_items'] as Map?)?['variant_name'] as String? ??
                      '')
                  .trim()
                  .isNotEmpty)
                '(${(it['invoice_items'] as Map)['variant_name']})',
            ].join(' '),
            toDouble(it['quantity']),
            toDouble(it['line_total']),
          ),
      ];

  final Map<String, dynamic> _result;
  final String originalNo;
  final String returnNo;

  /// (name, quantity, value back) per returned line.
  final List<(String, double, double)> returned;

  double get returnValue => toDouble(_result['return_value']);
  double get clearedOldBill => toDouble(_result['applied_to_original']);
  double get usedHere => toDouble(_result['credit_used']);
  double get refunded => toDouble(_result['refund']);
  double get keptAsAdvance => toDouble(_result['advance']);

  /// The money rows under the returned items.
  List<(String, double)> get rows => [
    ('Return value', returnValue),
    if (clearedOldBill > 0.005) ('Cleared old bill dues', clearedOldBill),
    ('Used on this bill', usedHere),
    if (refunded > 0.005) ('Given back', refunded),
    if (keptAsAdvance > 0.005) ('Kept as advance', keptAsAdvance),
  ];
}

List<String> billTerms(String? text) => [
  for (final l in (text ?? '').split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

String paymentModeLabel(Object? mode) => switch (mode) {
  'cash' => 'Cash',
  'upi' => 'UPI',
  'card' => 'Card',
  'bank' || 'bank_transfer' => 'Bank',
  'cheque' => 'Cheque',
  'credit' => 'Credit',
  'advance' => 'Advance',
  null || '' => 'Paid',
  _ => '${mode.toString()[0].toUpperCase()}${mode.toString().substring(1)}',
};

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Money without the ₹ sign, Indian grouping: 3,490.00.
String billMoney(num v) => _plain.format(v);
final _plain = NumberFormat('#,##,##0.00', 'en_IN');

// ---------------- amount in words (Indian system) ----------------

const _ones = [
  '',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];
const _tens = [
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];

String _below100(int n) {
  if (n < 20) return _ones[n];
  final t = _tens[n ~/ 10];
  return n % 10 == 0 ? t : '$t-${_ones[n % 10]}';
}

String _below1000(int n) {
  final parts = <String>[];
  if (n >= 100) parts.add('${_ones[n ~/ 100]} Hundred');
  if (n % 100 != 0) parts.add(_below100(n % 100));
  return parts.join(' ');
}

/// Whole number in words, lakh and crore: 1,25,000 → "One Lakh Twenty-Five
/// Thousand".
String numberInWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${numberInWords(crore)} Crore');
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (n > 0) parts.add(_below1000(n));
  return parts.join(' ');
}

/// "Rupees Three Thousand Five Hundred Eighty-Six Only", with paise when
/// there are any.
String rupeesInWords(num amount) {
  final paiseTotal = (amount.abs() * 100).round();
  final rupees = paiseTotal ~/ 100;
  final paise = paiseTotal % 100;
  final b = StringBuffer(amount < 0 ? 'Minus Rupees ' : 'Rupees ')
    ..write(numberInWords(rupees));
  if (paise > 0) b.write(' and ${_below100(paise)} Paise');
  b.write(' Only');
  return b.toString();
}

// ---------------- the shop's logo ----------------

final _logoCache = <String, Uint8List>{};

/// The shop's logo for printing, or null without one (or offline). Kept
/// for the session so each print doesn't download it again.
Future<Uint8List?> loadBillLogo(Map<String, dynamic> business) async {
  final url = (business['logo_url'] as String? ?? '').trim();
  if (url.isEmpty) return null;
  final cached = _logoCache[url];
  if (cached != null) return cached;
  try {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    return _logoCache[url] = res.bodyBytes;
  } catch (_) {
    return null;
  }
}
