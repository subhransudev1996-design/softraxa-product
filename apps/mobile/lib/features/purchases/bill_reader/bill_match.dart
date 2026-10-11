/// Matching a supplier's item names to the shop's own products:
/// "AMUL GHEE 1LTR TIN" is "Amul Pure Ghee 1 L". Sizes are written one way
/// (1LTR = 1 L = 1000 ml), filler words don't count, and two different
/// sizes never match. The shop checks every suggestion before it's used;
/// what it confirms is remembered per supplier (migration 0078) and
/// matched exactly next time.
library;

import 'dart:math' as math;

const _filler = {
  'of',
  'the',
  'and',
  'with',
  'new',
  'pkt',
  'packet',
  'pouch',
  'tin',
  'jar',
  'bottle',
  'btl',
  'box',
  'pack',
  'pc',
  'pcs',
  'nos',
  'no',
  'each',
  'rs',
  'mrp',
};

String _num(double v) {
  final s = v.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// A name's words, sizes written one way: "Amul GHEE 1Ltr." → amul ghee 1l;
/// "500 GMS" → 500g; "1000ML" → 1l.
List<String> nameTokens(String name) {
  var s = name.toLowerCase().replaceAll('&', ' and ');
  s = s.replaceAll(RegExp(r'[^a-z0-9.]+'), ' ');
  // Sizes: a number and its unit, together.
  s = s.replaceAllMapped(
    RegExp(
      r'(\d+(?:\.\d+)?)\s*(kgs?|kilos?|kilograms?|gms?|grams?|grms?|g|gr|mls?|millilitres?|milliliters?|ltrs?|litres?|liters?|lt|l)(?![a-z])',
    ),
    (m) {
      var v = double.parse(m.group(1)!);
      final u = m.group(2)!;
      String unit;
      if (u.startsWith('k')) {
        unit = 'kg';
      } else if (u.startsWith('g')) {
        unit = 'g';
      } else if (u.startsWith('m')) {
        unit = 'ml';
      } else {
        unit = 'l';
      }
      if (unit == 'g' && v >= 1000) {
        v /= 1000;
        unit = 'kg';
      } else if (unit == 'ml' && v >= 1000) {
        v /= 1000;
        unit = 'l';
      }
      return ' ${_num(v)}$unit ';
    },
  );
  return [
    for (final w in s.split(' '))
      if (w.isNotEmpty && w != '.' && !_filler.contains(w))
        w.replaceAll(RegExp(r'^\.+|\.+$'), ''),
  ].where((w) => w.isNotEmpty).toList();
}

/// The key a supplier's item name is remembered by.
String billItemKey(String name) {
  var t = nameTokens(name).join(' ');
  if (t.isEmpty) t = name.trim().toLowerCase();
  return t.length > 200 ? t.substring(0, 200) : t;
}

final _size = RegExp(r'^\d+(\.\d+)?(kg|g|ml|l)$');

/// A number with or without a unit: a size (1l, 500g), storage (256gb),
/// a model number (4b, 13c) or a plain number (Dolo 650).
final _measure = RegExp(r'^(\d+(?:\.\d+)?)([a-z]{0,4})$');

const _colours = {
  'black',
  'white',
  'red',
  'blue',
  'green',
  'yellow',
  'pink',
  'purple',
  'grey',
  'gray',
  'silver',
  'gold',
  'golden',
  'orange',
  'brown',
  'maroon',
  'navy',
  'beige',
  'cream',
  'violet',
  'peach',
  'mint',
  'lavender',
};

/// Two names that can't be the same product: a size, storage, model
/// number or plain number of one kind (unit) that differs between them
/// ("8GB+128GB" vs "8GB+256GB", "1 L" vs "500 ml", "Dolo 650" vs "Dolo
/// 500"), or different colours (White vs Black).
bool _conflict(List<String> a, List<String> b) {
  Map<String, Set<String>> measures(List<String> t) {
    final out = <String, Set<String>>{};
    for (final w in t) {
      final m = _measure.firstMatch(w);
      if (m == null) continue;
      // Litres and kilos are written in ml / g too (1l = 1000ml).
      final unit = switch (m.group(2)!) {
        'ml' => 'l',
        'g' => 'kg',
        final u => u,
      };
      out.putIfAbsent(unit, () => {}).add(w);
    }
    return out;
  }

  final ma = measures(a), mb = measures(b);
  for (final unit in ma.keys) {
    final other = mb[unit];
    if (other != null &&
        !(ma[unit]!.length == other.length && ma[unit]!.containsAll(other))) {
      return true;
    }
  }
  final ca = a.where(_colours.contains).toSet();
  final cb = b.where(_colours.contains).toSet();
  return ca.isNotEmpty && cb.isNotEmpty && ca.intersection(cb).isEmpty;
}

bool _closeWord(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  // One letter different, missing or extra ("detergant" / "detergent").
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/// How alike two names are, 0–1: shared words over all words (a shortened
/// word — "choc" for "chocolate" — counts most of one). Different sizes,
/// storage, model numbers or colours are never alike.
double nameScore(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (_conflict(a, b)) return 0;
  final used = <int>{};
  var matched = 0.0;
  for (final w in a) {
    var best = 0.0;
    var bestJ = -1;
    for (var j = 0; j < b.length; j++) {
      if (used.contains(j)) continue;
      final v = b[j];
      double s;
      if (w == v) {
        s = 1;
      } else if (_size.hasMatch(w) || _size.hasMatch(v)) {
        s = 0;
      } else if (w.length >= 3 &&
          v.length >= 3 &&
          (w.startsWith(v) || v.startsWith(w))) {
        s = 0.8;
      } else if (_closeWord(w, v)) {
        s = 0.8;
      } else {
        s = 0;
      }
      if (s > best) {
        best = s;
        bestJ = j;
      }
    }
    if (bestJ >= 0) {
      used.add(bestJ);
      matched += best;
    }
  }
  return 2 * matched / (a.length + b.length);
}

/// A product (and its sizes/colours) as matching needs it.
class MatchProduct {
  MatchProduct({
    required this.id,
    required this.name,
    this.sku = '',
    this.barcode = '',
    this.hsn = '',
    this.variants = const [],
  }) : tokens = nameTokens(name);

  factory MatchProduct.fromRow(Map<String, dynamic> p) => MatchProduct(
    id: p['id'] as String,
    name: p['name'] as String? ?? '',
    sku: p['sku'] as String? ?? '',
    barcode: p['barcode'] as String? ?? '',
    hsn: p['hsn_code'] as String? ?? '',
    variants: [
      for (final v in (p['product_variants'] as List? ?? const []))
        if ((v as Map)['is_active'] != false)
          MatchVariant(
            id: v['id'] as String,
            name: v['name'] as String? ?? '',
            sku: v['sku'] as String? ?? '',
            barcode: v['barcode'] as String? ?? '',
          ),
    ],
  );

  final String id, name, sku, barcode, hsn;
  final List<MatchVariant> variants;
  final List<String> tokens;
}

class MatchVariant {
  MatchVariant({
    required this.id,
    required this.name,
    this.sku = '',
    this.barcode = '',
  }) : tokens = nameTokens(name);

  final String id, name, sku, barcode;
  final List<String> tokens;
}

/// A suggested product for a bill line.
class ItemMatch {
  const ItemMatch(
    this.productId,
    this.variantId,
    this.score, {
    this.byCode = false,
  });

  final String productId;
  final String? variantId;

  /// 0–1; 1 for a barcode / stock no. printed on the bill.
  final double score;
  final bool byCode;
}

/// Below this a name is not suggested at all.
const minMatchScore = 0.5;

/// The shop's product most like a bill line: by a barcode or stock no.
/// printed on the bill first, else by name (HSN agreeing helps a little).
ItemMatch? bestMatch(
  String name,
  List<MatchProduct> products, {
  String code = '',
  String hsn = '',
}) {
  final tokens = nameTokens(name);
  final codes = {
    if (code.trim().length >= 4) code.trim().toLowerCase(),
    for (final w in name.toLowerCase().split(RegExp(r'\s+')))
      if (w.length >= 5 && RegExp(r'\d').hasMatch(w)) w,
  };
  if (codes.isNotEmpty) {
    for (final p in products) {
      for (final v in p.variants) {
        if ((v.barcode.isNotEmpty && codes.contains(v.barcode.toLowerCase())) ||
            (v.sku.isNotEmpty && codes.contains(v.sku.toLowerCase()))) {
          return ItemMatch(p.id, v.id, 1, byCode: true);
        }
      }
      if ((p.barcode.isNotEmpty && codes.contains(p.barcode.toLowerCase())) ||
          (p.sku.length >= 4 && codes.contains(p.sku.toLowerCase()))) {
        return ItemMatch(p.id, null, 1, byCode: true);
      }
    }
  }
  if (tokens.isEmpty) return null;
  ItemMatch? best;
  for (final p in products) {
    var s = nameScore(tokens, p.tokens);
    String? variant;
    // A size/colour named on the bill: the product's name and the
    // variant's together.
    for (final v in p.variants) {
      if (v.tokens.isEmpty) continue;
      final vs = nameScore(tokens, [...p.tokens, ...v.tokens]);
      if (vs > s) {
        s = vs;
        variant = v.id;
      }
    }
    if (s <= 0) continue;
    final h = hsn.replaceAll(RegExp(r'\D'), '');
    final ph = p.hsn.replaceAll(RegExp(r'\D'), '');
    if (h.length >= 4 && ph.length >= 4) {
      if (h.substring(0, 4) == ph.substring(0, 4)) {
        s += 0.05;
      } else if (h.substring(0, 2) != ph.substring(0, 2)) {
        s -= 0.15;
      }
    }
    if (best == null || s > best.score) best = ItemMatch(p.id, variant, s);
  }
  if (best == null || best.score < minMatchScore) return null;
  return ItemMatch(best.productId, best.variantId, math.min(best.score, 0.99));
}

/// How many of the product's units one of the bill's units is, when it
/// can be told: the product's own bulk unit ("Box of 12") or a dozen.
double defaultPackFactor(
  String billUnit, {
  String? secondaryUnit,
  double? conversionFactor,
  String baseUnit = '',
}) {
  String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  final u = n(billUnit);
  if (u.isEmpty) return 1;
  if (secondaryUnit != null &&
      conversionFactor != null &&
      conversionFactor > 0) {
    final s = n(secondaryUnit);
    const same = {
      'box': ['box', 'bx', 'boxes'],
      'case': ['case', 'cs', 'cse', 'cases'],
      'carton': ['carton', 'ctn', 'cartons', 'cart'],
      'bag': ['bag', 'bags'],
      'dozen': ['dozen', 'dz', 'doz', 'dzn'],
      'strip': ['strip', 'strips', 'stp'],
      'packet': ['packet', 'pkt', 'pack', 'packets'],
      'bundle': ['bundle', 'bdl', 'bundles'],
    };
    if (u == s) return conversionFactor;
    for (final names in same.values) {
      if (names.contains(u) && names.contains(s)) return conversionFactor;
    }
  }
  final base = n(baseUnit);
  if (const ['dozen', 'dz', 'doz', 'dzn'].contains(u) &&
      const ['pc', 'pcs', 'piece', 'pieces', 'nos', 'no', ''].contains(base)) {
    return 12;
  }
  return 1;
}
