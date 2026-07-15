import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';

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
  final _qty = TextEditingController();
  final _note = TextEditingController();
  String _mode = 'add'; // add | remove | damage
  bool _busy = false;

  double get currentStock =>
      toDouble((widget.variant ?? widget.product)['current_stock']);

  Future<void> _save() async {
    final q = double.tryParse(_qty.text);
    if (q == null || q <= 0) {
      showError(context, 'Enter a valid quantity');
      return;
    }
    // Whole-unit products (allow_decimal off) can't be adjusted by fractions.
    // Callers that pass a minimal product map without unit info skip this.
    final allowDecimal = (widget.product['units'] as Map?)?['allow_decimal'] as bool?;
    if (allowDecimal == false && q % 1 != 0) {
      showError(context, 'This product is stocked in whole units — enter a whole number');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(supabaseProvider).rpc('adjust_stock', params: {
        'p_product_id': widget.product['id'],
        'p_variant_id': widget.variant?['id'],
        'p_quantity': _mode == 'add' ? q : -q,
        'p_type': _mode == 'damage' ? 'damage' : 'adjustment',
        'p_note': _note.text.trim(),
      });
      if (mounted) {
        showSuccess(context, 'Stock updated');
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
          Text('Adjust stock', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${widget.product['name']}${widget.variant != null ? ' — ${widget.variant!['name']}' : ''}'
            '  •  Current: ${qty(currentStock)}',
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'add', label: Text('Add'), icon: Icon(Icons.add)),
              ButtonSegment(value: 'remove', label: Text('Remove'), icon: Icon(Icons.remove)),
              ButtonSegment(value: 'damage', label: Text('Damaged/Lost'), icon: Icon(Icons.dangerous_outlined)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note / reason (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save adjustment'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
