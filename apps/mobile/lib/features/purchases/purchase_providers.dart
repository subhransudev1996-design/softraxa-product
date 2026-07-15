import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';

class PurchaseFilter {
  const PurchaseFilter({this.search = '', this.preset = 'all', this.status});

  final String search;
  final String preset; // all | today | yesterday | week | month
  final String? status; // paid | partial | unpaid

  PurchaseFilter copyWith({
    String? search,
    String? preset,
    Object? status = _sentinel,
  }) => PurchaseFilter(
    search: search ?? this.search,
    preset: preset ?? this.preset,
    status: status == _sentinel ? this.status : status as String?,
  );

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

final purchasesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final filter = ref.watch(purchaseFilterProvider);

      var query = client
          .from('purchases')
          .select(
            'id, purchase_no, bill_no, supplier_name, purchase_date, total, '
            'paid_amount, due_amount, payment_status',
          );
      if (filter.search.trim().isNotEmpty) {
        final s = filter.search.trim();
        query = query.or(
          'purchase_no.ilike.%$s%,bill_no.ilike.%$s%,supplier_name.ilike.%$s%',
        );
      }
      if (filter.status != null) {
        query = query.eq('payment_status', filter.status!);
      }
      final range = purchasePresetRange(filter.preset);
      if (range != null) {
        final (from, to) = range;
        query = query
            .gte('purchase_date', ymd(from))
            .lte('purchase_date', ymd(to));
      }
      final rows = await query
          .order('purchase_date', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(rows);
    });

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
