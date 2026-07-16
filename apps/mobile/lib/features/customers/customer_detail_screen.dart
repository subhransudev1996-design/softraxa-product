import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/widgets.dart';
import 'customer_providers.dart';
import 'customers_screen.dart';
import '../../core/theme.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(customerLedgerProvider(customerId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          if (data.hasValue)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await showCustomerForm(
                  context,
                  ref,
                  existing: data.value!['customer'] as Map<String, dynamic>,
                );
                if (updated != null) {
                  ref.invalidate(customerLedgerProvider(customerId));
                }
              },
            ),
        ],
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(customerLedgerProvider(customerId)),
        builder: (d) {
          final c = d['customer'] as Map<String, dynamic>;
          final entries = d['entries'] as List<Map<String, dynamic>>;
          final due = toDouble(c['due_amount']);
          final creditLimit = c['credit_limit'] == null
              ? null
              : toDouble(c['credit_limit']);
          final overLimit = creditLimit != null && due > creditLimit;

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(customerLedgerProvider(customerId)),
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
                              c['name'] as String? ?? '',
                              radius: 26,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if ((c['phone'] as String? ?? '').isNotEmpty)
                                    Text(c['phone'] as String),
                                  if ((c['address'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(
                                      c['address'] as String,
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
                            const Text('Outstanding due'),
                            Text(
                              money(due),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: due > 0
                                    ? AppColors.red
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
                if (due > 0) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => showRecordCustomerPayment(
                      context,
                      ref,
                      customerId: customerId,
                      due: due,
                    ),
                    icon: const Icon(Icons.payments),
                    label: const Text('Receive payment'),
                  ),
                ],
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
    final discount = e['kind'] == 'invoice'
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
      onTap: e['kind'] == 'invoice'
          ? () => context.push('/invoices/${data['id']}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              switch (e['kind']) {
                'invoice' => Icons.receipt_long,
                'payment' => Icons.payments,
                _ => Icons.assignment_return,
              },
              size: 20,
              color: e['kind'] == 'invoice'
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
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
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
