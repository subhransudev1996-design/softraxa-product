import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/whatsapp_helper.dart';

/// Statuses after which the customer is told the job is done.
const jobDoneStatuses = {'ready', 'delivered', 'returned_unrepaired'};

/// The WhatsApp message for a finished job: what it was, the work done with
/// prices, total, advance and balance, and the shop to contact. In English,
/// like the bills (printed and shared output stays English).
String jobWhatsAppMessage(
  Map<String, dynamic> job, {
  required String shopName,
  String shopPhone = '',
}) {
  final status = job['status'] as String? ?? '';
  final name = (job['customer_name'] as String? ?? '').trim();
  final what = [
    job['item_name'] as String? ?? '',
    job['brand'] as String? ?? '',
    job['model'] as String? ?? '',
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
  final reg = (job['registration_no'] as String? ?? '').trim();
  final item = [
    if (what.isNotEmpty) what else 'item',
    if (reg.isNotEmpty) '($reg)',
  ].join(' ');
  final items = List<Map<String, dynamic>>.from(
    job['job_card_items'] as List? ?? const [],
  );
  final total = items.fold<double>(
    0,
    (s, it) => s + toDouble(it['line_total']),
  );
  final advance = toDouble(job['advance_amount']);
  final balance = (total - advance).clamp(0, double.infinity).toDouble();
  final invoiceNo = (job['invoices'] as Map?)?['invoice_no'] as String?;
  final warrantyEnd = job['warranty_end'];

  final b = StringBuffer()
    ..writeln(name.isEmpty ? 'Hello,' : 'Hello $name,')
    ..writeln();
  switch (status) {
    case 'delivered':
      b.writeln(
        'Your $item has been delivered. Thank you for choosing $shopName!',
      );
    case 'returned_unrepaired':
      b.writeln(
        'Your $item is ready to collect from $shopName. '
        'Unfortunately we could not repair it.',
      );
    default:
      b.writeln(
        'Good news! Your $item is repaired and ready to collect from $shopName.',
      );
  }
  b
    ..writeln()
    ..writeln('Job card: ${job['job_no'] ?? ''}');
  if (invoiceNo != null && invoiceNo.isNotEmpty) b.writeln('Bill: $invoiceNo');

  if (items.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Work done:');
    for (final it in items) {
      final q = toDouble(it['quantity']);
      b.writeln(
        '• ${it['name']}${q != 1 ? ' × ${qty(q)}' : ''} — ${money(it['line_total'] as num?)}',
      );
    }
    b
      ..writeln()
      ..writeln('Total: ${money(total)}');
    if (advance > 0) b.writeln('Advance paid: ${money(advance)}');
    if (status != 'delivered' && balance > 0) {
      b.writeln('Balance to pay: ${money(balance)}');
    }
  }
  if (status == 'delivered' && warrantyEnd != null) {
    b.writeln('Warranty until: ${dateStr(warrantyEnd)}');
  }

  b
    ..writeln()
    ..write('— $shopName');
  if (shopPhone.trim().isNotEmpty) b.write(', ${shopPhone.trim()}');
  return b.toString();
}

/// Opens WhatsApp on the customer's number with [jobWhatsAppMessage] typed
/// in. Without a number, the share sheet lets the user pick the chat.
Future<void> sendJobToWhatsApp(
  BuildContext context,
  Map<String, dynamic> job, {
  required String shopName,
  String shopPhone = '',
}) => sendWhatsAppText(
  job['customer_phone'] as String? ?? '',
  jobWhatsAppMessage(job, shopName: shopName, shopPhone: shopPhone),
  subject: 'Job card ${job['job_no'] ?? ''}',
);
