import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// One day at the shop, from the records the app already keeps: the bills
/// made, money that came in (at the counter and against old khata), what
/// went out (refunds, expenses) and, for the owner, the profit. Complements
/// the Cash book closing, which counts the cash drawer.
class DaySummary {
  const DaySummary({
    required this.day,
    required this.bills,
    required this.sales,
    required this.creditGiven,
    required this.received,
    required this.khataCollected,
    required this.refunds,
    required this.expenses,
    this.profit,
  });

  final DateTime day;
  final int bills;
  final double sales;

  /// Still unpaid on today's bills (went on customers' khata).
  final double creditGiven;

  /// Money in by mode: cash, upi, card, other (counter + khata receipts).
  final Map<String, double> received;

  /// Of [received]: paid against older dues (khata receipts).
  final double khataCollected;
  final double refunds;
  final double expenses;

  /// Net profit for the day; null when the user may not see profit.
  final double? profit;

  double get totalReceived => received.values.fold(0.0, (s, v) => s + v);
}

/// Adds up the day's rows (as loaded by [daySummaryProvider]).
DaySummary summarizeDay({
  required DateTime day,
  required List<Map<String, dynamic>> invoices,
  required List<Map<String, dynamic>> counterPayments,
  required List<Map<String, dynamic>> khataReceipts,
  required List<Map<String, dynamic>> returns,
  required List<Map<String, dynamic>> expenses,
  double? profit,
}) {
  final received = <String, double>{};
  void add(String? mode, double amount) {
    final m = switch (mode) {
      'upi' || 'card' => mode!,
      'cash' || null => 'cash',
      _ => 'other',
    };
    received[m] = (received[m] ?? 0) + amount;
  }

  for (final p in counterPayments) {
    add(p['payment_mode'] as String?, toDouble(p['amount']));
  }
  var khata = 0.0;
  for (final p in khataReceipts) {
    add(p['payment_mode'] as String?, toDouble(p['amount']));
    khata += toDouble(p['amount']);
  }
  double sum(List<Map<String, dynamic>> rows, String k) =>
      rows.fold(0.0, (s, r) => s + toDouble(r[k]));
  return DaySummary(
    day: day,
    bills: invoices.length,
    sales: sum(invoices, 'total'),
    creditGiven: sum([
      for (final i in invoices)
        if (i['customer_id'] != null) i,
    ], 'due_amount'),
    received: received,
    khataCollected: khata,
    refunds: sum(returns, 'refund_amount'),
    expenses: sum(expenses, 'amount'),
    profit: profit,
  );
}

const _modeNames = {
  'cash': 'Cash',
  'upi': 'UPI',
  'card': 'Card',
  'other': 'Bank/Other',
};

/// The summary as a WhatsApp message for the owner.
String daySummaryMessage(DaySummary s, String shopName) => [
  '*${shopName.trim().isEmpty ? 'Shop' : shopName.trim()}* — ${dateStr(s.day)}',
  '',
  'Bills: ${s.bills}',
  'Sales: ${money(s.sales)}',
  if (s.creditGiven >= 0.01) 'On credit (udhaar): ${money(s.creditGiven)}',
  '',
  'Money received: ${money(s.totalReceived)}',
  for (final m in const ['cash', 'upi', 'card', 'other'])
    if ((s.received[m] ?? 0) >= 0.01)
      '  ${_modeNames[m]}: ${money(s.received[m])}',
  if (s.khataCollected >= 0.01)
    '  (old dues collected: ${money(s.khataCollected)})',
  if (s.refunds >= 0.01) 'Refunds: ${money(s.refunds)}',
  if (s.expenses >= 0.01) 'Expenses: ${money(s.expenses)}',
  if (s.profit != null) 'Profit: ${money(s.profit)}',
].join('\n');

