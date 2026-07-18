import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'product_providers.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          const GuideButton('products'),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Categories, brands & units',
            onPressed: () => context.push('/products/master-data'),
          ),
          CoachTarget(
            page: 'products',
            id: 'master',
            child: IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Excel import',
              onPressed: () => context.push('/import'),
            ),
          ),
        ],
      ),
      floatingActionButton: CoachTarget(
        page: 'products',
        id: 'add',
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/products/new'),
          icon: const Icon(Icons.add),
          label: const Text('Add product'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: CoachTarget(
              page: 'products',
              id: 'search',
              child: SearchField(
                hint: 'Search name, SKU or barcode',
                onChanged: (v) =>
                    ref.read(productSearchProvider.notifier).set(v),
              ),
            ),
          ),
          Expanded(
            child: CoachTarget(
              page: 'products',
              id: 'list',
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(productsProvider),
                child: AsyncView(
                  value: products,
                  onRetry: () => ref.invalidate(productsProvider),
                  builder: (rows) => rows.isEmpty
                      ? const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          message:
                              'No products yet.\nAdd your first product or import from Excel.',
                        )
                      : isDesktop
                      ? DesktopTable<Map<String, dynamic>>(
                          rows: rows,
                          leadingWidth: _colLeadingWidth,
                          trailingWidth: _colStatusWidth,
                          columns: [
                            DesktopTableColumn(
                              label: 'Product',
                              flex: _colName,
                              comparable: (p) =>
                                  (p['name'] as String? ?? '').toLowerCase(),
                            ),
                            DesktopTableColumn(
                              label: 'Category',
                              flex: _colCategory,
                              comparable: (p) =>
                                  ((p['categories'] as Map?)?['name']
                                              as String? ??
                                          '')
                                      .toLowerCase(),
                            ),
                            DesktopTableColumn(
                              label: 'Brand',
                              flex: _colBrand,
                              comparable: (p) =>
                                  ((p['brands'] as Map?)?['name'] as String? ??
                                          '')
                                      .toLowerCase(),
                            ),
                            DesktopTableColumn(
                              label: 'Price',
                              flex: _colPrice,
                              alignEnd: true,
                              comparable: (p) => toDouble(p['selling_price']),
                            ),
                            DesktopTableColumn(
                              label: 'Stock',
                              flex: _colStock,
                              alignEnd: true,
                              comparable: (p) => toDouble(p['current_stock']),
                            ),
                          ],
                          rowBuilder: (context, product) =>
                              _ProductRow(product: product),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _ProductTile(product: rows[i]),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== desktop: sortable data table ====================
//
// The mobile card list works fine at phone width, but stretched across a
// desktop window it reads as a phone screen, not real desktop software —
// inventory software (reference: Vyapar Desktop) presents this kind of data
// as a dense, sortable table. This is purely additive: the mobile ListView
// above is untouched.

const _colName = 4;
const _colCategory = 2;
const _colBrand = 2;
const _colPrice = 2;
const _colStock = 2;
const _colStatusWidth = 120.0;
const _colLeadingWidth = 54.0;

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final stock = toDouble(product['current_stock']);
    final lowStock = toDouble(product['low_stock_qty']);
    final isOut = stock <= 0;
    final isLow = !isOut && lowStock > 0 && stock <= lowStock;
    final unit = (product['units'] as Map?)?['short_name'] as String? ?? '';
    final inactive = product['is_active'] == false;
    final name = product['name'] as String? ?? '';
    final sku = product['sku'] as String? ?? '';
    final accent = inactive ? AppColors.inkSoft : AppColors.accentFor(name);
    final category = (product['categories'] as Map?)?['name'] as String?;
    final brand = (product['brands'] as Map?)?['name'] as String?;

    return InkWell(
      onTap: () => context.push('/products/${product['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: _colLeadingWidth,
              child: product['image_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: product['image_url'] as String,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => IconChip(
                          Icons.inventory_2_outlined,
                          color: accent,
                          size: 36,
                        ),
                      ),
                    )
                  : IconChip(
                      Icons.inventory_2_outlined,
                      color: accent,
                      size: 36,
                    ),
            ),
            Expanded(
              flex: _colName,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        decoration: inactive
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (sku.isNotEmpty)
                      Text(
                        sku,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: _colCategory,
              child: Text(
                category ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: category == null ? AppColors.line : AppColors.inkSoft,
                ),
              ),
            ),
            Expanded(
              flex: _colBrand,
              child: Text(
                brand ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: brand == null ? AppColors.line : AppColors.inkSoft,
                ),
              ),
            ),
            Expanded(
              flex: _colPrice,
              child: Text(
                money(product['selling_price'] as num?),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Expanded(
              flex: _colStock,
              child: Text(
                qtyUnit(stock, unit),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: isOut
                      ? AppColors.red
                      : (isLow ? AppColors.orange : AppColors.green),
                ),
              ),
            ),
            SizedBox(
              width: _colStatusWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: inactive
                    ? StatusChip('inactive', color: AppColors.inkSoft)
                    : isOut
                    ? const StatusChip('out of stock', color: AppColors.red)
                    : isLow
                    ? const StatusChip('low stock', color: AppColors.orange)
                    : const StatusChip('active', color: AppColors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = toDouble(product['current_stock']);
    final lowStock = toDouble(product['low_stock_qty']);
    final isOut = stock <= 0;
    final isLow = !isOut && lowStock > 0 && stock <= lowStock;
    final unit = (product['units'] as Map?)?['short_name'] as String? ?? '';
    final inactive = product['is_active'] == false;
    final name = product['name'] as String;
    final accent = inactive ? AppColors.inkSoft : AppColors.accentFor(name);

    // Built manually instead of ListTile: ListTile's trailing slot enforces a
    // fixed max height independent of contentPadding, which a 2-line
    // trailing column (qty + status chip) can overflow by a pixel or two
    // under certain font metrics — a Row with mainAxisSize.min columns sizes
    // purely from content instead.
    return Card(
      child: InkWell(
        onTap: () => context.push('/products/${product['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              product['image_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: product['image_url'] as String,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => IconChip(
                          Icons.inventory_2_outlined,
                          color: accent,
                          size: 44,
                        ),
                      ),
                    )
                  : IconChip(
                      Icons.inventory_2_outlined,
                      color: accent,
                      size: 44,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        decoration: inactive
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          money(product['selling_price'] as num?),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if ((product['brands'] as Map?)?['name'] != null)
                          Flexible(
                            child: Text(
                              (product['brands'] as Map)['name'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    qtyUnit(stock, unit),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: isOut
                          ? AppColors.red
                          : (isLow ? AppColors.orange : AppColors.green),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (inactive)
                    StatusChip('inactive', color: AppColors.inkSoft)
                  else if (isOut)
                    const StatusChip('out of stock', color: AppColors.red)
                  else if (isLow)
                    const StatusChip('low stock', color: AppColors.orange),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
