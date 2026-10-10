/// Reading a supplier's bill: the words on its pages (from a PDF, or the
/// cells of an Excel/CSV sheet) → the bill number, date, supplier GSTIN,
/// total, and one line per item with its quantity, rate, discount and GST.
///
/// Bills come from Tally, Busy, Marg, Vyapar and many others, each laid out
/// its own way, so nothing here depends on one layout:
///  * the item table is found by its header row ("Description", "Qty",
///    "Rate", "Amount"…), and every column of the table is where its header
///    is — the numbers under "Qty" are the quantities;
///  * a line is trusted when its own numbers agree (qty × rate − discount =
///    amount); otherwise it's marked for the shop to check;
///  * a bill with no header the reader knows falls back to rows that hold
///    a quantity, a rate and an amount that multiply up.
///
/// Kept apart from the screens and from PDF reading so it's tested on its
/// own.
library;

import 'dart:math' as math;

/// A word on a bill page, placed in points from the page's top-left corner.
/// A sheet's cells are laid out as words on a grid, so sheets and PDFs are
/// read the same way.
class BillWord {
  const BillWord(
    this.text,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.page = 0,
  });

  final String text;
  final double left, top, right, bottom;
  final int page;

  double get height => bottom - top;
  double get midX => (left + right) / 2;
  double get midY => (top + bottom) / 2;

  @override
  String toString() => '"$text"@${left.round()},${top.round()}';
}

/// The words of a sheet (rows of cells) laid out on a grid. [page]: the
/// sheet's place in the workbook (a PDF turned into Excel has a sheet per
/// page).
List<BillWord> sheetWords(List<List<String>> rows, {int page = 0}) => [
  for (var r = 0; r < rows.length; r++)
    for (var c = 0; c < rows[r].length; c++)
      if (rows[r][c].trim().isNotEmpty)
        BillWord(
          rows[r][c].trim(),
          c * 100.0,
          r * 20.0,
          c * 100.0 + 90,
          r * 20.0 + 10,
          page: page,
        ),
];

/// One line of words across a page, left to right.
class BillRow {
  BillRow(this.page, this.words);

  final int page;
  final List<BillWord> words;

  double get top => words.map((w) => w.top).reduce(math.min);
  double get bottom => words.map((w) => w.bottom).reduce(math.max);
  double get height => bottom - top;
  String get text => words.map((w) => w.text).join(' ');
}

/// Words → rows: words whose heights overlap by at least half sit on one
/// row. Pages stay apart and in order.
List<BillRow> billRows(List<BillWord> words) {
  final pages = <int, List<BillWord>>{};
  for (final w in words) {
    if (w.text.trim().isEmpty) continue;
    pages.putIfAbsent(w.page, () => []).add(w);
  }
  final out = <BillRow>[];
  for (final page in pages.keys.toList()..sort()) {
    final list = pages[page]!..sort((a, b) => a.midY.compareTo(b.midY));
    final rows = <List<BillWord>>[];
    double top = 0, bottom = 0;
    for (final w in list) {
      if (rows.isNotEmpty) {
        final overlap = math.min(bottom, w.bottom) - math.max(top, w.top);
        final smaller = math.max(0.1, math.min(bottom - top, w.bottom - w.top));
        if (overlap >= smaller * 0.5) {
          rows.last.add(w);
          top = math.min(top, w.top);
          bottom = math.max(bottom, w.bottom);
          continue;
        }
      }
      rows.add([w]);
      top = w.top;
      bottom = w.bottom;
    }
    for (final r in rows) {
      out.add(BillRow(page, r..sort((a, b) => a.left.compareTo(b.left))));
    }
  }
  return out;
}

/// Words that sit close together (a space apart, not a column apart).
class BillPhrase {
  BillPhrase(this.words);

  final List<BillWord> words;

  double get left => words.first.left;
  double get right => words.last.right;
  String get text => words.map((w) => w.text).join(' ');
}