/// Loads one day's summary. Each part is read on its own: a part the user
/// may not see (expenses, profit) is left out instead of failing the rest.
final daySummaryProvider = FutureProvider.autoDispose
    .family<DaySummary, DateTime>((ref, day) async {
      final client = ref.watch(supabaseProvider);
      final start = DateTime(day.year, day.month, day.day);
      final from = start.toUtc().toIso8601String();
      final to = start.add(const Duration(days: 1)).toUtc().toIso8601String();
      Future<List<Map<String, dynamic>>> rows(Future<List<dynamic>> q) async {
        try {
          return List<Map<String, dynamic>>.from(await q);
        } catch (_) {
          return const [];
        }
      }

      final invoices = await client
          .from('invoices')
          .select('total, due_amount, customer_id')
          .gte('invoice_date', from)
          .lt('invoice_date', to)
          .eq('is_cancelled', false)
          .not('invoice_type', 'in', '(estimate,opening)');
      final counter = await rows(
        client
            .from('invoice_payments')
            .select('amount, payment_mode, invoices!inner(is_cancelled)')
            .gte('payment_date', from)
            .lt('payment_date', to)
            .eq('is_advance', false)
            .eq('reversed', false)
            .isFilter('customer_payment_id', null)
            .eq('invoices.is_cancelled', false),
      );
      final khata = await rows(
        client
            .from('customer_payments')
            .select('amount, payment_mode')
            .eq('payment_date', ymd(start))
            .isFilter('reversed_at', null),
      );
      final returns = await rows(
        client
            .from('sale_returns')
            .select('refund_amount')
            .gte('return_date', from)
            .lt('return_date', to),
      );
      final expenses = await rows(
        client.from('expenses').select('amount').eq('expense_date', ymd(start)),
      );
      double? profit;
      if (ref.read(appContextProvider).value?.canViewProfit ?? false) {
        try {
          final d = await client.rpc(
            'get_profit_report',
            params: {'p_from': ymd(start), 'p_to': ymd(start)},
          );
          profit = toDouble((d as Map)['net_profit']);
        } catch (_) {}
      }
      return summarizeDay(
        day: start,
        invoices: List<Map<String, dynamic>>.from(invoices),
        counterPayments: counter,
        khataReceipts: khata,
        returns: returns,
        expenses: expenses,
        profit: profit,
      );
    });

/// Today's summary, with ← → for other days and Share on WhatsApp.
Future<void> showDaySummary(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _DaySummaryDialog(),
);

class _DaySummaryDialog extends ConsumerStatefulWidget {
  const _DaySummaryDialog();

  @override
  ConsumerState<_DaySummaryDialog> createState() => _DaySummaryDialogState();
}

class _DaySummaryDialogState extends ConsumerState<_DaySummaryDialog> {
  late DateTime _day = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Widget _row(String label, double v, {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
            ),
            Text(
              money(v),
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(daySummaryProvider(_day));
    final isToday = _day == _today();
    return AlertDialog(
      title: Row(
        children: [
          IconButton(
            tooltip: t('Day before'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                setState(() => _day = _day.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: Text(
              isToday ? 'Today · ${dateStr(_day)}' : dateStr(_day),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17),
            ),
          ),
          IconButton(
            tooltip: t('Next day'),
            icon: const Icon(Icons.chevron_right),
            onPressed: isToday
                ? null
                : () =>
                      setState(() => _day = _day.add(const Duration(days: 1))),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: AsyncView(
          value: summary,
          onRetry: () => ref.invalidate(daySummaryProvider(_day)),
          builder: (s) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${s.bills} bill${s.bills == 1 ? '' : 's'}',
                style: TextStyle(color: AppColors.inkSoft),
              ),
              _row('Sales', s.sales, bold: true),
              if (s.creditGiven >= 0.01)
                _row('On credit (udhaar)', s.creditGiven, color: AppColors.red),
              const Divider(height: 20),
              _row(
                'Money received',
                s.totalReceived,
                bold: true,
                color: AppColors.green,
              ),
              for (final m in const ['cash', 'upi', 'card', 'other'])
                if ((s.received[m] ?? 0) >= 0.01)
                  _row('   ${_modeNames[m]}', s.received[m]!),
              if (s.khataCollected >= 0.01)
                _row('   of which old dues', s.khataCollected),
              if (s.refunds >= 0.01 || s.expenses >= 0.01)
                const Divider(height: 20),
              if (s.refunds >= 0.01)
                _row('Refunds', s.refunds, color: AppColors.orange),
              if (s.expenses >= 0.01)
                _row('Expenses', s.expenses, color: AppColors.orange),
              if (s.profit != null) ...[
                const Divider(height: 20),
                _row(
                  'Profit',
                  s.profit!,
                  bold: true,
                  color: s.profit! >= 0 ? AppColors.green : AppColors.red,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Close')),
        ),
        FilledButton.icon(
          style: dialogActionStyle,
          onPressed: summary.value == null
              ? null
              : () => sendWhatsAppText(
                  '',
                  daySummaryMessage(
                    summary.value!,
                    ref.read(appContextProvider).value?.businessName ?? '',
                  ),
                  subject: 'Day summary',
                ),
          icon: const Icon(Icons.share, size: 18),
          label: Text(t('Share')),
        ),
      ],
    );
  }
}
