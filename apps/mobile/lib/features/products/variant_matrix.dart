/// Variants as a shop thinks of them: a product comes in some sizes and
/// some colours, and every size in every colour is a variant. Making them
/// all at once, ordering sizes the way they're worn (S, M, L, XL — not
/// alphabetically), and laying them out as a size × colour grid for
/// billing, purchases and stock. Kept apart from the screens so it's
/// tested on its own.
library;

/// One thing a product varies by ("Size") and the values it comes in.
class VariantAxis {
  VariantAxis(this.name, [List<String>? values]) : values = values ?? [];

  final String name;
  final List<String> values;

  bool get isSize => looksLikeSize(name);
}

/// Every combination of the axes' values: the first axis changes slowest
/// (Red S, Red M, … Blue S, …). Axes without values are skipped.
List<Map<String, String>> variantCombinations(List<VariantAxis> axes) {
  final used = [
    for (final a in axes)
      if (a.values.isNotEmpty) a,
  ];
  if (used.isEmpty) return const [];
  var out = <Map<String, String>>[{}];
  for (final a in used) {
    out = [
      for (final partial in out)
        for (final v in a.values) {...partial, a.name: v},
    ];
  }
  return out;
}

/// "Red / M" — the axes' values in the axes' order.
String variantNameOf(Map<String, String> attrs) =>
    attrs.values.where((v) => v.trim().isNotEmpty).join(' / ');

/// The same combination, whatever the order or case of its keys.
String variantKey(Map<String, String> attrs) {
  final entries = [
    for (final e in attrs.entries)
      if (e.value.trim().isNotEmpty)
        '${e.key.trim().toLowerCase()}=${e.value.trim().toLowerCase()}',
  ]..sort();
  return entries.join('|');
}

bool looksLikeSize(String axisName) {
  final n = axisName.toLowerCase();
  return n.contains('size') || n == 'length' || n == 'waist';
}

/// Sizes in the order they're worn. Anything else keeps its place.
const _sizeLadder = [
  'free size',
  'xxs',
  'xs',
  's',
  'm',
  'l',
  'xl',
  'xxl',
  '2xl',
  'xxxl',
  '3xl',
  '4xl',
  '5xl',
];

/// Orders an axis's values: the clothing size ladder, then numbers by
/// value (28, 30, 32 / 6 kg, 8 kg), then the rest as first seen.
List<String> sortAxisValues(List<String> values) {
  int? ladder(String v) {
    final i = _sizeLadder.indexOf(v.trim().toLowerCase());
    return i < 0 ? null : i;
  }

  double? number(String v) => double.tryParse(
    RegExp(r'^\s*(\d+(\.\d+)?)').firstMatch(v)?.group(1) ?? '',
  );

  final indexed = values.indexed.toList();
  indexed.sort((a, b) {
    final la = ladder(a.$2), lb = ladder(b.$2);
    if (la != null && lb != null) return la.compareTo(lb);
    if (la != null) return -1;
    if (lb != null) return 1;
    final na = number(a.$2), nb = number(b.$2);
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    if (na != null && nb == null) return -1;
    if (na == null && nb != null) return 1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// A variant row's attributes as field → value.
Map<String, String> attributesOfRow(Map<String, dynamic> row) =>
    Map<String, String>.from(
      (row['attributes'] as Map? ?? const {}).map(
        (k, v) => MapEntry('$k', '$v'),
      ),
    );

/// The axes a product's variants use, keys in first-seen order and values
/// sorted ([sortAxisValues]).
List<VariantAxis> axesOf(List<Map<String, dynamic>> variants) {
  final axes = <String, List<String>>{};
  for (final v in variants) {
    for (final e in attributesOfRow(v).entries) {
      if (e.value.trim().isEmpty) continue;
      final list = axes.putIfAbsent(e.key, () => []);
      if (!list.contains(e.value)) list.add(e.value);
    }
  }
  return [
    for (final e in axes.entries) VariantAxis(e.key, sortAxisValues(e.value)),
  ];
}

/// Variants laid out as a grid: [columns] across (the sizes, when there
/// are sizes) and [rows] down (colours…; null for a single axis). [cell]
/// finds the variant for a row and column value.
class VariantGrid {
  VariantGrid._(this.rows, this.columns, this._cells);

  final VariantAxis? rows;
  final VariantAxis columns;
  final Map<String, Map<String, dynamic>> _cells;

  Map<String, dynamic>? cell(String? row, String column) =>
      _cells['${row ?? ''}\u0000$column'];

  List<String?> get rowValues => rows == null ? const [null] : rows!.values;
}

/// The grid for these variants, or null when they don't make one (more
/// than two axes, or variants without attributes) — then a plain list.
VariantGrid? variantGridOf(List<Map<String, dynamic>> variants) {
  if (variants.isEmpty) return null;
  final axes = axesOf(variants);
  if (axes.isEmpty || axes.length > 2) return null;
  // Sizes go across; with two axes and no size, the one with more values.
  VariantAxis columns;
  VariantAxis? rows;
  if (axes.length == 1) {
    columns = axes.single;
  } else {
    final sizeAt = axes.indexWhere((a) => a.isSize);
    final colIndex = sizeAt >= 0
        ? sizeAt
        : (axes[0].values.length >= axes[1].values.length ? 0 : 1);
    columns = axes[colIndex];
    rows = axes[1 - colIndex];
  }
  final cells = <String, Map<String, dynamic>>{};
  for (final v in variants) {
    final a = attributesOfRow(v);
    final col = a[columns.name];
    if (col == null || col.trim().isEmpty) return null;
    final row = rows == null ? '' : a[rows.name];
    if (rows != null && (row == null || row.trim().isEmpty)) return null;
    final key = '$row\u0000$col';
    if (cells.containsKey(key)) return null; // two variants in one box
    cells[key] = v;
  }
  return VariantGrid._(rows, columns, cells);
}

/// "KURTA-RED-M": the product's code (its SKU, else its name) and the
/// variant's values, upper case, letters and digits only.
String autoVariantSku(String productCode, Map<String, String> attrs) {
  String clean(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  var base = clean(productCode);
  if (base.length > 12) {
    base = base.substring(0, 12).replaceAll(RegExp(r'-+$'), '');
  }
  return [
    if (base.isNotEmpty) base,
    for (final v in attrs.values)
      if (clean(v).isNotEmpty) clean(v),
  ].join('-');
}
