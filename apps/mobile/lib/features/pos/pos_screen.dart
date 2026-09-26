import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customer_picker.dart';
import '../offline/offline_service.dart';
import '../products/product_providers.dart' show parseWeightedBarcode;
import '../stock/adjust_stock_sheet.dart';
import '../stock/piece_picker.dart';
import 'cart.dart';
import 'checkout_sheet.dart';
import 'loose_qty_sheet.dart';
import 'pos_providers.dart';

/// Shared "not enough stock" dialog: message + three evenly-sized, full-width,
/// evenly-spaced actions (Cancel / Add stock first / Add anyway). Buttons
/// live in [content] rather than [actions] so their width and spacing stay
/// consistent instead of falling back to AlertDialog's default cramped
/// overflow layout.
Future<String?> _showStockDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'add_stock'),
            child: const Text('Add stock first'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'add_anyway'),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> showImeiPicker(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  String? variantId,
  required String productName,
}) async {
  final client = ref.read(supabaseProvider);
  List<Map<String, dynamic>> serials = [];
  try {
    final rows = await client.rpc('get_available_serials', params: {
      'p_product_id': productId,
      'p_variant_id': variantId,
    });
    serials = List<Map<String, dynamic>>.from(rows as List? ?? []);
  } catch (_) {}

  final controller = TextEditingController();

  if (!context.mounted) return null;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Select IMEI / Serial — $productName'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Search or enter IMEI',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final code = isDesktopPlatform
                          ? await promptBarcode(context, title: 'Enter IMEI')
                          : await context.push<String>('/scan?mode=return');
                      if (code != null && code.isNotEmpty && ctx.mounted) {
                        Navigator.pop(ctx, code);
                      }
                    },
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    Navigator.pop(ctx, v.trim());
                  }
                },
              ),
              const SizedBox(height: 12),
              if (serials.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No in-stock IMEIs found in database. Type or scan an IMEI above.',
                    style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in serials)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.qr_code,
                            size: 18,
                            color: AppColors.purple,
                          ),
                          title: Text(
                            s['serial_no'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () =>
                              Navigator.pop(ctx, s['serial_no'] as String),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) Navigator.pop(ctx, val);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
}

