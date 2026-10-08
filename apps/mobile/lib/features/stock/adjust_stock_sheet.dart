import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import 'pack_qty_input.dart';

/// Manual stock adjustment / damaged-lost entry (PRD 7.11).
Future<bool?> showAdjustStockSheet(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> product,
  Map<String, dynamic>? variant,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AdjustStockSheet(product: product, variant: variant),
    ),
  );
}

class _AdjustStockSheet extends ConsumerStatefulWidget {
  const _AdjustStockSheet({required this.product, this.variant});

  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  @override
  ConsumerState<_AdjustStockSheet> createState() => _AdjustStockSheetState();
}

class _AdjustStockSheetState extends ConsumerState<_AdjustStockSheet> {
  final _qty = TextEditingController(); // loose units when counted in packs
  final _packs = TextEditingController();
  final _note = TextEditingController();
  String _mode = 'add'; // add | remove | damage
  bool _busy = false;

  double get currentStock =>
      toDouble((widget.variant ?? widget.product)['current_stock']);

  /// The product's bulk unit (Box of 50), when it has one: stock is then
  /// typed as full boxes + loose units.
  String get _packName =>
      (widget.product['secondary_unit_name'] as String? ?? '').trim();
  double get _packSize => toDouble(widget.product['conversion_factor']);
  bool get _inPacks => _packName.isNotEmpty && _packSize > 0;
  String get _unitShort =>
      (widget.product['units'] as Map?)?['short_name'] as String? ?? 'unit';

  @override
  void dispose() {
    _qty.dispose();
    _packs.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = _inPacks
        ? packQtyTotal(_packs.text, _qty.text, _packSize)
        : double.tryParse(_qty.text);
    if (q == null || q <= 0) {
      showError(context, t('Enter a valid quantity'));
      return;
    }
    // Whole-unit products (allow_decimal off) can't be adjusted by fractions.
    // Callers that pass a minimal product map without unit info skip this.
    final allowDecimal =
        (widget.product['units'] as Map?)?['allow_decimal'] as bool?;
    if (allowDecimal == false && q % 1 != 0) {
      showError(
        context,
        t('This product is stocked in whole units — enter a whole number'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'adjust_stock',
            params: {
              'p_product_id': widget.product['id'],
              'p_variant_id': widget.variant?['id'],
              'p_quantity': _mode == 'add' ? q : -q,
              'p_type': _mode == 'damage' ? 'damage' : 'adjustment',
              'p_note': _note.text.trim(),
            },
          );
      invalidateStockData(ref);
      if (mounted) {
        showSuccess(context, t('Stock updated'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Adjust stock'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.product['name']}${widget.variant != null ? ' — ${widget.variant!['name']}' : ''}'
            '  •  Current: ${qty(currentStock)}',
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'add',
                label: Text(t('Add')),
                icon: Icon(Icons.add),
              ),
              ButtonSegment(
                value: 'remove',
                label: Text(t('Remove')),
                icon: Icon(Icons.remove),
              ),
              ButtonSegment(
                value: 'damage',
                label: Text(t('Damaged/Lost')),
                icon: Icon(Icons.dangerous_outlined),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_inPacks)
            PackQtyInput(
              packs: _packs,
              loose: _qty,
              packName: _packName,
              unitShort: _unitShort,
              factor: _packSize,
              autofocus: true,
              onChanged: () => setState(() {}),
            )
          else
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: t('Quantity')),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: t('Note / reason (optional)'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t('Save adjustment')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
