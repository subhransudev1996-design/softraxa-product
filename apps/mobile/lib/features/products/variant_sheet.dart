import '../../core/i18n.dart';
import 'package:flutter/material.dart';

import '../../core/business_category.dart';
import '../../core/theme.dart';
import '../../core/variant_presets.dart';
import '../../core/widgets.dart';

/// Result of editing a variant in the sheet (not yet persisted).
class VariantDraft {
  VariantDraft({
    this.id,
    this.name = '',
    this.sku = '',
    this.barcode = '',
    Map<String, String>? attributes,
    this.purchasePrice,
    this.sellingPrice,
    this.mrp,
    this.openingStock = 0,
    this.lowStockQty,
  }) : attributes = attributes ?? {};

  final String? id; // null = new
  String name;
  String sku;
  String barcode;
  Map<String, String> attributes;
  double? purchasePrice;
  double? sellingPrice;
  double? mrp;
  double openingStock;
  double? lowStockQty;

  Map<String, dynamic> toRow(String productId) => {
    'product_id': productId,
    'name': name,
    'sku': sku,
    'barcode': barcode,
    'attributes': attributes,
    'purchase_price': purchasePrice,
    'selling_price': sellingPrice,
    'mrp': mrp,
    'low_stock_qty': lowStockQty,
  };

  static VariantDraft fromRow(Map<String, dynamic> row) => VariantDraft(
    id: row['id'] as String?,
    name: row['name'] as String? ?? '',
    sku: row['sku'] as String? ?? '',
    barcode: row['barcode'] as String? ?? '',
    attributes: attributesOf(row),
    purchasePrice: (row['purchase_price'] as num?)?.toDouble(),
    sellingPrice: (row['selling_price'] as num?)?.toDouble(),
    mrp: (row['mrp'] as num?)?.toDouble(),
    lowStockQty: (row['low_stock_qty'] as num?)?.toDouble(),
  );

  /// A saved variant row's attributes as field → value.
  static Map<String, String> attributesOf(Map<String, dynamic> row) =>
      Map<String, String>.from(
        (row['attributes'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v')),
      );
}

/// [productName] and [categoryName] pick fields that fit the product (a
/// washing machine gets Capacity and Type). [siblings] are the product's
/// other variants' attributes: a new variant copies their fields and offers
/// their values.
Future<VariantDraft?> showVariantSheet(
  BuildContext context, {
  required String businessType,
  VariantDraft? existing,
  bool allowOpeningStock = true,
  String productName = '',
  String categoryName = '',
  List<Map<String, String>> siblings = const [],
}) {
  final sheet = _VariantSheet(
    businessType: businessType,
    existing: existing,
    allowOpeningStock: allowOpeningStock,
    productName: productName,
    categoryName: categoryName,
    siblings: siblings,
  );
  // Desktop: a dialog, like the other pickers.
  if (isWideLayout(context)) {
    return showDialog<VariantDraft>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
          ),
          child: sheet,
        ),
      ),
    );
  }
  return showModalBottomSheet<VariantDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: sheet,
    ),
  );
}

class _VariantSheet extends StatefulWidget {
  const _VariantSheet({
    required this.businessType,
    this.existing,
    required this.allowOpeningStock,
    this.productName = '',
    this.categoryName = '',
    this.siblings = const [],
  });

  final String businessType;
  final VariantDraft? existing;
  final bool allowOpeningStock;
  final String productName;
  final String categoryName;
  final List<Map<String, String>> siblings;

  @override
  State<_VariantSheet> createState() => _VariantSheetState();
}

class _AttrRow {
  _AttrRow({String name = '', String value = ''})
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value);
  final TextEditingController name;
  final TextEditingController value;
}

