import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../pos/pos_providers.dart' show posProductColumns;

/// Stock to show for a product: its own, or its active variants' together.
double altStock(Map<String, dynamic> p) {
  if (p['has_variants'] == true) {
    final vs = (p['product_variants'] as List? ?? const []).cast<Map>().where(
      (v) => v['is_active'] != false,
    );
    if (vs.isNotEmpty) {
      return vs.fold<double>(0, (s, v) => s + toDouble(v['current_stock']));
    }
  }
  return toDouble(p['current_stock']);
}

/// Alternatives offered for a product (migration 0074): the shop's own links
/// first, then same-category products in stock. Each row is a full POS
/// product row plus 'picked' (linked by the shop). Empty when offline or on
/// a database without alternatives.
final productAlternativesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, productId) async {
      final client = ref.watch(supabaseProvider);
      try {
        final res = await client.rpc(
          'get_product_alternatives',
          params: {'p_product': productId, 'p_limit': 8},
        );
        final order = [
          for (final r in (res as List? ?? const []))
            Map<String, dynamic>.from(r as Map),
        ];
        if (order.isEmpty) return const [];
        final rows = await client
            .from('products')
            .select(posProductColumns)
            .inFilter('id', [for (final o in order) o['id']]);
        final byId = {
          for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r),
        };
        return [
          for (final o in order)
            if (byId[o['id']] != null)
              {...byId[o['id']]!, 'picked': o['picked'] == true},
        ];
      } catch (_) {
        return const [];
      }
    });

/// The shop's own alternatives of a product, for the product form.
Future<List<Map<String, dynamic>>> loadLinkedAlternatives(
  WidgetRef ref,
  String productId,
) async {
  final res = await ref
      .read(supabaseProvider)
      .rpc('get_linked_alternatives', params: {'p_product': productId});
  return [
    for (final r in (res as List? ?? const []))
      Map<String, dynamic>.from(r as Map),
  ];
}

Future<void> saveLinkedAlternatives(
  WidgetRef ref,
  String productId,
  List<String> ids,
) => ref
    .read(supabaseProvider)
    .rpc(
      'set_product_alternatives',
      params: {'p_product': productId, 'p_alternatives': ids},
    );

/// "Alternatives to …" under the New Bill search: a row of small cards with
/// name, price and stock. Hidden while loading, offline, or with none.
class AlternativesStrip extends ConsumerWidget {
  const AlternativesStrip({
    super.key,
    required this.productId,
    required this.productName,
    required this.onAdd,
    this.onSwap,
    this.onClose,
  });

  final String productId;
  final String productName;
  final void Function(Map<String, dynamic> product) onAdd;

  /// Replace the product just added with this one.
  final void Function(Map<String, dynamic> product)? onSwap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(productAlternativesProvider(productId)).value;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t('Alternatives to {v1}', {'v1': productName}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: t('Hide'),
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClose,
                ),
            ],
          ),
          SizedBox(
            height: onSwap == null ? 92 : 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _AltCard(
                product: rows[i],
                onAdd: () => onAdd(rows[i]),
                onSwap: onSwap == null ? null : () => onSwap!(rows[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AltCard extends StatelessWidget {
  const _AltCard({required this.product, required this.onAdd, this.onSwap});

  final Map<String, dynamic> product;
  final VoidCallback onAdd;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final stock = altStock(product);
    return SizedBox(
      width: 190,
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: product['picked'] == true
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.line,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        money(product['selling_price'] as num?),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      stock <= 0
                          ? t('Out of stock')
                          : t('Stock {v1}', {'v1': qty(stock)}),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: stock <= 0 ? AppColors.red : AppColors.green,
                      ),
                    ),
                  ],
                ),
                if (onSwap != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                      ),
                      onPressed: onSwap,
                      child: Text(
                        t('Swap'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short vertical list of alternatives inside a dialog (out of stock, or
/// the job card's part dialog). Nothing when there are none.
class AlternativesList extends ConsumerWidget {
  const AlternativesList({
    super.key,
    required this.productId,
    required this.onPick,
    this.title,
    this.inStockOnly = false,
  });

  final String productId;
  final void Function(Map<String, dynamic> product) onPick;
  final String? title;
  final bool inStockOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(productAlternativesProvider(productId)).value;
    final rows = [
      for (final r in all ?? const <Map<String, dynamic>>[])
        if (!inStockOnly || altStock(r) > 0) r,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title ?? t('Alternatives'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 4),
        for (final r in rows.take(5))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.swap_horiz,
              size: 18,
              color: AppColors.primary,
            ),
            title: Text(
              r['name'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${money(r['selling_price'] as num?)}  •  '
              '${t('Stock {v1}', {'v1': qty(altStock(r))})}',
            ),
            onTap: () => onPick(r),
          ),
      ],
    );
  }
}

/// Pick one of the shop's products to link as an alternative (not
/// [excludeIds]: the product itself and those already linked).
Future<Map<String, dynamic>?> pickAlternativeProduct(
  BuildContext context, {
  required Set<String> excludeIds,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  builder: (_) => _AlternativePicker(excludeIds: excludeIds),
);

class _AlternativePicker extends ConsumerStatefulWidget {
  const _AlternativePicker({required this.excludeIds});

  final Set<String> excludeIds;

  @override
  ConsumerState<_AlternativePicker> createState() => _AlternativePickerState();
}

class _AlternativePickerState extends ConsumerState<_AlternativePicker> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String text) async {
    final gen = ++_generation;
    try {
      var q = ref
          .read(supabaseProvider)
          .from('products')
          .select('id, name, selling_price, current_stock')
          .eq('is_active', true);
      final term = text.trim().replaceAll(RegExp(r'[,%()]'), ' ');
      if (term.isNotEmpty) q = q.ilike('name', '%$term%');
      final rows = await q.order('name').limit(40);
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows = [
          for (final r in rows)
            if (!widget.excludeIds.contains(r['id']))
              Map<String, dynamic>.from(r),
        ];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Add an alternative')),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('Search product'),
              ),
              onChanged: _load,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return ListTile(
                          dense: true,
                          title: Text(r['name'] as String? ?? ''),
                          subtitle: Text(
                            '${money(r['selling_price'] as num?)}  •  '
                            '${t('Stock {v1}', {'v1': qty(toDouble(r['current_stock']))})}',
                          ),
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel')),
        ),
      ],
    );
  }
}
