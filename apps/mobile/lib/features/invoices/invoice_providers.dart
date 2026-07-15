import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';

class InvoiceFilter {
  const InvoiceFilter({
    this.search = '',
    this.status,
    this.type,
    this.from,
    this.to,
  });

  final String search;
  final String? status; // paid | partial | unpaid
  final String? type; // gst | non_gst | cash_memo | estimate
  final DateTime? from;
  final DateTime? to;

  InvoiceFilter copyWith({
    String? search,
    Object? status = _s,
    Object? type = _s,
    Object? from = _s,
    Object? to = _s,
  }) => InvoiceFilter(
    search: search ?? this.search,
    status: status == _s ? this.status : status as String?,
    type: type == _s ? this.type : type as String?,
    from: from == _s ? this.from : from as DateTime?,
    to: to == _s ? this.to : to as DateTime?,
  );

  static const _s = Object();
}

final invoiceFilterProvider =
    NotifierProvider<InvoiceFilterNotifier, InvoiceFilter>(
      InvoiceFilterNotifier.new,
    );

class InvoiceFilterNotifier extends Notifier<InvoiceFilter> {
  @override
  InvoiceFilter build() => const InvoiceFilter();
  void set(InvoiceFilter f) => state = f;
}

final invoicesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = ref.watch(supabaseProvider);
  final filter = ref.watch(invoiceFilterProvider);

  var query = client
      .from('invoices')
      .select(
        'id, invoice_no, invoice_type, invoice_date, customer_name, customer_phone, '
        'total, paid_amount, due_amount, payment_status, payment_mode, is_cancelled, offline_created',
      );
  if (filter.search.isNotEmpty) {
    query = query.or(
      'invoice_no.ilike.%${filter.search}%,customer_name.ilike.%${filter.search}%,customer_phone.ilike.%${filter.search}%',
    );
  }
  if (filter.status != null) query = query.eq('payment_status', filter.status!);
  if (filter.type != null) query = query.eq('invoice_type', filter.type!);
  if (filter.from != null) {
    query = query.gte('invoice_date', filter.from!.toIso8601String());
  }
  if (filter.to != null) {
    final endOfDay = DateTime(
      filter.to!.year,
      filter.to!.month,
      filter.to!.day,
      23,
      59,
      59,
      999,
    );
    query = query.lte('invoice_date', endOfDay.toIso8601String());
  }
  final rows = await query.order('invoice_date', ascending: false).limit(200);
  return List<Map<String, dynamic>>.from(rows);
});

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final client = ref.watch(supabaseProvider);
      final row = await client
          .from('invoices')
          .select(
            '*, '
            'invoice_items(*, products(track_serial, current_stock, units(allow_decimal)), '
            'product_variants(current_stock)), '
            'invoice_payments(*)',
          )
          .eq('id', id)
          .single();
      return Map<String, dynamic>.from(row);
    });
