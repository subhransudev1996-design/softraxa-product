import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import '../pos/pos_providers.dart';
import '../products/product_providers.dart';
import '../services/service_providers.dart';
import 'job_card_providers.dart';

/// Job card detail: status timeline, spare parts / labor lines, advance,
/// and closing the job into a final product+service invoice (PRD Phase 2
/// §8-14).
class JobCardDetailScreen extends ConsumerWidget {
  const JobCardDetailScreen({super.key, required this.jobId});

  final String jobId;

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, String current) async {
    var selected = current;
    final note = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Update status'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in jobStatuses)
                  ChoiceChip(
                    label: Text(jobStatusLabel(s)),
                    selected: selected == s,
                    onSelected: (_) => setState(() => selected = s),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      ),
    );
    if (result != true) return;
    try {
      await ref.read(supabaseProvider).rpc('update_job_status', params: {
        'p_job_id': jobId,
        'p_status': selected,
        'p_note': note.text.trim(),
      });
      ref.invalidate(jobCardDetailProvider(jobId));
      ref.invalidate(jobCardsProvider);
      if (context.mounted) showSuccess(context, 'Status updated');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _addPart(BuildContext context, WidgetRef ref) async {
    final search = TextEditingController();
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _PartPicker(searchController: search),
      ),
    );
    if (selected == null || !context.mounted) return;
    final product = selected['product'] as Map<String, dynamic>;
    final variant = selected['variant'] as Map<String, dynamic>?;

    final qtyC = TextEditingController(text: '1');
    final priceC = TextEditingController(
        text: toDouble(variant?['selling_price'] ?? product['selling_price']).toStringAsFixed(2));
    final gstC = TextEditingController(text: toDouble(product['gst_rate']).toStringAsFixed(0));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${product['name']}${variant != null ? ' — ${variant['name']}' : ''}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: qtyC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity')),
          const SizedBox(height: 12),
          TextField(
              controller: priceC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price ₹ (per unit, excl. GST)')),
          const SizedBox(height: 12),
          TextField(
              controller: gstC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'GST %')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    try {
      await ref.read(supabaseProvider).rpc('add_job_card_item', params: {
        'payload': {
          'job_card_id': jobId,
          'item_type': 'part',
          'product_id': product['id'],
          'variant_id': variant?['id'],
          'name': '${product['name']}${variant != null ? ' (${variant['name']})' : ''}',
          'hsn_code': product['hsn_code'] ?? '',
          'quantity': double.tryParse(qtyC.text) ?? 1,
          'unit_price': double.tryParse(priceC.text) ?? 0,
          'cost_price': variant?['purchase_price'] ?? product['purchase_price'] ?? 0,
          'gst_rate': double.tryParse(gstC.text) ?? 0,
        },
      });
      ref.invalidate(jobCardDetailProvider(jobId));
      ref.invalidate(productsProvider);
      if (context.mounted) showSuccess(context, 'Part added — stock deducted');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _addLabor(BuildContext context, WidgetRef ref) async {
    List<Map<String, dynamic>> services;
    try {
      services = await ref.read(servicesProvider.future);
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    if (!context.mounted) return;
    Map<String, dynamic>? service;
    final name = TextEditingController();
    final price = TextEditingController();
    final gst = TextEditingController(text: '18');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add labor / service charge'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (services.isNotEmpty)
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: service,
                  decoration: const InputDecoration(labelText: 'From service catalog (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Type manually')),
                    for (final s in services)
                      DropdownMenuItem(value: s, child: Text(s['name'] as String)),
                  ],
                  onChanged: (v) => setState(() {
                    service = v;
                    if (v != null) {
                      name.text = v['name'] as String;
                      price.text = toDouble(v['price']).toStringAsFixed(2);
                      gst.text = toDouble(v['gst_rate']).toStringAsFixed(0);
                    }
                  }),
                ),
              const SizedBox(height: 12),
              TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Charge name *')),
              const SizedBox(height: 12),
              TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Price ₹ (excl. GST)')),
              const SizedBox(height: 12),
              TextField(
                  controller: gst,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'GST %')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (saved != true || name.text.trim().isEmpty || !context.mounted) return;
    try {
      await ref.read(supabaseProvider).rpc('add_job_card_item', params: {
        'payload': {
          'job_card_id': jobId,
          'item_type': 'labor',
          'service_id': service?['id'],
          'name': name.text.trim(),
          'quantity': 1,
          'unit_price': double.tryParse(price.text) ?? 0,
          'gst_rate': double.tryParse(gst.text) ?? 0,
        },
      });
      ref.invalidate(jobCardDetailProvider(jobId));
      if (context.mounted) showSuccess(context, 'Charge added');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _removeItem(BuildContext context, WidgetRef ref, Map<String, dynamic> item) async {
    final ok = await confirmDialog(context,
        title: 'Remove "${item['name']}"?',
        message: item['item_type'] == 'part'
            ? 'This will add the quantity back to stock.'
            : 'This charge will be removed from the bill.',
        confirmText: 'Remove');
    if (!ok) return;
    try {
      await ref
          .read(supabaseProvider)
          .rpc('remove_job_card_item', params: {'p_item_id': item['id']});
      ref.invalidate(jobCardDetailProvider(jobId));
      ref.invalidate(productsProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _close(BuildContext context, WidgetRef ref, Map<String, dynamic> job,
      double total, double advance) async {
    final remaining = (total - advance).clamp(0, double.infinity);
    final paid = TextEditingController(text: remaining.toStringAsFixed(2));
    final warranty = TextEditingController(text: job['warranty_days']?.toString() ?? '');
    String mode = 'cash';
    String invoiceType = ref.read(appContextProvider).value?.gstEnabled ?? true ? 'gst' : 'non_gst';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Close job & generate invoice'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Total: ${money(total)}  •  Advance already collected: ${money(advance)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gst', label: Text('GST')),
                  ButtonSegment(value: 'non_gst', label: Text('Non-GST')),
                ],
                selected: {invoiceType},
                onSelectionChanged: (s) => setState(() => invoiceType = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: paid,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Collect now ₹ (balance due)'),
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
                controller: warranty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Warranty (days, optional)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate invoice')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      final res = await ref.read(supabaseProvider).rpc('close_job_card', params: {
        'p_job_id': jobId,
        'payload': {
          'paid_amount': double.tryParse(paid.text) ?? 0,
          'payment_mode': mode,
          'invoice_type': invoiceType,
          'warranty_days': int.tryParse(warranty.text),
        },
      }) as Map<String, dynamic>;
      ref.invalidate(jobCardDetailProvider(jobId));
      ref.invalidate(jobCardsProvider);
      if (context.mounted) {
        showSuccess(context, 'Invoice ${res['invoice_no']} generated');
        context.push('/invoices/${res['invoice_id']}?new=1');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(jobCardDetailProvider(jobId));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Job card')),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(jobCardDetailProvider(jobId)),
        builder: (j) {
          final items = List<Map<String, dynamic>>.from(j['job_card_items'] as List? ?? []);
          final history = List<Map<String, dynamic>>.from(j['job_status_history'] as List? ?? [])
            ..sort((a, b) => DateTime.parse(b['created_at'].toString())
                .compareTo(DateTime.parse(a['created_at'].toString())));
          final status = j['status'] as String? ?? 'received';
          final subtotal = items.fold<double>(0, (s, it) => s + toDouble(it['quantity']) * toDouble(it['unit_price']));
          final tax = items.fold<double>(0, (s, it) => s + (toDouble(it['line_total']) - toDouble(it['quantity']) * toDouble(it['unit_price'])));
          final total = subtotal + tax;
          final advance = toDouble(j['advance_amount']);
          final closed = j['invoice_id'] != null;
          final invoiceNo = (j['invoices'] as Map?)?['invoice_no'] as String?;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(jobCardDetailProvider(jobId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(j['job_no'] as String,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                        StatusChip(jobStatusLabel(status),
                            color: jobStatusColors[status] ?? AppColors.inkSoft),
                      ]),
                      const SizedBox(height: 4),
                      Text(dateStr(j['created_at']),
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                      const Divider(height: 20),
                      Text(
                          '${(j['item_name'] as String? ?? '').isNotEmpty ? j['item_name'] : 'Item'}'
                          '${(j['brand'] as String? ?? '').isNotEmpty ? ' • ${j['brand']}' : ''}'
                          '${(j['model'] as String? ?? '').isNotEmpty ? ' ${j['model']}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      if ((j['serial_no'] as String? ?? '').isNotEmpty)
                        Text('IMEI/Serial: ${j['serial_no']}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                      if ((j['issue_description'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(j['issue_description'] as String, style: const TextStyle(fontSize: 13)),
                      ],
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.person_outline, size: 16, color: AppColors.inkSoft),
                        const SizedBox(width: 6),
                        Text(
                            (j['customer_name'] as String?)?.isNotEmpty == true
                                ? j['customer_name'] as String
                                : 'Walk-in customer',
                            style: const TextStyle(fontSize: 13)),
                      ]),
                      if ((j['technician_name'] as String? ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.engineering_outlined, size: 16, color: AppColors.inkSoft),
                          const SizedBox(width: 6),
                          Text(j['technician_name'] as String, style: const TextStyle(fontSize: 13)),
                        ]),
                      ],
                      if (j['expected_delivery'] != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.event_outlined, size: 16, color: AppColors.inkSoft),
                          const SizedBox(width: 6),
                          Text('Expected: ${dateStr(j['expected_delivery'])}',
                              style: const TextStyle(fontSize: 13)),
                        ]),
                      ],
                      if (invoiceNo != null) ...[
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => context.push('/invoices/${j['invoice_id']}'),
                          child: Row(children: [
                            const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.indigo),
                            const SizedBox(width: 6),
                            Text('Invoice $invoiceNo',
                                style: const TextStyle(
                                    color: AppColors.indigo, fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                        ),
                      ],
                      if (j['warranty_end'] != null) ...[
                        const SizedBox(height: 4),
                        Text('Warranty until ${dateStr(j['warranty_end'])}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.green, fontWeight: FontWeight.w600)),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _changeStatus(context, ref, status),
                  icon: const Icon(Icons.sync_alt),
                  label: Text('Status: ${jobStatusLabel(status)}'),
                ),
                const SectionLabel('Parts & labor'),
                if (items.isEmpty)
                  const EmptyState(icon: Icons.build_outlined, message: 'No parts or labor added yet')
                else
                  Card(
                    child: Column(children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: IconChip(
                              items[i]['item_type'] == 'part'
                                  ? Icons.inventory_2_outlined
                                  : Icons.build_outlined,
                              color: items[i]['item_type'] == 'part' ? AppColors.teal : AppColors.indigo,
                              size: 40),
                          title: Text(items[i]['name'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text(
                              'Qty ${qty(items[i]['quantity'] as num?)} × ${money(items[i]['unit_price'] as num?)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(money(items[i]['line_total'] as num?),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            if (!closed)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 18),
                                onPressed: () => _removeItem(context, ref, items[i]),
                                visualDensity: VisualDensity.compact,
                              ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                if (!closed) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addPart(context, ref),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Add part'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addLabor(context, ref),
                        icon: const Icon(Icons.build_outlined),
                        label: const Text('Add labor'),
                      ),
                    ),
                  ]),
                ],
                const SectionLabel('Billing'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      _row('Subtotal', money(subtotal)),
                      if (tax > 0) _row('GST', money(tax)),
                      _row('Total', money(total), bold: true),
                      if (advance > 0) _row('Advance collected', '- ${money(advance)}', color: AppColors.green),
                      const Divider(),
                      _row('Balance', money((total - advance).clamp(0, double.infinity)), bold: true),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                if (!closed)
                  FilledButton.icon(
                    onPressed: items.isEmpty ? null : () => _close(context, ref, j, total, advance),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Close job & generate invoice'),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('This job has been closed and billed.',
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
                  ),
                const SectionLabel('Status history'),
                Card(
                  child: Column(children: [
                    for (var i = 0; i < history.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.circle,
                            size: 10, color: jobStatusColors[history[i]['status']] ?? AppColors.inkSoft),
                        title: Text(jobStatusLabel(history[i]['status'] as String)),
                        subtitle: Text(
                            '${dateTimeStr(history[i]['created_at'])}'
                            '${(history[i]['note'] as String? ?? '').isNotEmpty ? '\n${history[i]['note']}' : ''}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 16 : 14, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ]),
    );
  }
}

/// Bottom sheet to pick a product (+ variant) to add as a job card part.
class _PartPicker extends ConsumerStatefulWidget {
  const _PartPicker({required this.searchController});
  final TextEditingController searchController;

  @override
  ConsumerState<_PartPicker> createState() => _PartPickerState();
}

class _PartPickerState extends ConsumerState<_PartPicker> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String search) async {
    try {
      final client = ref.read(supabaseProvider);
      var query = client.from('products').select(posProductColumns).eq('is_active', true);
      if (search.isNotEmpty) {
        query = query.or('name.ilike.%$search%,sku.ilike.%$search%,barcode.ilike.%$search%');
      }
      final rows = List<Map<String, dynamic>>.from(await query.order('name').limit(100));
      if (mounted) setState(() { _products = rows; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _select(Map<String, dynamic> product) async {
    final variants = List<Map<String, dynamic>>.from(product['product_variants'] as List? ?? [])
      ..removeWhere((v) => v['is_active'] == false);
    if (product['has_variants'] == true && variants.isNotEmpty) {
      final variant = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final v in variants)
              ListTile(title: Text(v['name'] as String), onTap: () => Navigator.pop(ctx, v)),
          ]),
        ),
      );
      if (variant == null || !mounted) return;
      Navigator.pop(context, {'product': product, 'variant': variant});
    } else {
      Navigator.pop(context, {'product': product, 'variant': null});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (ctx, scrollController) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchField(
            controller: widget.searchController,
            hint: 'Search product to use as spare part',
            autofocus: true,
            onChanged: _load,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  controller: scrollController,
                  itemCount: _products.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final p = _products[i];
                    return ListTile(
                      title: Text(p['name'] as String),
                      subtitle: Text(
                          'Stock: ${qty(toDouble(p['current_stock']))} • ${money(p['selling_price'] as num?)}'),
                      onTap: () => _select(p),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
