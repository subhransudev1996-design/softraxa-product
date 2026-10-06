import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// The udhaar reminder as the shop would say it: polite Hinglish, the
/// amount, how to pay (UPI ID if the shop has one) and who it's from.
String paymentReminderMessage({
  required String customerName,
  required double due,
  required String shopName,
  String shopPhone = '',
  String upiId = '',
}) {
  final name = customerName.trim();
  final shop = shopName.trim().isEmpty ? 'hamari dukaan' : shopName.trim();
  return [
    'Namaste${name.isEmpty ? '' : ' $name ji'} 🙏',
    '',
    '$shop mein aapka *${money(due)}* baaki hai.',
    'Kripya jaldi bhugtan kar dein.',
    if (upiId.trim().isNotEmpty) ...['', 'UPI: ${upiId.trim()}'],
    '',
    'Dhanyavaad,',
    shopName.trim().isEmpty ? 'Dukaan' : shopName.trim(),
    if (shopPhone.trim().isNotEmpty) shopPhone.trim(),
  ].join('\n');
}

/// Shows the reminder for [customer] (a customers row with name, phone,
/// due_amount), editable, then opens WhatsApp to their number. Nothing is
/// sent until the owner presses send in WhatsApp.
Future<void> showPaymentReminder(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> customer,
) async {
  final business = ref.read(appContextProvider).value?.business ?? {};
  final phone = customer['phone'] as String? ?? '';
  final text = TextEditingController(
    text: paymentReminderMessage(
      customerName: customer['name'] as String? ?? '',
      due: toDouble(customer['due_amount']),
      shopName: business['name'] as String? ?? '',
      shopPhone: business['phone'] as String? ?? '',
      upiId: business['upi_id'] as String? ?? '',
    ),
  );
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Remind on WhatsApp')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              whatsAppNumber(phone).isEmpty
                  ? 'No mobile number saved — you can pick the chat yourself.'
                  : 'To ${customer['name']} · $phone',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: t('Message (you can change it)'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t('Cancel')),
        ),
        FilledButton.icon(
          style: dialogActionStyle,
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.send, size: 18),
          label: Text(t('Open WhatsApp')),
        ),
      ],
    ),
  );
  final message = text.text.trim();
  text.dispose();
  if (send != true || message.isEmpty) return;
  try {
    await sendWhatsAppText(phone, message, subject: 'Payment reminder');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
