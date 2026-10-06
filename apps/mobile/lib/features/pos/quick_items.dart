import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import 'pos_providers.dart';

/// Product ids billed most often, most first — counted per bill line, so a
/// kilo of sugar and a packet of salt count the same (revenue would favour
/// costly items, which aren't the ones picked again and again).
List<String> mostBilledIds(Iterable<dynamic> productIds, {int take = 12}) {
  final counts = <String, int>{};
  for (final id in productIds) {
    if (id is String && id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
  }
  final ids = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return ids.take(take).toList();
}

/// The shop's best sellers of the last 30 days, as POS product rows (same
/// columns as search, so adding one works exactly like picking it there).
/// Empty when offline or there's no history — the row just doesn't show.
final quickItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      try {
        final client = ref.watch(supabaseProvider);
        final since = DateTime.now().subtract(const Duration(days: 30));
        final lines = await client
            .from('invoice_items')
            .select('product_id, invoices!inner(invoice_date, is_cancelled)')
            .not('product_id', 'is', null)
            .gte('invoices.invoice_date', since.toUtc().toIso8601String())
            .eq('invoices.is_cancelled', false)
            .limit(3000);
        final ids = mostBilledIds([for (final l in lines) l['product_id']]);
        if (ids.isEmpty) return const [];
        final rows = await client
            .from('products')
            .select(posProductColumns)
            .inFilter('id', ids)
            .eq('is_active', true);
        final byId = {for (final r in rows) r['id'] as String: r};
        return [
          for (final id in ids)
            if (byId[id] case final r?) Map<String, dynamic>.from(r),
        ];
      } catch (_) {
        return const [];
      }
    });

/// A row of one-tap buttons for the best sellers, under the search box.
class QuickItemsRow extends ConsumerWidget {
  const QuickItemsRow({super.key, required this.onPick});

  final void Function(Map<String, dynamic> product) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(quickItemsProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = items[i];
          return ActionChip(
            avatar: const Icon(
              Icons.bolt,
              size: 16,
              color: AppColors.orange,
            ),
            label: Text(
              '${p['name']}  ${money(toDouble(p['selling_price']))}',
              style: const TextStyle(fontSize: 12.5),
            ),
            tooltip: t('Add {v1}', {'v1': p['name']}),
            onPressed: () => onPick(p),
          );
        },
      ),
    );
  }
}
