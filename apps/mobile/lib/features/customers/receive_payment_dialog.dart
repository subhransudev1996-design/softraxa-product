import '../../core/i18n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// What the "Receive payment" dialog decided — sent to
/// record_customer_payment (migration 0041).
class PaymentRequest {
  const PaymentRequest({
    required this.amount,
    required this.mode,
    required this.note,
    this.invoiceIds,
  });

  final double amount;
  final String mode;
  final String note;

  /// Bills chosen by hand, in order; null = oldest bills first.
  final List<String>? invoiceIds;

  Map<String, dynamic> toParams(String customerId) => {
    'p_customer_id': customerId,
    'p_amount': amount,
    'p_mode': mode,
    'p_note': note,
    if (invoiceIds != null && invoiceIds!.isNotEmpty) 'p_invoice_ids': invoiceIds,
  };
}

/// One line of the server's allocation preview.
typedef Allocation = ({String invoiceNo, double due, double apply});

/// Parses preview_customer_payment's result.
({List<Allocation> allocations, double advance}) parsePaymentPreview(
  Map<String, dynamic> preview,
) => (
  allocations: [
    for (final a in (preview['allocations'] as List? ?? const []))
      (
        invoiceNo: '${(a as Map)['invoice_no'] ?? ''}',
        due: toDouble(a['due']),
        apply: toDouble(a['apply']),
      ),
  ],
  advance: toDouble(preview['advance']),
);

/// Receive a customer payment: amount, mode, and either oldest-bills-first
/// or bills picked by hand (D26). Shows, before saving, which bills it
/// settles and how much becomes an advance.
class ReceivePaymentDialog extends ConsumerStatefulWidget {
  const ReceivePaymentDialog({
    super.key,
    required this.customerId,
    required this.due,
  });

  final String customerId;
  final double due;

  @override
  ConsumerState<ReceivePaymentDialog> createState() =>
      _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends ConsumerState<ReceivePaymentDialog> {
  late final _amount = TextEditingController(
    text: widget.due > 0 ? widget.due.toStringAsFixed(2) : '',
  );
  final _note = TextEditingController();
  String _mode = 'cash';
  bool _pickBills = false;
  final _picked = <String>[]; // invoice ids, in the order chosen
  List<Map<String, dynamic>>? _openBills;
  ({List<Allocation> allocations, double advance})? _preview;
  String? _previewError;
  Timer? _debounce;
  int _previewSeq = 0;

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadOpenBills();
    _refreshPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadOpenBills() async {
    try {
      final rows = await ref
          .read(supabaseProvider)
          .from('invoices')
          .select('id, invoice_no, invoice_date, due_amount')
          .eq('customer_id', widget.customerId)
          .eq('is_cancelled', false)
          .neq('invoice_type', 'estimate')
          .gt('due_amount', 0)
          .order('invoice_date')
          .order('invoice_no')
          .limit(200);
      if (mounted) setState(() => _openBills = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (mounted) setState(() => _openBills = const []);
    }
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    final seq = ++_previewSeq;
    final amount = _amountValue;
    if (amount <= 0) {
      setState(() {
        _preview = null;
        _previewError = null;
      });
      return;
    }
    try {
      final res = await ref.read(supabaseProvider).rpc(
        'preview_customer_payment',
        params: {
          'p_customer_id': widget.customerId,
          'p_amount': amount,
          if (_pickBills && _picked.isNotEmpty) 'p_invoice_ids': _picked,
        },
      );
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = parsePaymentPreview(Map<String, dynamic>.from(res as Map));
        _previewError = null;
      });
    } catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = null;
        _previewError = friendlyError(e);
      });
    }
  }

  bool get _canSave =>
      _amountValue > 0 && (!_pickBills || _picked.isNotEmpty) && _previewError == null;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: Text(t('Receive payment')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.due > 0
                      ? 'Amount ₹ (due ${money(widget.due)})'
                      : 'Amount ₹ (kept as advance)',
                ),
                onChanged: (_) => _schedulePreview(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: InputDecoration(labelText: t('Payment mode')),
                items: [
                  DropdownMenuItem(value: 'cash', child: Text(t('Cash'))),
                  DropdownMenuItem(value: 'upi', child: Text(t('UPI'))),
                  DropdownMenuItem(value: 'card', child: Text(t('Card'))),
                ],
                onChanged: (v) => setState(() => _mode = v ?? 'cash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: InputDecoration(labelText: t('Note (optional)')),
              ),
              if ((_openBills ?? const []).isNotEmpty) ...[
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(t('Oldest bills first'))),
                    ButtonSegment(value: true, label: Text(t('Choose bills'))),
                  ],
                  selected: {_pickBills},
                  onSelectionChanged: (s) {
                    setState(() => _pickBills = s.first);
                    _refreshPreview();
                  },
                ),
                if (_pickBills)
                  for (final b in _openBills!)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _picked.contains(b['id']),
                      title: Text('${b['invoice_no']} • ${dateStr(b['invoice_date'])}'),
                      subtitle: Text(t('Due {v1}', {'v1': money(b['due_amount'] as num?)})),
                      onChanged: (v) {
                        setState(() {
                          v == true ? _picked.add(b['id'] as String) : _picked.remove(b['id']);
                        });
                        _refreshPreview();
                      },
                    ),
              ],
              const SizedBox(height: 12),
              if (_previewError != null)
                Text(_previewError!, style: const TextStyle(color: AppColors.red, fontSize: 12.5))
              else if (preview != null)
                _PreviewBox(preview: preview),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel')),
        ),
        FilledButton(
          style: dialogActionStyle,
          onPressed: _canSave
              ? () => Navigator.pop(
                  context,
                  PaymentRequest(
                    amount: _amountValue,
                    mode: _mode,
                    note: _note.text.trim(),
                    invoiceIds: _pickBills ? List.of(_picked) : null,
                  ),
                )
              : null,
          child: Text(t('Receive')),
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.preview});

  final ({List<Allocation> allocations, double advance}) preview;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12.5, color: AppColors.inkSoft);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('This payment will'), style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final a in preview.allocations)
            Text(
              a.apply >= a.due - 0.005
                  ? '• clear ${a.invoiceNo} (${money(a.apply)})'
                  : '• pay ${money(a.apply)} of ${a.invoiceNo} (${money(a.due - a.apply)} left)',
              style: style,
            ),
          if (preview.advance > 0.005)
            Text(
              t('• keep {v1} as advance for future bills', {'v1': money(preview.advance)}),
              style: style.copyWith(color: AppColors.green, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
