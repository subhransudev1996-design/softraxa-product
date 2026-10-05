import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import 'purchase_export.dart';
import 'purchase_providers.dart';
import '../../core/theme.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider);
    final filter = ref.watch(purchaseFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final mainAction = ScreenAction(
      label: 'Add purchase',
      icon: Icons.add,
      onPressed: () => context.push('/purchases/new'),
      coachPage: 'purchases',
      coachId: 'add',
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Purchases'),
        actions: [
          const _DownloadButton(),
          const GuideButton('purchases'),
          mainAction.inAppBar(context),
        ],
      ),
      floatingActionButton: mainAction.fab(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchField(
              hint: 'Search purchase no, bill no, supplier',
              onChanged: (v) => ref
                  .read(purchaseFilterProvider.notifier)
                  .set(filter.copyWith(search: v)),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CoachTarget(
              page: 'purchases',
              id: 'presets',
              child: Row(
                children: [
                  for (final p in const [
                    ('all', 'All'),
                    ('today', 'Today'),
                    ('yesterday', 'Yesterday'),
                    ('week', 'This week'),
                    ('month', 'This month'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.$2),
                        selected: filter.preset == p.$1,
                        onSelected: (_) => ref
                            .read(purchaseFilterProvider.notifier)
                            .set(filter.copyWith(preset: p.$1)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Full width, so a short row starts at the left instead of
          // being centred.
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: CoachTarget(
                page: 'purchases',
                id: 'status',
                child: Row(
                  children: [
                    for (final s in const [
                      (null, 'All'),
                      ('paid', 'Paid'),
                      ('partial', 'Partial'),
                      // DB value is still 'unpaid' — labeled "Credit" to match the
                      // "Credit (Due)" terminology used at checkout/sales.
                      ('unpaid', 'Credit'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s.$2),
                          selected: filter.status == s.$1,
                          onSelected: (_) => ref
                              .read(purchaseFilterProvider.notifier)
                              .set(filter.copyWith(status: s.$1)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(purchasesProvider),
              child: AsyncView(
                value: purchases,
                onRetry: () => ref.invalidate(purchasesProvider),
                builder: (rows) => rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.shopping_cart_outlined,
                        message:
                            'No purchases found.\nAdd purchase bills to increase stock.',
                      )
                    : isDesktop
                    ? DesktopTable<Map<String, dynamic>>(
                        // Newest first, like the phone list.
                        initialSortIndex: 2,
                        initialAscending: false,
                        rows: rows,
                        trailingWidth: 110,
                        columns: [
                          DesktopTableColumn(
                            label: 'Purchase #',
                            flex: 2,
                            comparable: (p) =>
                                p['purchase_no'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Supplier',
                            flex: 3,
                            comparable: (p) =>
                                (p['supplier_name'] as String? ?? '')
                                    .toLowerCase(),
                          ),
                          DesktopTableColumn(
                            label: 'Date',
                            flex: 2,
                            comparable: (p) =>
                                p['purchase_date'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Amount',
                            flex: 2,
                            alignEnd: true,
                            comparable: (p) => toDouble(p['total']),
                          ),
                        ],
                        rowBuilder: (context, p) => _PurchaseRow(purchase: p),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _PurchaseTile(purchase: rows[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Downloads the purchases matching the current search, date and status
/// filters as Excel (Save dialog on Windows, share sheet on phones).
class _DownloadButton extends ConsumerStatefulWidget {
  const _DownloadButton();

  @override
  ConsumerState<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<_DownloadButton> {
  bool _busy = false;

  static const _periods = {
    'all': 'All dates',
    'today': 'Today',
    'yesterday': 'Yesterday',
    'week': 'This week',
    'month': 'This month',
  };

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final filter = ref.read(purchaseFilterProvider);
    setState(() => _busy = true);
    try {
      final rows = await fetchPurchasesForExport(
        ref.read(supabaseProvider),
        filter,
      );
      if (rows.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No purchases to download for this filter')),
        );
        return;
      }
      final range = purchasePresetRange(filter.preset);
      final period = range == null
          ? _periods['all']!
          : range.$1 == range.$2
          ? dateStr(ymd(range.$1))
          : '${dateStr(ymd(range.$1))} to ${dateStr(ymd(range.$2))}';
      final bytes = buildPurchasesWorkbook(
        purchases: rows,
        businessName:
            ref.read(appContextProvider).value?.business?['name'] as String? ??
            '',
        period: [
          period,
          if (filter.status != null) purchaseStatusLabel(filter.status),
        ].join(' · '),
      );
      final stamp = range == null ? ymd(DateTime.now()) : ymd(range.$2);
      final message = await saveOrShareFile(
        bytes,
        'Purchases_${filter.preset}_$stamp.xlsx',
        subject: 'Purchases · $period',
      );
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Download Excel',
    onPressed: _busy ? null : _download,
    icon: _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download_outlined),
  );
}

// ==================== desktop: sortable data table ====================

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase});

  final Map<String, dynamic> purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return InkWell(
      onTap: () => context.push('/purchases/${p['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                p['purchase_no'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                (p['supplier_name'] as String? ?? '').isNotEmpty
                    ? p['supplier_name'] as String
                    : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateStr(p['purchase_date']),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                money(p['total'] as num?),
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
                child: StatusChip(p['payment_status'] as String? ?? ''),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.purchase});

  final Map<String, dynamic> purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    // Built manually instead of ListTile: its trailing slot
    // enforces a fixed max height independent of contentPadding,
    // which this 2-line trailing column (amount + status chip)
    // can overflow under some font metrics.
    return Card(
      child: InkWell(
        onTap: () => context.push('/purchases/${p['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const IconChip(
                Icons.shopping_cart_outlined,
                color: AppColors.teal,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['purchase_no']}'
                      '${(p['supplier_name'] as String? ?? '').isNotEmpty ? ' • ${p['supplier_name']}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr(p['purchase_date']),
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
                    money(p['total'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  StatusChip(p['payment_status'] as String? ?? ''),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseDetailProvider(purchaseId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(detail.value?['purchase_no'] as String? ?? 'Purchase'),
      ),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(purchaseDetailProvider(purchaseId)),
        builder: (p) {
          final items = List<Map<String, dynamic>>.from(
            p['purchase_items'] as List? ?? [],
          );
          final due = toDouble(p['due_amount']);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            p['purchase_no'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          StatusChip(p['payment_status'] as String? ?? ''),
                        ],
                      ),
                      Text(
                        dateStr(p['purchase_date']),
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 13,
                        ),
                      ),
                      if ((p['bill_no'] as String? ?? '').isNotEmpty)
                        Text(
                          'Supplier bill: ${p['bill_no']}',
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 13,
                          ),
                        ),
                      if ((p['supplier_name'] as String? ?? '').isNotEmpty) ...[
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.local_shipping_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text(p['supplier_name'] as String),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final it in items)
                      ListTile(
                        dense: true,
                        title: Text(it['product_name'] as String),
                        subtitle: Text(
                          '${qty(it['quantity'] as num?)} × ${money(it['unit_price'] as num?)}'
                          '${toDouble(it['gst_rate']) > 0 ? ' + GST ${qty(it['gst_rate'] as num?)}%' : ''}'
                          '${(it['serial_nos'] as List?)?.isNotEmpty == true ? '\nS/N: ${(it['serial_nos'] as List).join(', ')}' : ''}',
                        ),
                        trailing: Text(
                          money(it['line_total'] as num?),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _row('Subtotal', money(p['subtotal'] as num?)),
                          if (toDouble(p['tax_amount']) > 0)
                            _row('GST', money(p['tax_amount'] as num?)),
                          if (toDouble(p['discount_amount']) > 0)
                            _row(
                              'Discount',
                              '- ${money(p['discount_amount'] as num?)}',
                            ),
                          if (toDouble(p['extra_charges']) > 0)
                            _row(
                              'Extra charges',
                              money(p['extra_charges'] as num?),
                            ),
                          if (toDouble(p['round_off']) != 0)
                            _row('Round off', money(p['round_off'] as num?)),
                          const Divider(),
                          _row('Total', money(p['total'] as num?), bold: true),
                          _row('Paid', money(p['paid_amount'] as num?)),
                          if (due > 0)
                            _row(
                              'Due',
                              money(due),
                              bold: true,
                              color: AppColors.purple,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/purchases/$purchaseId/return', extra: p),
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('Record purchase return'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
