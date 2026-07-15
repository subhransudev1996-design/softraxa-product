import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../dashboard/dashboard_screen.dart';
import '../invoices/invoice_providers.dart';
import 'customer_providers.dart';
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

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
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
                helperText: 'Leave blank for no limit',
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

/// "Receive due payment" dialog — shared by the customer detail screen and
/// the desktop card's quick action, so there's one payment-recording path.
Future<void> showRecordCustomerPayment(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
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
        title: const Text('Receive due payment'),
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
                labelText: 'Amount ₹ (due ${money(due)})',
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
            child: const Text('Receive'),
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
          'record_customer_payment',
          params: {
            'p_customer_id': customerId,
            'p_amount': amt,
            'p_mode': mode,
            'p_note': note.text.trim(),
          },
        );
    ref.invalidate(customerLedgerProvider(customerId));
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(invoicesProvider);
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

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    final balanceFilter = ref.watch(customerBalanceFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCustomerForm(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Add customer'),
      ),
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
                                  onCall: (c['phone'] as String? ?? '').isEmpty
                                      ? null
                                      : () => _callPhone(
                                          context,
                                          c['phone'] as String,
                                        ),
                                  onPay: () => showRecordCustomerPayment(
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
                      style: const TextStyle(
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
                                color: AppColors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Text('due', style: TextStyle(fontSize: 11)),
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
