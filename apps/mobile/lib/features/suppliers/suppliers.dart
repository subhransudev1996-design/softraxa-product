import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../dashboard/dashboard_screen.dart';
import '../purchases/purchase_providers.dart';
import '../../core/theme.dart';

// ---------------- providers ----------------

final supplierSearchProvider = NotifierProvider<SupplierSearchNotifier, String>(
  SupplierSearchNotifier.new,
);

class SupplierSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final supplierBalanceFilterProvider =
    NotifierProvider<SupplierBalanceFilterNotifier, String>(
      SupplierBalanceFilterNotifier.new,
    );

class SupplierBalanceFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all'; // all | balance | clear
  void set(String v) => state = v;
}

final suppliersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final search = ref.watch(supplierSearchProvider).trim();
      final balanceFilter = ref.watch(supplierBalanceFilterProvider);
      var query = client.from('suppliers').select().eq('is_active', true);
      if (search.isNotEmpty) {
        query = query.or('name.ilike.%$search%,phone.ilike.%$search%');
      }
      if (balanceFilter == 'balance') query = query.gt('due_amount', 0);
      if (balanceFilter == 'clear') query = query.lte('due_amount', 0);
      final rows = await query.order('name').limit(200);
      return List<Map<String, dynamic>>.from(rows);
    });

/// Supplier + ledger of purchases, payments and returns (PRD 7.14).
final supplierLedgerProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final client = ref.watch(supabaseProvider);
      final supplier = await client
          .from('suppliers')
          .select()
          .eq('id', id)
          .single();
      final purchases = await client
          .from('purchases')
          .select(
            'id, purchase_no, bill_no, purchase_date, subtotal, discount_amount, total, paid_amount, due_amount, payment_status',
          )
          .eq('supplier_id', id)
          .order('purchase_date', ascending: false)
          .limit(100);
      final payments = await client
          .from('supplier_payments')
          .select()
          .eq('supplier_id', id)
          .order('payment_date', ascending: false)
          .limit(100);
      final returns = await client
          .from('purchase_returns')
          .select('id, return_no, return_date, total, received_amount')
          .eq('supplier_id', id)
          .order('return_date', ascending: false)
          .limit(100);

      final entries =
          <Map<String, dynamic>>[
            for (final p in purchases)
              {
                'kind': 'purchase',
                'date': p['purchase_date'],
                'label': 'Purchase ${p['purchase_no']}',
                'debit': p['total'],
                'credit': p['paid_amount'],
                'data': p,
              },
            for (final p in payments)
              {
                'kind': 'payment',
                'date': p['payment_date'],
                'label': 'Payment made (${p['payment_mode']})',
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
        'supplier': Map<String, dynamic>.from(supplier),
        'entries': entries,
      };
    });

// ---------------- form dialog ----------------

