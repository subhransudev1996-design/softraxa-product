import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/opening_balance.dart';
import '../../core/gst.dart';
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
      final rows = await query.order('name', ascending: true).limit(200);
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

  var state = existing?['state_code'] as String? ?? '';

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? t('Add supplier') : 'Edit supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t('Name *')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t('Phone')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                maxLines: 2,
                decoration: InputDecoration(labelText: t('Address')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gst,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('GSTIN (optional)'),
                  errorText: gstinError(gst.text),
                ),
                onChanged: (v) => setState(() {
                  state = stateFromGstin(v) ?? state;
                }),
              ),
              const SizedBox(height: 12),
              GstStateField(
                value: state,
                helperText: t('Another state means IGST on their bills'),
                onChanged: (v) => setState(() => state = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: creditLimit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t('Credit limit ₹ (optional)'),
                  helperText: t('Max amount you can owe this supplier — leave blank for no limit'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: gstinError(gst.text) == null
                ? () => Navigator.pop(ctx, true)
                : null,
            child: Text(t('Save')),
          ),
        ],
      ),
    ),
  );
  if (saved != true || name.text.trim().isEmpty) return null;

  final client = ref.read(supabaseProvider);
  final row = {
    'name': name.text.trim(),
    'phone': phone.text.trim(),
    'address': address.text.trim(),
    'gst_number': gst.text.trim().toUpperCase(),
    'state_code': state,
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
        title: Text(t('Pay supplier')),
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
                labelText: t('Amount ₹ (pending {v1})', {'v1': money(due)}),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: InputDecoration(labelText: t('Payment mode')),
              items: [
                DropdownMenuItem(value: 'cash', child: Text(t('Cash'))),
                DropdownMenuItem(value: 'upi', child: Text(t('UPI'))),
                DropdownMenuItem(value: 'card', child: Text(t('Card'))),
                DropdownMenuItem(value: 'other', child: Text(t('Bank/Other'))),
              ],
              onChanged: (v) => setState(() => mode = v ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: t('Note (optional)')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Pay')),
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
    if (context.mounted) showSuccess(context, t('Payment recorded'));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Deletes a supplier from the list. Their purchases, payments and returns
/// stay in the books (purchases keep the supplier's name), so this only hides
/// them: is_active = false, which every supplier list and picker filters on.
/// Not allowed while money is owed either way — that would hide a balance.
/// Returns true when deleted.
Future<bool> deleteSupplier(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> supplier,
) async {
  final name = supplier['name'] as String? ?? '';
  final due = toDouble(supplier['due_amount']);
  if (due.abs() >= 0.005) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Can\'t delete yet')),
        content: Text(
          due > 0
              ? 'You still owe $name ${money(due)}. Pay or settle it first, '
                    'then delete.'
              : '$name owes you ${money(-due)}. Settle it first, then delete.',
        ),
        actions: [
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('OK')),
          ),
        ],
      ),
    );
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Delete {name}?', {'name': name})),
      content: Text(t('They will no longer appear in your supplier list or when adding a purchase. Their past purchases and payments stay in your records and reports.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t('Cancel')),
        ),
        FilledButton(
          style: dialogActionStyle.copyWith(
            backgroundColor: const WidgetStatePropertyAll(AppColors.red),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('Delete')),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref
        .read(supabaseProvider)
        .from('suppliers')
        .update({'is_active': false})
        .eq('id', supplier['id'] as String);
    ref.invalidate(suppliersProvider);
    if (context.mounted) showSuccess(context, t('{name} deleted', {'name': name}));
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

Future<void> _callPhone(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  try {
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      showError(context, t('Could not open the phone dialer.'));
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

    final mainAction = ScreenAction(
      label: t('Add supplier'),
      icon: Icons.add,
      onPressed: () => showSupplierForm(context, ref),
      coachPage: 'suppliers',
      coachId: 'add',
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Suppliers')),
        actions: [
          // Import from Excel with opening balances (owner, migration 0051).
          if (ref.watch(appContextProvider).value?.isOwner ?? false)
            IconButton(
              tooltip: t('Import from Excel'),
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: () => context.push('/import/suppliers'),
            ),
          const GuideButton('suppliers'),
          mainAction.inAppBar(context),
        ],
      ),
      floatingActionButton: mainAction.fab(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: t('Search name or phone'),
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
              child: CoachTarget(
                page: 'suppliers',
                id: 'list',
                child: AsyncView(
                  value: suppliers,
                  onRetry: () => ref.invalidate(suppliersProvider),
                  builder: (rows) => rows.isEmpty
                      ? EmptyState(
                          icon: Icons.local_shipping_outlined,
                          message: t('No suppliers yet'),
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
                                    dueLabel: t('We owe'),
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
                                    onCall:
                                        (s['phone'] as String? ?? '').isEmpty
                                        ? null
                                        : () => _callPhone(
                                            context,
                                            s['phone'] as String,
                                          ),
                                    onPay:
                                        !(ref
                                                .watch(appContextProvider)
                                                .value
                                                ?.canManagePurchases ??
                                            false)
                                        ? null
                                        : () => showRecordSupplierPayment(
                                            context,
                                            ref,
                                            supplierId: s['id'] as String,
                                            due: toDouble(s['due_amount']),
                                          ),
                                    payLabel: t('Pay supplier'),
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
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
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
                        Text(t('we owe'), style: TextStyle(fontSize: 12)),
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
        leading: appBarBack(context),
        title: Text(t('Supplier')),
        actions: [
          const GuideButton('supplier_detail'),
          // Balance from before Dukania (owner, migration 0051).
          if (data.hasValue &&
              (ref.watch(appContextProvider).value?.isOwner ?? false))
            IconButton(
              tooltip: t('Opening balance'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              onPressed: () async {
                final party = data.value!['supplier'] as Map<String, dynamic>;
                final ok = await showOpeningBalanceDialog(
                  context,
                  ref,
                  supplier: true,
                  partyId: supplierId,
                  name: party['name'] as String? ?? '',
                );
                if (ok) ref.invalidate(supplierLedgerProvider(supplierId));
              },
            ),
          if (data.hasValue)
            CoachTarget(
              page: 'supplier_detail',
              id: 'edit',
              child: IconButton(
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
            ),
          if (data.hasValue &&
              (ref.watch(appContextProvider).value?.canManagePurchases ??
                  false))
            IconButton(
              tooltip: t('Delete supplier'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final deleted = await deleteSupplier(
                  context,
                  ref,
                  data.value!['supplier'] as Map<String, dynamic>,
                );
                if (!deleted || !context.mounted) return;
                context.canPop() ? context.pop() : context.go('/suppliers');
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
                CoachTarget(
                  page: 'supplier_detail',
                  id: 'info',
                  child: Card(
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
                                    if ((s['phone'] as String? ?? '')
                                        .isNotEmpty)
                                      Text(s['phone'] as String),
                                    if ((s['address'] as String? ?? '')
                                        .isNotEmpty)
                                      Text(
                                        s['address'] as String,
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
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('Pending payment')),
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
                                Text(t('Credit limit'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                                Text(
                                  money(creditLimit),
                                  style: TextStyle(
                                    fontSize: 13,
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
                                    t('Over credit limit by {v1}', {'v1': money(due - creditLimit)}),
                                    style: const TextStyle(
                                      fontSize: 13,
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
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CoachTarget(
                        page: 'supplier_detail',
                        id: 'pay',
                        child: FilledButton.icon(
                          onPressed: () => showRecordSupplierPayment(
                            context,
                            ref,
                            supplierId: supplierId,
                            due: due,
                          ),
                          icon: const Icon(Icons.payments),
                          label: Text(t('Pay supplier')),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CoachTarget(
                        page: 'supplier_detail',
                        id: 'new_purchase',
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                            '/purchases/new?supplier=$supplierId',
                          ),
                          icon: const Icon(Icons.add_shopping_cart),
                          label: Text(t('New purchase')),
                        ),
                      ),
                    ),
                  ],
                ),
                SectionLabel(t('Ledger')),
                if (entries.isEmpty)
                  EmptyState(
                    icon: Icons.receipt_long,
                    message: t('No transactions yet'),
                  )
                else
                  CoachTarget(
                    page: 'supplier_detail',
                    id: 'ledger',
                    child: Card(
                      child: Column(
                        children: [
                          for (final e in entries) _ledgerTile(context, e),
                        ],
                      ),
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
                  Text(subtitle, style: const TextStyle(fontSize: 13)),
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
