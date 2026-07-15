import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Attribute field templates per business type (PRD 7.5).
const variantTemplates = <String, List<String>>{
  'mobile': ['Model', 'RAM', 'Storage', 'Color'],
  'garment': ['Size', 'Color', 'Fabric', 'Gender', 'Design'],
  'hardware': ['Size/Weight', 'Material', 'Grade'],
  'other': ['Option'],
};

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
        attributes: Map<String, String>.from(
            (row['attributes'] as Map? ?? {}).map((k, v) => MapEntry('$k', '$v'))),
        purchasePrice: (row['purchase_price'] as num?)?.toDouble(),
        sellingPrice: (row['selling_price'] as num?)?.toDouble(),
        mrp: (row['mrp'] as num?)?.toDouble(),
        lowStockQty: (row['low_stock_qty'] as num?)?.toDouble(),
      );
}

Future<VariantDraft?> showVariantSheet(
  BuildContext context, {
  required String businessType,
  VariantDraft? existing,
  bool allowOpeningStock = true,
}) {
  return showModalBottomSheet<VariantDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _VariantSheet(
        businessType: businessType,
        existing: existing,
        allowOpeningStock: allowOpeningStock,
      ),
    ),
  );
}

class _VariantSheet extends StatefulWidget {
  const _VariantSheet({
    required this.businessType,
    this.existing,
    required this.allowOpeningStock,
  });

  final String businessType;
  final VariantDraft? existing;
  final bool allowOpeningStock;

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
  // Every field — including the business-type defaults — is just a starting
  // suggestion: the name is editable and the row can be removed entirely.
  late final List<_AttrRow> _rows = widget.existing != null
      ? [
          for (final e in widget.existing!.attributes.entries)
            _AttrRow(name: e.key, value: e.value),
        ]
      : [
          for (final f in variantTemplates[widget.businessType] ?? variantTemplates['other']!)
            _AttrRow(name: f),
        ];
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _barcode = TextEditingController(text: widget.existing?.barcode ?? '');
  late final _purchase = TextEditingController(
      text: widget.existing?.purchasePrice?.toString() ?? '');
  late final _selling = TextEditingController(
      text: widget.existing?.sellingPrice?.toString() ?? '');
  late final _mrp = TextEditingController(text: widget.existing?.mrp?.toString() ?? '');
  late final _opening = TextEditingController(
      text: widget.existing == null ? '' : widget.existing!.openingStock.toString());
  late final _lowStock = TextEditingController(
      text: widget.existing?.lowStockQty?.toString() ?? '');

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
      showError(context, 'Fill at least one attribute');
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.existing == null ? 'Add variant' : 'Edit variant',
              style: Theme.of(context).textTheme.titleLarge),
          const SectionLabel('Attributes'),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _rows[i].name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Field name'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _rows[i].value,
                    decoration: const InputDecoration(labelText: 'Value'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
                  onPressed: () => _removeField(i),
                ),
              ]),
            ),
          OutlinedButton.icon(
            onPressed: _addField,
            icon: const Icon(Icons.add),
            label: const Text('Add field'),
          ),
          const SectionLabel('Codes'),
          TextField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU (optional)')),
          const SizedBox(height: 12),
          TextField(controller: _barcode, decoration: const InputDecoration(labelText: 'Barcode (optional)')),
          const SectionLabel('Pricing (leave blank to use product price)'),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _purchase,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Purchase ₹'))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _selling,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Selling ₹'))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _mrp,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'MRP ₹'))),
          ]),
          const SectionLabel('Stock'),
          Row(children: [
            if (widget.allowOpeningStock) ...[
              Expanded(
                  child: TextField(
                      controller: _opening,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Opening stock'))),
              const SizedBox(width: 12),
            ],
            Expanded(
                child: TextField(
                    controller: _lowStock,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Low stock alert qty'))),
          ]),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save variant')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
