import '../../core/i18n.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../stock/adjust_stock_sheet.dart';
import '../stock/pieces_card.dart';
import 'alternatives.dart';
import 'product_providers.dart';
import 'variant_builder.dart';
import 'variant_grid.dart';
import 'variant_matrix.dart';
import 'variant_prices.dart';
import 'variant_sheet.dart';
import '../../core/theme.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> product,
  ) async {
    final client = ref.read(supabaseProvider);
    try {
      await client
          .from('products')
          .update({'is_active': !(product['is_active'] as bool? ?? true)})
          .eq('id', productId);
      ref.invalidate(productDetailProvider(productId));
      invalidateStockData(ref); // active flag drives POS/stock visibility
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: t('Delete product?'),
      message: t('This permanently removes the product. If it has sales history, deactivate it instead.'),
      confirmText: t('Delete'),
    );
    if (!ok) return;
    final client = ref.read(supabaseProvider);
    try {
      await client.from('products').delete().eq('id', productId);
      invalidateStockData(ref);
      if (context.mounted) {
        showSuccess(context, t('Product deleted'));
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          t('Cannot delete: product is used in bills or purchases. Deactivate it instead.'),
        );
      }
    }
  }

  Future<void> _addVariant(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> product,
  ) async {
    final businessType =
        ref.read(appContextProvider).value?.business?['business_type']
            as String? ??
        'other';
    final draft = await showVariantSheet(
      context,
      businessType: businessType,
      productName: product['name'] as String? ?? '',
      categoryName: (product['categories'] as Map?)?['name'] as String? ?? '',
      siblings: [
        for (final v in (product['product_variants'] as List? ?? []))
          VariantDraft.attributesOf(Map<String, dynamic>.from(v as Map)),
      ],
    );
    if (draft == null) return;
    final client = ref.read(supabaseProvider);
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      final vRow = await client
          .from('product_variants')
          .insert({...draft.toRow(productId), 'business_id': businessId})
          .select('id')
          .single();
      if (draft.openingStock > 0) {
        await client.rpc(
          'add_opening_stock',
          params: {
            'p_product_id': productId,
            'p_variant_id': vRow['id'],
            'p_quantity': draft.openingStock,
          },
        );
      }
      if (!(product['has_variants'] as bool? ?? false)) {
        await client
            .from('products')
            .update({'has_variants': true})
            .eq('id', productId);
      }
      ref.invalidate(productDetailProvider(productId));
      invalidateStockData(ref); // variant stock/price/barcode feed POS + stock
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Sizes & colours added later: only the new combinations are made.
  Future<void> _addSizes(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> product,
    List<Map<String, dynamic>> variants,
  ) async {
    final businessType =
        ref.read(appContextProvider).value?.business?['business_type']
            as String? ??
        'other';
    final sku = (product['sku'] as String? ?? '').trim();
    final made = await showVariantBuilder(
      context,
      businessType: businessType,
      productName: product['name'] as String? ?? '',
      categoryName: (product['categories'] as Map?)?['name'] as String? ?? '',
      productCode: sku.isNotEmpty ? sku : product['name'] as String? ?? '',
      productPrice: toDouble(product['selling_price']),
      existing: variants,
    );
    if (made == null || made.isEmpty) return;
    final client = ref.read(supabaseProvider);
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      final rows = List<Map<String, dynamic>>.from(
        await client
            .from('product_variants')
            .insert([
              for (final d in made)
                {...d.toRow(productId), 'business_id': businessId},
            ])
            .select('id'),
      );
      for (var i = 0; i < rows.length && i < made.length; i++) {
        if (made[i].openingStock > 0) {
          await client.rpc(
            'add_opening_stock',
            params: {
              'p_product_id': productId,
              'p_variant_id': rows[i]['id'],
              'p_quantity': made[i].openingStock,
            },
          );
        }
      }
      if (!(product['has_variants'] as bool? ?? false)) {
        await client
            .from('products')
            .update({'has_variants': true})
            .eq('id', productId);
      }
      ref.invalidate(productDetailProvider(productId));
      invalidateStockData(ref);
      if (context.mounted) {
        showSuccess(
          context,
          t('{v1} variants added', {'v1': made.length}),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Prices for all variants in one table; old sizes switched off.
  Future<void> _editPrices(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> product,
    List<Map<String, dynamic>> variants,
  ) async {
    final changes = await showVariantPrices(
      context,
      product: product,
      variants: variants,
    );
    if (changes == null || changes.isEmpty) return;
    final client = ref.read(supabaseProvider);
    try {
      for (final c in changes) {
        await client
            .from('product_variants')
            .update(c.toUpdate())
            .eq('id', c.id);
      }
      ref.invalidate(productDetailProvider(productId));
      invalidateStockData(ref);
      if (context.mounted) {
        showSuccess(
          context,
          t('{v1} variants updated', {'v1': changes.length}),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// A box in the stock grid: adjust its stock, or its details.
  Future<void> _variantActions(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                variant['name'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                t('Stock {v1} · {v2}', {
                  'v1': qty(toDouble(variant['current_stock'])),
                  'v2': money(
                    toDouble(
                      variant['selling_price'] ?? product['selling_price'],
                    ),
                  ),
                }),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(t('Adjust stock')),
              onTap: () => Navigator.pop(ctx, 'stock'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(t('Edit details (price, barcode, code)')),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'stock') {
      await showAdjustStockSheet(context, ref, product: product, variant: variant);
      ref.invalidate(productDetailProvider(productId));
    } else if (action == 'edit') {
      await _editVariant(context, ref, variant);
    }
  }

  /// When a product has variants, stock lives per-variant — adjusting the
  /// product-level total directly would desync it from the sum of variant
  /// stocks (see `apply_stock_movement` trigger). So instead of silently
  /// no-op'ing the tap, ask which variant to adjust.
  Future<Map<String, dynamic>?> _pickVariantToAdjust(
    BuildContext context,
    List<Map<String, dynamic>> variants,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('Adjust which variant?')),
        children: [
          for (final v in variants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, v),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      v['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    qty(toDouble(v['current_stock'])),
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _adjustStock(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> product,
    List<Map<String, dynamic>> variants,
  ) async {
    Map<String, dynamic>? variant;
    if (variants.isNotEmpty) {
      variant = await _pickVariantToAdjust(context, variants);
      if (variant == null) return; // cancelled
    }
    if (!context.mounted) return;
    await showAdjustStockSheet(
      context,
      ref,
      product: product,
      variant: variant,
    );
    ref.invalidate(productDetailProvider(productId));
    ref.invalidate(productsProvider);
  }

  Future<void> _editVariant(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> variant,
  ) async {
    final businessType =
        ref.read(appContextProvider).value?.business?['business_type']
            as String? ??
        'other';
    final draft = await showVariantSheet(
      context,
      businessType: businessType,
      existing: VariantDraft.fromRow(variant),
      allowOpeningStock: false,
    );
    if (draft == null) return;
    final client = ref.read(supabaseProvider);
    try {
      await client
          .from('product_variants')
          .update({
            'name': draft.name,
            'sku': draft.sku,
            'barcode': draft.barcode,
            'attributes': draft.attributes,
            'purchase_price': draft.purchasePrice,
            'selling_price': draft.sellingPrice,
            'mrp': draft.mrp,
            'low_stock_qty': draft.lowStockQty,
          })
          .eq('id', variant['id'] as String);
      ref.invalidate(productDetailProvider(productId));
      invalidateStockData(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider(productId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Product')),
        actions: [
          if (detail.hasValue) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push(
                  '/products/$productId/edit',
                  extra: detail.value,
                );
                ref.invalidate(productDetailProvider(productId));
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'toggle') _toggleActive(context, ref, detail.value!);
                if (v == 'delete') _delete(context, ref);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    detail.value!['is_active'] == true
                        ? t('Deactivate')
                        : 'Activate',
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(t('Delete'), style: TextStyle(color: AppColors.red)),
                ),
              ],
            ),
          ],
        ],
      ),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(productDetailProvider(productId)),
        builder: (p) {
          final variants = List<Map<String, dynamic>>.from(
            p['product_variants'] as List? ?? [],
          );
          final unit = (p['units'] as Map?)?['short_name'] as String? ?? '';
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(productDetailProvider(productId)),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            p['image_url'] != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl: p['image_url'] as String,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : IconChip(
                                    Icons.inventory_2_outlined,
                                    color: p['is_active'] == true
                                        ? AppColors.accentFor(
                                            p['name'] as String,
                                          )
                                        : AppColors.inkSoft,
                                    size: 80,
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if ((p['categories'] as Map?)?['name'] !=
                                          null)
                                        StatusChip(
                                          (p['categories'] as Map)['name']
                                              as String,
                                          color: AppColors.indigo,
                                        ),
                                      if ((p['brands'] as Map?)?['name'] !=
                                          null)
                                        StatusChip(
                                          (p['brands'] as Map)['name']
                                              as String,
                                          color: AppColors.teal,
                                        ),
                                      if (p['is_active'] != true)
                                        StatusChip(
                                          'inactive',
                                          color: AppColors.inkSoft,
                                        ),
                                      if (p['track_serial'] == true)
                                        StatusChip(t('IMEI/Serial'),
                                          color: AppColors.purple,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Selling: ${money(p['selling_price'] as num?)}'
                                    '${toDouble(p['mrp']) > 0 ? '  •  MRP: ${money(p['mrp'] as num?)}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    t('Purchase: {v1}  •  GST {v2}%', {'v1': money(p['purchase_price'] as num?), 'v2': qty(p['gst_rate'] as num?)}),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SectionLabel(t('Stock')),
                    Card(
                      child: Column(
                        children: [
                          // Built manually instead of ListTile: its trailing
                          // slot enforces a fixed max height independent of
                          // contentPadding, which the 2-line "500 kg (10 Bag)"
                          // trailing value can overflow under some font
                          // metrics (same overflow risk documented on the
                          // party-card tiles elsewhere in this app).
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const IconChip(
                                  Icons.warehouse_outlined,
                                  color: AppColors.indigo,
                                  size: 38,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(t('Current stock'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      // With a bulk unit configured (1 Bag =
                                      // 50 kg), explain the conversion.
                                      if ((p['secondary_unit_name']
                                                  as String?) !=
                                              null &&
                                          toDouble(p['conversion_factor']) > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            '1 ${p['secondary_unit_name']} = ${qty(toDouble(p['conversion_factor']))} $unit'
                                            '${toDouble(p['pack_price']) > 0 ? ' · sells at ${money(p['pack_price'] as num?)}' : ''}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.inkSoft,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  (p['secondary_unit_name'] as String?) !=
                                              null &&
                                          toDouble(p['conversion_factor']) > 0
                                      ? '${qtyUnit(toDouble(p['current_stock']), unit)}\n'
                                            '(${qty(toDouble(p['current_stock']) / toDouble(p['conversion_factor']))} ${p['secondary_unit_name']})'
                                      : qtyUnit(
                                          toDouble(p['current_stock']),
                                          unit,
                                        ),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const IconChip(
                              Icons.tune,
                              color: AppColors.orange,
                              size: 38,
                            ),
                            title: Text(t('Adjust stock / mark damaged'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: variants.isNotEmpty
                                ? Text(t('Choose a variant to adjust'),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.inkSoft,
                                    ),
                                  )
                                : null,
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () =>
                                _adjustStock(context, ref, p, variants),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const IconChip(
                              Icons.history,
                              color: AppColors.teal,
                              size: 38,
                            ),
                            title: Text(t('Stock movement history'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 20),
                            onTap: () =>
                                context.push('/stock/movements/$productId'),
                          ),
                        ],
                      ),
                    ),
                    if (p['track_pieces'] == true) ...[
                      const SizedBox(height: 12),
                      PiecesCard(product: p),
                    ],
                    if (p['track_serial'] == true) ...[
                      const SizedBox(height: 12),
                      _SerialsCard(productId: productId, product: p),
                    ],
                    _AlternativesCard(productId: productId),
                    if (p['sku'] != null && (p['sku'] as String).isNotEmpty ||
                        (p['barcode'] as String? ?? '').isNotEmpty) ...[
                      SectionLabel(t('Details')),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((p['sku'] as String? ?? '').isNotEmpty)
                                Text(t('SKU: {v1}', {'v1': p['sku']})),
                              if ((p['barcode'] as String? ?? '')
                                  .isNotEmpty) ...[
                                if ((p['sku'] as String? ?? '').isNotEmpty)
                                  const SizedBox(height: 6),
                                Text(t('Barcode: {v1}', {'v1': p['barcode']})),
                              ],
                              if ((p['hsn_code'] as String? ?? '')
                                  .isNotEmpty) ...[
                                if ((p['sku'] as String? ?? '').isNotEmpty ||
                                    (p['barcode'] as String? ?? '').isNotEmpty)
                                  const SizedBox(height: 6),
                                Text(t('HSN: {v1}', {'v1': p['hsn_code']})),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(t('Variants'),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                          PopupMenuButton<String>(
                            tooltip: t('Change variants'),
                            onSelected: (v) => switch (v) {
                              'sizes' => _addSizes(context, ref, p, variants),
                              'prices' => _editPrices(
                                context,
                                ref,
                                p,
                                variants,
                              ),
                              _ => _addVariant(context, ref, p),
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'sizes',
                                child: Text(t('Add sizes & colours')),
                              ),
                              if (variants.isNotEmpty)
                                PopupMenuItem(
                                  value: 'prices',
                                  child: Text(t('Prices & hide old ones')),
                                ),
                              PopupMenuItem(
                                value: 'one',
                                child: Text(t('Add one variant')),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    t('Change'),
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (variants.isEmpty)
                      Text(t('No variants'),
                        style: TextStyle(color: AppColors.inkSoft),
                      )
                    else if (variantGridOf(variants) case final grid?)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              VariantGridView(
                                grid: grid,
                                cellBuilder: (ctx, v) => VariantStockCell(
                                  variant: v,
                                  subtitle: v['is_active'] == false
                                      ? t('Hidden')
                                      : null,
                                  onTap: () =>
                                      _variantActions(context, ref, p, v),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t('Stock in each box: green in stock, orange low, red out. Tap a box to adjust it.'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final v in variants) ...[
                              ListTile(
                                title: Text(
                                  v['name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  '₹${v['selling_price'] ?? p['selling_price']}'
                                  '${(v['barcode'] as String? ?? '').isNotEmpty ? '  •  ${v['barcode']}' : ''}',
                                  style: TextStyle(
                                    color: AppColors.inkSoft,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      qty(toDouble(v['current_stock'])),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: toDouble(v['current_stock']) <= 0
                                            ? AppColors.red
                                            : AppColors.green,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.tune, size: 20),
                                      tooltip: t('Adjust stock'),
                                      onPressed: () async {
                                        await showAdjustStockSheet(
                                          context,
                                          ref,
                                          product: p,
                                          variant: v,
                                        );
                                        ref.invalidate(
                                          productDetailProvider(productId),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () => _editVariant(context, ref, v),
                              ),
                              if (v != variants.last) const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final productSerialsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, productId) async {
      final client = ref.watch(supabaseProvider);
      final rows = await client
          .from('product_serials')
          .select('*, invoice:invoices(invoice_no, invoice_date)')
          .eq('product_id', productId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    });

class _SerialsCard extends ConsumerWidget {
  const _SerialsCard({required this.productId, required this.product});

  final String productId;
  final Map<String, dynamic> product;

  Future<void> _addSerial(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Add IMEI / Serial Number')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t('IMEI / Serial Number'),
                hintText: t('e.g. 356789012345678'),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Add')),
          ),
        ],
      ),
    );

    if (added == true && controller.text.trim().isNotEmpty) {
      final client = ref.read(supabaseProvider);
      try {
        await client.rpc(
          'add_product_serials',
          params: {
            'p_product_id': productId,
            'p_variant_id': null,
            'p_serials': [controller.text.trim()],
          },
        );
        ref.invalidate(productSerialsProvider(productId));
        ref.invalidate(productDetailProvider(productId));
        if (context.mounted) showSuccess(context, t('IMEI added'));
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serialsAsync = ref.watch(productSerialsProvider(productId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code, size: 20, color: AppColors.purple),
                    SizedBox(width: 8),
                    Text(t('IMEI / Serial Numbers'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _addSerial(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(t('Add IMEI')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AsyncView(
              value: serialsAsync,
              onRetry: () => ref.invalidate(productSerialsProvider(productId)),
              builder: (serials) {
                if (serials.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(t('No IMEIs recorded yet. Tap "+ Add IMEI" above.'),
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                    ),
                  );
                }

                final inStock = serials
                    .where((s) => s['status'] == 'in_stock')
                    .toList();
                final sold = serials
                    .where((s) => s['status'] == 'sold')
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('In Stock ({v1})  •  Sold ({v2})', {'v1': inStock.length, 'v2': sold.length}),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (inStock.isNotEmpty) ...[
                      Text(t('Available In Stock'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in inStock)
                            Chip(
                              avatar: const Icon(
                                Icons.check_circle_outline,
                                size: 14,
                                color: AppColors.green,
                              ),
                              label: Text(
                                s['serial_no'] as String? ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                              backgroundColor: AppColors.green.withAlpha(20),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (sold.isNotEmpty) ...[
                      Text(t('Sold Units'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in sold)
                            Chip(
                              avatar: Icon(
                                Icons.sell_outlined,
                                size: 14,
                                color: AppColors.inkSoft,
                              ),
                              label: Text(
                                '${s['serial_no']}${s['invoice'] != null ? ' (${s['invoice']['invoice_no']})' : ''}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              backgroundColor: AppColors.canvas,
                            ),
                        ],
                      ),
                    ],
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

/// The shop's alternatives of this product (set in Edit); tap to open one.
class _AlternativesCard extends ConsumerWidget {
  const _AlternativesCard({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = [
      for (final r
          in ref.watch(productAlternativesProvider(productId)).value ??
              const <Map<String, dynamic>>[])
        if (r['picked'] == true) r,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t('Alternative products')),
        Card(
          child: Column(
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.swap_horiz,
                    color: AppColors.primary,
                  ),
                  title: Text(r['name'] as String? ?? ''),
                  subtitle: Text(
                    '${money(r['selling_price'] as num?)}  •  '
                    '${t('Stock {v1}', {'v1': qty(altStock(r))})}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/products/${r['id']}'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
