import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../customers/customer_picker.dart';
import '../dashboard/dashboard_screen.dart';
import '../../core/approvals.dart';
import '../approvals/approval_dialogs.dart';
import '../approvals/approvals_screen.dart';
import '../customers/customer_providers.dart';
import '../invoices/advance_actions.dart';
import '../returns/exchange.dart';
import '../invoices/invoice_providers.dart';
import '../offline/offline_service.dart';
import 'billing_service.dart';
import 'cart.dart';
import 'pos_providers.dart';
import '../../core/theme.dart';

Future<void> showCheckoutSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // Root navigator: over the bottom bar, not under it. Safe area: the
    // sheet stops below the status bar.
    useRootNavigator: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const _CheckoutSheet(),
    ),
  );
}

class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet();

  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _SplitEntry {
  _SplitEntry({this.mode = 'cash', String amount = ''})
    : amount = TextEditingController(text: amount);
  String mode;
  final TextEditingController amount;
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  final _discount = TextEditingController();
  bool _discountIsPercent = false;
  final _paid = TextEditingController();
  final _notes = TextEditingController();
  String _paymentMode = 'cash';
  late String _docType; // gst | non_gst | cash_memo | estimate
  bool _busy = false;
  bool _paidTouched = false;
  bool _splitMode = false;
  final List<_SplitEntry> _splits = [];

  // Exchange mode (D29): credit left over after the replacement is kept as
  // advance or refunded (walk-in customers: always refunded, PD28).
  String _excess = 'advance';
  String _refundMode = 'cash';

  ExchangeDraft? get _exchange => ref.read(exchangeDraftProvider);

  /// What the customer pays for this bill: the total, less the exchange
  /// credit in exchange mode.
  double _payable(CartState cart) {
    final ex = _exchange;
    if (ex == null) return cart.total;
    final rest = cart.total - ex.credit;
    return rest > 0 ? rest : 0;
  }

  @override
  void initState() {
    super.initState();
    final editing = ref.read(editingInvoiceProvider);
    if (editing != null) {
      _docType = editing.invoiceType;
    } else {
      final appContext = ref.read(appContextProvider).value;
      _docType = (appContext?.gstEnabled ?? true) ? 'gst' : 'non_gst';
    }
    final cart = ref.read(cartProvider);
    _discount.text = cart.billDiscount == 0
        ? ''
        : cart.billDiscount.toStringAsFixed(2);
    _discountIsPercent = cart.billDiscountIsPercent;
  }

  List<(String mode, double amount)> get _splitEntries => [
    for (final s in _splits) (s.mode, double.tryParse(s.amount.text) ?? 0),
  ];

  /// Amount actually collected so far, whichever payment UI is active. A
  /// split row marked "Credit (Due)" isn't real money received — it's the
  /// same as leaving that portion uncovered — so it's excluded here and
  /// simply flows into `due` (cart.total - paid) like any other shortfall.
  double _computePaid(CartState cart) {
    final payable = _payable(cart);
    if (_splitMode) {
      final collected = resolveSplitPayments(_splitEntries).collected;
      return collected > payable ? payable : collected;
    }
    return _paidTouched
        ? (double.tryParse(_paid.text) ?? 0)
        : (_paymentMode == 'credit' ? 0.0 : payable);
  }

  void _toggleSplit(double total) {
    setState(() {
      if (_splitMode) {
        _splitMode = false;
        _splits.clear();
      } else {
        _splitMode = true;
        _splits
          ..clear()
          ..add(
            _SplitEntry(
              mode: _paymentMode == 'credit' ? 'cash' : _paymentMode,
              amount: total.toStringAsFixed(2),
            ),
          );
      }
    });
  }

  void _addSplit(double total) {
    final collected = _splits.fold<double>(
      0,
      (s, e) => s + (double.tryParse(e.amount.text) ?? 0),
    );
    final remaining = (total - collected).clamp(0, double.infinity);
    setState(
      () => _splits.add(
        _SplitEntry(
          mode: 'upi',
          amount: remaining > 0 ? remaining.toStringAsFixed(2) : '',
        ),
      ),
    );
  }

  /// [extra] is merged into the create_invoice payload — `owner_ack` when
  /// the owner acknowledged the sale's exceptions (migration 0044).
  Future<void> _createBill({Map<String, dynamic> extra = const {}}) async {
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty) return;

    final missingSerial = cart.lines.any(
      (l) => l.trackSerial && l.serialNo.trim().isEmpty,
    );
    if (missingSerial && _docType != 'estimate') {
      final proceed = await confirmDialog(
        context,
        title: 'Missing IMEI/serial',
        message: 'Some items have no IMEI/serial number. Continue anyway?',
        confirmText: 'Continue',
      );
      if (!proceed) return;
    }
    if (!mounted) return;

    List<Map<String, dynamic>>? splitPayments;
    String paymentModeToSend = _paymentMode;
    if (_splitMode && _docType != 'estimate') {
      final hasAnyEntry = _splitEntries.any((e) => e.$2 > 0);
      if (!hasAnyEntry) {
        showError(context, 'Enter an amount for at least one payment method');
        return;
      }
      // Credit rows aren't real payments — they're excluded from what's
      // sent as `payments` (invoice_payments only records money actually
      // received); the amount still counts toward the bill via `due`
      // (cart.total - paid), same as an ordinary uncovered shortfall.
      final resolved = resolveSplitPayments(_splitEntries);
      splitPayments = [
        for (final e in resolved.realPayments) {'mode': e.$1, 'amount': e.$2},
      ];
      paymentModeToSend = resolved.mode;
    }
    // D15: staff without price permission can't go below the default
    // price at all. Beyond a staff discount limit the sale goes to the
    // owner for approval instead (PD10) — the server says so below.
    if (_docType != 'estimate') {
      final rights = await ref.read(pricingRightsProvider.future);
      final problem = pricingProblem(cart, rights);
      if (problem != null && !rights.canEditPrices) {
        if (mounted) showError(context, problem);
        return;
      }
    }
    final paid = _computePaid(cart);
    if (!mounted) return;
    final payable = _payable(cart);
    if (paid < payable - 0.005 &&
        cart.customer == null &&
        _docType != 'estimate') {
      showError(
        context,
        _exchange != null
            ? 'Collect the full difference for a walk-in exchange.'
            : 'Select a customer for credit/partial bills so the due can be tracked.',
      );
      return;
    }

    // Credit limit, overdue bills, below-cost and over-limit discounts are
    // checked by the server; it answers APPROVAL_REQUIRED (handled below).
    final newDue = (payable - paid).clamp(0, double.infinity);

    final exchange = _exchange;
    if (exchange != null) {
      await _createExchange(
        cart,
        exchange,
        paid: paid,
        paymentMode: paymentModeToSend,
        payments: splitPayments,
        extra: extra,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(billingServiceProvider)
          .createBill(
            cart: cart,
            invoiceType: _docType,
            paidAmount: _docType == 'estimate' ? 0 : paid,
            paymentMode: paymentModeToSend,
            payments: _docType == 'estimate' ? null : splitPayments,
            notes: _notes.text.trim(),
            extra: extra,
          );
      ref.read(cartProvider.notifier).clear();
      invalidateStockData(ref); // products/stock/POS/dashboard quantities
      ref.invalidate(invoicesProvider);
      ref.invalidate(recentInvoicesProvider);
      ref.invalidate(pendingBillCountProvider);
      if (!mounted) return;

      // PD22: offer the customer's advance for what's still due — asked,
      // never automatic. Needs a connection, so online bills only.
      final advance = toDouble(cart.customer?['advance_amount']);
      if (!result.offline &&
          result.invoiceId != null &&
          _docType != 'estimate' &&
          newDue > 0.005 &&
          advance > 0.005) {
        await applyAdvanceToInvoice(
          context,
          ref,
          invoiceId: result.invoiceId!,
          amount: advance < newDue ? advance : newDue.toDouble(),
          customerName: cart.customer?['name'] as String?,
        );
        if (!mounted) return;
      }
      Navigator.pop(context); // close sheet

      if (result.offline) {
        showSuccess(
          context,
          'Saved offline as ${result.invoiceNo}. It will sync automatically.',
        );
      } else {
        showSuccess(context, 'Bill ${result.invoiceNo} created');
        context.push('/invoices/${result.invoiceId}?new=1');
      }
    } catch (e) {
      final exceptions = approvalExceptions(e);
      if (exceptions != null && extra.isEmpty && mounted) {
        setState(() => _busy = false);
        await _needsApproval(
          exceptions,
          cart,
          paid: paid,
          paymentMode: paymentModeToSend,
          payments: splitPayments,
        );
        return;
      }
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// D17–D19: the owner acknowledges and bills; staff send the sale to the
  /// owner as a pending request (nothing sold until approved).
  Future<void> _needsApproval(
    List<Map<String, dynamic>> exceptions,
    CartState cart, {
    required double paid,
    required String paymentMode,
    List<Map<String, dynamic>>? payments,
  }) async {
    final isOwner = ref.read(appContextProvider).value?.isOwner ?? false;
    if (isOwner) {
      if (await showOwnerAcknowledge(context, exceptions) && mounted) {
        await _createBill(extra: const {'owner_ack': true});
      }
      return;
    }
    final reason = await showRequestApproval(context, exceptions);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(billingServiceProvider)
          .requestApproval(
            cart: cart,
            invoiceType: _docType,
            paidAmount: paid,
            paymentMode: paymentMode,
            payments: payments,
            notes: _notes.text.trim(),
            reason: reason,
          );
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(myApprovalsProvider);
      if (!mounted) return;
      Navigator.pop(context); // close sheet
      showSuccess(
        context,
        'Sent to the owner. Complete the sale from Approvals once it is approved.',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// D29: the return and the replacement bill in one server transaction
  /// (create_exchange, migration 0042). Needs a connection — no offline
  /// fallback. The request id makes a retry safe.
  Future<void> _createExchange(
    CartState cart,
    ExchangeDraft exchange, {
    required double paid,
    required String paymentMode,
    List<Map<String, dynamic>>? payments,
    Map<String, dynamic> extra = const {},
  }) async {
    setState(() => _busy = true);
    try {
      final sale = {
        ...buildInvoicePayload(
          cart: cart,
          invoiceType: _docType,
          paidAmount: paid,
          paymentMode: paymentMode,
          payments: payments,
          notes: _notes.text.trim(),
        ),
        ...extra,
      };
      final res = Map<String, dynamic>.from(
        await ref
                .read(supabaseProvider)
                .rpc(
                  'create_exchange',
                  params: {
                    'payload': {
                      'request_id': exchange.requestId,
                      'return': exchange.returnPayload,
                      'sale': sale,
                      'excess': exchange.hasCustomer ? _excess : 'refund',
                      'refund_mode': _refundMode,
                    },
                  },
                )
            as Map,
      );
      ref.read(cartProvider.notifier).clear();
      ref.read(exchangeDraftProvider.notifier).set(null);
      invalidateStockData(ref);
      ref.invalidate(invoicesProvider);
      ref.invalidate(recentInvoicesProvider);
      ref.invalidate(customersProvider);
      if (!mounted) return;
      Navigator.pop(context); // close sheet
      showSuccess(context, exchangeSummary(res));
      context.go('/invoices/${res['invoice_id']}?new=1');
    } catch (e) {
      // An exchange can't wait for approval at launch: the owner
      // acknowledges; staff are told to ask the owner.
      final exceptions = approvalExceptions(e);
      final isOwner = ref.read(appContextProvider).value?.isOwner ?? false;
      if (exceptions != null && isOwner && extra.isEmpty && mounted) {
        setState(() => _busy = false);
        if (await showOwnerAcknowledge(context, exceptions) && mounted) {
          await _createExchange(
            cart,
            exchange,
            paid: paid,
            paymentMode: paymentMode,
            payments: payments,
            extra: const {'owner_ack': true},
          );
        }
        return;
      }
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves edits to an existing invoice via `update_invoice` — payments
  /// already recorded are left untouched, only items/discount/notes change.
  Future<void> _saveEdit(
    EditingInvoice editing, {
    Map<String, dynamic> extra = const {},
  }) async {
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty) {
      showError(context, 'Add at least one item to the bill');
      return;
    }
    final missingSerial = cart.lines.any(
      (l) => l.trackSerial && l.serialNo.trim().isEmpty,
    );
    if (missingSerial) {
      final proceed = await confirmDialog(
        context,
        title: 'Missing IMEI/serial',
        message: 'Some items have no IMEI/serial number. Continue anyway?',
        confirmText: 'Continue',
      );
      if (!proceed) return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(billingServiceProvider)
          .updateBill(
            invoiceId: editing.id,
            cart: cart,
            invoiceType: editing.invoiceType,
            notes: _notes.text.trim(),
            extra: extra,
          );
      ref.read(cartProvider.notifier).clear();
      ref.read(editingInvoiceProvider.notifier).set(null);
      invalidateStockData(ref);
      ref.invalidate(invoiceDetailProvider(editing.id));
      ref.invalidate(invoicesProvider);
      ref.invalidate(recentInvoicesProvider);
      if (!mounted) return;
      showSuccess(context, 'Bill ${result.invoiceNo} updated');
      Navigator.pop(context); // close sheet
      if (context.mounted) context.pop(); // back to invoice detail
    } catch (e) {
      // Edits can't wait for approval at launch (0044): the owner
      // acknowledges; staff are told the owner must make this change.
      final exceptions = approvalExceptions(e);
      final isOwner = ref.read(appContextProvider).value?.isOwner ?? false;
      if (exceptions != null && isOwner && extra.isEmpty && mounted) {
        setState(() => _busy = false);
        if (await showOwnerAcknowledge(context, exceptions) && mounted) {
          await _saveEdit(editing, extra: const {'owner_ack': true});
        }
        return;
      }
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final editing = ref.watch(editingInvoiceProvider);
    final appContext = ref.watch(appContextProvider).value;
    final exchange = ref.watch(exchangeDraftProvider);
    final payable = _payable(cart);
    final excess = exchange == null ? 0.0 : exchange.credit - cart.total;
    final paid = _computePaid(cart);
    final due = (payable - paid).clamp(0, double.infinity);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            editing == null ? 'Checkout' : 'Save bill changes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          // ---- document type ----
          if (editing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_note,
                    size: 18,
                    color: AppColors.indigo,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Editing ${editing.invoiceNo} — ${editing.invoiceType.toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            SegmentedButton<String>(
              segments: [
                if (appContext?.gstEnabled ?? true)
                  const ButtonSegment(value: 'gst', label: Text('GST')),
                const ButtonSegment(value: 'non_gst', label: Text('Non-GST')),
                const ButtonSegment(
                  value: 'cash_memo',
                  label: Text('Cash memo'),
                ),
                if (exchange == null)
                  const ButtonSegment(
                    value: 'estimate',
                    label: Text('Estimate'),
                  ),
              ],
              selected: {_docType},
              onSelectionChanged: (s) => setState(() => _docType = s.first),
            ),
            if (_docType == 'estimate')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Estimates do not deduct stock or record payment.',
                  style: TextStyle(fontSize: 12, color: AppColors.orange),
                ),
              ),
          ],
          const SectionLabel('Customer'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  InitialsAvatar(
                    (cart.customer?['name'] as String?)?.isNotEmpty == true
                        ? cart.customer!['name'] as String
                        : 'Walk-in Customer',
                    radius: 20,
                    icon: cart.customer == null ? Icons.person_outline : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (cart.customer?['name'] as String?)?.isNotEmpty ==
                                  true
                              ? cart.customer!['name'] as String
                              : 'Walk-in customer',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (cart.customer != null) ...[
                          if ((cart.customer!['phone'] as String? ?? '')
                              .isNotEmpty)
                            Text(
                              cart.customer!['phone'] as String,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          if ((cart.customer!['address'] as String? ?? '')
                              .isNotEmpty)
                            Text(
                              cart.customer!['address'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          Builder(
                            builder: (context) {
                              final existingDue = toDouble(
                                cart.customer?['due_amount'],
                              );
                              final creditLimit =
                                  cart.customer?['credit_limit'] == null
                                  ? null
                                  : toDouble(cart.customer!['credit_limit']);
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 2,
                                  children: [
                                    Text(
                                      'Current due: ${money(existingDue)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: existingDue > 0
                                            ? AppColors.red
                                            : AppColors.green,
                                      ),
                                    ),
                                    if (creditLimit != null)
                                      Text(
                                        'Credit limit: ${money(creditLimit)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.inkSoft,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ] else
                          Text(
                            'No customer selected',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.inkSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Editing an existing bill never changes who it was
                  // billed to (update_invoice doesn't touch customer_id);
                  // an exchange stays with the original bill's customer.
                  if (editing == null && exchange == null)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final picked = await showCustomerPicker(context);
                            if (picked != null) {
                              await setCartCustomer(ref, picked);
                            }
                          },
                          child: Text(
                            cart.customer == null ? 'Select' : 'Change',
                          ),
                        ),
                        if (cart.customer != null)
                          TextButton(
                            onPressed: () => setCartCustomer(ref, null),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.inkSoft,
                            ),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SectionLabel('Bill summary'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _row('Items (${cart.itemCount})', money(cart.itemsGross)),
                  if (_docType == 'gst' && cart.taxTotal > 0)
                    _row('Included GST', money(cart.billTaxTotal), dim: true),
                  // Bill discounts need price permission (enforced by the
                  // server's invoice guard, migration 0037).
                  if (appContext?.canEditPrices ?? false) ...[
                    const SizedBox(height: 4),
                    const Text('Bill discount', style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    AmountOrPercentField(
                      controller: _discount,
                      isPercent: _discountIsPercent,
                      onModeChanged: (v) => setState(() {
                        _discountIsPercent = v;
                        ref.read(cartProvider.notifier).setBillDiscountMode(v);
                      }),
                      onChanged: (v) => ref
                          .read(cartProvider.notifier)
                          .setBillDiscount(double.tryParse(v) ?? 0),
                    ),
                  ],
                  if (cart.billDiscount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '− ${money(cart.billDiscountAmount)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  if (cart.priceReduction > 0.05)
                    Builder(
                      builder: (context) {
                        final rights = ref.watch(pricingRightsProvider).value;
                        final over =
                            rights != null &&
                            pricingProblem(cart, rights) != null;
                        return _row(
                          'Below default prices',
                          '${money(cart.priceReduction)} (${qty(cart.priceReductionPct)}%)'
                              '${rights != null && !rights.unlimited ? ' of ${qty(rights.limitPct)}% allowed' : ''}',
                          dim: !over,
                          color: over ? AppColors.red : null,
                        );
                      },
                    ),
                  const Divider(height: 20),
                  _row('Round off', money(cart.roundOff), dim: true),
                  _row('Total', money(cart.total), bold: true),
                  if (exchange != null) ...[
                    _row(
                      'Exchange credit (≈)',
                      '− ${money(exchange.credit < cart.total ? exchange.credit : cart.total)}',
                      color: AppColors.indigo,
                    ),
                    _row('To collect', money(payable), bold: true),
                  ],
                ],
              ),
            ),
          ),
          if (exchange != null && excess > 0.005) ...[
            const SizedBox(height: 8),
            Card(
              color: AppColors.green.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About ${money(excess)} of credit is left after this bill.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (exchange.hasCustomer)
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'advance',
                            label: Text('Keep as advance'),
                          ),
                          ButtonSegment(
                            value: 'refund',
                            label: Text('Refund now'),
                          ),
                        ],
                        selected: {_excess},
                        onSelectionChanged: (s) =>
                            setState(() => _excess = s.first),
                      )
                    else
                      Text(
                        'Walk-in customer: it will be refunded.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    if (!exchange.hasCustomer || _excess == 'refund') ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in const [
                            ('cash', 'Cash'),
                            ('upi', 'UPI'),
                          ])
                            ChoiceChip(
                              label: Text('Refund by ${m.$2}'),
                              selected: _refundMode == m.$1,
                              onSelected: (_) =>
                                  setState(() => _refundMode = m.$1),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _ProfitBanner(
            profit: cart.estimatedProfit,
            costMissing: cart.lines.any((l) => l.costPrice <= 0),
          ),
          if (editing == null && _docType != 'estimate') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel('Payment'),
                TextButton.icon(
                  onPressed: () => _toggleSplit(payable),
                  icon: Icon(
                    _splitMode ? Icons.close : Icons.call_split,
                    size: 16,
                  ),
                  label: Text(_splitMode ? 'Single method' : 'Split payment'),
                ),
              ],
            ),
            if (!_splitMode) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in const [
                    ('cash', 'Cash', Icons.payments_outlined),
                    ('upi', 'UPI', Icons.qr_code),
                    ('card', 'Card', Icons.credit_card),
                    ('credit', 'Credit (Due)', Icons.schedule),
                  ])
                    ChoiceChip(
                      avatar: Icon(mode.$3, size: 16),
                      label: Text(mode.$2),
                      selected: _paymentMode == mode.$1,
                      onSelected: (_) => setState(() {
                        _paymentMode = mode.$1;
                        _paidTouched = false;
                        _paid.text = mode.$1 == 'credit'
                            ? '0'
                            : payable.toStringAsFixed(2);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _paid,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Paid amount ₹',
                        hintText: payable.toStringAsFixed(2),
                      ),
                      onChanged: (_) => setState(() => _paidTouched = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Due',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        Text(
                          money(due),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: due > 0 ? AppColors.red : AppColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              for (var i = 0; i < _splits.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          initialValue: _splits[i].mode,
                          decoration: const InputDecoration(labelText: 'Mode'),
                          items: const [
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text('Cash'),
                            ),
                            DropdownMenuItem(value: 'upi', child: Text('UPI')),
                            DropdownMenuItem(
                              value: 'card',
                              child: Text('Card'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('Bank/Other'),
                            ),
                            DropdownMenuItem(
                              value: 'credit',
                              child: Text('Credit (Due)'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _splits[i].mode = v ?? 'cash'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _splits[i].amount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '₹ ',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: AppColors.red,
                        ),
                        onPressed: _splits.length > 1
                            ? () => setState(() => _splits.removeAt(i))
                            : null,
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addSplit(payable),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add payment method'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collected',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      Text(
                        money(paid),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Due',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      Text(
                        money(due),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: due > 0 ? AppColors.red : AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            if (due > 0 && cart.customer == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Select a customer on the bill to track this due.',
                  style: TextStyle(fontSize: 12, color: AppColors.red),
                ),
              ),
            if (due > 0 && cart.customer?['credit_limit'] != null)
              Builder(
                builder: (context) {
                  final creditLimit = toDouble(cart.customer!['credit_limit']);
                  final projectedDue =
                      toDouble(cart.customer?['due_amount']) + due;
                  if (projectedDue <= creditLimit) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This bill exceeds the credit limit of ${money(creditLimit)} '
                            '(due would be ${money(projectedDue)}).',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ] else if (editing != null) ...[
            const SectionLabel('Payment'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _row('Already paid', money(editing.paidAmount)),
                    _row('New bill total', money(cart.total), bold: true),
                    _row(
                      'Due after changes',
                      money(cart.total - editing.paidAmount),
                      bold: true,
                      color: (cart.total - editing.paidAmount) > 0
                          ? AppColors.red
                          : AppColors.green,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Payments already recorded on this bill are unaffected — only the items and total change.',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : editing != null
                ? () => _saveEdit(editing)
                : _createBill,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              editing != null
                  ? 'Save changes • ${money(cart.total)}'
                  : exchange != null
                  ? 'Complete exchange • collect ${money(payable)}'
                  : _docType == 'estimate'
                  ? 'Save estimate'
                  : 'Create bill • ${money(cart.total)}',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Owner-only estimated profit — after GST and every discount, minus cost of
/// goods. Shown solely in this checkout sheet, never on a printed
/// receipt/invoice PDF, since customers shouldn't see the shop's margin.
class _ProfitBanner extends StatelessWidget {
  const _ProfitBanner({required this.profit, this.costMissing = false});

  final double profit;

  /// Some items have no purchase price, so the profit is overstated.
  final bool costMissing;

  @override
  Widget build(BuildContext context) {
    final color = profit >= 0 ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            profit >= 0 ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              costMissing
                  ? 'Profit unknown — add purchase prices to see it'
                  : 'Your profit (not shown to customer)',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
          if (!costMissing)
            Text(
              money(profit),
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
        ],
      ),
    );
  }
}
