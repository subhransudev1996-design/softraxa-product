import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Condition of a returned item (D28, migration 0042). Only sellable goods
/// go back into stock; the rest are held out of sale.
const returnConditions = <String, String>{
  'sellable': 'Sellable',
  'inspection': 'Needs inspection',
  'damaged': 'Damaged',
  'scrap': 'Scrap',
};

/// "2 sellable, 1 damaged" for a condition → quantity split.
String conditionSplitLabel(Map<String, double> split) => [
  for (final e in split.entries)
    if (e.value > 0)
      '${qty(e.value)} ${returnConditions[e.key]?.toLowerCase() ?? e.key}',
].join(', ');

/// Share of each line's value left after the bill-level discount (PD26):
/// what the server uses to value a return.
double invoiceDiscountFactor(Map<String, dynamic> invoice) {
  final items = List<Map<String, dynamic>>.from(
    invoice['invoice_items'] as List? ?? const [],
  );
  final gross = items.fold(0.0, (s, it) => s + toDouble(it['line_total']));
  if (gross <= 0) return 1;
  final after = gross - toDouble(invoice['discount_amount']);
  return (after < 0 ? 0 : after) / gross;
}

/// Estimated credit an exchange has for the replacement: the return value
/// minus what the original bill still owes (settled first, D27). The
/// server computes the real figure; this is for the screen.
double estimateExchangeCredit({
  required double returnValue,
  required double originalDue,
}) {
  final credit = returnValue - (originalDue > 0 ? originalDue : 0);
  return credit > 0 ? credit : 0;
}

/// One-line result of create_exchange, from the server's figures.
String exchangeSummary(Map<String, dynamic> r) {
  final refund = toDouble(r['refund']);
  final advance = toDouble(r['advance']);
  final settled = toDouble(r['applied_to_original']);
  return [
    'Exchange done: return ${r['return_no']} (${money(toDouble(r['return_value']))}), '
        'new bill ${r['invoice_no']}',
    if (settled > 0) '${money(settled)} cleared the old bill',
    'credit used ${money(toDouble(r['credit_used']))}',
    if (refund > 0) 'refund ${money(refund)}',
    if (advance > 0) '${money(advance)} kept as advance',
  ].join(' • ');
}

/// An exchange in progress: the return part, prepared on the return screen,
/// waiting for replacement items in the POS (D29).
class ExchangeDraft {
  const ExchangeDraft({
    required this.requestId,
    required this.invoiceId,
    required this.invoiceNo,
    required this.returnPayload,
    required this.returnValue,
    required this.originalDue,
    required this.hasCustomer,
  });

  /// Sent with the exchange so a retry isn't posted twice.
  final String requestId;
  final String invoiceId;
  final String invoiceNo;

  /// create_sale_return payload (items with conditions, notes, override).
  final Map<String, dynamic> returnPayload;
  final double returnValue;
  final double originalDue;

  /// Walk-in exchanges must be paid in full and excess is always refunded.
  final bool hasCustomer;

  double get credit =>
      estimateExchangeCredit(returnValue: returnValue, originalDue: originalDue);
}

final exchangeDraftProvider =
    NotifierProvider<ExchangeDraftNotifier, ExchangeDraft?>(ExchangeDraftNotifier.new);

class ExchangeDraftNotifier extends Notifier<ExchangeDraft?> {
  @override
  ExchangeDraft? build() => null;
  void set(ExchangeDraft? v) => state = v;
}

/// Split a returned quantity across conditions. Returns null if cancelled.
Future<Map<String, double>?> showConditionSplitDialog(
  BuildContext context, {
  required String name,
  required double total,
  required Map<String, double> current,
}) {
  final ctrls = {
    for (final c in returnConditions.keys)
      c: TextEditingController(
        text: (current[c] ?? 0) > 0 ? qty(current[c]) : '',
      ),
  };
  return showDialog<Map<String, double>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final split = {
          for (final e in ctrls.entries) e.key: double.tryParse(e.value.text.trim()) ?? 0,
        };
        final sum = split.values.fold(0.0, (s, v) => s + v);
        final ok = (sum - total).abs() < 0.0005 && split.values.every((v) => v >= 0);
        return AlertDialog(
          title: Text('Condition — $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Split ${qty(total)} returned by condition.'),
              const SizedBox(height: 8),
              for (final e in returnConditions.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: ctrls[e.key],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: e.value),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              if (!ok)
                Text(
                  'The quantities must add up to ${qty(total)} (now ${qty(sum)}).',
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: dialogActionStyle,
              onPressed: ok
                  ? () => Navigator.pop(ctx, {
                      for (final e in split.entries)
                        if (e.value > 0) e.key: e.value,
                    })
                  : null,
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}
