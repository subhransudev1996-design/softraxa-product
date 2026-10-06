import '../../core/i18n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';

/// A customer's statement (khata) for a period. Every amount is one the app
/// already keeps — bill totals, what's paid and still due on each bill, the
/// receipts, and the khata balance — so it always matches the customer page.
/// No running balance is rebuilt from history (cancelled bills, advances and
/// edits would make one drift).
class CustomerStatement {
  const CustomerStatement({
    required this.from,
    required this.to,
    required this.bills,
    required this.payments,
    required this.returns,
    required this.unpaid,
    required this.earlierDue,
    required this.due,
    required this.advance,
  });

  final DateTime from;
  final DateTime to;

  /// Bills dated in the period (cancelled ones left out).
  final List<Map<String, dynamic>> bills;

  /// Khata receipts in the period (reversed ones left out).
  final List<Map<String, dynamic>> payments;

  /// Returns in the period.
  final List<Map<String, dynamic>> returns;

  /// Every bill still owing, oldest first, whatever its date.
  final List<Map<String, dynamic>> unpaid;

  /// Due on older bills not in [unpaid] (the page loads the latest 100).
  final double earlierDue;

  /// The khata balance now, and the advance held for the customer.
  final double due;
  final double advance;

  double get billed => bills.fold(0.0, (s, b) => s + toDouble(b['total']));
  double get received =>
      payments.fold(0.0, (s, p) => s + toDouble(p['amount']));
  double get returned => returns.fold(0.0, (s, r) => s + toDouble(r['total']));

  /// What the customer has to pay: due less the advance they already gave.
  double get netPayable => due - advance;
}

bool _inPeriod(dynamic date, DateTime from, DateTime to) {
  final d = DateTime.tryParse(date?.toString() ?? '')?.toLocal();
  if (d == null) return false;
  final day = DateTime(d.year, d.month, d.day);
  return !day.isBefore(from) && !day.isAfter(to);
}

/// Builds the statement from what the customer page loads
/// (customerLedgerProvider: customer, invoices, entries).
CustomerStatement buildCustomerStatement({
  required Map<String, dynamic> customer,
  required List<Map<String, dynamic>> invoices,
  required List<Map<String, dynamic>> entries,
  required DateTime from,
  required DateTime to,
}) {
  final f = DateTime(from.year, from.month, from.day);
  final t = DateTime(to.year, to.month, to.day);
  final live = [
    for (final i in invoices)
      if (i['is_cancelled'] != true && i['invoice_type'] != 'estimate') i,
  ];
  DateTime when(Map<String, dynamic> m, String k) =>
      DateTime.tryParse(m[k]?.toString() ?? '') ?? DateTime(2000);
  final bills = [
    for (final i in live)
      if (_inPeriod(i['invoice_date'], f, t)) i,
  ]..sort((a, b) => when(a, 'invoice_date').compareTo(when(b, 'invoice_date')));
  final unpaid = [
    for (final i in live)
      if (toDouble(i['due_amount']) >= 0.01) i,
  ]..sort((a, b) => when(a, 'invoice_date').compareTo(when(b, 'invoice_date')));
  final payments = [
    for (final e in entries)
      if (e['kind'] == 'payment' &&
          e['credit'] != null &&
          _inPeriod(e['date'], f, t))
        Map<String, dynamic>.from(e['data'] as Map),
  ]..sort((a, b) => when(a, 'payment_date').compareTo(when(b, 'payment_date')));
  final returns = [
    for (final e in entries)
      if (e['kind'] == 'return' && _inPeriod(e['date'], f, t))
        Map<String, dynamic>.from(e['data'] as Map),
  ];
  final due = toDouble(customer['due_amount']);
  final listedDue = unpaid.fold(0.0, (s, i) => s + toDouble(i['due_amount']));
  final earlier = ((due - listedDue) * 100).round() / 100;
  return CustomerStatement(
    from: f,
    to: t,
    bills: bills,
    payments: payments,
    returns: returns,
    unpaid: unpaid,
    earlierDue: earlier >= 0.01 ? earlier : 0,
    due: due,
    advance: toDouble(customer['advance_amount']),
  );
}

/// Default PDF fonts have no ₹ glyph, so amounts use "Rs." (as bills do).
String _rs(num? v) =>
    'Rs. ${NumberFormat('#,##,##0.00', 'en_IN').format(v ?? 0)}';

String _modeLabel(String? m) => switch (m) {
  'upi' => 'UPI',
  'card' => 'Card',
  'credit' => 'Credit',
  'other' => 'Bank/Other',
  _ => 'Cash',
};

