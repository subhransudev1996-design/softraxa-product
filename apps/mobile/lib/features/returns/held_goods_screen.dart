import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_refresh.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'exchange.dart';

/// Returned goods held out of sale (D28, migration 0042): awaiting
/// inspection, damaged or scrap. Current balances from the stock_holds view.
final heldGoodsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('stock_holds')
          .select()
          .order('product_name')
          .limit(500);
      return List<Map<String, dynamic>>.from(rows);
    });

/// Where held goods can go next, and who may send them there (PD29):
/// back to sale or written off needs stock permission; moving between
/// hold states needs returns permission.
List<(String to, String label)> heldGoodsMoves(
  String from, {
  required bool canStock,
  required bool canReturns,
}) => [
  if (canStock) ('sellable', 'Release to stock (passed inspection)'),
  if (canReturns)
    for (final c in const ['inspection', 'damaged', 'scrap'])
      if (c != from) (c, 'Mark as ${returnConditions[c]!.toLowerCase()}'),
  if (canStock && from != 'inspection') ('disposed', 'Write off (thrown away / sent back)'),
];

class HeldGoodsScreen extends ConsumerWidget {
  const HeldGoodsScreen({super.key});

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
    String to,
    String label,
  ) async {
    final held = toDouble(row['quantity']);
    final serial = row['serial_no'] as String? ?? '';
    final quantity = TextEditingController(text: qty(held));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${row['product_name']}'
              '${(row['variant_name'] as String? ?? '').isNotEmpty ? ' (${row['variant_name']})' : ''}'
              '${serial.isNotEmpty ? ' • $serial' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (serial.isEmpty)
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Quantity (held ${qty(held)})'),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: t('Note (e.g. inspection result)')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Confirm'))),
        ],
      ),
    );
    final q = serial.isNotEmpty ? 1.0 : (double.tryParse(quantity.text.trim()) ?? 0);
    if (ok != true || q <= 0) return;
    try {
      await ref.read(supabaseProvider).rpc(
        'move_held_stock',
        params: {
          'p_product_id': row['product_id'],
          'p_variant_id': row['variant_id'],
          'p_from': row['condition'],
          'p_to': to,
          'p_quantity': q,
          'p_serial_no': serial,
          'p_note': note.text.trim(),
        },
      );
      ref.invalidate(heldGoodsProvider);
      if (to == 'sellable') invalidateStockData(ref);
      if (context.mounted) showSuccess(context, t('Done'));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(heldGoodsProvider);
    final appCtx = ref.watch(appContextProvider).value;
    final canStock = appCtx?.canManageStock ?? false;
    final canReturns = appCtx?.canManageReturns ?? false;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Held returned goods')),
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(heldGoodsProvider),
        builder: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_outlined,
              message: t('Nothing held — every returned item is back in stock or written off.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(heldGoodsProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t('These returned items are not in sellable stock. Release them once they pass inspection, or write them off.'),
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 12),
                for (final r in rows)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${r['product_name']}'
                        '${(r['variant_name'] as String? ?? '').isNotEmpty ? ' (${r['variant_name']})' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          returnConditions[r['condition']] ?? '${r['condition']}',
                          if ((r['serial_no'] as String? ?? '').isNotEmpty) 'S/N ${r['serial_no']}',
                          'since ${dateStr(r['last_change'])}',
                        ].join(' • '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            qty(r['quantity'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          PopupMenuButton<(String, String)>(
                            tooltip: t('Move'),
                            enabled: canStock || canReturns,
                            onSelected: (m) => _move(context, ref, r, m.$1, m.$2),
                            itemBuilder: (_) => [
                              for (final m in heldGoodsMoves(
                                r['condition'] as String,
                                canStock: canStock,
                                canReturns: canReturns,
                              ))
                                PopupMenuItem(value: m, child: Text(m.$2)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
