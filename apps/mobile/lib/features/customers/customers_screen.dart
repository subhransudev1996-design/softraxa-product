import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../dashboard/dashboard_screen.dart';
import '../invoices/invoice_providers.dart';
import 'customer_providers.dart';
import 'receive_payment_dialog.dart';
import '../../core/theme.dart';

/// Add/edit customer dialog shared by the list and detail screens.
Future<Map<String, dynamic>?> showCustomerForm(
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
  // Existing rows carry the flag; a new customer starts on the store default.
  var unlimited = existing?['credit_unlimited'] == true;
  // Wholesale customers get wholesale prices from the first unit (PD05);
  // changing it needs the price permission (0043).
  var wholesale = existing?['is_wholesale'] == true;
  final canEditPrices =
      ref.read(appContextProvider).value?.canEditPrices ?? false;
  // Credit limits are owner-only (PD17; enforced by guard_party_columns).
  final isOwner = ref.read(appContextProvider).value?.isOwner ?? false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Add customer' : 'Edit customer'),
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
                decoration: InputDecoration(
                  labelText: 'GSTIN (optional)',
                  errorText: gstinError(gst.text),
                ),
                onChanged: (v) => setState(() {
                  state = stateFromGstin(v) ?? state;
                }),
              ),
              const SizedBox(height: 12),
              GstStateField(
                value: state,
                helperText: 'Another state means IGST on their invoices',
                onChanged: (v) => setState(() => state = v),
              ),
              const SizedBox(height: 4),
              if (canEditPrices)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Wholesale customer'),
                  subtitle: const Text('Wholesale prices from the first unit'),
                  value: wholesale,
                  onChanged: (v) => setState(() => wholesale = v),
                ),
              if (isOwner)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlimited credit'),
                  value: unlimited,
                  onChanged: (v) => setState(() => unlimited = v),
                ),
              if (isOwner && !unlimited)
                TextField(
                  controller: creditLimit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Credit limit ₹',
                    helperText: 'Leave blank to use the shop default',
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
            style: dialogActionStyle,
            onPressed: gstinError(gst.text) == null
                ? () => Navigator.pop(ctx, true)
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true || name.text.trim().isEmpty) return null;

  final client = ref.read(supabaseProvider);
  // A null limit (not unlimited) is replaced by the shop default in the
  // database (normalize_customer_credit, migration 0036).
  final row = {
    'name': name.text.trim(),
    'phone': phone.text.trim(),
    'address': address.text.trim(),
    'gst_number': gst.text.trim().toUpperCase(),
    'state_code': state,
    if (canEditPrices) 'is_wholesale': wholesale,
    if (isOwner) ...{
      'credit_unlimited': unlimited,
      'credit_limit': unlimited || creditLimit.text.trim().isEmpty
          ? null
          : double.tryParse(creditLimit.text),
    },
  };
  try {
    Map<String, dynamic> result;
    if (existing == null) {
      final businessId = ref.read(appContextProvider).value?.businessId;
      result = Map<String, dynamic>.from(
        await client
            .from('customers')
            .insert({...row, 'business_id': businessId})
            .select()
            .single(),
      );
    } else {
      result = Map<String, dynamic>.from(
        await client
            .from('customers')
            .update(row)
            .eq('id', existing['id'] as String)
            .select()
            .single(),
      );
    }
    ref.invalidate(customersProvider);
    return result;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

/// "Receive payment" — shared by the customer detail screen and the desktop
/// card's quick action, so there's one payment-recording path. Oldest bills
/// first or chosen bills; any excess becomes an advance (migration 0041).
Future<void> showRecordCustomerPayment(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  required double due,
}) async {
  final request = await showDialog<PaymentRequest>(
    context: context,
    builder: (_) => ReceivePaymentDialog(customerId: customerId, due: due),
  );
  if (request == null) return;
  try {
    await ref
        .read(supabaseProvider)
        .rpc('record_customer_payment', params: request.toParams(customerId));
    _refreshCustomerMoney(ref, customerId);
    if (context.mounted) showSuccess(context, 'Payment recorded');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Everything that shows a customer's balances or bills.
void _refreshCustomerMoney(WidgetRef ref, String customerId) {
  ref.invalidate(customerLedgerProvider(customerId));
  ref.invalidate(customersProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(invoicesProvider);
  ref.invalidate(recentInvoicesProvider);
}

/// Pay back part or all of a customer's advance. Owner only (0041).
Future<void> showRefundAdvance(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  required double advance,
}) async {
  final amount = TextEditingController(text: advance.toStringAsFixed(2));
  final note = TextEditingController();
  String mode = 'cash';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Refund advance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount ₹ (advance ${money(advance)})'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Paid back by'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Refund')),
        ],
      ),
    ),
  );
  final amt = double.tryParse(amount.text.trim()) ?? 0;
  if (ok != true || amt <= 0) return;
  try {
    await ref.read(supabaseProvider).rpc(
      'refund_customer_advance',
      params: {
        'p_customer_id': customerId,
        'p_amount': amt,
        'p_mode': mode,
        'p_note': note.text.trim(),
      },
    );
    _refreshCustomerMoney(ref, customerId);
    if (context.mounted) showSuccess(context, 'Refunded ${money(amt)}');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Reverse a recorded payment (owner only, reason required — PD23). Its
/// bills become due again; the receipt stays in history as reversed.
Future<void> showReversePayment(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  required Map<String, dynamic> payment,
}) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Reverse payment of ${money(payment['amount'] as num?)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The bills it paid will show as due again. The payment stays in '
              'the history, marked reversed.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                hintText: 'e.g. cheque bounced, entered twice',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: dialogActionStyle,
            onPressed: reason.text.trim().length >= 3 ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Reverse'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(supabaseProvider).rpc(
      'reverse_customer_payment',
      params: {'p_payment_id': payment['id'], 'p_reason': reason.text.trim()},
    );
    _refreshCustomerMoney(ref, customerId);
    if (context.mounted) showSuccess(context, 'Payment reversed');
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

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    final balanceFilter = ref.watch(customerBalanceFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final mainAction = ScreenAction(
      label: 'Add customer',
      icon: Icons.person_add,
      onPressed: () => showCustomerForm(context, ref),
      coachPage: 'customers',
      coachId: 'add',
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Customers'),
        actions: [
          // Import from Excel with opening balances (owner, migration 0051).
          if (ref.watch(appContextProvider).value?.isOwner ?? false)
            IconButton(
              tooltip: 'Import from Excel',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: () => context.push('/import/customers'),
            ),
          const GuideButton('customers'),
          mainAction.inAppBar(context),
        ],
      ),
      floatingActionButton: mainAction.fab(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: 'Search name or phone',
              onChanged: (v) =>
                  ref.read(customerSearchProvider.notifier).set(v),
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
                          .read(customerBalanceFilterProvider.notifier)
                          .set(f.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(customersProvider),
              child: CoachTarget(
                page: 'customers',
                id: 'list',
                child: AsyncView(
                  value: customers,
                  onRetry: () => ref.invalidate(customersProvider),
                  builder: (rows) => rows.isEmpty
                      ? const EmptyState(
                          icon: Icons.people_outline,
                          message: 'No customers yet',
                        )
                      : isDesktop
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: responsiveCardWrap([
                                for (final c in rows)
                                  PartyCard(
                                    name: c['name'] as String? ?? '',
                                    phone: c['phone'] as String? ?? '',
                                    due: toDouble(c['due_amount']),
                                    dueLabel: 'Due',
                                    dueColor: AppColors.red,
                                    creditLimit: c['credit_limit'] == null
                                        ? null
                                        : toDouble(c['credit_limit']),
                                    overLimit:
                                        c['credit_limit'] != null &&
                                        toDouble(c['due_amount']) >
                                            toDouble(c['credit_limit']),
                                    onTap: () =>
                                        context.push('/customers/${c['id']}'),
                                    onCall:
                                        (c['phone'] as String? ?? '').isEmpty
                                        ? null
                                        : () => _callPhone(
                                            context,
                                            c['phone'] as String,
                                          ),
                                    onPay: !(ref.watch(appContextProvider).value?.canRecordPayments ?? false)
                                        ? null
                                        : () => showRecordCustomerPayment(
                                      context,
                                      ref,
                                      customerId: c['id'] as String,
                                      due: toDouble(c['due_amount']),
                                    ),
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
                              _CustomerTile(customer: rows[i]),
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

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});

  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final due = toDouble(c['due_amount']);
    final creditLimit = c['credit_limit'] == null
        ? null
        : toDouble(c['credit_limit']);
    final overLimit = creditLimit != null && due > creditLimit;
    // Built manually instead of ListTile (its trailing slot enforces a fixed
    // max height independent of contentPadding, which this 2-line trailing
    // column can overflow under some font metrics).
    return Card(
      child: InkWell(
        onTap: () => context.push('/customers/${c['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              InitialsAvatar(c['name'] as String? ?? ''),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      c['phone'] as String? ?? '',
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
                                color: AppColors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Text('due', style: TextStyle(fontSize: 12)),
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
