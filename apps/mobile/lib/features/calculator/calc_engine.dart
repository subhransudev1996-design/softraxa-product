import '../../core/formatters.dart';

/// The shop calculator: numbers and operators like any calculator, plus
/// products and services from the shop's own lists at their own prices
/// (Tata Salt × 3 + Fitting charge). Kept apart from the screen so the
/// sums are tested on their own.

/// A product or service put into a calculation. [price] is what one unit
/// costs the customer, GST included — the figure the calculator adds up.
class CalcItem {
  const CalcItem({
    required this.kind,
    required this.name,
    required this.price,
    this.gstRate = 0,
    this.product,
    this.variant,
    this.service,
    this.packSize,
    this.unit = '',
  });

  /// 'product' or 'service'.
  final String kind;
  final String name;
  final double price;
  final double gstRate;
  final Map<String, dynamic>? product;
  final Map<String, dynamic>? variant;
  final Map<String, dynamic>? service;

  /// Pieces in one pack when the product is put in by the pack (Box of 10
  /// at the box price); null for single units.
  final double? packSize;
  final String unit;

  bool get isPack => packSize != null;
}

enum CalcTokenKind { number, item, op, percent }

class CalcToken {
  const CalcToken.number(this.text) : kind = CalcTokenKind.number, item = null;
  const CalcToken.op(this.text) : kind = CalcTokenKind.op, item = null;
  const CalcToken.percent()
    : kind = CalcTokenKind.percent,
      text = '%',
      item = null;
  const CalcToken.item(CalcItem this.item)
    : kind = CalcTokenKind.item,
      text = '';

  final CalcTokenKind kind;
  final String text;
  final CalcItem? item;

  bool get isValue =>
      kind == CalcTokenKind.number ||
      kind == CalcTokenKind.item ||
      kind == CalcTokenKind.percent;
}

/// The operators, as shown on the keys.
const calcPlus = '+', calcMinus = '−', calcTimes = '×', calcDivide = '÷';

/// One part of the sum between + and −, as it shows on the tape and goes
/// to a bill: "Tata Salt × 3" with its amount. [item] is null for a typed
/// amount; [qty] is then 1 and [amount] the figure.
class CalcLine {
  const CalcLine({
    required this.label,
    required this.amount,
    this.item,
    this.qty = 1,
  });

  final String label;
  final double amount;
  final CalcItem? item;
  final double qty;
}

class CalcResult {
  const CalcResult({required this.total, required this.lines, this.problem});

  /// Null while the sum can't be worked out (nothing typed, ÷ 0).
  final double? total;
  final List<CalcLine> lines;

  /// Why the calculation can't become a bill, estimate or quote, in
  /// English for t(); null when it can.
  final String? problem;

  bool get hasItems => lines.any((l) => l.item != null);
}

/// The keys pressed so far, and what they come to.
class CalcState {
  const CalcState([this.tokens = const []]);

  final List<CalcToken> tokens;

  bool get isEmpty => tokens.isEmpty;
  CalcToken? get _last => tokens.isEmpty ? null : tokens.last;

  /// A digit, "00" or ".". After a product it starts a quantity
  /// (Salt then 3 → Salt × 3).
  CalcState digit(String d) {
    final last = _last;
    if (last?.kind == CalcTokenKind.number) {
      final text = last!.text;
      if (d == '.' && text.contains('.')) return this;
      if (text.replaceAll('.', '').length >= 12) return this;
      var next = text == '0' && d != '.' ? d : text + d;
      if (next == '00') next = '0';
      return CalcState([
        ...tokens.sublist(0, tokens.length - 1),
        CalcToken.number(next),
      ]);
    }
    final start = d == '.' ? '0.' : (d == '00' ? '0' : d);
    return CalcState([
      ...tokens,
      if (last != null && last.kind != CalcTokenKind.op)
        const CalcToken.op(calcTimes),
      CalcToken.number(start),
    ]);
  }

  /// + − × ÷. Pressing another replaces it; only − can start a sum.
  CalcState op(String o) {
    final last = _last;
    if (last == null) {
      return o == calcMinus ? const CalcState([CalcToken.op(calcMinus)]) : this;
    }
    if (last.kind == CalcTokenKind.op) {
      if (tokens.length == 1) return this;
      return CalcState([
        ...tokens.sublist(0, tokens.length - 1),
        CalcToken.op(o),
      ]);
    }
    return CalcState([...tokens, CalcToken.op(o)]);
  }