/// POS / billing screen (PRD 7.7). The search field also receives input from
/// external keyboard-wedge barcode scanners (they type the code and press
/// Enter, which triggers [_onSubmitted]).
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(posSearchProvider.notifier).set('');
  }

  Future<void> _addToCart(
    Map<String, dynamic> product, {
    Map<String, dynamic>? presetVariant,
  }) async {
    final variants = List<Map<String, dynamic>>.from(
      product['product_variants'] as List? ?? [],
    )..removeWhere((v) => v['is_active'] == false);

    Map<String, dynamic>? variant = presetVariant;
    if (variant == null &&
        product['has_variants'] == true &&
        variants.isNotEmpty) {
      variant = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select variant — ${product['name']}',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in variants)
                      ListTile(
                        title: Text(
                          v['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          money(
                            (v['selling_price'] ?? product['selling_price'])
                                as num?,
                          ),
                        ),
                        trailing: StatusChip(
                          'Stock ${qty(toDouble(v['current_stock']))}',
                          color: toDouble(v['current_stock']) <= 0
                              ? AppColors.red
                              : AppColors.green,
                        ),
                        onTap: () => Navigator.pop(ctx, v),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (variant == null) return;
    }

    // Loose/weighed goods (unit has allow_decimal): ask for the quantity —
    // by weight/length or by ₹ amount — instead of silently adding 1.
    var addQty = 1.0;
    final unitMap = product['units'] as Map?;
    if (unitMap?['allow_decimal'] == true) {
      if (!mounted) return;
      final result = await showLooseQtySheet(
        context,
        name:
            '${product['name']}${variant != null ? ' (${variant['name']})' : ''}',
        rate: toDouble(variant?['selling_price'] ?? product['selling_price']),
        unitName: unitMap?['short_name'] as String? ?? '',
        secondaryUnitName: product['secondary_unit_name'] as String?,
        conversionFactor: (product['conversion_factor'] as num?)?.toDouble(),
      );
      if (result == null || !mounted) return;
      addQty = result.qty;
    }

    // Cut-piece stores (rods/sheets): pick which physical piece this cut
    // comes from, so the remnant lengths stay accurate. Optional — skipping
    // is always allowed; variants don't take part (pieces are per-product).
    String? pieceId;
    if (product['track_pieces'] == true && variant == null) {
      if (!mounted) return;
      final pick = await showPiecePicker(
        context,
        ref,
        productId: product['id'] as String,
        productName: product['name'] as String,
        needQty: addQty,
        unitName: (product['units'] as Map?)?['short_name'] as String? ?? '',
      );
      if (pick == null || !mounted) return; // cancelled
      pieceId = pick.piece?['id'] as String?;
    }

    String serialNo = '';
    if (product['track_serial'] == true) {
      if (!mounted) return;
      final pickedSerial = await showImeiPicker(
        context,
        ref,
        productId: product['id'] as String,
        variantId: variant?['id'] as String?,
        productName: product['name'] as String,
      );
      if (pickedSerial == null || pickedSerial.isEmpty || !mounted) return;
      serialNo = pickedSerial;
    }

    var stock = toDouble(variant?['current_stock'] ?? product['current_stock']);
    final alreadyInCart = ref
        .read(cartProvider.notifier)
        .qtyInCart(product['id'] as String, variant?['id'] as String?);
    final projectedQty = alreadyInCart + addQty;
    if (projectedQty > stock) {
      final proceed = await _confirmStockIssue(
        product,
        variant,
        stock,
        projectedQty,
      );
      if (!mounted) return;
      if (!proceed) return;
    }

    ref
        .read(cartProvider.notifier)
        .addProduct(
          product,
          variant: variant,
          serialNo: serialNo,
          addQty: addQty,
          pieceId: pieceId,
        );
    _clearSearch();
    _searchFocus.requestFocus();
  }

  /// Shows an out-of-stock / exceeds-stock warning with an "Add stock
  /// first" shortcut. Returns true if the caller should still proceed.
  Future<bool> _confirmStockIssue(
    Map<String, dynamic> product,
    Map<String, dynamic>? variant,
    double stock,
    double attemptedQty,
  ) async {
    final label =
        '${product['name']}${variant != null ? ' (${variant['name']})' : ''}';
    final message = stock <= 0
        ? '$label has 0 in stock. Add stock first, or add it to the bill anyway?'
        : '$label only has ${qty(stock)} in stock, but this bill would need ${qty(attemptedQty)}. '
              'Add stock first, or continue anyway?';
    final action = await _showStockDialog(
      context,
      title: stock <= 0 ? 'Out of stock' : 'Not enough stock',
      message: message,
    );
    if (action == 'add_anyway') return true;
    if (action == 'add_stock') {
      if (!mounted) return false;
      final adjusted = await showAdjustStockSheet(
        context,
        ref,
        product: product,
        variant: variant,
      );
      if (adjusted == true) {
        ref.invalidate(posProductsProvider);
        if (!mounted) return false;
        final fresh = await _freshStock(product, variant);
        return fresh >= attemptedQty;
      }
    }
    return false;
  }

  Future<double> _freshStock(
    Map<String, dynamic> product,
    Map<String, dynamic>? variant,
  ) async {
    try {
      final client = ref.read(supabaseProvider);
      if (variant != null) {
        final row = await client
            .from('product_variants')
            .select('current_stock')
            .eq('id', variant['id'] as String)
            .single();
        return toDouble(row['current_stock']);
      }
      final row = await client
          .from('products')
          .select('current_stock')
          .eq('id', product['id'] as String)
          .single();
      return toDouble(row['current_stock']);
    } catch (_) {
      return 0;
    }
  }

  /// External scanner / manual entry: exact barcode match first.
  Future<void> _onSubmitted(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    final products = ref.read(posProductsProvider).value ?? [];
    // exact barcode match on product or variant
    for (final p in products) {
      if (p['barcode'] == code) {
        await _addToCart(p);
        return;
      }
      for (final v in List<Map<String, dynamic>>.from(
        p['product_variants'] as List? ?? [],
      )) {
        if (v['barcode'] == code) {
          await _addToCart(p, presetVariant: v);
          return;
        }
      }
    }
    // Weighted scale-label barcode (loose goods): the embedded item code
    // matches the product's Barcode field, and the label's weight becomes
    // the quantity — no loose-qty sheet needed, the scale already weighed it.
    final weighted = parseWeightedBarcode(code);
    if (weighted != null) {
      for (final p in products) {
        if (p['barcode'] == weighted.itemCode &&
            (p['units'] as Map?)?['allow_decimal'] == true) {
          final stock = toDouble(p['current_stock']);
          final projected =
              ref
                  .read(cartProvider.notifier)
                  .qtyInCart(p['id'] as String, null) +
              weighted.weightKg;
          if (projected > stock) {
            final proceed = await _confirmStockIssue(p, null, stock, projected);
            if (!mounted || !proceed) return;
          }
          ref
              .read(cartProvider.notifier)
              .addProduct(p, addQty: weighted.weightKg);
          _clearSearch();
          _searchFocus.requestFocus();
          return;
        }
      }
    }
    // single search result -> add it
    if (products.length == 1) {
      await _addToCart(products.first);
      return;
    }
    // Nothing matched (or the code is ambiguous against 2+ results still
    // shown below) — say so instead of silently doing nothing, which from
    // a hardware barcode-scanner wedge looks identical to the scanner
    // itself being broken.
    if (mounted) {
      showError(
        context,
        products.isEmpty
            ? 'No product found for "$code"'
            : '"$code" matches ${products.length} products — pick one below',
      );
    }
  }

  /// Applies a quantity change to a line already in the cart, warning (with
  /// an "Add stock first" shortcut and a non-blocking override) if it would
  /// exceed the stock captured when the line was added.
  Future<void> _changeQty(CartLine line, double newQty) async {
    final stock = line.availableStock;
    if (stock != null && newQty > stock) {
      final action = await _showStockDialog(
        context,
        title: 'Not enough stock',
        message:
            '${line.name} only has ${qty(stock)} in stock, but this bill would need '
            '${qty(newQty)}. Add stock first, or continue anyway?',
      );
      if (action == null || action == 'cancel') return;
      if (action == 'add_stock') {
        final productMap = {
          'id': line.productId,
          'name': line.name,
          'current_stock': stock,
        };
        final variantMap = line.variantId != null
            ? {
                'id': line.variantId,
                'name': line.variantName,
                'current_stock': stock,
              }
            : null;
        if (!mounted) return;
        final adjusted = await showAdjustStockSheet(
          context,
          ref,
          product: productMap,
          variant: variantMap,
        );
        if (adjusted != true) return;
        ref.invalidate(posProductsProvider);
        if (!mounted) return;
        final fresh = await _freshStock(productMap, variantMap);
        ref.read(cartProvider.notifier).updateAvailableStock(line, fresh);
        if (fresh < newQty) {
          if (mounted) {
            showError(
              context,
              'Still not enough stock (${qty(fresh)} available).',
            );
          }
          return;
        }
      }
    }
    ref.read(cartProvider.notifier).changeQty(line, newQty);
  }

  Future<void> _editLine(CartLine line) async {
    final price = TextEditingController(text: line.price.toStringAsFixed(2));
    final qtyC = TextEditingController(text: qty(line.qty));
    final discount = TextEditingController(
      text: line.discount == 0 ? '' : line.discount.toStringAsFixed(2),
    );
    final serial = TextEditingController(text: line.serialNo);
    var discountIsPercent = line.discountIsPercent;
    // The server rejects below-list prices and discounts without this
    // permission (migration 0037 check_line_price), so don't offer them.
    final canEditPrices =
        ref.read(appContextProvider).value?.canEditPrices ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(line.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyC,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: price,
                        readOnly: !canEditPrices,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Price ₹',
                          helperText: canEditPrices ? null : 'Owner sets prices',
                        ),
                      ),
                    ),
                  ],
                ),
                if (canEditPrices) ...[
                  const SizedBox(height: 12),
                  AmountOrPercentField(
                    controller: discount,
                    isPercent: discountIsPercent,
                    onModeChanged: (v) =>
                        setDialogState(() => discountIsPercent = v),
                    label: 'Line discount',
                  ),
                ],
                if (line.trackSerial) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: serial,
                    decoration: const InputDecoration(
                      labelText: 'IMEI / Serial no.',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final notifier = ref.read(cartProvider.notifier);
    var newQty = double.tryParse(qtyC.text) ?? line.qty;
    if (!line.allowDecimal && newQty % 1 != 0) {
      showError(
        context,
        '${line.name} is sold in whole ${line.unitName.isEmpty ? 'units' : line.unitName} — quantity must be a whole number',
      );
      newQty = line.qty;
    }
    await _changeQty(line, newQty);
    if (!mounted) return;
    final updated = ref
        .read(cartProvider)
        .lines
        .firstWhere((l) => l.key == line.key, orElse: () => line);
    notifier.changePrice(updated, double.tryParse(price.text) ?? line.price);
    notifier.changeDiscount(updated, double.tryParse(discount.text) ?? 0);
    notifier.changeDiscountMode(updated, discountIsPercent);
    if (line.trackSerial) notifier.changeSerial(updated, serial.text.trim());
  }

  String _lineDiscountLabel(CartLine line) {
    if (line.discount <= 0) return '';
    return line.discountIsPercent
        ? '  −${qty(line.discount)}% (${money(line.discountAmount)})'
        : '  −${money(line.discountAmount)}';
  }

  /// Confirms discarding in-progress edits before leaving the edit route —
  /// without this, a back gesture would leave the invoice's items sitting in
  /// the global cart with [editingInvoiceProvider] still set, silently
  /// hijacking the next "New Bill" the cashier starts.
  Future<bool> _confirmDiscardEdit() async {
    final ok = await confirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Changes to this bill haven\'t been saved yet.',
      confirmText: 'Discard',
    );
    if (ok) {
      ref.read(cartProvider.notifier).clear();
      ref.read(editingInvoiceProvider.notifier).set(null);
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final search = ref.watch(posSearchProvider);
    final products = ref.watch(posProductsProvider);
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final pendingCount = ref.watch(pendingBillCountProvider).value ?? 0;
    final editing = ref.watch(editingInvoiceProvider);

    final scaffold = Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        // In edit-bill mode the back arrow must run the same discard-confirm
        // guard as the system back gesture (a plain pop would bypass the
        // PopScope below — GoRouter's programmatic pop doesn't consult it).
        leading: editing != null
            ? BackButton(
                onPressed: () async {
                  if (await _confirmDiscardEdit() && context.mounted) {
                    context.pop();
                  }
                },
              )
            : appBarBack(context),
        title: Text(
          editing == null ? 'New Bill' : 'Edit Bill — ${editing.invoiceNo}',
        ),
        actions: [
          const GuideButton('pos'),
          if (!isOnline)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: StatusChip('offline', color: AppColors.orange),
            ),
          if (pendingCount > 0)
            IconButton(
              icon: Badge(
                label: Text('$pendingCount'),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.sync_problem),
              ),
              tooltip: 'Pending offline bills',
              onPressed: () => context.push('/offline-bills'),
            ),
          if (cart.lines.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear bill',
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Clear bill?',
                  message: 'Remove all items from this bill?',
                  confirmText: 'Clear',
                );
                if (ok) ref.read(cartProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: CoachTarget(
                    page: 'pos',
                    id: 'search',
                    child: SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      hint: 'Search or scan barcode…',
                      onChanged: (v) =>
                          ref.read(posSearchProvider.notifier).set(v),
                      onSubmitted: _onSubmitted,
                      suffix: search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _clearSearch,
                            )
                          : null,
                    ),
                  ),
                ),
                if (!isDesktopPlatform) ...[
                  const SizedBox(width: 8),
                  CoachTarget(
                    page: 'pos',
                    id: 'scan',
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.push('/scan'),
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.qr_code_scanner,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // customer row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: CoachTarget(
              page: 'pos',
              id: 'customer',
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  // Editing an existing bill never changes who it was billed
                  // to (update_invoice doesn't touch customer_id) — the
                  // customer here is just shown for context, not editable.
                  onTap: editing != null
                      ? null
                      : () async {
                          final customer = await showCustomerPicker(context);
                          if (customer != null) {
                            ref
                                .read(cartProvider.notifier)
                                .setCustomer(customer);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        cart.customer == null
                            ? const IconChip(
                                Icons.person_add_alt_1,
                                color: AppColors.indigo,
                                size: 34,
                              )
                            : InitialsAvatar(
                                cart.customer!['name'] as String? ?? '',
                                radius: 17,
                              ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            cart.customer == null
                                ? 'Walk-in customer (tap to select)'
                                : '${cart.customer!['name']}'
                                      '${(cart.customer!['phone'] as String? ?? '').isNotEmpty ? ' • ${cart.customer!['phone']}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: cart.customer == null
                                  ? AppColors.inkSoft
                                  : AppColors.ink,
                              fontWeight: cart.customer == null
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (editing != null)
                          const SizedBox.shrink()
                        else if (cart.customer != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => ref
                                .read(cartProvider.notifier)
                                .setCustomer(null),
                          )
                        else
                          Icon(
                            Icons.chevron_right,
                            color: AppColors.inkSoft,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: search.isNotEmpty
                // ---- search results ----
                ? AsyncView(
                    value: products,
                    onRetry: () => ref.invalidate(posProductsProvider),
                    builder: (rows) => rows.isEmpty
                        ? EmptyState(
                            icon: Icons.search_off,
                            message: 'No product found for "$search"',
                            action: OutlinedButton.icon(
                              onPressed: () => context.push('/products/new'),
                              icon: const Icon(Icons.add),
                              label: const Text('Add product'),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = rows[i];
                              final stock = toDouble(p['current_stock']);
                              return Card(
                                child: ListTile(
                                  leading: const IconChip(
                                    Icons.inventory_2_outlined,
                                    color: AppColors.indigo,
                                    size: 38,
                                  ),
                                  title: Text(
                                    p['name'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    money(p['selling_price'] as num?),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: StatusChip(
                                    'Stock ${qty(stock)}',
                                    color: stock <= 0
                                        ? AppColors.red
                                        : AppColors.green,
                                  ),
                                  onTap: () => _addToCart(p),
                                ),
                              );
                            },
                          ),
                  )
                // ---- cart lines ----
                : cart.lines.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    message:
                        'Bill is empty.\nSearch or scan products to add them.',
                  )
                : CoachTarget(
                    page: 'pos',
                    id: 'cart',
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: cart.lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final line = cart.lines[i];
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _editLine(line),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  IconChip(
                                    line.trackSerial
                                        ? Icons.smartphone
                                        : Icons.inventory_2_outlined,
                                    color: AppColors.accentFor(line.name),
                                    size: 42,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${line.name}${line.variantName.isNotEmpty ? ' — ${line.variantName}' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${money(line.price)} × ${qty(line.qty)}${_lineDiscountLabel(line)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.inkSoft,
                                          ),
                                        ),
                                        if (line.trackSerial)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              line.serialNo.isEmpty
                                                  ? 'Tap to add IMEI/serial'
                                                  : 'S/N: ${line.serialNo}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: line.serialNo.isEmpty
                                                    ? AppColors.orange
                                                    : AppColors.inkSoft,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        money(line.gross),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _QtyStepper(
                                        qty: line.qty,
                                        onDecrement: () => ref
                                            .read(cartProvider.notifier)
                                            .changeQty(line, line.qty - 1),
                                        onIncrement: () =>
                                            _changeQty(line, line.qty + 1),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          // ---- bottom bar ----
          if (cart.lines.isNotEmpty)
            SafeArea(
              top: false,
              child: CoachTarget(
                page: 'pos',
                id: 'charge',
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    boxShadow: softShadow(20),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${cart.itemCount} items • Qty ${qty(cart.totalQty)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.inkSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              money(cart.total),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (cart.taxTotal > 0)
                              Text(
                                'incl. GST ${money(cart.taxTotal)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => showCheckoutSheet(context),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(
                          editing == null ? 'Checkout' : 'Review changes',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(150, 52),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // Editing an existing invoice is the only case that needs interception —
    // the normal "New Bill" shell-tab flow is left completely untouched
    // (no PopScope at all), so there's zero behavior change for the
    // everyday path. `canPop: false` plus an explicit `Navigator.pop` after
    // confirming is the pattern Flutter's own docs recommend for this exact
    // "confirm before leaving" case — a re-check of `canPop` itself would
    // otherwise re-block the very pop the confirmation just approved.
    if (editing == null) return scaffold;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardEdit() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: scaffold,
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onDecrement,
    required this.onIncrement,
  });

  final double qty;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove, onDecrement),
          SizedBox(
            width: 28,
            child: Text(
              qtyStr(qty),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          _stepBtn(Icons.add, onIncrement),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

String qtyStr(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
