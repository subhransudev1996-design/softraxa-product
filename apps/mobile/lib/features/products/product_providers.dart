import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';

/// Search text for the product list.
final productSearchProvider = NotifierProvider<ProductSearchNotifier, String>(
  ProductSearchNotifier.new,
);

class ProductSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final productsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final search = ref.watch(productSearchProvider).trim();

  var query = client.from('products').select(
      'id, name, sku, barcode, selling_price, mrp, purchase_price, gst_rate, '
      'current_stock, low_stock_qty, image_url, has_variants, track_serial, is_active, '
      'categories(name), brands(name), units(name, short_name)');
  if (search.isNotEmpty) {
    query = query.or('name.ilike.%$search%,sku.ilike.%$search%,barcode.ilike.%$search%');
  }
  final rows = await query.order('name').limit(200);
  return List<Map<String, dynamic>>.from(rows);
});

final productDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
  final client = ref.watch(supabaseProvider);
  final row = await client.from('products').select(
      '*, categories(name), brands(name), units(name, short_name, allow_decimal), '
      'product_variants(*)').eq('id', id).single();
  return Map<String, dynamic>.from(row);
});

/// Weighted (scale-label) barcode — EAN-13 in the in-store '2' prefix range,
/// the format label-printing weighing scales emit for loose goods:
///   2P IIIII WWWWW C  →  prefix(2) + 5-digit item code + weight in grams + check
/// Store owners set the product's Barcode field to the 5-digit item code.
/// Returns null unless the code is 13 digits starting with '2'.
({String itemCode, double weightKg})? parseWeightedBarcode(String code) {
  if (code.length != 13 || !code.startsWith('2')) return null;
  if (int.tryParse(code) == null) return null;
  final itemCode = code.substring(2, 7);
  final grams = int.tryParse(code.substring(7, 12));
  if (grams == null || grams <= 0) return null;
  return (itemCode: itemCode, weightKg: grams / 1000);
}

/// Find a product (or variant) by scanned barcode. Returns:
/// {product: ..., variant: ...?, qty: double?} or null when nothing matches.
/// `qty` is only present for weighted (scale-label) barcodes.
Future<Map<String, dynamic>?> findByBarcode(dynamic client, String code) async {
  final products = await client
      .from('products')
      .select('*, units(name, short_name, allow_decimal)')
      .eq('barcode', code)
      .eq('is_active', true)
      .limit(1);
  if ((products as List).isNotEmpty) {
    return {'product': Map<String, dynamic>.from(products.first), 'variant': null};
  }
  final variants = await client
      .from('product_variants')
      .select('*, products(*, units(name, short_name, allow_decimal))')
      .eq('barcode', code)
      .eq('is_active', true)
      .limit(1);
  if ((variants as List).isNotEmpty) {
    final v = Map<String, dynamic>.from(variants.first);
    final p = Map<String, dynamic>.from(v['products'] as Map);
    v.remove('products');
    return {'product': p, 'variant': v};
  }
  // No exact match: try a weighted scale-label barcode. Only accepted when a
  // product exists with the embedded item code AND its unit allows decimals,
  // so ordinary retail EAN-13s starting with 2 can't mis-fire into a sale.
  final weighted = parseWeightedBarcode(code);
  if (weighted != null) {
    final byItemCode = await client
        .from('products')
        .select('*, units(name, short_name, allow_decimal)')
        .eq('barcode', weighted.itemCode)
        .eq('is_active', true)
        .limit(1);
    if ((byItemCode as List).isNotEmpty) {
      final p = Map<String, dynamic>.from(byItemCode.first);
      if ((p['units'] as Map?)?['allow_decimal'] == true) {
        return {'product': p, 'variant': null, 'qty': weighted.weightKg};
      }
    }
  }
  return null;
}

// ---------- Master data (categories / brands / units) ----------
final categoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('categories')
      .select()
      .eq('is_active', true)
      .order('name');
  return List<Map<String, dynamic>>.from(rows);
});

final brandsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('brands')
      .select()
      .eq('is_active', true)
      .order('name');
  return List<Map<String, dynamic>>.from(rows);
});

final unitsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows =
      await ref.watch(supabaseProvider).from('units').select().order('name');
  return List<Map<String, dynamic>>.from(rows);
});
