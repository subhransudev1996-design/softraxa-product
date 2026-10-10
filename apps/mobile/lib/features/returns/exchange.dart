import '../../core/i18n.dart';
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

/// One item coming back in an exchange, as the customer bought it: shown
/// while the replacement is billed, so the shop sees what was paid.
class ExchangeReturnLine {
  const ExchangeReturnLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.shownQty,
    required this.qtyLabel,
    required this.rate,
    required this.paid,
  });

  final String? productId;
  final String name;

  /// Quantity in the unit stock is kept in (pieces).
  final double qty;

  /// Quantity in the unit [rate] is for: packs when whole packs came back.
  final double shownQty;

  /// "1", "2 Box", "1 Box + 3 pcs".
  final String qtyLabel;

  /// The bill's price per [shownQty] unit, GST included, before discounts.
  final double rate;

  /// What it is worth back: the price paid after the bill's discounts.
  final double paid;

  /// Rate × quantity less what was paid: the discounts it had.
  double get discount {
    final d = gross - paid;
    return d > 0.005 ? d : 0;
  }

  double get gross => _r2(rate * shownQty);
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// What the customer paid per piece for each product coming back (the
/// lowest, if it's on more than one line): the price a same-product
/// replacement gets by default (0077).
Map<String, double> exchangeOldPrices(List<ExchangeReturnLine> lines) {
  final out = <String, double>{};
  for (final l in lines) {
    final id = l.productId;
    if (id == null || l.qty <= 0) continue;
    final each = l.paid / l.qty;
    final had = out[id];
    if (had == null || each < had) out[id] = each;
  }
  return out;
}

/// "Bought 09 Oct 2026 · 3 days ago · exchange within 7 days".
String billAgeText(DateTime? bought, int days, int windowDays) => [
  if (bought != null) t('Bought {v1}', {'v1': dateStr(bought)}),
  days == 0
      ? t('today')
      : (days == 1 ? t('1 day ago') : t('{v1} days ago', {'v1': days})),
  if (windowDays > 0) t('returns within {v1} days', {'v1': windowDays}),
].join(' · ');

/// [exchangeDifference]'s label, translated.
String exchangeDifferenceLabel(String label) => switch (label) {
  'Customer pays' => t('Customer pays'),
  'Give back' => t('Give back'),
  'Even exchange' => t('Even exchange'),
  _ => label,
};

/// The exchange in one line: what the customer pays, or gets back, once
/// the return credit is set against the new items.
({String label, double amount}) exchangeDifference({
  required double credit,
  required double newTotal,
}) {
  final d = _r2(newTotal - credit);
  if (d > 0.005) return (label: 'Customer pays', amount: d);
  if (d < -0.005) return (label: 'Give back', amount: -d);
  return (label: 'Even exchange', amount: 0);
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
    this.invoiceDate,
    this.invoiceTotal = 0,
    this.returned = const [],
  });

  /// The old bill: when it was made and what it came to.
  final DateTime? invoiceDate;
  final double invoiceTotal;

  /// The items coming back, as bought.
  final List<ExchangeReturnLine> returned;

  /// Per-piece price paid for each product coming back.
  Map<String, double> get oldPrices => exchangeOldPrices(returned);

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

  double get credit => estimateExchangeCredit(
    returnValue: returnValue,
    originalDue: originalDue,
  );
}

final exchangeDraftProvider =
    NotifierProvider<ExchangeDraftNotifier, ExchangeDraft?>(
      ExchangeDraftNotifier.new,
    );

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
          for (final e in ctrls.entries)
            e.key: double.tryParse(e.value.text.trim()) ?? 0,
        };
        final sum = split.values.fold(0.0, (s, v) => s + v);
        final ok =
            (sum - total).abs() < 0.0005 && split.values.every((v) => v >= 0);
        return AlertDialog(
          title: Text(t('Condition — {name}', {'name': name})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('Split {v1} returned by condition.', {'v1': qty(total)})),
              const SizedBox(height: 8),
              for (final e in returnConditions.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: ctrls[e.key],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: e.value),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              if (!ok)
                Text(
                  t('The quantities must add up to {v1} (now {v2}).', {
                    'v1': qty(total),
                    'v2': qty(sum),
                  }),
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: ok
                  ? () => Navigator.pop(ctx, {
                      for (final e in split.entries)
                        if (e.value > 0) e.key: e.value,
                    })
                  : null,
              child: Text(t('Done')),
            ),
          ],
        );
      },
    ),
  );
}