class _VariantSheetState extends State<_VariantSheet> {
  // Every field is a suggestion: the name is editable and the row can be
  // removed. Where the fields come from, in order:
  //   1. editing: the variant's own fields;
  //   2. the product already has variants: the same fields, same order;
  //   3. the product's name or category matches a preset (washing machine…);
  //   4. the shop type's fields (PRD 7.5).
  late VariantPreset? _preset = suggestVariantPreset(
    name: widget.productName,
    category: widget.categoryName,
  );
  late bool _fromSiblings =
      widget.existing == null && widget.siblings.any((m) => m.isNotEmpty);
  late final List<_AttrRow> _rows = widget.existing != null
      ? [
          for (final e in widget.existing!.attributes.entries)
            _AttrRow(name: e.key, value: e.value),
        ]
      : _fromSiblings
      ? [
          for (final k in widget.siblings.firstWhere((m) => m.isNotEmpty).keys)
            _AttrRow(name: k),
        ]
      : _rowsFor(_preset);
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _barcode = TextEditingController(
    text: widget.existing?.barcode ?? '',
  );
  late final _purchase = TextEditingController(
    text: widget.existing?.purchasePrice?.toString() ?? '',
  );
  late final _selling = TextEditingController(
    text: widget.existing?.sellingPrice?.toString() ?? '',
  );
  late final _mrp = TextEditingController(
    text: widget.existing?.mrp?.toString() ?? '',
  );
  late final _opening = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.openingStock.toString(),
  );
  late final _lowStock = TextEditingController(
    text: widget.existing?.lowStockQty?.toString() ?? '',
  );

  List<_AttrRow> _rowsFor(VariantPreset? preset) => [
    for (final f
        in preset?.fields.map((f) => f.name) ??
            categoryOf(widget.businessType).variantFields)
      _AttrRow(name: f),
  ];

  /// Switch to another product type's fields; a value already typed into a
  /// field of the same name is kept.
  void _usePreset(VariantPreset? preset) {
    final typed = {
      for (final r in _rows)
        if (r.value.text.trim().isNotEmpty)
          r.name.text.trim().toLowerCase(): r.value.text,
    };
    setState(() {
      _preset = preset;
      _fromSiblings = false;
      _rows
        ..clear()
        ..addAll(_rowsFor(preset));
      for (final r in _rows) {
        r.value.text = typed[r.name.text.trim().toLowerCase()] ?? '';
      }
    });
  }

  /// One-tap values for a field: what this product's other variants used,
  /// then common values for that field name.
  List<String> _optionsFor(String fieldName) {
    final key = fieldName.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final out = <String>[];
    void add(String v) {
      if (v.trim().isNotEmpty && !out.contains(v)) out.add(v);
    }

    for (final m in widget.siblings) {
      for (final e in m.entries) {
        if (e.key.trim().toLowerCase() == key) add(e.value);
      }
    }
    // The chosen product type's own values; other types' values only for a
    // field it doesn't define (a washing machine's Type isn't "Split").
    final own = (_preset?.fields ?? const <VariantField>[]).where(
      (f) => f.name.toLowerCase() == key,
    );
    if (own.isNotEmpty) {
      own.expand((f) => f.options).forEach(add);
    } else {
      optionsForField(fieldName).forEach(add);
    }
    return out.take(8).toList();
  }

  String get _sourceLabel {
    if (_fromSiblings) return 'Same fields as this product\'s other variants';
    if (_preset != null) return 'Fields for: ${_preset!.label}';
    return 'Fields for your shop type';
  }

  void _addField() {
    setState(() => _rows.add(_AttrRow()));
  }

  void _removeField(int index) {
    setState(() => _rows.removeAt(index));
  }

  void _save() {
    final attributes = <String, String>{
      for (final row in _rows)
        if (row.name.text.trim().isNotEmpty && row.value.text.trim().isNotEmpty)
          row.name.text.trim(): row.value.text.trim(),
    };
    final name = attributes.values.join(' / ');
    if (name.isEmpty) {
      showError(context, t('Fill at least one attribute'));
      return;
    }
    Navigator.pop(
      context,
      VariantDraft(
        id: widget.existing?.id,
        name: name,
        sku: _sku.text.trim(),
        barcode: _barcode.text.trim(),
        attributes: attributes,
        purchasePrice: double.tryParse(_purchase.text),
        sellingPrice: double.tryParse(_selling.text),
        mrp: double.tryParse(_mrp.text),
        openingStock: double.tryParse(_opening.text) ?? 0,
        lowStockQty: double.tryParse(_lowStock.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialog = isWideLayout(context);
    final list = ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: dialog,
      children: [
        Text(
          widget.existing == null ? t('Add variant') : 'Edit variant',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SectionLabel(t('Attributes')),
        if (widget.existing == null) ...[
          _FieldsSource(label: _sourceLabel, onPick: _usePreset),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _rows[i].name,
                        onChanged: (_) => setState(() {}),
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: t('Field name'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _rows[i].value,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: t('Value')),
                      ),
                    ),
                    IconButton(
                      tooltip: t('Remove field'),
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: AppColors.red,
                      ),
                      onPressed: () => _removeField(i),
                    ),
                  ],
                ),
                _ValueChips(
                  row: _rows[i],
                  options: _optionsFor(_rows[i].name.text),
                  onPicked: () => setState(() {}),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addField,
          icon: const Icon(Icons.add),
          label: Text(t('Add field')),
        ),
        SectionLabel(t('Codes')),
        TextField(
          controller: _sku,
          decoration: InputDecoration(labelText: t('SKU (optional)')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _barcode,
          decoration: InputDecoration(labelText: t('Barcode (optional)')),
        ),
        SectionLabel(t('Pricing (leave blank to use product price)')),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _purchase,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: t('Purchase ₹')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _selling,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: t('Selling ₹')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _mrp,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: t('MRP ₹')),
              ),
            ),
          ],
        ),
        SectionLabel(t('Stock')),
        Row(
          children: [
            if (widget.allowOpeningStock) ...[
              Expanded(
                child: TextField(
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: t('Opening stock')),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: TextField(
                controller: _lowStock,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t('Low stock alert qty'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: Text(t('Save variant'))),
        const SizedBox(height: 24),
      ],
    );
    if (dialog) return list;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scrollController) =>
          PrimaryScrollController(controller: scrollController, child: list),
    );
  }
}

/// "Fields for: Washing machine · Change" — pick another product type.
class _FieldsSource extends StatelessWidget {
  const _FieldsSource({required this.label, required this.onPick});

  final String label;
  final ValueChanged<VariantPreset?> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          PopupMenuButton<int>(
            tooltip: t('Use the fields of another product type'),
            onSelected: (i) => onPick(i < 0 ? null : variantPresets[i]),
            itemBuilder: (_) => [
              for (var i = 0; i < variantPresets.length; i++)
                PopupMenuItem(value: i, child: Text(variantPresets[i].label)),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: -1,
                child: Text(t('My shop type\'s fields')),
              ),
            ],
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(t('Change'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-fill values under a field.
class _ValueChips extends StatelessWidget {
  const _ValueChips({
    required this.row,
    required this.options,
    required this.onPicked,
  });

  final _AttrRow row;
  final List<String> options;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final current = row.value.text.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(o),
              selected: o == current,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                row.value.text = o;
                onPicked();
              },
            ),
        ],
      ),
    );
  }
}
