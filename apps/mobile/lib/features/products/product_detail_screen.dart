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
import 'product_providers.dart';
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
      title: 'Delete product?',
      message:
          'This permanently removes the product. If it has sales history, deactivate it instead.',
      confirmText: 'Delete',
    );
    if (!ok) return;
    final client = ref.read(supabaseProvider);
    try {
      await client.from('products').delete().eq('id', productId);
      invalidateStockData(ref);
      if (context.mounted) {
        showSuccess(context, 'Product deleted');
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          'Cannot delete: product is used in bills or purchases. Deactivate it instead.',
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
    final draft = await showVariantSheet(context, businessType: businessType);
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
        title: const Text('Adjust which variant?'),
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
        title: const Text('Product'),
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
                        ? 'Deactivate'
                        : 'Activate',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppColors.red)),
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
                                        const StatusChip(
                                          'IMEI/Serial',
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
                                    'Purchase: ${money(p['purchase_price'] as num?)}  •  GST ${qty(p['gst_rate'] as num?)}%',
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
                    const SectionLabel('Stock'),
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
                                      const Text(
                                        'Current stock',
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
                                            '1 ${p['secondary_unit_name']} = ${qty(toDouble(p['conversion_factor']))} $unit',
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
                            title: const Text(
                              'Adjust stock / mark damaged',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: variants.isNotEmpty
                                ? Text(
                                    'Choose a variant to adjust',
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
                            title: const Text(
                              'Stock movement history',
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
                    if (p['sku'] != null && (p['sku'] as String).isNotEmpty ||
                        (p['barcode'] as String? ?? '').isNotEmpty) ...[
                      const SectionLabel('Details'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((p['sku'] as String? ?? '').isNotEmpty)
                                Text('SKU: ${p['sku']}'),
                              if ((p['barcode'] as String? ?? '')
                                  .isNotEmpty) ...[
                                if ((p['sku'] as String? ?? '').isNotEmpty)
                                  const SizedBox(height: 6),
                                Text('Barcode: ${p['barcode']}'),
                              ],
                              if ((p['hsn_code'] as String? ?? '')
                                  .isNotEmpty) ...[
                                if ((p['sku'] as String? ?? '').isNotEmpty ||
                                    (p['barcode'] as String? ?? '').isNotEmpty)
                                  const SizedBox(height: 6),
                                Text('HSN: ${p['hsn_code']}'),
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
                          Text(
                            'Variants',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                          TextButton.icon(
                            onPressed: () => _addVariant(context, ref, p),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                    if (variants.isEmpty)
                      Text(
                        'No variants',
                        style: TextStyle(color: AppColors.inkSoft),
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
                                      tooltip: 'Adjust stock',
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
        title: const Text('Add IMEI / Serial Number'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'IMEI / Serial Number',
                hintText: 'e.g. 356789012345678',
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

    if (added == true && controller.text.trim().isNotEmpty) {
      final client = ref.read(supabaseProvider);
      try {
        await client.rpc('add_product_serials', params: {
          'p_product_id': productId,
          'p_variant_id': null,
          'p_serials': [controller.text.trim()],
        });
        ref.invalidate(productSerialsProvider(productId));
        ref.invalidate(productDetailProvider(productId));
        if (context.mounted) showSuccess(context, 'IMEI added');
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
                const Row(
                  children: [
                    Icon(Icons.qr_code, size: 20, color: AppColors.purple),
                    SizedBox(width: 8),
                    Text(
                      'IMEI / Serial Numbers',
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
                  label: const Text('Add IMEI'),
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
                    child: Text(
                      'No IMEIs recorded yet. Tap "+ Add IMEI" above.',
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                    ),
                  );
                }

                final inStock = serials.where((s) => s['status'] == 'in_stock').toList();
                final sold = serials.where((s) => s['status'] == 'sold').toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'In Stock (${inStock.length})  •  Sold (${sold.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (inStock.isNotEmpty) ...[
                      const Text(
                        'Available In Stock',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.green),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in inStock)
                            Chip(
                              avatar: const Icon(Icons.check_circle_outline, size: 14, color: AppColors.green),
                              label: Text(s['serial_no'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                              backgroundColor: AppColors.green.withAlpha(20),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (sold.isNotEmpty) ...[
                      Text(
                        'Sold Units',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in sold)
                            Chip(
                              avatar: Icon(Icons.sell_outlined, size: 14, color: AppColors.inkSoft),
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
