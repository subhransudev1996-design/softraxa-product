import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_refresh.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'piece_providers.dart';

/// "Cut pieces" management card on the product detail page — for rod/sheet
/// stores tracking individual remnants (PRD Phase 3). Pieces are auxiliary:
/// totals live in current_stock; this card just records how the total is
/// physically split, with a mismatch hint when the two drift apart.
class PiecesCard extends ConsumerWidget {
  const PiecesCard({super.key, required this.product});

  final Map<String, dynamic> product;

  String get _productId => product['id'] as String;
  String get _unit =>
      (product['units'] as Map?)?['short_name'] as String? ?? '';

  Future<void> _addPieces(BuildContext context, WidgetRef ref) async {
    final countC = TextEditingController(text: '1');
    final lengthC = TextEditingController();
    final labelC = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add pieces'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: countC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'How many'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: lengthC,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'Length each${_unit.isEmpty ? '' : ' ($_unit)'}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelC,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                helperText: 'e.g. Rack A',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final count = int.tryParse(countC.text) ?? 0;
    final length = double.tryParse(lengthC.text) ?? 0;
    if (count <= 0 || length <= 0) {
      if (context.mounted) showError(context, 'Enter a valid count and length');
      return;
    }
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      final label = labelC.text.trim();
      await ref.read(supabaseProvider).from('stock_pieces').insert([
        for (var i = 0; i < count; i++)
          {
            'business_id': businessId,
            'product_id': _productId,
            'label': count > 1 && label.isNotEmpty ? '$label ${i + 1}' : label,
            'length': length,
          },
      ]);
      ref.invalidate(stockPiecesProvider(_productId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _editPiece(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> piece,
  ) async {
    final lengthC = TextEditingController(
      text: qty(toDouble(piece['length'])).replaceAll(',', ''),
    );
    final labelC = TextEditingController(text: piece['label'] as String? ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit piece'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: lengthC,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Length${_unit.isEmpty ? '' : ' ($_unit)'}',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: labelC,
              decoration: const InputDecoration(labelText: 'Label (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final length = double.tryParse(lengthC.text) ?? 0;
    if (length <= 0) {
      if (context.mounted) showError(context, 'Enter a valid length');
      return;
    }
    try {
      await ref
          .read(supabaseProvider)
          .from('stock_pieces')
          .update({'length': length, 'label': labelC.text.trim()})
          .eq('id', piece['id'] as String);
      ref.invalidate(stockPiecesProvider(_productId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _scrapPiece(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> piece,
  ) async {
    final length = toDouble(piece['length']);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scrap this piece?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${qty(length)} $_unit leaves available stock as scrap.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason *'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () {
              if (reason.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Mark scrap'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Server-side: the piece and total stock change together (0049).
      await ref
          .read(supabaseProvider)
          .rpc(
            'reclassify_piece',
            params: {
              'p_piece': piece['id'],
              'p_status': 'scrap',
              'p_reason': reason.text.trim(),
            },
          );
      ref.invalidate(stockPiecesProvider(_productId));
      invalidateStockData(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Per-product cutting rules (PD27, PD40, PD42, PD44; migration 0049).
  Future<void> _editRules(BuildContext context, WidgetRef ref) async {
    String n(String k) {
      final v = toDouble(product[k]);
      return v == 0 ? '' : qty(v);
    }

    final allowance = TextEditingController(text: n('cutting_allowance'));
    final minLeft = TextEditingController(text: n('min_remnant_length'));
    final charge = TextEditingController(text: n('cutting_charge'));
    var returns = product['allow_piece_returns'] == true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Cutting rules'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: allowance,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cutting loss per cut ($_unit)',
                    helperText:
                        'Lost at each cut, e.g. 0.01 — the shop\'s loss',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minLeft,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Smallest reusable leftover ($_unit)',
                    helperText: 'Shorter leftovers are suggested as scrap',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: charge,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cutting charge per cut ₹ (optional)',
                    helperText: 'Added to the bill as its own line',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: returns,
                  onChanged: (v) => setState(() => returns = v),
                  title: const Text('Allow returns of cut pieces'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    double v(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
    try {
      await ref
          .read(supabaseProvider)
          .from('products')
          .update({
            'cutting_allowance': v(allowance),
            'min_remnant_length': v(minLeft),
            'cutting_charge': v(charge),
            'allow_piece_returns': returns,
          })
          .eq('id', _productId);
      invalidateStockData(ref);
      if (context.mounted) showSuccess(context, 'Cutting rules saved');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pieces = ref.watch(stockPiecesProvider(_productId));
    final currentStock = toDouble(product['current_stock']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconChip(
                  Icons.straighten,
                  color: AppColors.teal,
                  size: 38,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Cut pieces',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                IconButton(
                  tooltip: 'Cutting rules',
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: () => _editRules(context, ref),
                ),
                TextButton.icon(
                  onPressed: () => _addPieces(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            pieces.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text(friendlyError(e)),
              ),
              data: (rows) {
                final piecesTotal = rows.fold<double>(
                  0,
                  (s, p) => s + toDouble(p['length']),
                );
                final mismatch = (piecesTotal - currentStock).abs() > 0.001;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rows.isEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(0, 4, 8, 4),
                        child: Text(
                          'No pieces recorded. Add them so billing can pick '
                          'which piece each cut comes from.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    for (final piece in rows)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${(piece['label'] as String? ?? '').isNotEmpty ? '${piece['label']} — ' : ''}'
                              '${qty(toDouble(piece['length']))} $_unit'
                              '${switch (piece['source']) {
                                'remnant' => ' · offcut',
                                'return' => ' · returned',
                                _ => '',
                              }}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _editPiece(context, ref, piece),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.red,
                            ),
                            tooltip: 'Mark scrap',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _scrapPiece(context, ref, piece),
                          ),
                        ],
                      ),
                    if (rows.isNotEmpty && mismatch)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 8),
                        child: Text(
                          'Pieces total ${qty(piecesTotal)} $_unit, stock is '
                          '${qty(currentStock)} $_unit — update pieces or adjust stock.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