/// The statement as an A4 PDF to share or print.
Future<Uint8List> buildStatementPdf({
  required Map<String, dynamic> business,
  required Map<String, dynamic> customer,
  required CustomerStatement s,
}) async {
  final doc = pw.Document();
  const small = pw.TextStyle(fontSize: 9);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final head = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Set<int> right = const {},
  }) => pw.TableHelper.fromTextArray(
    headerStyle: head,
    cellStyle: const pw.TextStyle(fontSize: 9.5),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
    headers: headers,
    data: rows,
  );
  pw.Widget section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(title, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
  );
  pw.Widget line(String label, String value, {bool strong = false}) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: strong ? bold : null),
      pw.Text(value, style: strong ? bold : null),
    ],
  );
  final upi = (business['upi_id'] as String? ?? '').trim();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  business['name'] as String? ?? '',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                if ((business['address'] as String? ?? '').isNotEmpty)
                  pw.Text(business['address'] as String, style: small),
                if ((business['phone'] as String? ?? '').isNotEmpty)
                  pw.Text('Phone: ${business['phone']}', style: small),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('STATEMENT OF ACCOUNT',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text('${dateStr(s.from)} to ${dateStr(s.to)}', style: small),
                pw.Text('Printed ${dateStr(DateTime.now())}', style: small),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('Customer', style: small),
        pw.Text(customer['name'] as String? ?? '', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if ((customer['phone'] as String? ?? '').isNotEmpty)
          pw.Text('Phone: ${customer['phone']}', style: small),
        section(t('Bills in this period')),
        if (s.bills.isEmpty)
          pw.Text('No bills.', style: small)
        else
          table(
            ['Date', 'Bill no', 'Amount', 'Paid', 'Due now'],
            [
              for (final b in s.bills)
                [
                  dateStr(b['invoice_date']),
                  b['invoice_no'] as String? ?? '',
                  _rs(toDouble(b['total'])),
                  _rs(toDouble(b['paid_amount'])),
                  _rs(toDouble(b['due_amount'])),
                ],
            ],
            right: {2, 3, 4},
          ),
        if (s.payments.isNotEmpty) ...[
          section(t('Payments received')),
          table(
            ['Date', 'Mode', 'Amount'],
            [
              for (final p in s.payments)
                [
                  dateStr(p['payment_date']),
                  _modeLabel(p['payment_mode'] as String?),
                  _rs(toDouble(p['amount'])),
                ],
            ],
            right: {2},
          ),
        ],
        if (s.returns.isNotEmpty) ...[
          section(t('Returns')),
          table(
            ['Date', 'Return no', 'Amount'],
            [
              for (final r in s.returns)
                [
                  dateStr(r['return_date']),
                  r['return_no'] as String? ?? '',
                  _rs(toDouble(r['total'])),
                ],
            ],
            right: {2},
          ),
        ],
        section(t('Bills still to be paid')),
        if (s.unpaid.isEmpty && s.earlierDue < 0.01)
          pw.Text('Nothing pending.', style: small)
        else
          table(
            ['Date', 'Bill no', 'Due'],
            [
              if (s.earlierDue >= 0.01) ['', 'Earlier balance', _rs(s.earlierDue)],
              for (final b in s.unpaid)
                [
                  dateStr(b['invoice_date']),
                  b['invoice_no'] as String? ?? '',
                  _rs(toDouble(b['due_amount'])),
                ],
            ],
            right: {2},
          ),
        pw.SizedBox(height: 16),
        pw.Container(
          width: 260,
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            children: [
              line('Total due', _rs(s.due)),
              if (s.advance >= 0.01) line('Advance with us', '- ${_rs(s.advance)}'),
              pw.Divider(),
              s.netPayable >= 0
                  ? line('Amount payable', _rs(s.netPayable), strong: true)
                  : line('Advance balance', _rs(-s.netPayable), strong: true),
            ],
          ),
        ),
        if (upi.isNotEmpty && s.netPayable >= 0.01) ...[
          pw.SizedBox(height: 12),
          pw.Text('Pay by UPI: $upi', style: bold),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Asks for the period, then shares or prints the statement.
Future<void> showCustomerStatement(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> ledger,
) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final periods = <(String, DateTime)>[
    ('This month', DateTime(now.year, now.month, 1)),
    ('Last 3 months', DateTime(now.year, now.month - 2, 1)),
    ('This year', DateTime(now.month >= 4 ? now.year : now.year - 1, 4, 1)),
    ('All', DateTime(2000)),
  ];
  var chosen = 1;
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t('Customer statement')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('Bills, payments and what is still due, as a PDF.')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < periods.length; i++)
                  ChoiceChip(
                    label: Text(periods[i].$1),
                    selected: chosen == i,
                    onSelected: (_) => setState(() => chosen = i),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'print'),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(t('Print')),
          ),
          FilledButton.icon(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, 'share'),
            icon: const Icon(Icons.share, size: 18),
            label: Text(t('Share PDF')),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final customer = ledger['customer'] as Map<String, dynamic>;
  final statement = buildCustomerStatement(
    customer: customer,
    invoices: List<Map<String, dynamic>>.from(ledger['invoices'] as List),
    entries: List<Map<String, dynamic>>.from(ledger['entries'] as List),
    from: periods[chosen].$2,
    to: today,
  );
  try {
    final bytes = await buildStatementPdf(
      business: ref.read(appContextProvider).value?.business ?? {},
      customer: customer,
      s: statement,
    );
    final name =
        'Statement_${(customer['name'] as String? ?? 'customer').replaceAll(' ', '_')}_${ymd(today)}.pdf';
    if (action == 'print') {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    } else {
      final message = await saveOrShareFile(
        bytes,
        name,
        subject: 'Statement — ${customer['name']}',
      );
      if (message != null && context.mounted) showSuccess(context, message);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
