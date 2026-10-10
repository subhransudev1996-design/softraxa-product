import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'variant_matrix.dart';

/// One variant's new prices and whether it's still sold, from
/// [showVariantPrices]. Only variants that changed are returned.
class VariantPriceChange {
  const VariantPriceChange({
    required this.id,
    required this.sellingPrice,
    required this.purchasePrice,
    required this.isActive,
  });

  final String id;

  /// Null = the product's price.
  final double? sellingPrice;
  final double? purchasePrice;
  final bool isActive;

  Map<String, dynamic> toUpdate() => {
    'selling_price': sellingPrice,
    'purchase_price': purchasePrice,
    'is_active': isActive,
  };
}

/// All of a product's variants in one table: selling and purchase price
/// for each, "set all" at the top, and a switch to stop selling an old
/// size or colour (hidden from billing, kept in past bills).
Future<List<VariantPriceChange>?> showVariantPrices(
  BuildContext context, {
  required Map<String, dynamic> product,
  required List<Map<String, dynamic>> variants,
}) => Navigator.of(context).push<List<VariantPriceChange>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _VariantPrices(product: product, variants: variants),
  ),
);

class _Line {
  _Line(Map<String, dynamic> v)
    : id = v['id'] as String,
      name = v['name'] as String? ?? '',
      sell = TextEditingController(text: _text(v['selling_price'])),
      buy = TextEditingController(text: _text(v['purchase_price'])),
      active = v['is_active'] != false,
      _sell0 = _text(v['selling_price']),
      _buy0 = _text(v['purchase_price']),
      _active0 = v['is_active'] != false;

  final String id;
  final String name;
  final TextEditingController sell;
  final TextEditingController buy;
  bool active;
  final String _sell0;
  final String _buy0;
  final bool _active0;

  static String _text(Object? v) {
    if (v == null) return '';
    final d = toDouble(v);
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  bool get changed =>
      sell.text.trim() != _sell0 ||
      buy.text.trim() != _buy0 ||
      active != _active0;
}

class _VariantPrices extends StatefulWidget {
  const _VariantPrices({required this.product, required this.variants});

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> variants;

  @override
  State<_VariantPrices> createState() => _VariantPricesState();
}

class _VariantPricesState extends State<_VariantPrices> {
  late final List<_Line> _lines = () {
    // In size order, colour by colour.
    final grid = variantGridOf(widget.variants);
    final ordered = <Map<String, dynamic>>[];
    if (grid != null) {
      for (final r in grid.rowValues) {
        for (final c in grid.columns.values) {
          final v = grid.cell(r, c);
          if (v != null) ordered.add(v);
        }
      }
    }
    for (final v in widget.variants) {
      if (!ordered.contains(v)) ordered.add(v);
    }
    return [for (final v in ordered) _Line(v)];
  }();
  final _allSell = TextEditingController();

  void _setAll() {
    setState(() {
      for (final l in _lines) {
        l.sell.text = _allSell.text.trim();
      }
    });
  }

  void _save() {
    final out = <VariantPriceChange>[];
    for (final l in _lines) {
      if (!l.changed) continue;
      out.add(
        VariantPriceChange(
          id: l.id,
          sellingPrice: double.tryParse(l.sell.text.trim()),
          purchasePrice: double.tryParse(l.buy.text.trim()),
          isActive: l.active,
        ),
      );
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final base = money(toDouble(widget.product['selling_price']));
    final baseBuy = money(toDouble(widget.product['purchase_price']));
    final changed = _lines.where((l) => l.changed).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Variant prices')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: changed == 0 ? null : _save,
              child: Text(t('Save ({v1})', {'v1': changed})),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _allSell,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: t('Selling price for all ₹'),
                    hintText: base,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _setAll, child: Text(t('Apply'))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Empty = the product price ({v1}). Switch off a size or colour you no longer sell: it is hidden from billing, past bills keep it.',
              {'v1': base},
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
          SectionLabel(t('{v1} variants', {'v1': _lines.length})),
          for (final l in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      l.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: l.active ? null : AppColors.inkSoft,
                        decoration: l.active
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: l.sell,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: t('Selling ₹'),
                        hintText: base,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: l.buy,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: t('Purchase ₹'),
                        hintText: baseBuy,
                      ),
                    ),
                  ),
                  Switch(
                    value: l.active,
                    onChanged: (v) => setState(() => l.active = v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
