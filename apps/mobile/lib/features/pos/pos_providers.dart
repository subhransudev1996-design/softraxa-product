import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../offline/offline_service.dart';

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
    'secondary_unit_name, conversion_factor, track_pieces, '
    'units(name, short_name, allow_decimal), '
    'product_variants(id, name, sku, barcode, attributes, purchase_price, '
    'selling_price, mrp, current_stock, is_active)';

/// Products for the POS search. Online: queries Supabase and refreshes the
/// offline cache. Offline: searches the local cache (PRD 7.10).
final posProductsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
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
      await query.order('name').limit(100),
    );
    // Keep the whole catalogue cached for offline billing (throttled,
    // paged, removes stale rows) — not just this first page of results.
    unawaited(offline.syncCatalog());
    return rows;
  } catch (_) {
    return offline.searchCachedProducts(search);
  }
});
