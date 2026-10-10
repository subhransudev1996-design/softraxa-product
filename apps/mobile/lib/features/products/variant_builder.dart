import 'package:flutter/material.dart';

import '../../core/business_category.dart';
import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/variant_presets.dart';
import '../../core/widgets.dart';
import 'variant_matrix.dart';
import 'variant_sheet.dart';

/// "Sizes & colours": pick what a product comes in — tap S M L XL, tap
/// Red Blue — and every combination is made at once, in one table with
/// its stock and price. Used when adding a product (all its variants) and
/// later from the product page (only the new combinations; the ones
/// already made are shown, locked).
///
/// Returns the variants to make; null when cancelled.
Future<List<VariantDraft>?> showVariantBuilder(
  BuildContext context, {
  required String businessType,
  String productName = '',
  String categoryName = '',
  String productCode = '',
  double? productPrice,
  List<VariantDraft> drafts = const [],
  List<Map<String, dynamic>> existing = const [],
  bool allowOpeningStock = true,
}) => Navigator.of(context).push<List<VariantDraft>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _VariantBuilder(
      businessType: businessType,
      productName: productName,
      categoryName: categoryName,
      productCode: productCode,
      productPrice: productPrice,
      drafts: drafts,
      existing: existing,
      allowOpeningStock: allowOpeningStock,
    ),
  ),
);

class _AxisState {
  _AxisState(
    this.name,
    this.options, {
    List<String>? selected,
    Set<String>? locked,
  }) : selected = selected ?? [],
       locked = locked ?? {};

  final String name;
  final List<String> options;
  final List<String> selected;

  /// Values that variants already use (edit later): can't be unticked here.
  final Set<String> locked;
  final custom = TextEditingController();
}

class _Row {
  _Row(this.attrs, {String stock = '', String price = ''})
    : stock = TextEditingController(text: stock),
      price = TextEditingController(text: price);

  final Map<String, String> attrs;
  final TextEditingController stock;
  final TextEditingController price;
}

class _VariantBuilder extends StatefulWidget {
  const _VariantBuilder({
    required this.businessType,
    required this.productName,
    required this.categoryName,
    required this.productCode,
    required this.productPrice,
    required this.drafts,
    required this.existing,
    required this.allowOpeningStock,
  });

  final String businessType;
  final String productName;
  final String categoryName;
  final String productCode;
  final double? productPrice;
  final List<VariantDraft> drafts;
  final List<Map<String, dynamic>> existing;
  final bool allowOpeningStock;

  @override
  State<_VariantBuilder> createState() => _VariantBuilderState();
}

class _VariantBuilderState extends State<_VariantBuilder> {
  late final VariantPreset? _preset = suggestVariantPreset(
    name: widget.productName,
    category: widget.categoryName,
  );

  /// Types offered as chips: this product's kind, the shop type's, and
  /// the everyday ones.
  late final List<String> _types = () {
    final out = <String>[];
    void add(String s) {
      if (s.trim().isNotEmpty &&
          !out.any((o) => o.toLowerCase() == s.toLowerCase())) {
        out.add(s);
      }
    }

    for (final a in axesOf(widget.existing)) {
      add(a.name);
    }
    for (final d in widget.drafts) {
      d.attributes.keys.forEach(add);
    }
    _preset?.fields.forEach((f) => add(f.name));
    categoryOf(
      widget.businessType,
    ).variantFields.where((f) => f != 'Option').forEach(add);
    for (final s in ['Size', 'Color', 'Weight', 'Pack']) {
      add(s);
    }
    return out;
  }();

  final List<_AxisState> _axes = [];
  final Map<String, _Row> _rows = {};
  final _samePrice = TextEditingController();
  bool _autoSku = false;

  late final Set<String> _existingKeys = {
    for (final v in widget.existing) variantKey(attributesOfRow(v)),
  };

