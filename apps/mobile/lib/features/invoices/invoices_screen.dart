import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/date_range_filter.dart';
import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/widgets.dart';
import '../../core/supabase_providers.dart';
import 'invoice_detail_screen.dart' show canModifyInvoice, modifyInvoiceById;
import 'invoice_providers.dart';
import '../../core/theme.dart';

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final filter = ref.watch(invoiceFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final mainAction = ScreenAction(
      label: t('New bill'),
      icon: Icons.add,
      onPressed: () => context.go('/pos'),
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Invoices')),
        actions: [const GuideButton('invoices'), mainAction.inAppBar(context)],
      ),
      floatingActionButton: mainAction.fab(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: CoachTarget(
              page: 'invoices',
              id: 'search',
              child: SearchField(
                hint: t('Search invoice no, customer, phone'),
                onChanged: (v) => ref
                    .read(invoiceFilterProvider.notifier)
                    .set(filter.copyWith(search: v)),
              ),
            ),
          ),
          CoachTarget(
            page: 'invoices',
            id: 'filters',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: DateRangeFilterChip(
                      from: filter.from,
                      to: filter.to,
                      onChanged: (r) => ref
                          .read(invoiceFilterProvider.notifier)
                          .set(filter.copyWith(from: r?.start, to: r?.end)),
                    ),
                  ),
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
                ],
              ),
            ),
          ),
          Expanded(
            child: CoachTarget(
              page: 'invoices',
              id: 'list',
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(invoicesProvider),
                child: AsyncView(
                  value: invoices,
                  onRetry: () => ref.invalidate(invoicesProvider),
                  builder: (rows) => rows.isEmpty
                      ? EmptyState(
                          icon: Icons.receipt_long,
                          message: t('No invoices found'),
                        )
                      : isDesktop
                      ? DesktopTable<Map<String, dynamic>>(
                          // Newest first, like the phone list.
                          initialSortIndex: 2,
                          initialAscending: false,
                          rows: rows,
                          trailingWidth: 150,
                          columns: [
                            DesktopTableColumn(
                              label: t('Invoice #'),
                              flex: 2,
                              comparable: (r) =>
                                  r['invoice_no'] as String? ?? '',
                            ),
                            DesktopTableColumn(
                              label: t('Customer'),
                              flex: 3,
                              comparable: (r) =>
                                  (r['customer_name'] as String? ?? '')
                                      .toLowerCase(),
                            ),
                            DesktopTableColumn(
                              label: t('Date'),
                              flex: 2,
                              comparable: (r) =>
                                  r['invoice_date'] as String? ?? '',
                            ),
                            DesktopTableColumn(
                              label: t('Amount'),
                              flex: 2,
                              alignEnd: true,
                              comparable: (r) => toDouble(r['total']),
                            ),
                          ],
                          rowBuilder: (context, inv) =>
                              _InvoiceRow(invoice: inv),
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
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== desktop: sortable data table ====================

class _InvoiceRow extends ConsumerWidget {
  const _InvoiceRow({required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = invoice;
    final canEdit = canModifyInvoice(inv, ref.watch(appContextProvider).value);
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
                  if (returnLabel(inv) case final label?)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: StatusChip(label, color: AppColors.purple),
                    ),
                  if (inv['offline_created'] == true)
                    Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: t('Made offline — synced'),

                        child: Icon(
                          Icons.cloud_off,

                          size: 14,

                          color: AppColors.orange,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                customerName.isEmpty ? t('Walk-in') : customerName,
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
              width: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  StatusChip(
                    cancelled
                        ? 'cancelled'
                        : inv['payment_status'] as String? ?? '',
                  ),
                  if (canEdit) IconButton(
                    tooltip: t('Modify'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => modifyInvoiceById(
                      context,
                      ref,
                      inv['id'] as String,
                    ),
                  ) else const SizedBox(width: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _InvoiceTile extends ConsumerWidget {
  const _InvoiceTile({required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = invoice;
    final canEdit = canModifyInvoice(inv, ref.watch(appContextProvider).value);
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
                          StatusChip('estimate', color: AppColors.inkSoft),
                        if (returnLabel(inv) case final label?)
                          StatusChip(label, color: AppColors.purple),
                        if (inv['offline_created'] == true)
                          Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Tooltip(
                              message: t('Made offline — synced'),

                              child: Icon(
                                Icons.cloud_off,

                                size: 14,

                                color: AppColors.orange,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(inv['customer_name'] as String?)?.isNotEmpty == true ? inv['customer_name'] : t('Walk-in')}'
                      ' • ${dateTimeStr(inv['invoice_date'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
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
              if (canEdit) IconButton(
                    tooltip: t('Modify'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => modifyInvoiceById(
                      context,
                      ref,
                      inv['id'] as String,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "returned" when goods worth the whole bill came back, "part returned"
/// when some did; null for a bill without returns.
String? returnLabel(Map<String, dynamic> inv) {
  final returns = inv['sale_returns'] as List? ?? const [];
  if (returns.isEmpty) return null;
  final returned = returns.fold<double>(
    0,
    (s, r) => s + toDouble((r as Map)['total']),
  );
  if (returned <= 0) return null;
  // ₹1 of slack for rounding between the bill and its credit notes.
  return returned >= toDouble(inv['total']) - 1 ? 'returned' : 'part returned';
}
