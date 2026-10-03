import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../../core/formatters.dart';
import '../offline/offline_service.dart';
import 'cart.dart';

final posSearchProvider = NotifierProvider<PosSearchNotifier, String>(
  PosSearchNotifier.new,
);

class PosSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

const posProductColumns =
    'id, name, sku, barcode, selling_price, mrp, purchase_price, gst_rate, '
    'hsn_code, current_stock, track_serial, has_variants, is_active, '
    'wholesale_price, wholesale_min_qty, image_url, '
    'secondary_unit_name, conversion_factor, pack_price, track_pieces, '
    'cutting_charge, '
    'units(name, short_name, allow_decimal), '
    'product_variants(id, name, sku, barcode, attributes, purchase_price, '
    'selling_price, mrp, current_stock, is_active)';

/// Products for the POS search. Online: queries Supabase and refreshes the
/// offline cache. Offline: searches the local cache (PRD 7.10).
final posProductsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final search = ref.watch(posSearchProvider).trim();
      final offline = ref.read(offlineServiceProvider);

      try {
        final client = ref.watch(supabaseProvider);
        var query = client
            .from('products')
            .select(posProductColumns)
            .eq('is_active', true);
        if (search.isNotEmpty) {
          query = query.or(
            'name.ilike.%$search%,sku.ilike.%$search%,barcode.ilike.%$search%',
          );
        }
        final rows = List<Map<String, dynamic>>.from(
          await query.order('name', ascending: true).limit(100),
        );
        // Keep the whole catalogue cached for offline billing (throttled,
        // paged, removes stale rows) — not just this first page of results.
        unawaited(offline.syncCatalog());
        return rows;
      } catch (_) {
        return offline.searchCachedProducts(search);
      }
    });

/// Sets the bill's customer and applies their agreed prices and wholesale
/// status to the cart (D15, migration 0043). Offline, agreed prices can't
/// be fetched, so lines fall back to wholesale/retail.
Future<void> setCartCustomer(
  WidgetRef ref,
  Map<String, dynamic>? customer,
) async {
  final notifier = ref.read(cartProvider.notifier);
  notifier.setCustomer(customer);
  if (customer == null) {
    notifier.applyCustomerPricing(const {}, wholesale: false);
    return;
  }
  final wholesale = customer['is_wholesale'] == true;
  var prices = <String, double>{};
  try {
    final rows = await ref
        .read(supabaseProvider)
        .from('customer_prices')
        .select('product_id, variant_id, price')
        .eq('customer_id', customer['id'] as String);
    prices = {
      for (final r in List<Map<String, dynamic>>.from(rows))
        '${r['product_id']}:${r['variant_id'] ?? ''}': toDouble(r['price']),
    };
  } catch (_) {
    // Offline or not yet migrated: no agreed prices.
  }
  // The cashier may have switched customer while this loaded.
  if (ref.read(cartProvider).customer?['id'] != customer['id']) return;
  notifier.applyCustomerPricing(prices, wholesale: wholesale);
}

/// The signed-in user's pricing rights (get_my_pricing_rights, 0043):
/// owners are unlimited; staff have a percentage limit. Offline, falls back
/// to the cached price permission with a 0% limit — the server re-checks.
typedef PricingRights = ({bool unlimited, bool canEditPrices, double limitPct});

final pricingRightsProvider = FutureProvider<PricingRights>((ref) async {
  final ctx = ref.watch(appContextProvider).value;
  try {
    final r = Map<String, dynamic>.from(
      await ref.read(supabaseProvider).rpc('get_my_pricing_rights') as Map,
    );
    return (
      unlimited: r['unlimited'] == true,
      canEditPrices: r['can_edit_prices'] == true,
      limitPct: toDouble(r['discount_limit_pct']),
    );
  } catch (_) {
    final owner = ctx?.isOwner ?? false;
    return (
      unlimited: owner,
      canEditPrices: owner || (ctx?.canEditPrices ?? false),
      limitPct: owner ? 100.0 : 0.0,
    );
  }
});

/// Why this bill's prices are over the user's rights, or null if fine.
String? pricingProblem(CartState cart, PricingRights rights) {
  final reduction = cart.priceReduction;
  if (rights.unlimited || reduction <= 0.05) return null;
  if (!rights.canEditPrices) {
    return 'This bill is ${money(reduction)} below the default prices — '
        'you don\'t have permission to change prices or give discounts.';
  }
  if (reduction > cart.defaultTotal * rights.limitPct / 100 + 0.05) {
    return 'This bill is ${money(reduction)} (${qty(cart.priceReductionPct)}%) below '
        'the default prices — your discount limit is ${qty(rights.limitPct)}%. Ask the owner.';
  }
  return null;
}