  @override
  void initState() {
    super.initState();
    // Edit later: the axes and values already in use, locked.
    for (final a in axesOf(widget.existing)) {
      _axes.add(
        _AxisState(
          a.name,
          _optionsFor(a.name),
          selected: [...a.values],
          locked: {...a.values},
        ),
      );
    }
    // Changing the variants of a product being added: what was chosen.
    if (widget.existing.isEmpty && widget.drafts.isNotEmpty) {
      final rows = [
        for (final d in widget.drafts)
          {'attributes': d.attributes, 'name': d.name},
      ];
      for (final a in axesOf(rows)) {
        _axes.add(
          _AxisState(a.name, _optionsFor(a.name), selected: [...a.values]),
        );
      }
      for (final d in widget.drafts) {
        _rows[variantKey(d.attributes)] = _Row(
          d.attributes,
          stock: d.openingStock > 0 ? qty(d.openingStock) : '',
          price: d.sellingPrice == null ? '' : _num(d.sellingPrice!),
        );
      }
      _autoSku =
          widget.drafts.isNotEmpty &&
          widget.drafts.every(
            (d) =>
                d.sku.isNotEmpty &&
                d.sku == autoVariantSku(widget.productCode, d.attributes),
          );
    }
    // Nothing yet: start with this kind of product's first type (Size for
    // clothes) so the first tap is on a value.
    if (_axes.isEmpty && _types.isNotEmpty) {
      _axes.add(_AxisState(_types.first, _optionsFor(_types.first)));
    }
  }

  static const _clothingSizes = [
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    '3XL',
    'Free size',
  ];

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  List<String> _optionsFor(String name) {
    final key = name.toLowerCase();
    final out = <String>[];
    void add(String v) {
      if (v.trim().isNotEmpty && !out.contains(v)) out.add(v);
    }

    for (final a in axesOf(widget.existing)) {
      if (a.name.toLowerCase() == key) a.values.forEach(add);
    }
    final own = (_preset?.fields ?? const <VariantField>[]).where(
      (f) => f.name.toLowerCase() == key,
    );
    if (own.isNotEmpty) {
      // A kurta's sizes are S M L — not a wire's sq mm or a tile's cm.
      own.expand((f) => f.options).forEach(add);
    } else if (looksLikeSize(name) && _preset == null) {
      _clothingSizes.forEach(add);
    } else {
      optionsForField(name).take(10).forEach(add);
    }
    return out;
  }

  // ---------------- choosing ----------------

  void _toggleType(String name) {
    setState(() {
      final i = _axes.indexWhere((a) => a.name == name);
      if (i >= 0) {
        if (_axes[i].locked.isEmpty) _axes.removeAt(i);
      } else {
        _axes.add(_AxisState(name, _optionsFor(name)));
      }
    });
  }

