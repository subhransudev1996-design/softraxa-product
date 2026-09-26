import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../purchases/purchase_providers.dart';
import '../suppliers/suppliers.dart';
import '../../core/theme.dart';

/// Tap-to-type return quantity — needed for loose goods where the sold
/// quantity is fractional (e.g. 1.19 kg) and the ±1 stepper can't reach it.
/// Caps at [max] (can't return more than sold/purchased/in-stock).
Future<double?> _promptReturnQty(
  BuildContext context, {
  required String name,
  required double max,
  required double current,
}) async {
  final c = TextEditingController(
    text: current == 0 ? '' : qty(current).replaceAll(',', ''),
  );
  final v = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Return qty',
          helperText: 'Max ${qty(max)}',
        ),
        onSubmitted: (_) => Navigator.pop(ctx, double.tryParse(c.text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
          child: const Text('Set'),
        ),
      ],
    ),
  );
  if (v == null) return null;
  if (v < 0 || v > max) {
    if (context.mounted) {
      showError(context, 'Enter a quantity between 0 and ${qty(max)}');
    }
    return null;
  }
  return (v * 1000).round() / 1000;
}

// ================= SALE RETURNS (PRD 7.11) =================

class SaleReturnFilter {
  const SaleReturnFilter({this.search = '', this.from, this.to});

  final String search;
  final DateTime? from;
  final DateTime? to;

  SaleReturnFilter copyWith({
    String? search,
    Object? from = _s,
    Object? to = _s,
  }) => SaleReturnFilter(
    search: search ?? this.search,
    from: from == _s ? this.from : from as DateTime?,
    to: to == _s ? this.to : to as DateTime?,
  );

  static const _s = Object();
}

final saleReturnFilterProvider =
    NotifierProvider<SaleReturnFilterNotifier, SaleReturnFilter>(
      SaleReturnFilterNotifier.new,
    );

class SaleReturnFilterNotifier extends Notifier<SaleReturnFilter> {
  @override
  SaleReturnFilter build() => const SaleReturnFilter();
  void set(SaleReturnFilter f) => state = f;
}

final saleReturnsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final filter = ref.watch(saleReturnFilterProvider);

      var query = client
          .from('sale_returns')
          .select('*, invoices(invoice_no), customers(name)');
      if (filter.from != null) {
        query = query.gte('return_date', filter.from!.toIso8601String());
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
        query = query.lte('return_date', endOfDay.toIso8601String());
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('return_date', ascending: false).limit(200),
      );

      if (filter.search.trim().isEmpty) return rows.take(100).toList();
      final q = filter.search.trim().toLowerCase();
      return rows
          .where(
            (r) =>
                (r['return_no'] as String? ?? '').toLowerCase().contains(q) ||
                ((r['invoices'] as Map?)?['invoice_no'] as String? ?? '')
                    .toLowerCase()
                    .contains(q) ||
                ((r['customers'] as Map?)?['name'] as String? ?? '')
                    .toLowerCase()
                    .contains(q),
          )
          .take(100)
          .toList();
    });

/// Sale return + its line items (PRD 7.11).
final saleReturnDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final client = ref.watch(supabaseProvider);
      final row = await client
          .from('sale_returns')
          .select(
            '*, invoices(invoice_no), customers(name), sale_return_items(*)',
          )
          .eq('id', id)
          .single();
      return Map<String, dynamic>.from(row);
    });

class SaleReturnsScreen extends ConsumerWidget {
  const SaleReturnsScreen({super.key});