Future<Map<String, dynamic>?> showSupplierForm(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) async {
  final name = TextEditingController(text: existing?['name'] as String? ?? '');
  final phone = TextEditingController(
    text: existing?['phone'] as String? ?? '',
  );
  final address = TextEditingController(
    text: existing?['address'] as String? ?? '',
  );
  final gst = TextEditingController(
    text: existing?['gst_number'] as String? ?? '',
  );
  final creditLimit = TextEditingController(
    text: existing?['credit_limit'] == null
        ? ''
        : toDouble(existing!['credit_limit']).toStringAsFixed(0),
  );

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add supplier' : 'Edit supplier'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: gst,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'GSTIN (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: creditLimit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Credit limit ₹ (optional)',
                helperText:
                    'Max amount you can owe this supplier — leave blank for no limit',
              ),
            ),
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
  );
  if (saved != true || name.text.trim().isEmpty) return null;

  final client = ref.read(supabaseProvider);
  final row = {
    'name': name.text.trim(),
    'phone': phone.text.trim(),
    'address': address.text.trim(),
    'gst_number': gst.text.trim().toUpperCase(),
    'credit_limit': creditLimit.text.trim().isEmpty
        ? null
        : double.tryParse(creditLimit.text),
  };
  try {
    Map<String, dynamic> result;
    if (existing == null) {
      final businessId = ref.read(appContextProvider).value?.businessId;
      result = Map<String, dynamic>.from(
        await client
            .from('suppliers')
            .insert({...row, 'business_id': businessId})
            .select()
            .single(),
      );
    } else {
      result = Map<String, dynamic>.from(
        await client
            .from('suppliers')
            .update(row)
            .eq('id', existing['id'] as String)
            .select()
            .single(),
      );
    }
    ref.invalidate(suppliersProvider);
    return result;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

/// "Pay supplier" dialog — shared by the supplier detail screen and the
/// desktop card's quick action, so there's one payment-recording path.
Future<void> showRecordSupplierPayment(
  BuildContext context,
  WidgetRef ref, {
  required String supplierId,
  required double due,
}) async {
  final amount = TextEditingController(
    text: due > 0 ? due.toStringAsFixed(2) : '',
  );
  final note = TextEditingController();
  String mode = 'cash';
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Pay supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount ₹ (pending ${money(due)})',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Payment mode'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'other', child: Text('Bank/Other')),
              ],
              onChanged: (v) => setState(() => mode = v ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pay'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final amt = double.tryParse(amount.text) ?? 0;
  if (amt <= 0) return;
  try {
    await ref
        .read(supabaseProvider)
        .rpc(
          'record_supplier_payment',
          params: {
            'p_supplier_id': supplierId,
            'p_amount': amt,
            'p_mode': mode,
            'p_note': note.text.trim(),
          },
        );
    ref.invalidate(supplierLedgerProvider(supplierId));
    ref.invalidate(suppliersProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(purchasesProvider);
    if (context.mounted) showSuccess(context, 'Payment recorded');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> _callPhone(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  try {
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      showError(context, 'Could not open the phone dialer.');
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

// ---------------- list screen ----------------

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    final balanceFilter = ref.watch(supplierBalanceFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Suppliers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSupplierForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add supplier'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: 'Search name or phone',
              onChanged: (v) =>
                  ref.read(supplierSearchProvider.notifier).set(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('balance', 'Has balance'),
                  ('clear', 'Cleared'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: balanceFilter == f.$1,
                      onSelected: (_) => ref
                          .read(supplierBalanceFilterProvider.notifier)
                          .set(f.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(suppliersProvider),
              child: AsyncView(
                value: suppliers,
                onRetry: () => ref.invalidate(suppliersProvider),
                builder: (rows) => rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.local_shipping_outlined,
                        message: 'No suppliers yet',
                      )
                    : isDesktop
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1400),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: responsiveCardWrap([
                              for (final s in rows)
                                PartyCard(
                                  name: s['name'] as String? ?? '',
                                  phone: s['phone'] as String? ?? '',
                                  due: toDouble(s['due_amount']),
                                  dueLabel: 'We owe',
                                  dueColor: AppColors.purple,
                                  creditLimit: s['credit_limit'] == null
                                      ? null
                                      : toDouble(s['credit_limit']),
                                  overLimit:
                                      s['credit_limit'] != null &&
                                      toDouble(s['due_amount']) >
                                          toDouble(s['credit_limit']),
                                  onTap: () =>
                                      context.push('/suppliers/${s['id']}'),
                                  onCall: (s['phone'] as String? ?? '').isEmpty
                                      ? null
                                      : () => _callPhone(
                                          context,
                                          s['phone'] as String,
                                        ),
                                  onPay: () => showRecordSupplierPayment(
                                    context,
                                    ref,
                                    supplierId: s['id'] as String,
                                    due: toDouble(s['due_amount']),
                                  ),
                                  payLabel: 'Pay supplier',
                                ),
                            ]),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _SupplierTile(supplier: rows[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _SupplierTile extends StatelessWidget {
  const _SupplierTile({required this.supplier});

  final Map<String, dynamic> supplier;

  @override
  Widget build(BuildContext context) {
    final s = supplier;
    final due = toDouble(s['due_amount']);
    final creditLimit = s['credit_limit'] == null
        ? null
        : toDouble(s['credit_limit']);
    final overLimit = creditLimit != null && due > creditLimit;
    // Built manually instead of ListTile (its trailing slot enforces a fixed
    // max height independent of contentPadding, which this 2-line trailing
    // column can overflow under some font metrics).
    return Card(
      child: InkWell(
        onTap: () => context.push('/suppliers/${s['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              InitialsAvatar(s['name'] as String? ?? ''),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      s['phone'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              due > 0
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (overLimit) ...[
                              const Icon(
                                Icons.warning_amber,
                                size: 14,
                                color: AppColors.orange,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              money(due),
                              style: const TextStyle(
                                color: AppColors.purple,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Text('we owe', style: TextStyle(fontSize: 11)),
                      ],
                    )
                  : const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- detail / ledger screen ----------------

class SupplierDetailScreen extends ConsumerWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(supplierLedgerProvider(supplierId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Supplier'),
        actions: [
          if (data.hasValue)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await showSupplierForm(
                  context,
                  ref,
                  existing: data.value!['supplier'] as Map<String, dynamic>,
                );
                if (updated != null) {
                  ref.invalidate(supplierLedgerProvider(supplierId));
                }
              },
            ),
        ],
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(supplierLedgerProvider(supplierId)),
        builder: (d) {
          final s = d['supplier'] as Map<String, dynamic>;
          final entries = d['entries'] as List<Map<String, dynamic>>;
          final due = toDouble(s['due_amount']);
          final creditLimit = s['credit_limit'] == null
              ? null
              : toDouble(s['credit_limit']);
          final overLimit = creditLimit != null && due > creditLimit;

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(supplierLedgerProvider(supplierId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            InitialsAvatar(
                              s['name'] as String? ?? '',
                              radius: 26,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if ((s['phone'] as String? ?? '').isNotEmpty)
                                    Text(s['phone'] as String),
                                  if ((s['address'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(
                                      s['address'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.inkSoft,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pending payment'),
                            Text(
                              money(due),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: due > 0
                                    ? AppColors.purple
                                    : AppColors.green,
                              ),
                            ),
                          ],
                        ),
                        if (creditLimit != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Credit limit',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                              Text(
                                money(creditLimit),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (overLimit) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                size: 16,
                                color: AppColors.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Over credit limit by ${money(due - creditLimit)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showRecordSupplierPayment(
                          context,
                          ref,
                          supplierId: supplierId,
                          due: due,
                        ),
                        icon: const Icon(Icons.payments),
                        label: const Text('Pay supplier'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/purchases/new?supplier=$supplierId'),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('New purchase'),
                      ),
                    ),
                  ],
                ),
                const SectionLabel('Ledger'),
                if (entries.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long,
                    message: 'No transactions yet',
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final e in entries) _ledgerTile(context, e),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ledgerTile(BuildContext context, Map<String, dynamic> e) {
    final data = e['data'] as Map;
    final discount = e['kind'] == 'purchase'
        ? toDouble(data['discount_amount'])
        : 0.0;
    final subtitle = discount > 0
        ? '${dateStr(e['date'])} • ₹${discount.toStringAsFixed(0)} discount applied'
        : dateStr(e['date']);
    // Built manually instead of ListTile: its trailing slot enforces a fixed
    // max height independent of contentPadding, which a trailing column can
    // overflow under some font metrics if both debit and credit ever render
    // together.
    return InkWell(
      onTap: e['kind'] == 'purchase'
          ? () => context.push('/purchases/${data['id']}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              switch (e['kind']) {
                'purchase' => Icons.shopping_cart,
                'payment' => Icons.payments,
                _ => Icons.assignment_return,
              },
              size: 20,
              color: e['kind'] == 'purchase'
                  ? AppColors.indigo
                  : AppColors.green,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e['label'] as String),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (e['debit'] != null && toDouble(e['debit']) > 0)
                  Text(
                    '+ ${money(e['debit'] as num?)}',
                    style: const TextStyle(
                      color: AppColors.purple,
                      fontSize: 13,
                    ),
                  ),
                if (e['credit'] != null && toDouble(e['credit']) > 0)
                  Text(
                    '- ${money(e['credit'] as num?)}',
                    style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