  Future<void> _otherType() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('What else does it vary by?')),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: t('e.g. Design, Flavour, Length'),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(t('Add')),
          ),
        ],
      ),
    );
    final n = (name ?? '').trim();
    if (n.isEmpty || !mounted) return;
    if (!_types.any((t) => t.toLowerCase() == n.toLowerCase())) _types.add(n);
    if (!_axes.any((a) => a.name.toLowerCase() == n.toLowerCase())) {
      setState(() => _axes.add(_AxisState(n, _optionsFor(n))));
    }
  }

  void _toggleValue(_AxisState a, String v) {
    if (a.locked.contains(v)) return;
    setState(() {
      if (a.selected.contains(v)) {
        a.selected.remove(v);
      } else {
        a.selected.add(v);
      }
    });
  }

  /// "XXL, 3XL" typed in: each becomes a chip, ticked.
  void _addCustom(_AxisState a) {
    final values = a.custom.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    setState(() {
      for (final v in values) {
        if (!a.options.contains(v)) a.options.add(v);
        if (!a.selected.contains(v)) a.selected.add(v);
      }
      a.custom.clear();
    });
  }

  // ---------------- the table ----------------

  List<Map<String, String>> get _combos => variantCombinations([
    for (final a in _axes) VariantAxis(a.name, sortAxisValues(a.selected)),
  ]);

  _Row _rowFor(Map<String, String> attrs) =>
      _rows.putIfAbsent(variantKey(attrs), () => _Row(attrs));

  void _applySamePrice() {
    setState(() {
      for (final c in _combos) {
        if (!_existingKeys.contains(variantKey(c))) {
          _rowFor(c).price.text = _samePrice.text.trim();
        }
      }
    });
  }

  void _done() {
    final previous = {
      for (final d in widget.drafts) variantKey(d.attributes): d,
    };
    final out = <VariantDraft>[];
    for (final c in _combos) {
      final key = variantKey(c);
      if (_existingKeys.contains(key)) continue;
      final row = _rowFor(c);
      final before = previous[key];
      out.add(
        VariantDraft(
          name: variantNameOf(c),
          attributes: c,
          sku: _autoSku
              ? autoVariantSku(widget.productCode, c)
              : (before?.sku ?? ''),
          barcode: before?.barcode ?? '',
          purchasePrice: before?.purchasePrice,
          mrp: before?.mrp,
          lowStockQty: before?.lowStockQty,
          sellingPrice: double.tryParse(row.price.text.trim()),
          openingStock: double.tryParse(row.stock.text.trim()) ?? 0,
        ),
      );
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final combos = _combos;
    final newCount = combos
        .where((c) => !_existingKeys.contains(variantKey(c)))
        .length;
    final editingLater = widget.existing.isNotEmpty;
    final priceHint = widget.productPrice == null
        ? t('Product price')
        : money(widget.productPrice);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('Sizes & colours')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: (editingLater && newCount == 0) ? null : _done,
              child: Text(
                editingLater
                    ? t('Add {v1}', {'v1': newCount})
                    : t('Done ({v1})', {'v1': newCount}),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t('What does it come in?'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _types)
                FilterChip(
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: WidgetStateTextStyle.resolveWith(
                    (st) => TextStyle(
                      color: st.contains(WidgetState.selected)
                          ? Colors.white
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  label: Text(name),
                  selected: _axes.any((a) => a.name == name),
                  onSelected: (_) => _toggleType(name),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(t('Other')),
                onPressed: _otherType,
              ),
            ],
          ),
          for (final a in _axes) ...[
            const SizedBox(height: 16),
            Text(
              t('{v1} — tap the ones you have', {'v1': a.name}),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in [
                  ...a.options,
                  ...a.selected.where((s) => !a.options.contains(s)),
                ])
                  FilterChip(
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle: WidgetStateTextStyle.resolveWith(
                      (st) => TextStyle(
                        color: st.contains(WidgetState.selected)
                            ? Colors.white
                            : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    label: Text(v),
                    selected: a.selected.contains(v),
                    onSelected: a.locked.contains(v)
                        ? null
                        : (_) => _toggleValue(a, v),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: a.custom,
              decoration: InputDecoration(
                isDense: true,
                hintText: t('Add your own, e.g. 3XL, Maroon'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _addCustom(a),
                ),
              ),
              onSubmitted: (_) => _addCustom(a),
            ),
          ],
          const SizedBox(height: 20),
          SectionLabel(
            editingLater
                ? (newCount == 1
                      ? t('1 new variant')
                      : t('{v1} new variants', {'v1': newCount}))
                : (combos.length == 1
                      ? t('1 variant')
                      : t('{v1} variants', {'v1': combos.length})),
          ),
          if (combos.isEmpty)
            Text(
              t('Tap a size, colour or other value above.'),
              style: TextStyle(color: AppColors.inkSoft),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _samePrice,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: t('Same price for all ₹'),
                      hintText: priceHint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _applySamePrice,
                  child: Text(t('Apply')),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _autoSku,
              onChanged: (v) => setState(() => _autoSku = v),
              title: Text(t('Make codes automatically')),
              subtitle: Text(autoVariantSku(widget.productCode, combos.first)),
            ),
            const SizedBox(height: 4),
            for (final c in combos)
              Builder(
                builder: (context) {
                  final made = _existingKeys.contains(variantKey(c));
                  final row = _rowFor(c);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            variantNameOf(c),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: made ? AppColors.inkSoft : null,
                            ),
                          ),
                        ),
                        if (made)
                          Expanded(
                            flex: 7,
                            child: Text(
                              t('Already there'),
                              style: TextStyle(color: AppColors.inkSoft),
                            ),
                          )
                        else ...[
                          if (widget.allowOpeningStock) ...[
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: row.stock,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: t('Stock'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: row.price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: t('Price ₹'),
                                hintText: priceHint,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            Text(
              t('Leave the price empty to use the product price.'),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
