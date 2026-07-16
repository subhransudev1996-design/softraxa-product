import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';

/// Stock overview with low / out-of-stock filters (PRD 7.11).
final stockFilterProvider =
    NotifierProvider<StockFilterNotifier, String>(StockFilterNotifier.new);

class StockFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all'; // all | low | out
  void set(String v) => state = v;
}

final stockSearchProvider =
    NotifierProvider<StockSearchNotifier, String>(StockSearchNotifier.new);

class StockSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final stockListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final filter = ref.watch(stockFilterProvider);
  final search = ref.watch(stockSearchProvider).trim();
  var query = client
      .from('products')
      .select('id, name, sku, barcode, current_stock, low_stock_qty, purchase_price, selling_price, '
          'has_variants, units(short_name, allow_decimal), product_variants(id, name, current_stock, low_stock_qty)')
      .eq('is_active', true);
  if (search.isNotEmpty) {
    query = query.or('name.ilike.%$search%,sku.ilike.%$search%,barcode.ilike.%$search%');
  }
  final rows =
      List<Map<String, dynamic>>.from(await query.order('name').limit(500));

  bool isLow(num stock, num low) => low > 0 && stock <= low && stock > 0;

  return switch (filter) {
    'low' => rows.where((p) {
        if (p['has_variants'] == true) {
          return List<Map<String, dynamic>>.from(p['product_variants'] as List? ?? [])
              .any((v) => isLow(toDouble(v['current_stock']),
                  toDouble(v['low_stock_qty'] ?? p['low_stock_qty'])));
        }
        return isLow(toDouble(p['current_stock']), toDouble(p['low_stock_qty']));
      }).toList(),
    'out' => rows.where((p) {
        if (p['has_variants'] == true) {
          return List<Map<String, dynamic>>.from(p['product_variants'] as List? ?? [])
              .any((v) => toDouble(v['current_stock']) <= 0);
        }
        return toDouble(p['current_stock']) <= 0;
      }).toList(),
    _ => rows,
  };
});

class StockScreen extends ConsumerWidget {
  const StockScreen({super.key, this.initialFilter});

