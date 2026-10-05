import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';

class PurchaseFilter {
  const PurchaseFilter({
    this.search = '',
    this.preset = 'all',
    this.status,
    this.from,
    this.to,
  });

  final String search;
  final String preset; // all | today | yesterday | week | month | custom
  final String? status; // paid | partial | unpaid
  final DateTime? from; // only for preset 'custom'
  final DateTime? to;

  PurchaseFilter copyWith({
    String? search,
    String? preset,
    Object? status = _sentinel,
    Object? from = _sentinel,
    Object? to = _sentinel,
  }) => PurchaseFilter(
    search: search ?? this.search,
    preset: preset ?? this.preset,
    status: status == _sentinel ? this.status : status as String?,
    from: from == _sentinel ? this.from : from as DateTime?,
    to: to == _sentinel ? this.to : to as DateTime?,
  );

  /// The (from, to) day range this filter covers, or null for all dates.
  (DateTime, DateTime)? get range => preset == 'custom'
      ? (from != null && to != null ? (from!, to!) : null)
      : purchasePresetRange(preset);

  static const _sentinel = Object();
}

final purchaseFilterProvider =
    NotifierProvider<PurchaseFilterNotifier, PurchaseFilter>(
      PurchaseFilterNotifier.new,
    );

class PurchaseFilterNotifier extends Notifier<PurchaseFilter> {
  @override
  PurchaseFilter build() => const PurchaseFilter();
  void set(PurchaseFilter f) => state = f;
}

/// (from, to) inclusive day range for a quick date preset, or null for 'all'.
(DateTime, DateTime)? purchasePresetRange(String preset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (preset) {
    case 'today':
      return (today, today);
    case 'yesterday':
      final y = today.subtract(const Duration(days: 1));
      return (y, y);
    case 'week':
      return (today.subtract(Duration(days: today.weekday - 1)), today);
    case 'month':
      return (DateTime(today.year, today.month, 1), today);
    default:
      return null;
  }
}

/// The purchases matching [filter] (search, date preset, status), newest first.
PostgrestTransformBuilder<PostgrestList> _filteredPurchases(
  SupabaseClient client,
  PurchaseFilter filter,
  String columns,
) {
  var query = client.from('purchases').select(columns);
  if (filter.search.trim().isNotEmpty) {
    final s = filter.search.trim();
    query = query.or(
      'purchase_no.ilike.%$s%,bill_no.ilike.%$s%,supplier_name.ilike.%$s%',
    );
  }
  if (filter.status != null) {
    query = query.eq('payment_status', filter.status!);
  }
  final range = filter.range;
  if (range != null) {
    final (from, to) = range;
    query = query.gte('purchase_date', ymd(from)).lte('purchase_date', ymd(to));
  }
  return query
      .order('purchase_date', ascending: false)
      .order('purchase_no', ascending: false);
}

final purchasesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final filter = ref.watch(purchaseFilterProvider);
      final rows = await _filteredPurchases(
        client,
        filter,
        'id, purchase_no, bill_no, supplier_name, purchase_date, total, '
        'paid_amount, due_amount, payment_status',
      ).limit(200);
      return List<Map<String, dynamic>>.from(rows);
    });

/// Every purchase matching [filter], with its items, for the Excel download.
/// Unlike the on-screen list (200 rows) this pages through all of them.
Future<List<Map<String, dynamic>>> fetchPurchasesForExport(
  SupabaseClient client,
  PurchaseFilter filter,
) async {
  const page = 500;
  final all = <Map<String, dynamic>>[];
  for (var from = 0; ; from += page) {
    final rows = await _filteredPurchases(
      client,
      filter,
      'purchase_no, bill_no, supplier_name, purchase_date, subtotal, '
      'discount_amount, tax_amount, extra_charges, total, paid_amount, '
      'due_amount, payment_status, payment_mode, notes, '
      'purchase_items(product_name, quantity, unit_price, discount_amount, '
      'gst_rate, tax_amount, line_total)',
    ).range(from, from + page - 1);
    all.addAll(List<Map<String, dynamic>>.from(rows));
    if (rows.length < page) return all;
  }
}

final purchaseDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final client = ref.watch(supabaseProvider);
      final row = await client
          .from('purchases')
          .select(
            '*, purchase_items(*, products(current_stock), product_variants(current_stock))',
          )
          .eq('id', id)
          .single();
      return Map<String, dynamic>.from(row);
    });
