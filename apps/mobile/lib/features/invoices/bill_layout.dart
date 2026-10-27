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
    this.publisher = '',
    this.author = '',
    this.cardDiscount = 0,
  });

  final String name;

  /// Book details (0094), printed as columns when any line has them.
  final String publisher;
  final String author;

  /// The discount card's part of this line, when the bill shows it on its
  /// own row ([BillLayout.cardSplit]); [discount] is then the line's own
  /// (regular) discount and [total] is before the card.
  final double cardDiscount;

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

  late final List<BillLine> lines = _splitCard([
    for (final it in items) _line(it),
  ]);

  /// The card's % on this bill (0083).
  double get _cardPct => toDouble(invoice['discount_card_pct']);

  /// The card type as it is now, when the bill was loaded with it.
  Map? get _cardType =>
      (invoice['discount_cards'] as Map?)?['discount_card_types'] as Map?;

  /// Whether the card covered this item: stock items only, and the
  /// categories its type names.
  bool _cardCovers(Map<String, dynamic> it) {
    if ((it['product_id'] as String? ?? '').isEmpty) return false;
    final type = _cardType;
    if (type == null) return true;
    final cats = {
      for (final c in (type['category_ids'] as List? ?? const [])) '$c',
    };
    final cat = (it['products'] as Map?)?['category_id'] as String?;
    return switch (type['applies_to']) {
      'only' => cats.contains(cat),
      'except' => !cats.contains(cat),
      _ => true,
    };
  }

  /// True when each line's card part could be told apart from its own
  /// discount, so the bill prints the regular discount in the lines and
  /// "Less card discount" below the total (0094).
  bool get cardSplit {
    lines; // worked out with the lines
    return _cardSplit;
  }

  bool _cardSplit = false;

  /// The card took its % of what was left after the line's own discount,
  /// so its part is (amount - discount) x pct / (100 - pct).
  List<BillLine> _splitCard(List<BillLine> raw) {
    final pct = _cardPct;
    if (pct <= 0 || pct >= 100 || raw.length != items.length) return raw;
    final parts = [
      for (var i = 0; i < raw.length; i++)
        () {
          if (!_cardCovers(items[i])) return 0.0;
          final part = _r2(
            (raw[i].amount - raw[i].discount) * pct / (100 - pct),
          );
          // More than the line's whole discount: the card wasn't used on
          // it (an item it didn't cover when billed).
          return part < 0 || part > raw[i].discount + 0.01 ? 0.0 : part;
        }(),
    ];
    final sum = parts.fold(0.0, (s, v) => s + v);
    if (sum <= 0) return raw;
    // Without the card type to go by, every item was taken as covered:
    // only trust that when it adds up to what the bill recorded.
    if (_cardType == null &&
        (sum - cardAmount).abs() > (cardAmount * 0.02).clamp(1, 1e9)) {
      return raw;
    }
    _cardSplit = true;
    return [
      for (var i = 0; i < raw.length; i++)
        parts[i] == 0
            ? raw[i]
            : BillLine(
                name: raw[i].name,
                isPack: raw[i].isPack,
                sku: raw[i].sku,
                size: raw[i].size,
                qty: raw[i].qty,
                unit: raw[i].unit,
                rate: raw[i].rate,
                amount: raw[i].amount,
                discount: _r2(raw[i].discount - parts[i]),
                total: _r2(raw[i].total + parts[i]),
                publisher: raw[i].publisher,
                author: raw[i].author,
                cardDiscount: parts[i],
              ),
    ];
  }

  /// The card's whole part, when printed on its own row.
  double get cardSplitAmount => lines.fold(0.0, (s, l) => s + l.cardDiscount);

  /// Publisher / Author columns: only when some line has them.
  bool get anyPublisher => lines.any((l) => l.publisher.isNotEmpty);
  bool get anyAuthor => lines.any((l) => l.author.isNotEmpty);

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
      publisher: ((it['products'] as Map?)?['publisher'] as String? ?? '')
          .trim(),
      author: ((it['products'] as Map?)?['author'] as String? ?? '').trim(),
    );
  }

  double get totalQty => lines.fold(0.0, (s, l) => s + l.qty);
  double get totalAmount => lines.fold(0.0, (s, l) => s + l.amount);
  double get totalLineDiscount => lines.fold(0.0, (s, l) => s + l.discount);
  double get linesTotal => lines.fold(0.0, (s, l) => s + l.total);

  /// The typed bill discount. An offer's part is printed on its own line
  /// ([offerLine], 0084), so it isn't counted here as well.
  double get billDiscount =>
      toDouble(invoice['discount_amount']) - toDouble(invoice['offer_amount']);
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

  /// What comes off (or is added to) the items' total, in order, down to
  /// the net amount: the card's part when printed on its own row, the
  /// offer / coupon, the typed bill discount and the round-off.
  List<(String, double)> get adjustments => [
    if (cardSplit && cardSplitAmount > 0)
      (
        'Less card discount'
            '${_cardTypeName.isEmpty ? '' : ' ($_cardTypeName ${qty(_cardPct)}%)'}',
        -cardSplitAmount,
      ),
    if (offerAmount > 0) (offerTotalLabel, -offerAmount),
    if (billDiscount > 0.005) ('Bill discount', -billDiscount),
    if (roundOff != 0) ('Round off', roundOff),
  ];

  String get _cardTypeName =>
      (invoice['discount_card_type'] as String? ?? '').trim();

  /// "Less coupon SC-0001" / "Less offer: Diwali 10%".
  String get offerTotalLabel {
    final name = (invoice['offer_name'] as String? ?? '').trim();
    final code = (invoice['offer_code'] as String? ?? '').trim();
    if (code.isNotEmpty) return 'Less coupon $code';
    return name.isEmpty ? 'Less offer' : 'Less offer: $name';
  }

  /// The card's number by the customer's name: "Gold card: 2017 1234".
  String get cardTopLine {
    final no = (invoice['discount_card_no'] as String? ?? '').trim();
    if (no.isEmpty) return '';
    return '${_cardTypeName.isEmpty ? 'Discount' : _cardTypeName} card: $no';
  }

  /// What the customer saved: the MRP (or the rate, when higher) of every
  /// line against what they pay. 0 when nothing was saved.
  double get youSaved {
    var full = 0.0;
    for (var i = 0; i < items.length && i < lines.length; i++) {
      final mrp = toDouble(items[i]['mrp']) * toDouble(items[i]['quantity']);
      full += mrp > lines[i].amount ? mrp : lines[i].amount;
    }
    final saved = _r2(full - netAmount);
    return saved >= 1 ? saved : 0;
  }

  /// The discount card on the bill (0083): "Gold card 2017 1234 1234 4109
  /// (10% off)", or '' when none. Its discount is already in the lines.
  String get cardLine {
    final no = (invoice['discount_card_no'] as String? ?? '').trim();
    if (no.isEmpty) return '';
    final type = (invoice['discount_card_type'] as String? ?? '').trim();
    final pct = toDouble(invoice['discount_card_pct']);
    return '${type.isEmpty ? 'Discount' : type} card $no'
        '${pct > 0 ? ' (${qty(pct)}% off)' : ''}';
  }

  /// What the card took off the bill.
  double get cardAmount => toDouble(invoice['discount_card_amount']);

  /// The offer on the bill (0084): "Scratch & Win (SC-0001)", or '' when
  /// none. Its amount is part of the bill discount.
  String get offerLine {
    final name = (invoice['offer_name'] as String? ?? '').trim();
    if (name.isEmpty || offerAmount <= 0) return '';
    final code = (invoice['offer_code'] as String? ?? '').trim();
    return code.isEmpty ? 'Offer: $name' : 'Offer: $name ($code)';
  }

  double get offerAmount => toDouble(invoice['offer_amount']);

  /// GST by rate, from each line's stored split (after any bill discount,
  /// migration 0040). Only for GST bills that charged GST.
  List<GstSummaryRow> get gstSummary =>
      isGst ? gstSummaryRows(items) : const [];

  bool get gstIsInterState => gstSummary.any((r) => r.igst != 0);

  /// The shop's terms & conditions, one per line, blank lines dropped.
  List<String> get terms => billTerms(business['bill_terms'] as String?);

  /// The note at the bottom of the bill, line by line (migration 0093).
  List<BillNoteLine> get footer =>
      billNoteLines(business['bill_footer'] as String?);
}

/// One line of the bill's bottom note; a line written between *stars*
/// prints in bold.
typedef BillNoteLine = ({String text, bool bold});

List<BillNoteLine> billNoteLines(String? text) => [
  for (final raw in (text ?? '').split('\n'))
    if (raw.trim().isNotEmpty)
      () {
        final l = raw.trim();
        final starred = l.length > 2 && l.startsWith('*') && l.endsWith('*');
        return (
          text: starred ? l.substring(1, l.length - 1).trim() : l,
          bold: starred,
        );
      }(),
];

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
