import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_refresh.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'piece_providers.dart';

/// Same-length pieces shown as one row: "12 ft × 3".
class PieceGroup {
  const PieceGroup(this.length, this.pieces);
  final double length;
  final List<Map<String, dynamic>> pieces;
}

/// Groups available pieces by length, longest first.
List<PieceGroup> groupPieces(List<Map<String, dynamic>> rows) {
  final byLength = <double, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final len = (toDouble(r['length']) * 1000).round() / 1000;
    byLength.putIfAbsent(len, () => []).add(r);
  }
  final keys = byLength.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) PieceGroup(k, byLength[k]!)];
}

/// "Pieces in stock" on the product page — rods, pipe, wire, cloth sold in
/// cut lengths. The app keeps the pieces by itself (migration 0064): new
/// stock becomes full pieces, each bill cuts the best piece. This card
/// only shows them, and fixes the odd case where they drift from stock.
class PiecesCard extends ConsumerWidget {
  const PiecesCard({super.key, required this.product});

  final Map<String, dynamic> product;

  String get _productId => product['id'] as String;
  String get _unit =>
      (product['units'] as Map?)?['short_name'] as String? ?? '';

  void _refresh(WidgetRef ref) {
    ref.invalidate(stockPiecesProvider(_productId));
    invalidateStockData(ref);
  }

  Future<void> _matchToStock(BuildContext context, WidgetRef ref) async {
    try {
      final change = toDouble(
        await ref
            .read(supabaseProvider)
            .rpc('match_pieces_to_stock', params: {'p_product': _productId}),
      );
      _refresh(ref);
      if (context.mounted) {
        showSuccess(
          context,
          change > 0
              ? '${qty(change)} $_unit added as pieces'
              : change < 0
              ? '${qty(-change)} $_unit taken off the smallest pieces'
              : 'Pieces already match stock',
        );
      }
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Correct the length')),
        content: TextField(
          controller: lengthC,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Actual length${_unit.isEmpty ? '' : ' ($_unit)'}',
            helperText: t('Measured on the shelf'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Save')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final length = double.tryParse(lengthC.text) ?? 0;
    if (length <= 0) {
      if (context.mounted) showError(context, t('Enter a valid length'));
      return;
    }
    try {
      await ref
          .read(supabaseProvider)
          .from('stock_pieces')
          .update({'length': length})
          .eq('id', piece['id'] as String);
      ref.invalidate(stockPiecesProvider(_productId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _throwAway(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> piece,
  ) async {
    final length = toDouble(piece['length']);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Throw away a ${qty(length)} $_unit piece?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock goes down by ${qty(length)} $_unit.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t('Why? *'),
                helperText: t('e.g. bent, rusted, too short to sell'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () {
              if (reason.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: Text(t('Throw away')),
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
      _refresh(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Full length and the optional cutting details (0049, 0064), in plain
  /// words.
  Future<void> _editSettings(BuildContext context, WidgetRef ref) async {
    String n(String k) {
      final v = toDouble(product[k]);
      return v == 0 ? '' : qty(v).replaceAll(',', '');
    }

    final full = TextEditingController(text: n('piece_length'));
    final charge = TextEditingController(text: n('cutting_charge'));
    final minLeft = TextEditingController(text: n('min_remnant_length'));
    final allowance = TextEditingController(text: n('cutting_allowance'));
    var returns = product['allow_piece_returns'] == true;
    var more =
        toDouble(product['min_remnant_length']) > 0 ||
        toDouble(product['cutting_allowance']) > 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t('Cut length settings')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: full,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Full length of 1 piece ($_unit)',
                    helperText: t('1 rod = 12 ft → 12. Empty for wire coils'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: charge,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: t('Charge for each cut ₹ (optional)'),
                    helperText: t('Added to the bill by itself'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: returns,
                  onChanged: (v) => setState(() => returns = v),
                  title: Text(t('Customers can return cut pieces')),
                ),
                if (!more)
                  TextButton(
                    onPressed: () => setState(() => more = true),
                    child: Text(t('More settings')),
                  )
                else ...[
                  TextField(
                    controller: minLeft,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Throw away leftovers shorter than ($_unit)',
                      helperText: t('Empty = keep every leftover'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: allowance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Lost at each cut by the saw ($_unit)',
                      helperText: t('Usually empty'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Save')),
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
            'piece_length': v(full),
            'cutting_charge': v(charge),
            'min_remnant_length': v(minLeft),
            'cutting_allowance': v(allowance),
            'allow_piece_returns': returns,
          })
          .eq('id', _productId);
      invalidateStockData(ref);
      if (context.mounted) showSuccess(context, t('Saved'));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pieces = ref.watch(stockPiecesProvider(_productId));
    final currentStock = toDouble(product['current_stock']);
    final fullLength = toDouble(product['piece_length']);
    final canFix = ref.watch(appContextProvider).value?.canManageStock ?? false;

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('Pieces in stock'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        fullLength > 0
                            ? 'Full piece = ${qty(fullLength)} $_unit · '
                                  'kept up to date by itself'
                            : 'Kept up to date by itself',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t('Settings'),
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: () => _editSettings(context, ref),
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
                    const SizedBox(height: 6),
                    if (rows.isEmpty && !mismatch)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                        child: Text(t('No stock yet. When you add stock or a purchase, it shows up here as pieces.'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    for (final g in groupPieces(rows))
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${qty(g.length)} $_unit',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (g.pieces.length > 1)
                                    TextSpan(text: '  × ${g.pieces.length}'),
                                  TextSpan(
                                    text:
                                        fullLength > 0 &&
                                            (g.length - fullLength).abs() <
                                                0.001
                                        ? '  full'
                                        : '  leftover',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                          if (canFix)
                            PopupMenuButton<String>(
                              tooltip: t('Change'),
                              icon: const Icon(Icons.more_vert, size: 18),
                              onSelected: (a) => a == 'edit'
                                  ? _editPiece(context, ref, g.pieces.first)
                                  : _throwAway(context, ref, g.pieces.first),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(
                                    g.pieces.length > 1
                                        ? 'Correct one piece\'s length'
                                        : 'Correct the length',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'scrap',
                                  child: Text(
                                    g.pieces.length > 1
                                        ? 'Throw away one piece'
                                        : 'Throw away',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    if (mismatch)
                      Container(
                        margin: const EdgeInsets.only(top: 8, right: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        decoration: BoxDecoration(
                          color: AppColors.orangeSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Pieces add up to ${qty(piecesTotal)} $_unit, '
                                'stock is ${qty(currentStock)} $_unit.',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (canFix)
                              TextButton(
                                onPressed: () => _matchToStock(context, ref),
                                child: Text(t('Match to stock')),
                              ),
                          ],
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