List<BillPhrase> billPhrases(BillRow row) {
  final out = <BillPhrase>[];
  for (final w in row.words) {
    if (out.isNotEmpty) {
      final last = out.last.words.last;
      final gap = w.left - last.right;
      final h = math.min(last.height, w.height);
      if (gap < h * 0.45) {
        out.last.words.add(w);
        continue;
      }
    }
    out.add(BillPhrase([w]));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Columns
// ---------------------------------------------------------------------------

/// What a column of the item table holds.
enum BillCol {
  sno,
  name,
  code,
  hsn,
  qty,
  free,
  unit,
  rate,
  rateIncl,
  mrp,
  disc,
  discAmt,
  taxable,
  gst,
  gstPart,
  taxAmt,
  amount,
  ignore,
}

/// Header words → the column they head. Lower case, dots dropped, other
/// punctuation turned into spaces, "%" kept as its own word.
const Map<String, BillCol> _keywords = {
  'sl no': BillCol.sno,
  's no': BillCol.sno,
  'sr no': BillCol.sno,
  'sno': BillCol.sno,
  'sn': BillCol.sno,
  'slno': BillCol.sno,
  'srno': BillCol.sno,
  'sl': BillCol.sno,
  'sr': BillCol.sno,
  '#': BillCol.sno,
  'no': BillCol.sno,
  'item code': BillCol.code,
  'product code': BillCol.code,
  'part no': BillCol.code,
  'code': BillCol.code,
  'barcode': BillCol.code,
  'ean': BillCol.code,
  'sku': BillCol.code,
  'description of goods and services': BillCol.name,
  'description of goods': BillCol.name,
  'description of services': BillCol.name,
  'product description': BillCol.name,
  'item description': BillCol.name,
  'description': BillCol.name,
  'particulars': BillCol.name,
  'particular': BillCol.name,
  'item name': BillCol.name,
  'product name': BillCol.name,
  'name of product': BillCol.name,
  'name of item': BillCol.name,
  'item': BillCol.name,
  'items': BillCol.name,
  'product': BillCol.name,
  'products': BillCol.name,
  'goods': BillCol.name,
  'material': BillCol.name,
  'name': BillCol.name,
  'hsn sac code': BillCol.hsn,
  'hsn sac': BillCol.hsn,
  'hsn code': BillCol.hsn,
  'hsn': BillCol.hsn,
  'sac': BillCol.hsn,
  'batch no': BillCol.ignore,
  'batch': BillCol.ignore,
  'exp date': BillCol.ignore,
  'expiry': BillCol.ignore,
  'exp': BillCol.ignore,
  'mfg': BillCol.ignore,
  'pack': BillCol.ignore,
  'packing': BillCol.ignore,
  'mrp': BillCol.mrp,
  'billed qty': BillCol.qty,
  'bill qty': BillCol.qty,
  'shipped qty': BillCol.qty,
  'quantity': BillCol.qty,
  'qty': BillCol.qty,
  'free qty': BillCol.free,
  'scheme qty': BillCol.free,
  'sch qty': BillCol.free,
  'fr qty': BillCol.free,
  'free': BillCol.free,
  'uom': BillCol.unit,
  'unit': BillCol.unit,
  'units': BillCol.unit,
  'per': BillCol.unit,
  'rate incl of tax': BillCol.rateIncl,
  'rate inclusive of tax': BillCol.rateIncl,
  'rate incl tax': BillCol.rateIncl,
  'rate incl gst': BillCol.rateIncl,
  'price incl tax': BillCol.rateIncl,
  'rate per unit': BillCol.rate,
  'price per unit': BillCol.rate,
  'price unit': BillCol.rate,
  'unit price': BillCol.rate,
  'basic rate': BillCol.rate,
  'purchase rate': BillCol.rate,
  'pur rate': BillCol.rate,
  'p rate': BillCol.rate,
  'net rate': BillCol.rate,
  'rate': BillCol.rate,
  'price': BillCol.rate,
  'disc amt': BillCol.discAmt,
  'disc amount': BillCol.discAmt,
  'discount amount': BillCol.discAmt,
  'discount amt': BillCol.discAmt,
  'dis amt': BillCol.discAmt,
  'sch amt': BillCol.discAmt,
  'discount %': BillCol.disc,
  'disc %': BillCol.disc,
  'dis %': BillCol.disc,
  'cd %': BillCol.disc,
  'sch %': BillCol.disc,
  'scheme %': BillCol.disc,
  'td %': BillCol.disc,
  'discount': BillCol.disc,
  'disc': BillCol.disc,
  'dis': BillCol.disc,
  'cd': BillCol.disc,
  'taxable value': BillCol.taxable,
  'taxable amount': BillCol.taxable,
  'taxable amt': BillCol.taxable,
  'taxable val': BillCol.taxable,
  'assessable value': BillCol.taxable,
  'taxable': BillCol.taxable,
  'gst %': BillCol.gst,
  'gst rate': BillCol.gst,
  'tax %': BillCol.gst,
  'tax rate': BillCol.gst,
  'igst %': BillCol.gst,
  'igst rate': BillCol.gst,
  'gst': BillCol.gst,
  'igst': BillCol.gst,
  'cgst %': BillCol.gstPart,
  'sgst %': BillCol.gstPart,
  'utgst %': BillCol.gstPart,
  'cgst rate': BillCol.gstPart,
  'sgst rate': BillCol.gstPart,
  'utgst rate': BillCol.gstPart,
  'cgst': BillCol.gstPart,
  'sgst': BillCol.gstPart,
  'utgst': BillCol.gstPart,
  'cgst amt': BillCol.taxAmt,
  'cgst amount': BillCol.taxAmt,
  'sgst amt': BillCol.taxAmt,
  'sgst amount': BillCol.taxAmt,
  'utgst amt': BillCol.taxAmt,
  'utgst amount': BillCol.taxAmt,
  'igst amt': BillCol.taxAmt,
  'igst amount': BillCol.taxAmt,
  'gst amt': BillCol.taxAmt,
  'gst amount': BillCol.taxAmt,
  'tax amt': BillCol.taxAmt,
  'tax amount': BillCol.taxAmt,
  'tax': BillCol.taxAmt,
  'net amount': BillCol.amount,
  'net amt': BillCol.amount,
  'net value': BillCol.amount,
  'total amount': BillCol.amount,
  'total value': BillCol.amount,
  'line total': BillCol.amount,
  'amount rs': BillCol.amount,
  'amount inr': BillCol.amount,
  'amount': BillCol.amount,
  'amt': BillCol.amount,
  'total': BillCol.amount,
  'value': BillCol.amount,
};

final int _longestKeyword = _keywords.keys
    .map((k) => k.split(' ').length)
    .reduce(math.max);

/// A header's text as the keywords are written: "Disc.%" → "disc %",
/// "HSN/SAC" → "hsn sac", "Amount(₹)" → "amount".
String normalizeHeader(String s) => s
    .toLowerCase()
    .replaceAll('.', '')
    .replaceAll('₹', ' ')
    .replaceAll('%', ' % ')
    .replaceAll(RegExp(r'[^a-z0-9%#]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// The column a header's words name, or null. "Description of Goods" →
/// name; "CGST Rate" → part of GST.
BillCol? columnFor(String header) {
  final n = normalizeHeader(header);
  if (n.isEmpty) return null;
  final exact = _keywords[n];
  if (exact != null) return exact;
  // The longest run of words that is a keyword ("Rate (Rs.)" → rate).
  final words = n.split(' ');
  for (var len = math.min(_longestKeyword, words.length); len > 0; len--) {
    for (var i = 0; i + len <= words.length; i++) {
      final k = _keywords[words.sublist(i, i + len).join(' ')];
      if (k != null) return k;
    }
  }
  return null;
}

/// One column of the item table: where it is and what it holds.
class BillColumn {
  BillColumn(this.label, this.left, this.right, this.role);

  final String label;
  final double left, right;
  BillCol role;

  /// The header as stored in a supplier's remembered layout.
  String get key => normalizeHeader(label);

  @override
  String toString() => '$label=${role.name}';
}

/// The columns a header row (and the row of sub-headers under it, if any)
/// make. [overrides]: columns the shop set for this supplier, by header.
List<BillColumn> _columnsOf(
  BillRow header,
  BillRow? sub,
  Map<String, BillCol> overrides,
) {
  final top = billPhrases(header);
  final cols = <BillColumn>[];
  final subs = sub == null ? const <BillPhrase>[] : billPhrases(sub);
  final childrenOf = <int, List<BillPhrase>>{};
  final orphans = <BillPhrase>[];
  for (final s in subs) {
    var best = -1;
    var bestOverlap = 0.0;
    for (var i = 0; i < top.length; i++) {
      final o = math.min(top[i].right, s.right) - math.max(top[i].left, s.left);
      if (o > bestOverlap) {
        bestOverlap = o;
        best = i;
      }
    }
    if (best < 0) {
      // Under no header word: the nearest one by centre, else on its own.
      final mid = (s.left + s.right) / 2;
      var nearest = double.infinity;
      for (var i = 0; i < top.length; i++) {
        final d = (((top[i].left + top[i].right) / 2) - mid).abs();
        final reach = (top[i].right - top[i].left) / 2 + header.height * 2;
        if (d < nearest && d <= reach) {
          nearest = d;
          best = i;
        }
      }
    }
    if (best < 0) {
      orphans.add(s);
    } else {
      childrenOf.putIfAbsent(best, () => []).add(s);
    }
  }
  for (var i = 0; i < top.length; i++) {
    final p = top[i];
    final kids = childrenOf[i] ?? const [];
    if (kids.length >= 2) {
      // "CGST" over "Rate" and "Amount": a column each.
      for (final k in kids) {
        cols.add(
          BillColumn('${p.text} ${k.text}', k.left, k.right, BillCol.ignore),
        );
      }
    } else if (kids.length == 1) {
      // "Taxable" over "Value": one column.
      cols.add(
        BillColumn(
          '${p.text} ${kids.single.text}',
          math.min(p.left, kids.single.left),
          math.max(p.right, kids.single.right),
          BillCol.ignore,
        ),
      );
    } else {
      cols.addAll(_splitPhrase(p));
    }
  }
  for (final o in orphans) {
    cols.add(BillColumn(o.text, o.left, o.right, BillCol.ignore));
  }
  cols.sort((a, b) => a.left.compareTo(b.left));
  for (final c in cols) {
    c.role = overrides[c.key] ?? columnFor(c.label) ?? BillCol.ignore;
  }
  // A "No" that isn't first is part of something else ("Batch No").
  for (var i = 1; i < cols.length; i++) {
    if (cols[i].role == BillCol.sno && overrides[cols[i].key] == null) {
      cols[i].role = BillCol.ignore;
    }
  }
  return cols;
}

/// A phrase that is two headers set close together ("Qty Rate") becomes
/// two columns; "Description of Goods" stays one.
List<BillColumn> _splitPhrase(BillPhrase p) {
  if (p.words.length < 2 || columnFor(p.text) == null) {
    return [BillColumn(p.text, p.left, p.right, BillCol.ignore)];
  }
  final whole = _keywords[normalizeHeader(p.text)];
  if (whole != null) {
    return [BillColumn(p.text, p.left, p.right, BillCol.ignore)];
  }
  // Group words: each starts a new column where its own words begin a
  // keyword that the words before it don't continue.
  final groups = <List<BillWord>>[];
  var i = 0;
  while (i < p.words.length) {
    var taken = 0;
    for (
      var len = math.min(_longestKeyword, p.words.length - i);
      len > 0;
      len--
    ) {
      final text = p.words.sublist(i, i + len).map((w) => w.text).join(' ');
      if (_keywords.containsKey(normalizeHeader(text))) {
        taken = len;
        break;
      }
    }
    if (taken == 0) {
      // Not a keyword: part of the column before ("Name of Goods").
      if (groups.isEmpty) {
        groups.add([p.words[i]]);
      } else {
        groups.last.add(p.words[i]);
      }
      i++;
    } else {
      groups.add(p.words.sublist(i, i + taken));
      i += taken;
    }
  }
  if (groups.length == 1) {
    return [BillColumn(p.text, p.left, p.right, BillCol.ignore)];
  }
  return [
    for (final g in groups)
      BillColumn(
        g.map((w) => w.text).join(' '),
        g.first.left,
        g.last.right,
        BillCol.ignore,
      ),
  ];
}

bool _hasDigit(String s) => RegExp(r'\d').hasMatch(s);

/// How much a row looks like the item table's header: the kinds of
/// columns it names. A header names the item and its qty or amount.
int _headerScore(BillRow row) {
  if (_hasDigit(row.text.replaceAll(RegExp(r'\d+\s*%'), ''))) {
    // A header has no numbers (a "GST 18%" may be there, but no amounts).
    final digits = RegExp(r'\d').allMatches(row.text).length;
    if (digits > 4) return 0;
  }
  final roles = <BillCol>{};
  for (final p in billPhrases(row)) {
    for (final c in _splitPhrase(p)) {
      final r = columnFor(c.label);
      if (r != null && r != BillCol.ignore && r != BillCol.sno) roles.add(r);
    }
  }
  if (!roles.contains(BillCol.name)) return 0;
  if (!roles.contains(BillCol.qty) && !roles.contains(BillCol.amount)) {
    return 0;
  }
  return roles.length >= 3 ? roles.length : 0;
}

/// The row right under a header that continues it ("Value" under
/// "Taxable", "Rate | Amount" under "CGST"): close, no amounts, header
/// words only.
bool _isSubHeader(BillRow header, BillRow next) {
  if (next.page != header.page) return false;
  if (next.top - header.bottom > header.height * 1.6) return false;
  if (_hasDigit(next.text.replaceAll(RegExp(r'\d+\s*%'), ''))) return false;
  final phrases = billPhrases(next);
  if (phrases.isEmpty) return false;
  var known = 0;
  for (final p in phrases) {
    final n = normalizeHeader(p.text);
    if (n.isEmpty ||
        columnFor(p.text) != null ||
        const {
          '%',
          'rs',
          'inr',
          'of goods',
          'incl of tax',
          'per unit',
        }.contains(n)) {
      known++;
    }
  }
  return known * 2 >= phrases.length;
}

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

/// A money or quantity amount as bills print it: "1,23,456.00", "₹ 550",
/// "Rs. 12.5", "(10.00)". Null when it isn't one.
double? billNumber(String s) {
  var t = s
      .replaceAll('₹', '')
      .replaceAll(RegExp(r'\b(Rs|INR)\.?', caseSensitive: false), '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .trim();
  var negative = false;
  if (t.startsWith('(') && t.endsWith(')')) {
    negative = true;
    t = t.substring(1, t.length - 1);
  }
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  }
  if (!RegExp(r'^\d*\.?\d+$').hasMatch(t)) return null;
  final v = double.tryParse(t);
  if (v == null) return null;
  return negative ? -v : v;
}

/// "10 Pcs" → (10, "Pcs"); "10+2" → qty 10 with 2 free; "12.000" → 12.
({double qty, double free, String unit})? billQty(String s) {
  final t = s.replaceAll(',', '').trim();
  final scheme = RegExp(
    r'^(\d*\.?\d+)\s*\+\s*(\d*\.?\d+)\s*([A-Za-z]*)$',
  ).firstMatch(t);
  if (scheme != null) {
    return (
      qty: double.parse(scheme.group(1)!),
      free: double.parse(scheme.group(2)!),
      unit: scheme.group(3) ?? '',
    );
  }
  final m = RegExp(r'^(\d*\.?\d+)\s*([A-Za-z][A-Za-z.]{0,9})?$').firstMatch(t);
  if (m == null) return null;
  return (
    qty: double.parse(m.group(1)!),
    free: 0,
    unit: (m.group(2) ?? '').replaceAll('.', ''),
  );
}

/// A cell that may be a percentage or an amount — "5%", "₹ 10 (5%)",
/// "10.00" — as (percent, amount).
({double? pct, double? amt}) _pctOrAmount(String s) {
  final pct = RegExp(r'(\d*\.?\d+)\s*%').firstMatch(s);
  final rest = s.replaceAll(RegExp(r'\(?\s*\d*\.?\d+\s*%\s*\)?'), ' ').trim();
  return (
    pct: pct == null ? null : double.parse(pct.group(1)!),
    amt: rest.isEmpty ? null : billNumber(rest),
  );
}

const gstSlabs = [
  0.0,
  0.1,
  0.25,
  1.0,
  1.5,
  3.0,
  5.0,
  6.0,
  12.0,
  18.0,
  28.0,
  40.0,
];

/// The GST slab nearest [rate] when it is close to one (a rate worked out
/// from amounts: 17.98 → 18).
double? nearestSlab(double rate) {
  for (final s in gstSlabs) {
    if ((s - rate).abs() <= math.max(0.3, s * 0.03)) return s;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Lines
// ---------------------------------------------------------------------------

/// One item line as printed on the bill, and what it comes to.
class BillLine {
  BillLine({
    required this.name,
    this.code = '',
    this.hsn = '',
    required this.qty,
    this.free = 0,
    this.unit = '',
    this.rate,
    this.rateIncl,
    this.mrp,
    this.discPct,
    this.discAmt,
    this.taxable,
    this.gstRate,
    this.taxAmt,
    this.amount,
    this.fromHeader = true,
  });

  String name;
  final String code;
  final String hsn;
  final double qty;
  final double free;
  final String unit;
  final double? rate;
  final double? rateIncl;
  final double? mrp;
  final double? discPct;
  final double? discAmt;
  final double? taxable;

  /// GST % printed on the line; null when the bill has no GST column (the
  /// product's own rate is used then).
  double? gstRate;
  final double? taxAmt;
  final double? amount;

  /// Read from a known table header (false: guessed from the numbers).
  final bool fromHeader;

  /// IMEI / serial numbers printed under the item.
  final List<String> serials = [];

  /// Set by [resolve]: the value before GST, and whether the line's own
  /// numbers agree with each other.
  double value = 0;
  bool agrees = false;

  /// Units that come in: billed and free.
  double get stockQty => qty + free;

  /// Cost of one unit before GST, the free ones counted in.
  double get unitCost => stockQty > 0 ? value / stockQty : 0;

  /// Works out [value] (before GST) from what the bill printed, and checks
  /// the line: qty × rate less discount should come to its taxable value,
  /// or its amount with or without GST.
  void resolve() {
    _resolve();
    value = (value * 100).roundToDouble() / 100; // to the paisa
  }

  void _resolve() {
    final g = gstRate;
    final r =
        rate ??
        (rateIncl != null && g != null ? rateIncl! / (1 + g / 100) : null);
    final gross = r == null ? null : qty * r;
    // Expected value after discount; a bare "Disc" may be % or ₹.
    final expected = <double>[];
    if (gross != null) {
      if (discPct != null) {
        expected.add(gross * (1 - discPct! / 100) - (discAmt ?? 0));
      } else if (discAmt != null) {
        expected.add(gross - discAmt!);
      } else {
        expected.add(gross);
      }
    }
    bool near(double a, double b) =>
        (a - b).abs() <= math.max(1.0, b.abs() * 0.01);

    if (taxable != null) {
      value = taxable!;
      agrees = expected.isEmpty || expected.any((e) => near(e, value));
      if (expected.isEmpty && amount != null && g != null) {
        agrees = near(value * (1 + g / 100), amount!) || near(value, amount!);
      }
      return;
    }
    if (amount != null) {
      final a = amount!;
      final candidates = <double>[a];
      if (g != null && g > 0) candidates.add(a / (1 + g / 100));
      if (taxAmt != null && taxAmt! > 0) candidates.add(a - taxAmt!);
      if (expected.isEmpty) {
        value = a;
        agrees = false;
        return;
      }
      double? best;
      var bestDiff = double.infinity;
      for (final c in candidates) {
        for (final e in expected) {
          final d = (c - e).abs();
          if (d < bestDiff) {
            bestDiff = d;
            best = c;
          }
        }
      }
      value = best ?? a;
      agrees = expected.any((e) => near(e, value));
      return;
    }
    value = expected.isEmpty ? 0 : expected.first;
    agrees = expected.isNotEmpty;
  }
}

/// What was read from a bill.
class ParsedBill {
  ParsedBill({
    required this.lines,
    required this.columns,
    this.billNo = '',
    this.date,
    this.gstins = const [],
    this.supplierName = '',
    this.total,
    this.foundHeader = true,
  });

  final List<BillLine> lines;

  /// The item table's columns as read (empty when no header was found).
  final List<BillColumn> columns;
  final String billNo;
  final DateTime? date;

  /// GSTINs on the bill, in order (the supplier's usually first).
  final List<String> gstins;

  /// The biggest name at the top of the bill: usually the supplier.
  final String supplierName;

  /// The bill's grand total, if printed.
  final double? total;

  /// The item table's header was found (false: lines were guessed).
  final bool foundHeader;
}

final _stopRow = RegExp(
  r'^(sub\s*total|total|grand\s*total|net\s*total|taxable\s*value|amount\s*chargeable|'
  r'amount\s*in\s*words|rupees|bank\s*details|declaration|e\s*&\s*o\s*e|'
  r'terms|continued)',
  caseSensitive: false,
);

/// "Continued to page 2": the table goes on, the bill isn't over.
final _continued = RegExp(r'^continued', caseSensitive: false);

/// The table's own total line ("Total", "Grand Total").
final _totalRow = RegExp(r'^(grand\s*)?total\b', caseSensitive: false);

/// IMEI / serial numbers on a line of their own under an item:
/// "350846584550521", "IMEI: 3508…, 3508…", "S/N AB12345678".
List<String>? _serialsIn(String text) {
  final t = text.replaceFirst(
    RegExp(
      r'^(imei|serial|s\s*/\s*n|sr\.?\s*no|s\.?\s*no)\s*(no|nos|number|numbers)?\.?\s*[:\-]?\s*',
      caseSensitive: false,
    ),
    '',
  );
  final parts = t.split(RegExp(r'[,;\s]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  for (final p in parts) {
    if (!RegExp(r'^[A-Za-z0-9\-/]{6,24}$').hasMatch(p)) return null;
    if (RegExp(r'\d').allMatches(p).length < 6) return null;
  }
  return parts;
}

final _notName = RegExp(
  r'^(batch|exp|expiry|mfg|imei|serial|s\s*no|sl\s*no|output|input|cgst|sgst|igst|'
  r'less|add|round|freight|discount|cess)\b',
  caseSensitive: false,
);

/// Reads a bill from its words. [ownGstin]: the shop's own GSTIN (not the
/// supplier's). [overrides]: column roles the shop chose for this supplier
/// (header key → role).
ParsedBill parseBill(
  List<BillWord> words, {
  String ownGstin = '',
  Map<String, BillCol> overrides = const {},
}) {
  final rows = billRows(words);
  // A bill printed in copies (original, duplicate for transporter,
  // triplicate) has its table again after its total: each table after a
  // finished one is a segment, and a segment the same as one before is a
  // copy.
  final segments = <List<BillLine>>[[]];
  var finished = false;
  double? tableTotal;
  int? firstHeader;
  List<BillColumn> columns = const [];
  var foundHeader = false;

  // Each page's table: under its header (or the last page's header when a
  // page goes straight on), until the totals.
  int? lastPage;
  var inTable = false;
  var tableEnded = false;
  BillRow? lastItemRow;
  var continuations = 0;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.page != lastPage) {
      lastPage = row.page;
      inTable = foundHeader && !tableEnded;
      tableEnded = false;
      lastItemRow = null;
    }
    if (_headerScore(row) > 0) {
      final sub = i + 1 < rows.length && _isSubHeader(row, rows[i + 1])
          ? rows[i + 1]
          : null;
      columns = _columnsOf(row, sub, overrides);
      firstHeader ??= i;
      if (finished && segments.last.isNotEmpty) segments.add([]);
      finished = false;
      foundHeader = true;
      inTable = true;
      tableEnded = false;
      lastItemRow = null;
      if (sub != null) i++;
      continue;
    }
    if (!inTable) continue;
    final cells = _cellsOf(row, columns);
    final nameText = (cells[BillCol.name] ?? '').trim();
    final firstText = row.words.first.text;
    final stopText = nameText.isEmpty ? firstText : nameText;
    if (_stopRow.hasMatch(stopText)) {
      inTable = false;
      tableEnded = true;
      if (!_continued.hasMatch(stopText)) {
        finished = true;
        if (tableTotal == null && _totalRow.hasMatch(stopText)) {
          tableTotal = _lastNumber(row);
        }
      }
      continue;
    }
    final line = _lineOf(cells);
    if (line != null) {
      segments.last.add(line);
      lastItemRow = row;
      continuations = 0;
      continue;
    }
    final last = segments.last.isEmpty ? null : segments.last.last;
    if (last == null ||
        lastItemRow == null ||
        nameText.isEmpty ||
        _numbersIn(cells) ||
        row.top - lastItemRow.bottom >= lastItemRow.height * 1.2) {
      continue;
    }
    // IMEI / serial numbers under the item: kept as its serials.
    final serials = _serialsIn(nameText);
    if (serials != null) {
      last.serials.addAll(serials);
      lastItemRow = row;
      continue;
    }
    // A name running on to the next line, with no numbers of its own.
    if (continuations < 2 && !_notName.hasMatch(nameText)) {
      last.name = '${last.name} $nameText';
      lastItemRow = row;
      continuations++;
    }
  }

  final lines = <BillLine>[];
  final seen = <String>{};
  for (final seg in segments) {
    final key = seg
        .map((l) => '${l.name}|${l.qty}|${l.rate}|${l.amount}|${l.taxable}')
        .join('\n');
    if (seg.isEmpty || !seen.add(key)) continue;
    lines.addAll(seg);
  }

  if (!foundHeader || lines.isEmpty) {
    final guessed = _guessLines(rows);
    if (guessed.isNotEmpty) {
      lines
        ..clear()
        ..addAll(guessed);
      foundHeader = false;
    }
  }
  for (final l in lines) {
    l.resolve();
  }
  final total = _totalOf(rows, tableTotal);
  _impliedGst(lines, total);

  // The bill's details are above its item table (on a sheet of their
  // own, sometimes), else on its first page.
  final head = firstHeader != null && firstHeader > 0
      ? rows.sublist(0, firstHeader)
      : rows
            .where((r) => r.page == (rows.isEmpty ? 0 : rows.first.page))
            .toList();
  final gstins = _gstinsOf(rows, ownGstin);
  return ParsedBill(
    lines: lines,
    columns: columns,
    billNo: _billNoOf(head),
    date: _dateOf(head),
    gstins: gstins,
    supplierName: _supplierNameOf(head),
    total: total,
    foundHeader: foundHeader,
  );
}

/// GST shown only in the tax rows (Tally's "CGST" / "SGST" lines), not on
/// each line: when one GST slab takes the lines' value to the bill's total
/// (a rupee of round-off aside), every line has that rate.
void _impliedGst(List<BillLine> lines, double? total) {
  if (total == null || lines.isEmpty) return;
  if (lines.any((l) => l.gstRate != null)) return;
  final value = lines.fold<double>(0, (s, l) => s + l.value);
  if (value <= 0 || total < value) return;
  final rate = nearestSlab((total - value) / value * 100);
  if (rate == null) return;
  if ((value * (1 + rate / 100) - total).abs() > math.max(1.0, total * 0.001)) {
    return;
  }
  for (final l in lines) {
    l.gstRate = rate;
  }
}

/// A row's words gathered by column. A header sits inside its column's
/// cell, so whatever a cell holds — left-aligned, centred or right-aligned
/// past a short header ("10" under "Qty") — ends to the right of its own
/// header's start and no further than the next header's start: a word
/// belongs to the last column whose header starts before its right edge.
Map<BillCol, String> _cellsOf(BillRow row, List<BillColumn> columns) {
  final out = <BillCol, String>{};
  if (columns.isEmpty) return out;
  final parts = <int, List<String>>{};
  for (final w in row.words) {
    var j = 0;
    while (j + 1 < columns.length && columns[j + 1].left < w.right - 0.5) {
      j++;
    }
    parts.putIfAbsent(j, () => []).add(w.text);
  }
  final gstParts = <double>[];
  for (final e in parts.entries) {
    final col = columns[e.key];
    final text = e.value.join(' ');
    if (col.role == BillCol.gstPart) {
      final v = _pctOrAmount(text);
      final rate = v.pct ?? v.amt;
      if (rate != null && rate <= 28) gstParts.add(rate);
      continue;
    }
    if (col.role == BillCol.taxAmt && out[BillCol.taxAmt] != null) {
      // CGST + SGST amounts: added up.
      final a = billNumber(out[BillCol.taxAmt]!) ?? 0;
      final b = billNumber(text) ?? 0;
      out[BillCol.taxAmt] = '${a + b}';
      continue;
    }
    out[col.role] = out[col.role] == null ? text : '${out[col.role]} $text';
  }
  if (gstParts.isNotEmpty && out[BillCol.gst] == null) {
    out[BillCol.gst] = '${gstParts.fold<double>(0, (s, v) => s + v)}%';
  }
  return out;
}

bool _numbersIn(Map<BillCol, String> cells) {
  for (final c in const [
    BillCol.qty,
    BillCol.rate,
    BillCol.amount,
    BillCol.taxable,
  ]) {
    final t = cells[c];
    if (t != null && _hasDigit(t)) return true;
  }
  return false;
}

/// An item line from its cells, or null when the row isn't one (a total,
/// a tax line, a heading).
BillLine? _lineOf(Map<BillCol, String> cells) {
  var name = (cells[BillCol.name] ?? '').trim();
  final q = billQty(cells[BillCol.qty] ?? '');
  if (q == null || q.qty <= 0) return null;
  if (name.isEmpty || !RegExp(r'[A-Za-z]').hasMatch(name)) return null;
  if (_notName.hasMatch(name)) return null;
  double? num(BillCol c) => cells[c] == null ? null : billNumber(cells[c]!);
  final rate = num(BillCol.rate);
  final amount = num(BillCol.amount);
  final taxable = num(BillCol.taxable);
  final rateIncl = num(BillCol.rateIncl);
  if (rate == null && amount == null && taxable == null && rateIncl == null) {
    return null;
  }
  // A serial number stuck in front of the name ("1 Amul Ghee").
  name = name.replaceFirst(RegExp(r'^\d{1,3}[.)]?\s+'), '');

  double? discPct, discAmt;
  final d = cells[BillCol.disc];
  if (d != null && d.trim().isNotEmpty) {
    final v = _pctOrAmount(d);
    if (v.pct != null) {
      discPct = v.pct;
    } else if (v.amt != null) {
      // A plain number under "Disc": a percentage, unless it can't be.
      discPct = v.amt! <= 100 ? v.amt : null;
      discAmt = v.amt! > 100 ? v.amt : null;
    }
  }
  final da = num(BillCol.discAmt);
  if (da != null && da > 0) discAmt = (discAmt ?? 0) + da;
  if (discPct == 0) discPct = null;

  double? gst, taxAmt = num(BillCol.taxAmt);
  final g = cells[BillCol.gst];
  if (g != null && g.trim().isNotEmpty) {
    final v = _pctOrAmount(g);
    if (v.pct != null) {
      gst = v.pct;
      if (v.amt != null) taxAmt ??= v.amt;
    } else if (v.amt != null) {
      if (v.amt! <= 40 && nearestSlab(v.amt!) == v.amt) {
        gst = v.amt;
      } else {
        taxAmt ??= v.amt;
      }
    }
  }
  // GST from the tax amount when no rate is printed.
  if (gst == null && taxAmt != null && taxAmt > 0) {
    final base =
        taxable ??
        (amount != null ? amount - taxAmt : null) ??
        (rate != null ? rate * q.qty : null);
    if (base != null && base > 0) gst = nearestSlab(taxAmt / base * 100);
  }

  var free = q.free;
  final f = billQty(cells[BillCol.free] ?? '');
  if (f != null) free += f.qty;
  var unit = q.unit;
  final u = (cells[BillCol.unit] ?? '').trim();
  if (unit.isEmpty && u.isNotEmpty && !_hasDigit(u)) unit = u;

  return BillLine(
    name: name.replaceAll(RegExp(r'\s+'), ' '),
    code: (cells[BillCol.code] ?? '').trim(),
    hsn: (cells[BillCol.hsn] ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    qty: q.qty,
    free: free,
    unit: unit,
    rate: rate,
    rateIncl: rateIncl,
    mrp: num(BillCol.mrp),
    discPct: discPct,
    discAmt: discAmt,
    taxable: taxable,
    gstRate: gst,
    taxAmt: taxAmt,
    amount: amount,
  );
}

/// No header the reader knows: rows that start with a name and hold a
/// quantity, a rate and an amount that multiply up (qty × rate, less a
/// discount, = amount).
List<BillLine> _guessLines(List<BillRow> rows) {
  final out = <BillLine>[];
  for (final row in rows) {
    final texts = row.words.map((w) => w.text).toList();
    final nums = <(int, double)>[];
    for (var i = 0; i < texts.length; i++) {
      final v = billNumber(texts[i]);
      if (v != null) nums.add((i, v));
    }
    if (nums.length < 3) continue;
    final nameWords = <String>[];
    for (var i = 0; i < texts.length; i++) {
      if (billNumber(texts[i]) != null) {
        if (nameWords.isEmpty) continue; // a serial number before the name
        // Numbers inside a name ("Ghee 1 L") stay when letters follow.
        if (i + 1 < texts.length &&
            billNumber(texts[i + 1]) == null &&
            RegExp(r'^[A-Za-z]{1,3}$').hasMatch(texts[i + 1])) {
          nameWords.add(texts[i]);
          continue;
        }
        break;
      }
      nameWords.add(texts[i]);
    }
    final name = nameWords.join(' ').trim();
    if (!RegExp(r'[A-Za-z]{2}').hasMatch(name) || _notName.hasMatch(name)) {
      continue;
    }
    if (_stopRow.hasMatch(name)) continue;
    // qty × rate = amount, the amount to the right of both.
    BillLine? found;
    for (var a = nums.length - 1; a >= 2 && found == null; a--) {
      final amount = nums[a].$2;
      if (amount <= 0) continue;
      for (var qi = 0; qi < a && found == null; qi++) {
        for (var ri = qi + 1; ri < a && found == null; ri++) {
          final qty = nums[qi].$2, rate = nums[ri].$2;
          if (qty <= 0 || rate <= 0 || qty > 100000) continue;
          if (qty % 1 != 0 && qty > 1000) continue;
          final gross = qty * rate;
          if ((gross - amount).abs() <= math.max(1.0, amount * 0.01)) {
            found = BillLine(
              name: name,
              qty: qty,
              rate: rate,
              amount: amount,
              fromHeader: false,
            );
          } else if (gross > amount) {
            // A discount % between rate and amount.
            for (var di = ri + 1; di < a && found == null; di++) {
              final d = nums[di].$2;
              if (d > 0 &&
                  d < 100 &&
                  (gross * (1 - d / 100) - amount).abs() <=
                      math.max(1.0, amount * 0.01)) {
                found = BillLine(
                  name: name,
                  qty: qty,
                  rate: rate,
                  discPct: d,
                  amount: amount,
                  fromHeader: false,
                );
              }
            }
          }
        }
      }
    }
    if (found != null) {
      // A GST % after the rate, if one is printed with a % sign.
      for (final w in row.words) {
        final m = RegExp(r'^(\d*\.?\d+)%$').firstMatch(w.text);
        if (m != null) {
          final v = double.parse(m.group(1)!);
          if (nearestSlab(v) == v && v != found.discPct) found.gstRate = v;
        }
      }
      out.add(found);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Bill details
// ---------------------------------------------------------------------------

final _gstinPattern = RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b');

List<String> _gstinsOf(List<BillRow> rows, String ownGstin) {
  final own = ownGstin.trim().toUpperCase();
  final out = <String>[];
  for (final r in rows) {
    for (final m in _gstinPattern.allMatches(r.text.toUpperCase())) {
      final g = m.group(0)!;
      if (g != own && !out.contains(g)) out.add(g);
    }
  }
  return out;
}

final _billNoLabel = RegExp(
  r'\b(invoice|inv|bill|voucher|document|doc)\.?\s*(no|number|#)\.?\s*[:\-]?\s*',
  caseSensitive: false,
);

/// The bill number: after "Invoice No." on its line, or right under it
/// (Tally prints the label and the number in a box, one above the other).
String _billNoOf(List<BillRow> rows) {
  for (var i = 0; i < rows.length; i++) {
    final text = rows[i].text;
    final m = _billNoLabel.firstMatch(text);
    if (m == null) continue;
    final after = text.substring(m.end).trim();
    final token = RegExp(r'^[A-Za-z0-9][A-Za-z0-9/\-_.]*').firstMatch(after);
    if (token != null &&
        _hasDigit(token.group(0)!) &&
        !_isLabelWord(token.group(0)!)) {
      return token.group(0)!.replaceFirst(RegExp(r'\.$'), '');
    }
    // The value under the label.
    final labelWord = rows[i].words.firstWhere(
      (w) => RegExp(
        r'^(invoice|inv|bill|voucher|document|doc)',
        caseSensitive: false,
      ).hasMatch(w.text),
      orElse: () => rows[i].words.first,
    );
    for (var j = i + 1; j < rows.length && j <= i + 2; j++) {
      for (final w in rows[j].words) {
        if (w.left >= labelWord.left - labelWord.height &&
            w.left <= labelWord.right + labelWord.height * 4 &&
            _hasDigit(w.text) &&
            _parseDate(w.text) == null) {
          return w.text.replaceFirst(RegExp(r'^[:\-]+'), '');
        }
      }
    }
  }
  return '';
}

bool _isLabelWord(String s) =>
    RegExp(r'^(dated?|date)$', caseSensitive: false).hasMatch(s);

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'sept': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// A date as bills print it: 10-Oct-26, 10/10/2026, 10.10.2026,
/// 2026-10-10, 10 October 2026.
DateTime? _parseDate(String s) {
  final t = s.trim();
  int year(String y) {
    final v = int.parse(y);
    return v < 100 ? 2000 + v : v;
  }

  DateTime? make(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) {
      return null;
    }
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null;
  }

  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(t);
  if (m != null) {
    return make(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$').firstMatch(t);
  if (m != null) {
    return make(
      year(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
    );
  }
  m = RegExp(
    r'^(\d{1,2})[-/. ]?([A-Za-z]{3,9})[-/., ]*(\d{2}|\d{4})$',
  ).firstMatch(t);
  if (m != null) {
    final mon =
        _months[m.group(2)!.toLowerCase().substring(0, 3)] ??
        _months[m.group(2)!.toLowerCase()];
    if (mon == null) return null;
    return make(year(m.group(3)!), mon, int.parse(m.group(1)!));
  }
  return null;
}

/// Date-looking runs in a line ("Dated 10-Oct-26", "Date: 10 Oct 2026").
Iterable<DateTime> _datesIn(String text) sync* {
  final runs = RegExp(
    r'\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|'
    r'\d{1,2}[-/. ]?[A-Za-z]{3,9}[-/., ]*\d{2,4}',
  ).allMatches(text);
  for (final r in runs) {
    final d = _parseDate(r.group(0)!);
    if (d != null) yield d;
  }
}

/// The bill date: on the "Date"/"Dated" line or right under it, else the
/// first date near the top of the bill.
DateTime? _dateOf(List<BillRow> rows) {
  final label = RegExp(
    r'\b(dated|invoice\s*date|bill\s*date|inv\s*date|date)\b',
    caseSensitive: false,
  );
  for (var i = 0; i < rows.length; i++) {
    final text = rows[i].text;
    final m = label.firstMatch(text);
    if (m == null) continue;
    if (RegExp(
      r'\b(due|expiry|exp|delivery|order|po|dispatch|challan|e-?way)\b\s*\S*\s*date',
      caseSensitive: false,
    ).hasMatch(text.substring(0, m.end))) {
      continue;
    }
    final after = _datesIn(text.substring(m.start));
    if (after.isNotEmpty) return after.first;
    final labelWord = rows[i].words.firstWhere(
      (w) => label.hasMatch(w.text),
      orElse: () => rows[i].words.first,
    );
    for (var j = i + 1; j < rows.length && j <= i + 2; j++) {
      for (final w in rows[j].words) {
        if (w.left >= labelWord.left - labelWord.height * 2 &&
            w.left <= labelWord.right + labelWord.height * 6) {
          final d = _parseDate(w.text);
          if (d != null) return d;
        }
      }
    }
  }
  for (final r in rows.take(40)) {
    final d = _datesIn(r.text);
    if (d.isNotEmpty) return d.first;
  }
  return null;
}

/// The last number on a row (a total, an amount).
double? _lastNumber(BillRow row) {
  for (final w in row.words.reversed) {
    final v = billNumber(w.text);
    if (v != null && v > 0) return v;
  }
  return null;
}

/// The bill's total: on a "Grand Total" / "Invoice Total" / "Net Amount"
/// line, else the item table's own "Total" line ([tableTotal]: a tax
/// summary below it has a "Total" of its own), else the last "Total" line.
double? _totalOf(List<BillRow> rows, double? tableTotal) {
  const labels = [
    r'grand\s*total',
    r'invoice\s*(total|amount|value)',
    r'total\s*inv(oice)?\.?\s*(amt|amount|value)',
    r'net\s*(amount|payable|total)',
    r'(total\s*)?amount\s*payable',
    r'bill\s*amount',
    r'total\s*amount',
  ];
  double? find(String l) {
    final re = RegExp('\\b$l\\b', caseSensitive: false);
    double? found;
    for (final r in rows) {
      final m = re.firstMatch(r.text);
      if (m == null) continue;
      if (RegExp(
        r'\b(sub\s*total|total\s*(qty|quantity|items|tax|gst|discount))\b',
        caseSensitive: false,
      ).hasMatch(r.text.substring(m.start))) {
        continue;
      }
      final last = _lastNumber(r);
      if (last != null) found = last; // the last such line wins
    }
    return found;
  }

  for (final l in labels) {
    final v = find(l);
    if (v != null) return v;
  }
  return tableTotal ?? find(r'total');
}

const _titleWords = {
  'tax invoice',
  'invoice',
  'bill of supply',
  'retail invoice',
  'gst invoice',
  'original',
  'duplicate',
  'triplicate',
  'original for recipient',
  'duplicate for transporter',
  'triplicate for supplier',
  'e-invoice',
  'cash memo',
  'estimate',
};

/// The supplier's name: the biggest text at the top that isn't a title
/// ("TAX INVOICE"), a label or a number.
String _supplierNameOf(List<BillRow> rows) {
  if (rows.isEmpty) return '';
  final limit = rows.first.top + (rows.last.bottom - rows.first.top) * 0.35;
  BillPhrase? best;
  var bestHeight = 0.0;
  for (final r in rows) {
    if (r.top > limit) break;
    for (final p in billPhrases(r)) {
      final t = p.text.trim();
      final n = t.toLowerCase().replaceAll(RegExp(r'[^a-z\- ]'), '').trim();
      if (t.length < 3 || _titleWords.contains(n)) continue;
      if (!RegExp(r'[A-Za-z]{3}').hasMatch(t)) continue;
      if (RegExp(
        r'[:]|\b(gstin|gst|phone|ph|mob|email|state|invoice|dated?|buyer|consignee|ship|bill)\b',
        caseSensitive: false,
      ).hasMatch(t)) {
        continue;
      }
      final h = p.words.map((w) => w.height).reduce(math.max);
      if (h > bestHeight + 0.5) {
        bestHeight = h;
        best = p;
      }
    }
  }
  // "R.J.S. Enterprises Pvt. Ltd - (2024-26)\nPlot No- 128" → the name:
  // its first line, without Tally's financial-year tag.
  return (best?.text ?? '')
      .split('\n')
      .first
      .replaceFirst(RegExp(r'\s*-?\s*\(\d{4}\s*-\s*\d{2,4}\)\s*$'), '')
      .trim();
}
