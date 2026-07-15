import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';

final customerSearchProvider = NotifierProvider<CustomerSearchNotifier, String>(
  CustomerSearchNotifier.new,
);

class CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final customerBalanceFilterProvider =
    NotifierProvider<CustomerBalanceFilterNotifier, String>(
      CustomerBalanceFilterNotifier.new,
    );

class CustomerBalanceFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all'; // all | balance | clear
  void set(String v) => state = v;
}

final customersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final search = ref.watch(customerSearchProvider).trim();
      final balanceFilter = ref.watch(customerBalanceFilterProvider);
      var query = client.from('customers').select().eq('is_active', true);
      if (search.isNotEmpty) {
        query = query.or('name.ilike.%$search%,phone.ilike.%$search%');
      }
      if (balanceFilter == 'balance') query = query.gt('due_amount', 0);
      if (balanceFilter == 'clear') query = query.lte('due_amount', 0);
      final rows = await query.order('name').limit(200);
      return List<Map<String, dynamic>>.from(rows);
    });

/// Customer + unified ledger (invoices, payments, returns) — PRD 7.13.
final customerLedgerProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final client = ref.watch(supabaseProvider);
      final customer = await client
          .from('customers')
          .select()
          .eq('id', id)
          .single();
      final invoices = await client
          .from('invoices')
          .select(
            'id, invoice_no, invoice_date, subtotal, discount_amount, total, paid_amount, due_amount, payment_status, is_cancelled, invoice_type',
          )
          .eq('customer_id', id)
          .neq('invoice_type', 'estimate')
          .order('invoice_date', ascending: false)
          .limit(100);
      final payments = await client
          .from('customer_payments')
          .select()
          .eq('customer_id', id)
          .order('payment_date', ascending: false)
          .limit(100);
      final returns = await client
          .from('sale_returns')
          .select('id, return_no, return_date, total, refund_amount')
          .eq('customer_id', id)
          .order('return_date', ascending: false)
          .limit(100);

      // merge into one ledger, newest first
      final entries =
          <Map<String, dynamic>>[
            for (final inv in invoices)
              {
                'kind': 'invoice',
                'date': inv['invoice_date'],
                'label': 'Invoice ${inv['invoice_no']}',
                'debit': inv['total'],
                'credit': inv['paid_amount'],
                'data': inv,
              },
            for (final p in payments)
              {
                'kind': 'payment',
                'date': p['payment_date'],
                'label': 'Payment received (${p['payment_mode']})',
                'debit': null,
                'credit': p['amount'],
                'data': p,
              },
            for (final r in returns)
              {
                'kind': 'return',
                'date': r['return_date'],
                'label': 'Return ${r['return_no']}',
                'debit': null,
                'credit': r['total'],
                'data': r,
              },
          ]..sort(
            (a, b) => DateTime.parse(
              b['date'].toString(),
            ).compareTo(DateTime.parse(a['date'].toString())),
          );

      return {
        'customer': Map<String, dynamic>.from(customer),
        'entries': entries,
        'invoices': List<Map<String, dynamic>>.from(invoices),
      };
    });