  /// % after a number: "200 + 10%" is 220, "200 − 10%" is 180, "50 × 10%"
  /// is 5 — the way shop calculators work.
  CalcState percent() {
    final last = _last;
    if (last?.kind != CalcTokenKind.number) return this;
    return CalcState([...tokens, const CalcToken.percent()]);
  }

  /// A product or service. After a bare number it is that many (3 then
  /// Salt → 3 × Salt); otherwise it is added (Salt × 3 then Sugar → … +
  /// Sugar).
  CalcState addItem(CalcItem item) {
    final last = _last;
    // Times only a bare number ("3" then Salt); once this part of the sum
    // has an item ("Salt × 3"), the next item is added.
    var termHasItem = false;
    for (final tk in tokens.reversed) {
      if (tk.kind == CalcTokenKind.op &&
          (tk.text == calcPlus || tk.text == calcMinus)) {
        break;
      }
      if (tk.kind == CalcTokenKind.item) termHasItem = true;
    }
    return CalcState([
      ...tokens,
      if (last != null && last.kind != CalcTokenKind.op)
        CalcToken.op(
          last.kind == CalcTokenKind.number && !termHasItem
              ? calcTimes
              : calcPlus,
        ),
      CalcToken.item(item),
    ]);
  }

  CalcState backspace() {
    final last = _last;
    if (last == null) return this;
    if (last.kind == CalcTokenKind.number && last.text.length > 1) {
      return CalcState([
        ...tokens.sublist(0, tokens.length - 1),
        CalcToken.number(last.text.substring(0, last.text.length - 1)),
      ]);
    }
    return CalcState(tokens.sublist(0, tokens.length - 1));
  }

  /// "=": with only numbers the sum becomes its answer, to carry on from.
  /// With products in it nothing changes — they stay linked for the bill.
  CalcState equals() {
    final r = evaluate();
    if (r.total == null || r.hasItems) return this;
    final v = double.parse(r.total!.toStringAsFixed(2));
    if (v < 0) {
      return CalcState([
        const CalcToken.op(calcMinus),
        CalcToken.number(_n(-v)),
      ]);
    }
    return CalcState([CalcToken.number(_n(v))]);
  }

  /// The sum, and its parts between + and −.
  CalcResult evaluate() {
    // Ignore a trailing operator while it's being typed.
    var list = tokens;
    while (list.isNotEmpty && list.last.kind == CalcTokenKind.op) {
      list = list.sublist(0, list.length - 1);
    }
    if (list.isEmpty) return const CalcResult(total: null, lines: []);

    // Split into terms: each starts with its sign.
    final terms = <({bool minus, List<CalcToken> parts})>[];
    var minus = false;
    var current = <CalcToken>[];
    for (var i = 0; i < list.length; i++) {
      final tk = list[i];
      if (tk.kind == CalcTokenKind.op &&
          (tk.text == calcPlus || tk.text == calcMinus)) {
        if (current.isEmpty) {
          // A leading minus.
          if (tk.text == calcMinus) minus = !minus;
          continue;
        }
        terms.add((minus: minus, parts: current));
        minus = tk.text == calcMinus;
        current = [];
      } else {
        current.add(tk);
      }
    }
    if (current.isNotEmpty) terms.add((minus: minus, parts: current));

    double total = 0;
    final lines = <CalcLine>[];
    String? problem;
    for (final (index, term) in terms.indexed) {
      final t = _term(term.parts, total);
      if (t == null) return const CalcResult(total: null, lines: []);
      final value = term.minus ? -t.value : t.value;
      total += value;
      final qty = term.minus ? -t.qty : t.qty;
      if (t.items > 1) {
        problem ??= 'Two items are multiplied together';
      } else if (t.itemDivided) {
        problem ??= 'An item is divided';
      } else if (t.item != null && qty <= 0) {
        problem ??= 'An item has a minus or zero quantity';
      }
      lines.add(
        CalcLine(
          label: _label(term.minus, index > 0, term.parts),
          amount: _r2(value),
          item: t.items == 1 ? t.item : null,
          qty: t.items == 1 ? qty : 1,
        ),
      );
    }
    return CalcResult(total: _r2(total), lines: lines, problem: problem);
  }

