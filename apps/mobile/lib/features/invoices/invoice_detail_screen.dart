import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../customers/customer_providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../pos/cart.dart';
import 'advance_actions.dart';
import 'invoice_pdf.dart';
import 'invoice_providers.dart';
import 'thermal_printer.dart';
import '../../core/theme.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({
    super.key,
    required this.invoiceId,
    this.justCreated = false,
  });

  final String invoiceId;
  final bool justCreated;

  Future<void> _sharePdf(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invoice, {
    required bool thermal,
  }) async {
    final business = ref.read(appContextProvider).value?.business ?? {};
    final items = List<Map<String, dynamic>>.from(
      invoice['invoice_items'] as List? ?? [],
    );
    final pdf = InvoicePdf(business: business, invoice: invoice, items: items);
    final doc = thermal ? await pdf.buildThermal() : await pdf.buildA4();
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: '${invoice['invoice_no']}.pdf',
    );
  }

  Future<void> _printPdf(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invoice, {
    required bool thermal,
  }) async {
    final business = ref.read(appContextProvider).value?.business ?? {};
    final items = List<Map<String, dynamic>>.from(
      invoice['invoice_items'] as List? ?? [],
    );
    final pdf = InvoicePdf(business: business, invoice: invoice, items: items);
    final doc = thermal ? await pdf.buildThermal() : await pdf.buildA4();
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  /// Place of supply defaults to the customer's state (or the store's); it
  /// only needs changing when goods are delivered to a different state. The
  /// database re-splits the lines into CGST+SGST / IGST (migration 0036).
  Future<void> _changePlaceOfSupply(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invoice,
  ) async {
    var selected = invoice['place_of_supply'] as String? ?? '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Place of supply'),
        content: GstStateField(
          value: selected,
          helperText: 'State where the goods are delivered',
          onChanged: (v) => selected = v,
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
    if (saved != true || selected == invoice['place_of_supply']) return;
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'set_invoice_place_of_supply',
            params: {'p_invoice_id': invoice['id'], 'p_state': selected},
          );
      ref.invalidate(invoiceDetailProvider(invoice['id'] as String));
      if (context.mounted) showSuccess(context, 'Place of supply updated');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invoice,
  ) async {
    final due = toDouble(invoice['due_amount']);
    final amount = TextEditingController(text: due.toStringAsFixed(2));
    String mode = 'cash';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Record payment'),
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Record'),
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
              'p_customer_id': invoice['customer_id'],
              'p_amount': amt,
              'p_mode': mode,
              'p_invoice_id': invoice['id'],
            },
          );
      ref.invalidate(invoiceDetailProvider(invoiceId));
      ref.invalidate(invoicesProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(recentInvoicesProvider);
      if (context.mounted) showSuccess(context, 'Payment recorded');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel invoice?',
      message:
          'Stock will be restored and customer due reversed. Any amount already '
          'paid is kept as the customer\'s advance. This cannot be undone.',
      confirmText: 'Cancel invoice',
    );
    if (!ok) return;
    try {
      await ref
          .read(supabaseProvider)
          .rpc('cancel_invoice', params: {'p_invoice_id': invoiceId});
      ref.invalidate(invoiceDetailProvider(invoiceId));
      ref.invalidate(invoicesProvider);
      invalidateStockData(ref); // cancel restores stock
      ref.invalidate(recentInvoicesProvider);
      if (context.mounted) showSuccess(context, 'Invoice cancelled');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Loads this invoice's items into the cart and opens it for editing —
  /// reuses the whole POS/checkout flow (see `pos_screen.dart` and
  /// `checkout_sheet.dart`'s `editingInvoiceProvider` branches) instead of a
  /// separate editor, so adding/removing/changing items works identically to
  /// building a new bill.
  Future<void> _editBill(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> inv,
  ) async {
    final liveCart = ref.read(cartProvider);
    if (liveCart.lines.isNotEmpty && ref.read(editingInvoiceProvider) == null) {
      final proceed = await confirmDialog(
        context,
        title: 'Replace current bill?',
        message:
            'You have an unsaved bill in progress. Editing this invoice will replace it.',
        confirmText: 'Continue',
      );
      if (!proceed) return;
    }

    Map<String, dynamic>? customer;
    final customerId = inv['customer_id'] as String?;
    if (customerId != null) {
      try {
        customer = Map<String, dynamic>.from(
          await ref
              .read(supabaseProvider)
              .from('customers')
              .select()
              .eq('id', customerId)
              .single(),
        );
      } catch (_) {
        // Deleted/inaccessible customer — fall back to the invoice's own
        // name/phone snapshot so the bill can still be edited.
        customer = {
          'id': customerId,
          'name': inv['customer_name'],
          'phone': inv['customer_phone'],
        };
      }
    }

    final items = List<Map<String, dynamic>>.from(
      inv['invoice_items'] as List? ?? [],
    );
    if (!context.mounted) return;
    ref
        .read(cartProvider.notifier)
        .replaceAll(
          CartState(
            lines: invoiceItemsToCartLines(items),
            customer: customer,
            billDiscount: toDouble(inv['discount_amount']),
          ),
        );
    ref
        .read(editingInvoiceProvider.notifier)
        .set(
          EditingInvoice(
            id: invoiceId,
            invoiceNo: inv['invoice_no'] as String,
            invoiceType: inv['invoice_type'] as String,
            paidAmount: toDouble(inv['paid_amount']),
          ),
        );
    await context.push('/invoices/$invoiceId/edit');
    ref.invalidate(invoiceDetailProvider(invoiceId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(invoiceDetailProvider(invoiceId));
    final features = ref.watch(appContextProvider).value;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(detail.value?['invoice_no'] as String? ?? 'Invoice'),
        actions: [
          if (detail.hasValue &&
              detail.value!['is_cancelled'] != true &&
              (features?.canEditInvoices ?? false))
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _editBill(context, ref, detail.value!);
                if (v == 'cancel') _cancel(context, ref);
              },
              itemBuilder: (_) => [
                // Opening balances can't be edited, only cancelled (0051).
                if (detail.value!['invoice_type'] != 'opening')
                  const PopupMenuItem(value: 'edit', child: Text('Edit bill')),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text(
                    'Cancel invoice',
                    style: TextStyle(color: AppColors.red),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        builder: (inv) {
          final items = List<Map<String, dynamic>>.from(
            inv['invoice_items'] as List? ?? [],
          );
          // Reversed receipts stay in the database for history (0041) but
          // no longer count as paid.
          final payments = [
            for (final p in List<Map<String, dynamic>>.from(
              inv['invoice_payments'] as List? ?? [],
            ))
              if (p['reversed'] != true) p,
          ];
          final advance = toDouble(
            (inv['customers'] as Map?)?['advance_amount'],
          );
          final cancelled = inv['is_cancelled'] == true;
          final due = toDouble(inv['due_amount']);
          final isGst = inv['invoice_type'] == 'gst';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (cancelled)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.redSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel, color: AppColors.red),
                      SizedBox(width: 8),
                      Text(
                        'This invoice is cancelled',
                        style: TextStyle(color: AppColors.red),
                      ),
                    ],
                  ),
                ),
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
                            inv['invoice_no'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          StatusChip(
                            cancelled
                                ? 'cancelled'
                                : inv['payment_status'] as String,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateTimeStr(inv['invoice_date']),
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${_typeLabel(inv['invoice_type'] as String)} • ${inv['payment_mode']}',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 13,
                        ),
                      ),
                      // PD19/PD20: when the unpaid amount is due.
                      if (due > 0 && inv['due_date'] != null && !cancelled)
                        Builder(
                          builder: (context) {
                            final dueDate = DateTime.tryParse(
                              '${inv['due_date']}',
                            );
                            final late =
                                dueDate != null &&
                                dueDate.isBefore(
                                  DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                );
                            return Text(
                              '${late ? 'Overdue since' : 'Due by'} ${dateStr(inv['due_date'])}',
                              style: TextStyle(
                                color: late ? AppColors.red : AppColors.inkSoft,
                                fontSize: 13,
                                fontWeight: late
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            );
                          },
                        ),
                      // Migration 0044: how a rule exception on this sale was cleared.
                      if ((inv['exception_status'] as String? ?? '').isNotEmpty)
                        Text(
                          switch (inv['exception_status']) {
                            'approved' => 'Approved by the owner',
                            'acknowledged' => 'Owner acknowledged the warnings',
                            'flagged' =>
                              'Billed offline — flagged for owner review',
                            _ => '${inv['exception_status']}',
                          },
                          style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (isGst)
                        InkWell(
                          onTap: cancelled
                              ? null
                              : () => _changePlaceOfSupply(context, ref, inv),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Place of supply: '
                              '${gstStateLabel(inv['place_of_supply'] as String?).isEmpty ? 'not set' : gstStateLabel(inv['place_of_supply'] as String?)}'
                              '${cancelled ? '' : '  ✎'}',
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      if ((inv['customer_name'] as String? ?? '')
                          .isNotEmpty) ...[
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              '${inv['customer_name']}'
                              '${(inv['customer_phone'] as String? ?? '').isNotEmpty ? ' • ${inv['customer_phone']}' : ''}',
                            ),
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
                        title: Text(
                          '${it['product_name']}'
                          '${(it['variant_name'] as String? ?? '').isNotEmpty ? ' (${it['variant_name']})' : ''}',
                        ),
                        subtitle: Text(
                          '${qtyUnit(it['quantity'] as num?, it['unit_name'] as String?)} × '
                          '${money(toDouble(it['unit_price']) * (isGst ? 1 + toDouble(it['gst_rate']) / 100 : 1))}'
                          '${(it['serial_no'] as String? ?? '').isNotEmpty ? '\nS/N: ${it['serial_no']}' : ''}',
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
                          _row(
                            'Subtotal',
                            money(
                              toDouble(inv['subtotal']) +
                                  toDouble(inv['tax_amount']),
                            ),
                          ),
                          if (toDouble(inv['discount_amount']) > 0)
                            _row(
                              'Discount',
                              '- ${money(inv['discount_amount'] as num?)}',
                            ),
                          if (isGst && toDouble(inv['tax_amount']) > 0)
                            for (final (label, amount) in gstBreakupRows(items))
                              _row('Included $label', money(amount), dim: true),
                          if (toDouble(inv['round_off']) != 0)
                            _row(
                              'Round off',
                              money(inv['round_off'] as num?),
                              dim: true,
                            ),
                          const Divider(),
                          _row(
                            'Total',
                            money(inv['total'] as num?),
                            bold: true,
                          ),
                          _row('Paid', money(inv['paid_amount'] as num?)),
                          // Return credit settles the bill's balance first
                          // (migration 0038, spec D27).
                          if (toDouble(inv['credit_amount']) > 0)
                            _row(
                              'Returns credit',
                              money(inv['credit_amount'] as num?),
                            ),
                          if (due > 0)
                            _row(
                              'Due',
                              money(due),
                              bold: true,
                              color: AppColors.red,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (payments.length > 1) ...[
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Payment history',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      for (final p in payments)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.payments_outlined,
                            size: 20,
                          ),
                          title: Text(money(p['amount'] as num?)),
                          subtitle: Text(
                            '${p['is_advance'] == true ? 'advance' : p['payment_mode']}'
                            ' • ${dateTimeStr(p['payment_date'])}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (!cancelled) ...[
                if (due > 0 &&
                    inv['customer_id'] != null &&
                    inv['invoice_type'] != 'estimate' &&
                    (features?.canRecordPayments ?? false))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      onPressed: () => _recordPayment(context, ref, inv),
                      icon: const Icon(Icons.payments),
                      label: Text('Record payment (due ${money(due)})'),
                    ),
                  ),
                // PD22: an advance is used only when the shop chooses to.
                if (due > 0 &&
                    advance > 0 &&
                    inv['invoice_type'] != 'estimate' &&
                    (features?.canRecordPayments ?? false))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => applyAdvanceToInvoice(
                        context,
                        ref,
                        invoiceId: invoiceId,
                        amount: advance < due ? advance : due,
                        customerName: inv['customer_name'] as String?,
                      ),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(
                        'Use advance ${money(advance < due ? advance : due)} '
                        '(of ${money(advance)})',
                      ),
                    ),
                  ),
                Row(
                  children: [
                    if (features?.featureOn('pdf_invoice') ?? true)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _sharePdf(context, ref, inv, thermal: false),
                          icon: const Icon(Icons.share),
                          label: const Text('Share PDF'),
                        ),
                      ),
                    if (features?.featureOn('a4_print') ?? true) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _printPdf(context, ref, inv, thermal: false),
                          icon: const Icon(Icons.print),
                          label: const Text('A4 print'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (features?.featureOn('thermal_print') ?? true) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => isDesktopPlatform
                              ? _printPdf(context, ref, inv, thermal: true)
                              : ThermalPrinterService.printInvoice(
                                  context,
                                  business:
                                      ref
                                          .read(appContextProvider)
                                          .value
                                          ?.business ??
                                      {},
                                  invoice: inv,
                                  items: items,
                                ),
                          icon: const Icon(Icons.receipt),
                          label: const Text('Thermal print'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _sharePdf(context, ref, inv, thermal: true),
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Receipt PDF'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
    'gst' => 'GST Invoice',
    'non_gst' => 'Invoice',
    'cash_memo' => 'Cash Memo',
    'estimate' => 'Estimate',
    'opening' => 'Opening balance',
    _ => type,
  };

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    bool dim = false,
    Color? color,
  }) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
      color: color ?? (dim ? AppColors.inkSoft : null),
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