  final String? initialFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(stockFilterProvider);
    final list = ref.watch(stockListProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Stock'), actions: const [GuideButton('stock')]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SearchField(
            hint: 'Search product, SKU, barcode',
            onChanged: (v) => ref.read(stockSearchProvider.notifier).set(v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'low', label: Text('Low stock')),
              ButtonSegment(value: 'out', label: Text('Out of stock')),
            ],
            selected: {filter},
            onSelectionChanged: (s) =>
                ref.read(stockFilterProvider.notifier).set(s.first),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(stockListProvider),
            child: AsyncView(
              value: list,
              onRetry: () => ref.invalidate(stockListProvider),
              builder: (rows) => rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.warehouse_outlined, message: 'Nothing here')
                  : isDesktop
                      ? DesktopTable<Map<String, dynamic>>(
                          rows: rows,
                          trailingWidth: 100,
                          columns: [
                            DesktopTableColumn(
                                label: 'Product',
                                flex: 3,
                                comparable: (p) =>
                                    (p['name'] as String? ?? '').toLowerCase()),
                            const DesktopTableColumn(label: 'Detail', flex: 3),
                            DesktopTableColumn(
                                label: 'Stock',
                                flex: 2,
                                alignEnd: true,
                                comparable: (p) => toDouble(p['current_stock'])),
                          ],
                          rowBuilder: (context, p) => _StockRow(product: p),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _StockTile(product: rows[i]),
                        ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ==================== desktop: sortable data table ====================

class _StockRow extends StatelessWidget {
  const _StockRow({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stock = toDouble(p['current_stock']);
    final low = toDouble(p['low_stock_qty']);
    final unit = (p['units'] as Map?)?['short_name'] as String? ?? '';
    final isOut = stock <= 0;
    final isLow = !isOut && low > 0 && stock <= low;

    return InkWell(
      onTap: () => context.push('/products/${p['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Text(p['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: p['has_variants'] == true
                  ? Text(
                      [
                        for (final v in List<Map<String, dynamic>>.from(
                            p['product_variants'] as List? ?? []))
                          '${v['name']}: ${qty(toDouble(v['current_stock']))}'
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft))
                  : Text('Value: ${money(stock * toDouble(p['purchase_price']))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(qtyUnit(stock, unit),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: isOut ? AppColors.red : (isLow ? AppColors.orange : AppColors.green))),
          ),
          SizedBox(
            width: 100,
            child: Align(
              alignment: Alignment.centerRight,
              child: isOut
                  ? const StatusChip('out', color: AppColors.red)
                  : isLow
                      ? const StatusChip('low', color: AppColors.orange)
                      : const StatusChip('ok', color: AppColors.green),
            ),
          ),
        ]),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _StockTile extends StatelessWidget {
  const _StockTile({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stock = toDouble(p['current_stock']);
    final low = toDouble(p['low_stock_qty']);
    final unit = (p['units'] as Map?)?['short_name'] as String? ?? '';
    final isOut = stock <= 0;
    final isLow = !isOut && low > 0 && stock <= low;
    final accent = isOut
        ? AppColors.red
        : (isLow ? AppColors.orange : AppColors.accentFor(p['name'] as String));
    // Built manually instead of ListTile: its trailing slot
    // enforces a fixed max height independent of
    // contentPadding, which a 2-line trailing column (qty +
    // status chip) can overflow under some font metrics.
    return Card(
      child: InkWell(
        onTap: () => context.push('/products/${p['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconChip(Icons.inventory_2_outlined, color: accent, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  p['has_variants'] == true
                      ? Text(
                          [
                            for (final v in List<Map<String, dynamic>>.from(
                                p['product_variants'] as List? ?? []))
                              '${v['name']}: ${qty(toDouble(v['current_stock']))}'
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.inkSoft))
                      : Text('Value: ${money(stock * toDouble(p['purchase_price']))}',
                          style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(qtyUnit(stock, unit),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isOut ? AppColors.red : (isLow ? AppColors.orange : AppColors.green))),
                const SizedBox(height: 2),
                if (isOut)
                  const StatusChip('out', color: AppColors.red)
                else if (isLow)
                  const StatusChip('low', color: AppColors.orange),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Stock movement history for one product (PRD 7.11).
final stockMovementsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, productId) async {
  final client = ref.watch(supabaseProvider);
  final rows = await client
      .from('stock_movements')
      .select('*, product_variants(name)')
      .eq('product_id', productId)
      .order('created_at', ascending: false)
      .limit(200);
  return List<Map<String, dynamic>>.from(rows);
});

class StockMovementsScreen extends ConsumerWidget {
  const StockMovementsScreen({super.key, required this.productId});

  final String productId;

  static final _labels = {
    'opening': ('Opening stock', Icons.flag_outlined, AppColors.inkSoft),
    'purchase': ('Purchase', Icons.shopping_cart_outlined, AppColors.green),
    'sale': ('Sale', Icons.receipt_long_outlined, AppColors.indigo),
    'sale_return': ('Sale return', Icons.assignment_return_outlined, AppColors.teal),
    'purchase_return': ('Purchase return', Icons.assignment_return_outlined, AppColors.orange),
    'adjustment': ('Adjustment', Icons.tune, AppColors.purple),
    'damage': ('Damaged/Lost', Icons.dangerous_outlined, AppColors.red),
    'import': ('Excel import', Icons.upload_file_outlined, AppColors.inkSoft),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(stockMovementsProvider(productId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Stock history')),
      body: AsyncView(
        value: movements,
        onRetry: () => ref.invalidate(stockMovementsProvider(productId)),
        builder: (rows) => rows.isEmpty
            ? const EmptyState(icon: Icons.history, message: 'No stock movements yet')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final m = rows[i];
                  final info = _labels[m['movement_type']] ??
                      (m['movement_type'] as String, Icons.circle_outlined, AppColors.inkSoft);
                  final q = toDouble(m['quantity']);
                  final variantName = (m['product_variants'] as Map?)?['name'] as String?;
                  return ListTile(
                    leading: IconChip(info.$2, color: info.$3, size: 40),
                    title: Text(info.$1 + (variantName != null ? ' — $variantName' : ''),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                        '${dateTimeStr(m['created_at'])}'
                        '${(m['note'] as String? ?? '').isNotEmpty ? '\n${m['note']}' : ''}',
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                    trailing: Text('${q > 0 ? '+' : ''}${qty(q)}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: q > 0 ? AppColors.green : AppColors.red)),
                  );
                },
              ),
      ),
    );
  }
}