  Future<void> _newReturn(BuildContext context, WidgetRef ref) async {
    // 1. pick the original invoice
    final search = TextEditingController();
    final invoice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _InvoicePicker(searchController: search),
      ),
    );
    if (invoice == null || !context.mounted) return;
    await context.push('/sale-returns/new', extra: invoice);
  }

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    SaleReturnFilter filter,
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
          .read(saleReturnFilterProvider.notifier)
          .set(filter.copyWith(from: picked.start, to: picked.end));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(saleReturnsProvider);
    final filter = ref.watch(saleReturnFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Sale returns'),
        actions: [
          const GuideButton('sale_returns'),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Filter by date',
            onPressed: () => _pickRange(context, ref, filter),
          ),
        ],
      ),
      floatingActionButton: CoachTarget(
        page: 'sale_returns',
        id: 'add',
        child: FloatingActionButton.extended(
          onPressed: () => _newReturn(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New return'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchField(
              hint: 'Search return no, invoice no, customer',
              onChanged: (v) => ref
                  .read(saleReturnFilterProvider.notifier)
                  .set(filter.copyWith(search: v)),
            ),
          ),
          if (filter.from != null && filter.to != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    '${dateStr(filter.from)} → ${dateStr(filter.to)}',
                  ),
                  onPressed: () => _pickRange(context, ref, filter),
                  onDeleted: () => ref
                      .read(saleReturnFilterProvider.notifier)
                      .set(filter.copyWith(from: null, to: null)),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(saleReturnsProvider),
              child: AsyncView(
                value: returns,
                onRetry: () => ref.invalidate(saleReturnsProvider),
                builder: (rows) => rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.assignment_return_outlined,
                        message: 'No sale returns found',
                      )
                    : isDesktop
                    ? DesktopTable<Map<String, dynamic>>(
                        rows: rows,
                        trailingWidth: 90,
                        columns: [
                          DesktopTableColumn(
                            label: 'Return #',
                            flex: 2,
                            comparable: (r) => r['return_no'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Against invoice',
                            flex: 2,
                            comparable: (r) =>
                                (r['invoices'] as Map?)?['invoice_no']
                                    as String? ??
                                '',
                          ),
                          DesktopTableColumn(
                            label: 'Date',
                            flex: 2,
                            comparable: (r) =>
                                r['return_date'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Amount',
                            flex: 2,
                            alignEnd: true,
                            comparable: (r) => toDouble(r['total']),
                          ),
                        ],
                        rowBuilder: (context, r) =>
                            _SaleReturnRow(saleReturn: r),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _SaleReturnTile(saleReturn: rows[i]),
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

class _SaleReturnRow extends StatelessWidget {
  const _SaleReturnRow({required this.saleReturn});

  final Map<String, dynamic> saleReturn;

  @override
  Widget build(BuildContext context) {
    final r = saleReturn;
    return InkWell(
      onTap: () => context.push('/sale-returns/${r['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                r['return_no'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (r['invoices'] as Map?)?['invoice_no'] as String? ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateStr(r['return_date']),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                money(r['total'] as num?),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.inkSoft,
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

class _SaleReturnTile extends StatelessWidget {
  const _SaleReturnTile({required this.saleReturn});

  final Map<String, dynamic> saleReturn;

  @override
  Widget build(BuildContext context) {
    final r = saleReturn;
    // Built manually instead of ListTile (its trailing slot
    // enforces a fixed max height independent of
    // contentPadding, which this 2-line trailing column can
    // overflow under some font metrics).
    return Card(
      child: InkWell(
        onTap: () => context.push('/sale-returns/${r['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const IconChip(
                Icons.assignment_return_outlined,
                color: AppColors.orange,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['return_no'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Against ${(r['invoices'] as Map?)?['invoice_no'] ?? '—'} • ${dateStr(r['return_date'])}',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
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
                    money(r['total'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoicePicker extends ConsumerStatefulWidget {
  const _InvoicePicker({required this.searchController});
  final TextEditingController searchController;

  @override
  ConsumerState<_InvoicePicker> createState() => _InvoicePickerState();
}

class _InvoicePickerState extends ConsumerState<_InvoicePicker> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String search) async {
    try {
      final client = ref.read(supabaseProvider);
      var query = client
          .from('invoices')
          .select('*, invoice_items(*)')
          .eq('is_cancelled', false)
          .neq('invoice_type', 'estimate');
      if (search.isNotEmpty) {
        query = query.or(
          'invoice_no.ilike.%$search%,customer_name.ilike.%$search%',
        );
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('invoice_date', ascending: false).limit(50),
      );
      if (mounted) {
        setState(() {
          _invoices = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              controller: widget.searchController,
              hint: 'Search invoice no or customer',
              autofocus: true,
              onChanged: _load,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    controller: scrollController,
                    itemCount: _invoices.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final inv = _invoices[i];
                      return ListTile(
                        title: Text(
                          '${inv['invoice_no']} • ${money(inv['total'] as num?)}',
                        ),
                        subtitle: Text(
                          '${(inv['customer_name'] as String?)?.isNotEmpty == true ? inv['customer_name'] : 'Walk-in'}'
                          ' • ${dateStr(inv['invoice_date'])}',
                        ),
                        onTap: () => Navigator.pop(context, inv),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Sale return detail: which products were returned, quantities and amounts.
class SaleReturnDetailScreen extends ConsumerWidget {
  const SaleReturnDetailScreen({super.key, required this.returnId});

  final String returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(saleReturnDetailProvider(returnId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Sale return'),
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(saleReturnDetailProvider(returnId)),
        builder: (r) {
          final items = List<Map<String, dynamic>>.from(
            r['sale_return_items'] as List? ?? [],
          );
          final invoiceNo = (r['invoices'] as Map?)?['invoice_no'] as String?;
          final customerName = (r['customers'] as Map?)?['name'] as String?;

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(saleReturnDetailProvider(returnId)),
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
                            Expanded(
                              child: Text(
                                r['return_no'] as String,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              money(r['total'] as num?),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr(r['return_date']),
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 12.5,
                          ),
                        ),
                        if (invoiceNo != null) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () =>
                                context.push('/invoices/${r['invoice_id']}'),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 16,
                                  color: AppColors.indigo,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Against invoice $invoiceNo',
                                  style: const TextStyle(
                                    color: AppColors.indigo,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (customerName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            customerName,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SectionLabel('Returned products'),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const IconChip(
                            Icons.inventory_2_outlined,
                            color: AppColors.orange,
                            size: 40,
                          ),
                          title: Text(
                            items[i]['product_name'] as String? ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            'Qty ${qty(items[i]['quantity'] as num?)} × ${money(items[i]['unit_price'] as num?)}'
                            '${(items[i]['serial_no'] as String? ?? '').isNotEmpty ? '\nIMEI/Serial: ${items[i]['serial_no']}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          trailing: Text(
                            money(items[i]['line_total'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SectionLabel('Settlement'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Refund mode'),
                            Text(
                              (r['refund_mode'] as String? ?? 'cash')
                                  .toUpperCase(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Refunded now'),
                            Text(
                              money(r['refund_amount'] as num?),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (toDouble(r['total']) -
                                toDouble(r['refund_amount']) >
                            0.005) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Adjusted against due'),
                              Text(
                                money(
                                  toDouble(r['total']) -
                                      toDouble(r['refund_amount']),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if ((r['notes'] as String? ?? '').isNotEmpty) ...[
                  const SectionLabel('Note'),
                  Text(r['notes'] as String),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Create a sale return from an invoice: choose quantities to return.
class SaleReturnFormScreen extends ConsumerStatefulWidget {
  const SaleReturnFormScreen({super.key, required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  ConsumerState<SaleReturnFormScreen> createState() =>
      _SaleReturnFormScreenState();
}

class _SaleReturnFormScreenState extends ConsumerState<SaleReturnFormScreen> {
  late final List<Map<String, dynamic>> _items =
      List<Map<String, dynamic>>.from(
        widget.invoice['invoice_items'] as List? ?? [],
      );
  late final Map<String, double> _returnQty = {
    for (final it in _items) it['id'] as String: 0,
  };
  final _refund = TextEditingController();
  final _notes = TextEditingController();
  String _refundMode = 'cash';
  bool _busy = false;
  bool _refundTouched = false;

  /// Already-returned quantity per product/variant on this invoice (from
  /// earlier sale returns), keyed the same way as [_maxReturnable]. Loaded
  /// best-effort on open so the qty stepper can't be pushed past what's
  /// actually left to return — the server (`create_sale_return`) is the
  /// real enforcement point, this is just so the UI doesn't let a cashier
  /// try to return the same invoice twice and only find out after saving.
  Map<String, double> _alreadyReturned = {};
  bool _loadingReturned = true;

  @override
  void initState() {
    super.initState();
    _loadAlreadyReturned();
  }

  Future<void> _loadAlreadyReturned() async {
    try {
      final rows = await ref
          .read(supabaseProvider)
          .from('sale_return_items')
          .select(
            'product_id, variant_id, quantity, sale_returns!inner(invoice_id)',
          )
          .eq('sale_returns.invoice_id', widget.invoice['id'] as String);
      final map = <String, double>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final key = '${r['product_id']}:${r['variant_id'] ?? ''}';
        map[key] = (map[key] ?? 0) + toDouble(r['quantity']);
      }
      if (mounted) {
        setState(() {
          _alreadyReturned = map;
          _loadingReturned = false;
        });
      }
    } catch (_) {
      // Best-effort only — the server still hard-blocks over-returning.
      if (mounted) setState(() => _loadingReturned = false);
    }
  }

  bool get _isGst => widget.invoice['invoice_type'] == 'gst';

  double _lineInclRate(Map<String, dynamic> it) =>
      toDouble(it['unit_price']) *
      (_isGst ? 1 + toDouble(it['gst_rate']) / 100 : 1);

  /// How much of this line is still returnable: originally sold minus
  /// whatever earlier returns already took, floored at zero.
  double _maxReturnable(Map<String, dynamic> it) {
    final key = '${it['product_id']}:${it['variant_id'] ?? ''}';
    final already = _alreadyReturned[key] ?? 0;
    return (toDouble(it['quantity']) - already).clamp(0, double.infinity);
  }

  double get _total => _items.fold(0.0, (s, it) {
    final q = _returnQty[it['id']] ?? 0;
    return s + q * _lineInclRate(it);
  });

  double get _refundAmount =>
      _refundTouched ? (double.tryParse(_refund.text) ?? 0) : _total;

  Future<void> _save() async {
    final returningItems = _items
        .where((it) => (_returnQty[it['id']] ?? 0) > 0)
        .toList();
    if (returningItems.isEmpty) {
      showError(context, 'Enter return quantity for at least one item');
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'invoice_id': widget.invoice['id'],
        'customer_id': widget.invoice['customer_id'],
        'refund_amount': _refundAmount,
        'refund_mode': _refundMode,
        'notes': _notes.text.trim(),
        'items': [
          for (final it in returningItems)
            {
              'product_id': it['product_id'],
              'variant_id': it['variant_id'],
              'product_name': it['product_name'],
              'serial_no': it['serial_no'] ?? '',
              'quantity': _returnQty[it['id']],
              'unit_price': _lineInclRate(it),
              'tax_amount': 0,
              'line_total': double.parse(
                ((_returnQty[it['id']] ?? 0) * _lineInclRate(it))
                    .toStringAsFixed(2),
              ),
            },
        ],
      };
      final res =
          await ref
                  .read(supabaseProvider)
                  .rpc('create_sale_return', params: {'payload': payload})
              as Map<String, dynamic>;
      ref.invalidate(saleReturnsProvider);
      invalidateStockData(ref);
      if (mounted) {
        // The server values the return from the original bill and settles
        // the bill's due first (migration 0038), so report its figures.
        final applied = toDouble(res['applied_to_bill']);
        final refund = toDouble(res['refund']);
        showSuccess(
          context,
          'Return ${res['return_no']} recorded — ${money(res['total'] as num?)}'
          '${applied > 0 ? ', ${money(applied)} off the bill' : ''}'
          '${refund > 0 ? ', ${money(refund)} to refund' : ''}',
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text('Return — ${widget.invoice['invoice_no']}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Select items to return'),
          for (final it in _items)
            Builder(
              builder: (context) {
                final maxReturnable = _loadingReturned
                    ? 0.0
                    : _maxReturnable(it);
                final already =
                    _alreadyReturned['${it['product_id']}:${it['variant_id'] ?? ''}'] ??
                    0;
                final canReturn = !_loadingReturned && maxReturnable > 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${it['product_name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Sold: ${qty(it['quantity'] as num?)} @ ${money(_lineInclRate(it))}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                              if (_loadingReturned)
                                Text(
                                  'Checking earlier returns…',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkSoft,
                                  ),
                                )
                              else if (already > 0)
                                Text(
                                  maxReturnable <= 0
                                      ? 'Already fully returned'
                                      : '${qty(already)} already returned — ${qty(maxReturnable)} left to return',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: maxReturnable <= 0
                                        ? AppColors.red
                                        : AppColors.orange,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: !canReturn
                              ? null
                              : () => setState(() {
                                  final cur = _returnQty[it['id']] ?? 0;
                                  if (cur > 0) {
                                    _returnQty[it['id'] as String] = (cur - 1)
                                        .clamp(0, double.infinity);
                                  }
                                }),
                        ),
                        InkWell(
                          onTap: !canReturn
                              ? null
                              : () async {
                                  final v = await _promptReturnQty(
                                    context,
                                    name: '${it['product_name']}',
                                    max: maxReturnable,
                                    current: _returnQty[it['id']] ?? 0,
                                  );
                                  if (v != null && mounted) {
                                    setState(
                                      () => _returnQty[it['id'] as String] = v,
                                    );
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Text(
                              qty(_returnQty[it['id']] ?? 0),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: !canReturn
                              ? null
                              : () => setState(() {
                                  final cur = _returnQty[it['id']] ?? 0;
                                  if (cur < maxReturnable) {
                                    _returnQty[it['id'] as String] = (cur + 1)
                                        .clamp(0, maxReturnable);
                                  }
                                }),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SectionLabel('Refund'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _refund,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Refund now ₹',
                    hintText: _total.toStringAsFixed(2),
                  ),
                  onChanged: (_) => setState(() => _refundTouched = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _refundMode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                    DropdownMenuItem(
                      value: 'credit',
                      child: Text('Adjust in due'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _refundMode = v ?? 'cash'),
                ),
              ),
            ],
          ),
          if (_total - _refundAmount > 0.005 &&
              widget.invoice['customer_id'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${money(_total - _refundAmount)} will be adjusted against the customer\'s due.',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Reason / note (optional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _total <= 0 ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Record return • ${money(_total)}'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ================= PURCHASE RETURNS (PRD 7.12) =================

class PurchaseReturnFilter {
  const PurchaseReturnFilter({this.search = '', this.from, this.to});

  final String search;
  final DateTime? from;
  final DateTime? to;

  PurchaseReturnFilter copyWith({
    String? search,
    Object? from = _s,
    Object? to = _s,
  }) => PurchaseReturnFilter(
    search: search ?? this.search,
    from: from == _s ? this.from : from as DateTime?,
    to: to == _s ? this.to : to as DateTime?,
  );

  static const _s = Object();
}

final purchaseReturnFilterProvider =
    NotifierProvider<PurchaseReturnFilterNotifier, PurchaseReturnFilter>(
      PurchaseReturnFilterNotifier.new,
    );

class PurchaseReturnFilterNotifier extends Notifier<PurchaseReturnFilter> {
  @override
  PurchaseReturnFilter build() => const PurchaseReturnFilter();
  void set(PurchaseReturnFilter f) => state = f;
}

final purchaseReturnsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final filter = ref.watch(purchaseReturnFilterProvider);

      var query = client
          .from('purchase_returns')
          .select('*, purchases(purchase_no), suppliers(name)');
      if (filter.from != null) {
        query = query.gte('return_date', ymd(filter.from!));
      }
      if (filter.to != null) {
        query = query.lte('return_date', ymd(filter.to!));
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('return_date', ascending: false).limit(200),
      );

      if (filter.search.trim().isEmpty) return rows.take(100).toList();
      final q = filter.search.trim().toLowerCase();
      return rows
          .where(
            (r) =>
                (r['return_no'] as String? ?? '').toLowerCase().contains(q) ||
                ((r['purchases'] as Map?)?['purchase_no'] as String? ?? '')
                    .toLowerCase()
                    .contains(q) ||
                ((r['suppliers'] as Map?)?['name'] as String? ?? '')
                    .toLowerCase()
                    .contains(q),
          )
          .take(100)
          .toList();
    });

/// Purchase return + its line items (PRD 7.12).
final purchaseReturnDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final client = ref.watch(supabaseProvider);
      final row = await client
          .from('purchase_returns')
          .select(
            '*, purchases(purchase_no), suppliers(name), purchase_return_items(*)',
          )
          .eq('id', id)
          .single();
      return Map<String, dynamic>.from(row);
    });

class PurchaseReturnsScreen extends ConsumerWidget {
  const PurchaseReturnsScreen({super.key});

  Future<void> _newReturn(BuildContext context, WidgetRef ref) async {
    final search = TextEditingController();
    final purchase = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _PurchasePicker(searchController: search),
      ),
    );
    if (purchase == null || !context.mounted) return;
    await context.push('/purchases/${purchase['id']}/return', extra: purchase);
  }

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    PurchaseReturnFilter filter,
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
          .read(purchaseReturnFilterProvider.notifier)
          .set(filter.copyWith(from: picked.start, to: picked.end));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(purchaseReturnsProvider);
    final filter = ref.watch(purchaseReturnFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Purchase returns'),
        actions: [
          const GuideButton('purchase_returns'),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Filter by date',
            onPressed: () => _pickRange(context, ref, filter),
          ),
        ],
      ),
      floatingActionButton: CoachTarget(
        page: 'purchase_returns',
        id: 'add',
        child: FloatingActionButton.extended(
          onPressed: () => _newReturn(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New return'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchField(
              hint: 'Search return no, purchase no, supplier',
              onChanged: (v) => ref
                  .read(purchaseReturnFilterProvider.notifier)
                  .set(filter.copyWith(search: v)),
            ),
          ),
          if (filter.from != null && filter.to != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    '${dateStr(filter.from)} → ${dateStr(filter.to)}',
                  ),
                  onPressed: () => _pickRange(context, ref, filter),
                  onDeleted: () => ref
                      .read(purchaseReturnFilterProvider.notifier)
                      .set(filter.copyWith(from: null, to: null)),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(purchaseReturnsProvider),
              child: AsyncView(
                value: returns,
                onRetry: () => ref.invalidate(purchaseReturnsProvider),
                builder: (rows) => rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.assignment_return_outlined,
                        message: 'No purchase returns found',
                      )
                    : isDesktop
                    ? DesktopTable<Map<String, dynamic>>(
                        rows: rows,
                        trailingWidth: 90,
                        columns: [
                          DesktopTableColumn(
                            label: 'Return #',
                            flex: 2,
                            comparable: (r) => r['return_no'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Against purchase',
                            flex: 2,
                            comparable: (r) =>
                                (r['purchases'] as Map?)?['purchase_no']
                                    as String? ??
                                '',
                          ),
                          DesktopTableColumn(
                            label: 'Supplier',
                            flex: 2,
                            comparable: (r) =>
                                ((r['suppliers'] as Map?)?['name'] as String? ??
                                        '')
                                    .toLowerCase(),
                          ),
                          DesktopTableColumn(
                            label: 'Date',
                            flex: 2,
                            comparable: (r) =>
                                r['return_date'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: 'Amount',
                            flex: 2,
                            alignEnd: true,
                            comparable: (r) => toDouble(r['total']),
                          ),
                        ],
                        rowBuilder: (context, r) =>
                            _PurchaseReturnRow(purchaseReturn: r),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _PurchaseReturnTile(purchaseReturn: rows[i]),
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

class _PurchaseReturnRow extends StatelessWidget {
  const _PurchaseReturnRow({required this.purchaseReturn});

  final Map<String, dynamic> purchaseReturn;

  @override
  Widget build(BuildContext context) {
    final r = purchaseReturn;
    return InkWell(
      onTap: () => context.push('/purchase-returns/${r['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                r['return_no'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (r['purchases'] as Map?)?['purchase_no'] as String? ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (r['suppliers'] as Map?)?['name'] as String? ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateStr(r['return_date']),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                money(r['total'] as num?),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.inkSoft,
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

class _PurchaseReturnTile extends StatelessWidget {
  const _PurchaseReturnTile({required this.purchaseReturn});

  final Map<String, dynamic> purchaseReturn;

  @override
  Widget build(BuildContext context) {
    final r = purchaseReturn;
    // Built manually instead of ListTile (its trailing
    // slot enforces a fixed max height independent of
    // contentPadding, which this 2-line trailing column
    // can overflow under some font metrics).
    return Card(
      child: InkWell(
        onTap: () => context.push('/purchase-returns/${r['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const IconChip(
                Icons.assignment_return_outlined,
                color: AppColors.orange,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['return_no'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Against ${(r['purchases'] as Map?)?['purchase_no'] ?? '—'}'
                      '${(r['suppliers'] as Map?)?['name'] != null ? ' • ${(r['suppliers'] as Map)['name']}' : ''}'
                      ' • ${dateStr(r['return_date'])}',
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
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
                    money(r['total'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Purchase return detail: which products were returned, quantities and amounts.
class PurchaseReturnDetailScreen extends ConsumerWidget {
  const PurchaseReturnDetailScreen({super.key, required this.returnId});

  final String returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(purchaseReturnDetailProvider(returnId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Purchase return'),
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(purchaseReturnDetailProvider(returnId)),
        builder: (r) {
          final items = List<Map<String, dynamic>>.from(
            r['purchase_return_items'] as List? ?? [],
          );
          final purchaseNo =
              (r['purchases'] as Map?)?['purchase_no'] as String?;
          final supplierName = (r['suppliers'] as Map?)?['name'] as String?;

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(purchaseReturnDetailProvider(returnId)),
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
                            Expanded(
                              child: Text(
                                r['return_no'] as String,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              money(r['total'] as num?),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr(r['return_date']),
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 12.5,
                          ),
                        ),
                        if (purchaseNo != null) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () =>
                                context.push('/purchases/${r['purchase_id']}'),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 16,
                                  color: AppColors.teal,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Against purchase $purchaseNo',
                                  style: const TextStyle(
                                    color: AppColors.teal,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (supplierName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            supplierName,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SectionLabel('Returned products'),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const IconChip(
                            Icons.inventory_2_outlined,
                            color: AppColors.orange,
                            size: 40,
                          ),
                          title: Text(
                            items[i]['product_name'] as String? ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            'Qty ${qty(items[i]['quantity'] as num?)} × ${money(items[i]['unit_price'] as num?)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          trailing: Text(
                            money(items[i]['line_total'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SectionLabel('Settlement'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Received now'),
                            Text(
                              money(r['received_amount'] as num?),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (toDouble(r['total']) -
                                toDouble(r['received_amount']) >
                            0.005) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Adjusted against supplier due'),
                              Text(
                                money(
                                  toDouble(r['total']) -
                                      toDouble(r['received_amount']),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.purple,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if ((r['notes'] as String? ?? '').isNotEmpty) ...[
                  const SectionLabel('Note'),
                  Text(r['notes'] as String),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bottom sheet to pick a purchase to return items from (any purchase, not just
/// the one currently open) — fetches full purchase_items before returning.
class _PurchasePicker extends ConsumerStatefulWidget {
  const _PurchasePicker({required this.searchController});
  final TextEditingController searchController;

  @override
  ConsumerState<_PurchasePicker> createState() => _PurchasePickerState();
}

class _PurchasePickerState extends ConsumerState<_PurchasePicker> {
  List<Map<String, dynamic>> _purchases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String search) async {
    try {
      final client = ref.read(supabaseProvider);
      var query = client
          .from('purchases')
          .select(
            'id, purchase_no, bill_no, supplier_name, purchase_date, total',
          );
      if (search.isNotEmpty) {
        query = query.or(
          'purchase_no.ilike.%$search%,bill_no.ilike.%$search%,supplier_name.ilike.%$search%',
        );
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('purchase_date', ascending: false).limit(50),
      );
      if (mounted) {
        setState(() {
          _purchases = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _select(Map<String, dynamic> purchase) async {
    setState(() => _loading = true);
    try {
      final full = await ref
          .read(supabaseProvider)
          .from('purchases')
          .select(
            '*, purchase_items(*, products(current_stock), product_variants(current_stock))',
          )
          .eq('id', purchase['id'] as String)
          .single();
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(full));
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              controller: widget.searchController,
              hint: 'Search purchase no, bill no, supplier',
              autofocus: true,
              onChanged: _load,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _purchases.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    message: 'No purchases found',
                  )
                : ListView.separated(
                    controller: scrollController,
                    itemCount: _purchases.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final p = _purchases[i];
                      return ListTile(
                        title: Text(
                          '${p['purchase_no']} • ${money(p['total'] as num?)}',
                        ),
                        subtitle: Text(
                          '${(p['supplier_name'] as String?)?.isNotEmpty == true ? p['supplier_name'] : 'No supplier'}'
                          ' • ${dateStr(p['purchase_date'])}',
                        ),
                        onTap: () => _select(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class PurchaseReturnFormScreen extends ConsumerStatefulWidget {
  const PurchaseReturnFormScreen({super.key, required this.purchase});

  final Map<String, dynamic> purchase;

  @override
  ConsumerState<PurchaseReturnFormScreen> createState() =>
      _PurchaseReturnFormScreenState();
}

class _PurchaseReturnFormScreenState
    extends ConsumerState<PurchaseReturnFormScreen> {
  late final List<Map<String, dynamic>> _items =
      List<Map<String, dynamic>>.from(
        widget.purchase['purchase_items'] as List? ?? [],
      );
  late final Map<String, double> _returnQty = {
    for (final it in _items) it['id'] as String: 0,
  };
  final _received = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  bool _receivedTouched = false;

  /// Already-returned quantity per product/variant on this purchase (from
  /// earlier purchase returns) — same purpose as the sale-return form's
  /// equivalent map: the server hard-blocks over-returning, this just keeps
  /// the UI from letting someone try to return the same purchase twice.
  Map<String, double> _alreadyReturned = {};
  bool _loadingReturned = true;

  @override
  void initState() {
    super.initState();
    _loadAlreadyReturned();
  }

  Future<void> _loadAlreadyReturned() async {
    try {
      final rows = await ref
          .read(supabaseProvider)
          .from('purchase_return_items')
          .select(
            'product_id, variant_id, quantity, purchase_returns!inner(purchase_id)',
          )
          .eq('purchase_returns.purchase_id', widget.purchase['id'] as String);
      final map = <String, double>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final key = '${r['product_id']}:${r['variant_id'] ?? ''}';
        map[key] = (map[key] ?? 0) + toDouble(r['quantity']);
      }
      if (mounted) {
        setState(() {
          _alreadyReturned = map;
          _loadingReturned = false;
        });
      }
    } catch (_) {
      // Best-effort only — the server still hard-blocks over-returning.
      if (mounted) setState(() => _loadingReturned = false);
    }
  }

  double _lineRate(Map<String, dynamic> it) =>
      toDouble(it['unit_price']) * (1 + toDouble(it['gst_rate']) / 100);

  /// Stock actually on hand for this line right now — a return can never
  /// exceed this, regardless of how much was originally purchased, since
  /// some of it may already have been sold.
  double _availableStock(Map<String, dynamic> it) {
    final variant = it['product_variants'] as Map?;
    final product = it['products'] as Map?;
    return toDouble((variant ?? product)?['current_stock']);
  }

  double _maxReturnable(Map<String, dynamic> it) {
    if (_loadingReturned) return 0;
    final key = '${it['product_id']}:${it['variant_id'] ?? ''}';
    final already = _alreadyReturned[key] ?? 0;
    final remaining = toDouble(it['quantity']) - already;
    final flooredRemaining = remaining < 0 ? 0.0 : remaining;
    final available = _availableStock(it);
    return flooredRemaining < available ? flooredRemaining : available;
  }

  double get _total => _items.fold(0.0, (s, it) {
    final q = _returnQty[it['id']] ?? 0;
    return s + q * _lineRate(it);
  });

  double get _receivedAmount =>
      _receivedTouched ? (double.tryParse(_received.text) ?? 0) : 0;

  Future<void> _save() async {
    final returningItems = _items
        .where((it) => (_returnQty[it['id']] ?? 0) > 0)
        .toList();
    if (returningItems.isEmpty) {
      showError(context, 'Enter return quantity for at least one item');
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'purchase_id': widget.purchase['id'],
        'supplier_id': widget.purchase['supplier_id'],
        'received_amount': _receivedAmount,
        'notes': _notes.text.trim(),
        'items': [
          for (final it in returningItems)
            {
              'product_id': it['product_id'],
              'variant_id': it['variant_id'],
              'product_name': it['product_name'],
              'quantity': _returnQty[it['id']],
              'unit_price': _lineRate(it),
              'tax_amount': 0,
              'line_total': double.parse(
                ((_returnQty[it['id']] ?? 0) * _lineRate(it)).toStringAsFixed(
                  2,
                ),
              ),
            },
        ],
      };
      final res =
          await ref
                  .read(supabaseProvider)
                  .rpc('create_purchase_return', params: {'payload': payload})
              as Map<String, dynamic>;
      ref.invalidate(purchasesProvider);
      invalidateStockData(ref);
      ref.invalidate(suppliersProvider);
      ref.invalidate(purchaseReturnsProvider);
      if (mounted) {
        final applied = toDouble(res['applied_to_bill']);
        final received = toDouble(res['received']);
        showSuccess(
          context,
          'Return ${res['return_no']} recorded — ${money(res['total'] as num?)}'
          '${applied > 0 ? ', ${money(applied)} off the purchase' : ''}'
          '${received > 0 ? ', ${money(received)} received back' : ''}',
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text('Return — ${widget.purchase['purchase_no']}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Select items to return to supplier'),
          for (final it in _items)
            Builder(
              builder: (context) {
                final maxReturnable = _maxReturnable(it);
                final available = _availableStock(it);
                final already =
                    _alreadyReturned['${it['product_id']}:${it['variant_id'] ?? ''}'] ??
                    0;
                final fullyReturned =
                    !_loadingReturned && already >= toDouble(it['quantity']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${it['product_name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Bought: ${qty(it['quantity'] as num?)} @ ${money(_lineRate(it))}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                              Text(
                                _loadingReturned
                                    ? 'Checking earlier returns…'
                                    : fullyReturned
                                    ? 'Already fully returned on this purchase'
                                    : maxReturnable <= 0
                                    ? 'None in stock — already sold, can\'t return'
                                    : already > 0
                                    ? '${qty(already)} already returned — in stock: ${qty(available)} returnable'
                                    : 'In stock: ${qty(available)} returnable',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: maxReturnable <= 0
                                      ? AppColors.red
                                      : AppColors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            final cur = _returnQty[it['id']] ?? 0;
                            if (cur > 0) {
                              _returnQty[it['id'] as String] = (cur - 1).clamp(
                                0,
                                double.infinity,
                              );
                            }
                          }),
                        ),
                        InkWell(
                          onTap: maxReturnable <= 0
                              ? null
                              : () async {
                                  final v = await _promptReturnQty(
                                    context,
                                    name: '${it['product_name']}',
                                    max: maxReturnable,
                                    current: _returnQty[it['id']] ?? 0,
                                  );
                                  if (v != null && mounted) {
                                    setState(
                                      () => _returnQty[it['id'] as String] = v,
                                    );
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Text(
                              qty(_returnQty[it['id']] ?? 0),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: maxReturnable <= 0
                              ? null
                              : () => setState(() {
                                  final cur = _returnQty[it['id']] ?? 0;
                                  if (cur < maxReturnable) {
                                    _returnQty[it['id'] as String] = (cur + 1)
                                        .clamp(0, maxReturnable);
                                  }
                                }),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SectionLabel('Settlement'),
          TextField(
            controller: _received,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Refund received now ₹ (rest adjusts supplier due)',
            ),
            onChanged: (_) => setState(() => _receivedTouched = true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Reason / note (optional)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _total <= 0 ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Record return • ${money(_total)}'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
