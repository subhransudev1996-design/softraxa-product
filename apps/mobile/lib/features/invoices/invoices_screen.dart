import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/widgets.dart';
import 'invoice_providers.dart';
import '../../core/theme.dart';

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    InvoiceFilter filter,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: filter.from != null && filter.to != null
          ? DateTimeRange(start: filter.from!, end: filter.to!)
          : null,
    );
    if (picked != null) {
      ref
          .read(invoiceFilterProvider.notifier)
          .set(filter.copyWith(from: picked.start, to: picked.end));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final filter = ref.watch(invoiceFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          const GuideButton('invoices'),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Filter by date',
            onPressed: () => _pickRange(context, ref, filter),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/pos'),
        icon: const Icon(Icons.add),
        label: const Text('New bill'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: CoachTarget(page: 'invoices', id: 'search', child: SearchField(
              hint: 'Search invoice no, customer, phone',
              onChanged: (v) => ref
                  .read(invoiceFilterProvider.notifier)
                  .set(filter.copyWith(search: v)),
            )),
          ),
          CoachTarget(page: 'invoices', id: 'filters', child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final s in const [
                  (null, 'All'),
                  ('paid', 'Paid'),
                  ('partial', 'Partial'),
                  // DB value is still 'unpaid' — labeled "Credit" to match
                  // the "Credit (Due)" terminology used at checkout.
                  ('unpaid', 'Credit'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.$2),
                      selected: filter.status == s.$1,
                      onSelected: (_) => ref
                          .read(invoiceFilterProvider.notifier)
                          .set(filter.copyWith(status: s.$1)),
                    ),
                  ),
                const SizedBox(width: 8),
                for (final t in const [
                  ('estimate', 'Estimates'),
                  ('cash_memo', 'Cash memos'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t.$2),
                      selected: filter.type == t.$1,
                      onSelected: (sel) => ref
                          .read(invoiceFilterProvider.notifier)
                          .set(filter.copyWith(type: sel ? t.$1 : null)),
                    ),
                  ),
                if (filter.from != null && filter.to != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      avatar: const Icon(Icons.date_range, size: 16),
                      label: Text(
                        '${dateStr(filter.from)} → ${dateStr(filter.to)}',
                      ),
                      onPressed: () => _pickRange(context, ref, filter),
                      onDeleted: () => ref
                          .read(invoiceFilterProvider.notifier)
                          .set(filter.copyWith(from: null, to: null)),
                    ),
                  ),
              ],
            ),
          )),
          Expanded(
            child: CoachTarget(page: 'invoices', id: 'list', child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(invoicesProvider),
              child: AsyncView(
                value: invoices,
                onRetry: () => ref.invalidate(invoicesProvider),
                builder: (rows) => rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long,
                        message: 'No invoices found',
                      )
                    : isDesktop
                    ? DesktopTable<Map<String, dynamic>>(
                        rows: rows,
                        trailingWidth: 110,
                        columns: [
                          DesktopTableColumn(
                            label: 'Invoice #',
                            flex: 2,
                            comparable: (r) => r['invoice_no'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Customer',
                            flex: 3,
                            comparable: (r) =>
                                (r['customer_name'] as String? ?? '')
                                    .toLowerCase(),
                          ),
                          DesktopTableColumn(
                            label: 'Date',
                            flex: 2,
                            comparable: (r) =>
                                r['invoice_date'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Amount',
                            flex: 2,
                            alignEnd: true,
                            comparable: (r) => toDouble(r['total']),
                          ),
                        ],
                        rowBuilder: (context, inv) => _InvoiceRow(invoice: inv),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _InvoiceTile(invoice: rows[i]),
                      ),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// ==================== desktop: sortable data table ====================

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final cancelled = inv['is_cancelled'] == true;
    final customerName = (inv['customer_name'] as String?) ?? '';

    return InkWell(
      onTap: () => context.push('/invoices/${inv['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      inv['invoice_no'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (inv['invoice_type'] == 'estimate')
                    Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: StatusChip('estimate', color: AppColors.inkSoft),
                    ),
                  if (inv['offline_created'] == true)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: AppColors.orange,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                customerName.isEmpty ? 'Walk-in' : customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateTimeStr(inv['invoice_date']),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                money(inv['total'] as num?),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Align(
                alignment: Alignment.centerRight,
                child: StatusChip(
                  cancelled
                      ? 'cancelled'
                      : inv['payment_status'] as String? ?? '',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final cancelled = inv['is_cancelled'] == true;
    final customerName = (inv['customer_name'] as String?) ?? '';
    // Built manually instead of ListTile (its trailing
    // slot enforces a fixed max height independent of
    // contentPadding, which this 2-line trailing column
    // can overflow under some font metrics).
    return Card(
      child: InkWell(
        onTap: () => context.push('/invoices/${inv['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              InitialsAvatar(customerName.isEmpty ? 'W C' : customerName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          inv['invoice_no'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: cancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (inv['invoice_type'] == 'estimate')
                          StatusChip(
                            'estimate',
                            color: AppColors.inkSoft,
                          ),
                        if (inv['offline_created'] == true)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.cloud_off,
                              size: 14,
                              color: AppColors.orange,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(inv['customer_name'] as String?)?.isNotEmpty == true ? inv['customer_name'] : 'Walk-in'}'
                      ' • ${dateTimeStr(inv['invoice_date'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(inv['total'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  StatusChip(
                    cancelled
                        ? 'cancelled'
                        : inv['payment_status'] as String? ?? '',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