  /// A term's value. [before] is the sum so far, for "+ 10%".
  static ({
    double value,
    double qty,
    CalcItem? item,
    int items,
    bool itemDivided,
  })?
  _term(List<CalcToken> parts, double before) {
    double value = 1;
    double qty = 1;
    CalcItem? item;
    var items = 0;
    var itemDivided = false;
    var divide = false;
    final single = parts.length == 2 && parts[1].kind == CalcTokenKind.percent;
    for (var i = 0; i < parts.length; i++) {
      final tk = parts[i];
      if (tk.kind == CalcTokenKind.op) {
        divide = tk.text == calcDivide;
        continue;
      }
      if (tk.kind == CalcTokenKind.percent) continue;
      double f;
      if (tk.kind == CalcTokenKind.item) {
        f = tk.item!.price;
        item = tk.item;
        items++;
        if (divide) itemDivided = true;
      } else {
        f = double.tryParse(tk.text) ?? 0;
        final pct =
            i + 1 < parts.length && parts[i + 1].kind == CalcTokenKind.percent;
        if (pct) f = single ? before * f / 100 : f / 100;
        if (divide) {
          qty = f == 0 ? double.nan : qty / f;
        } else {
          qty *= f;
        }
      }
      if (divide) {
        if (f == 0) return null;
        value /= f;
      } else {
        value *= f;
      }
    }
    if (value.isNaN || value.isInfinite) return null;
    return (
      value: value,
      qty: double.parse(qty.toStringAsFixed(3)),
      item: item,
      items: items,
      itemDivided: itemDivided,
    );
  }

  static String _label(bool minus, bool added, List<CalcToken> parts) {
    final b = StringBuffer(
      minus
          ? '$calcMinus '
          : added
          ? '$calcPlus '
          : '',
    );
    for (final tk in parts) {
      switch (tk.kind) {
        case CalcTokenKind.number:
          b.write(tk.text);
        case CalcTokenKind.percent:
          b.write('%');
        case CalcTokenKind.op:
          b.write(' ${tk.text} ');
        case CalcTokenKind.item:
          b.write(itemLabel(tk.item!));
      }
    }
    return b.toString();
  }
}

/// "Tata Salt 1 kg (₹28)", "Parle-G (Box of 10, ₹95)".
String itemLabel(CalcItem i) => i.isPack
    ? '${i.name} (${i.unit} of ${qty(i.packSize)}, ${money(i.price)})'
    : '${i.name} (${money(i.price)})';

double _r2(double v) => (v * 100).roundToDouble() / 100;

String _n(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// The calculation as a price quote to send on WhatsApp. In English, like
/// the bills (printed and shared output stays English).
String calcQuoteMessage(
  CalcResult r, {
  required String shopName,
  String shopPhone = '',
  String customerName = '',
}) {
  final b = StringBuffer()
    ..writeln(
      customerName.trim().isEmpty ? 'Hello,' : 'Hello ${customerName.trim()},',
    )
    ..writeln()
    ..writeln('Price quote from $shopName:')
    ..writeln();
  for (final l in r.lines) {
    final i = l.item;
    if (i != null) {
      final what = i.isPack
          ? '${i.name} (${i.unit} of ${qty(i.packSize)})'
          : i.name;
      b.writeln(
        '• $what${l.qty != 1 ? ' × ${qty(l.qty)}' : ''} — ${money(l.amount)}',
      );
    } else if (l.amount < 0) {
      b.writeln('• Discount — −${money(-l.amount)}');
    } else {
      b.writeln('• Other charges — ${money(l.amount)}');
    }
  }
  b
    ..writeln()
    ..writeln('Total: ${money(r.total)}');
  if (r.lines.any((l) => (l.item?.gstRate ?? 0) > 0)) {
    b.writeln('Prices include GST.');
  }
  b
    ..writeln()
    ..write('— $shopName');
  if (shopPhone.trim().isNotEmpty) b.write(', ${shopPhone.trim()}');
  return b.toString();
}
