import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supabase_providers.dart';
import 'widgets.dart';

/// Used only until the number set in the admin panel is known (older
/// database, or before the first sign-in).
String get supportWhatsAppNumber {
  final num = dotenv.env['SUPPORT_WHATSAPP_NUMBER'] ?? '917437988568';
  return num.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Formats store details and launches WhatsApp with a pre-filled message.
Future<void> launchWhatsAppContact(
  BuildContext context,
  AppContext? ctx, {
  String? customReason,
  // Overrides the number from the admin panel settings (ctx.supportWhatsApp).
  String? number,
}) async {
  final storeName = ctx?.businessName.isNotEmpty == true
      ? ctx!.businessName
      : 'My Store';
  final ownerName =
      (ctx?.business?['owner_name'] as String?)?.isNotEmpty == true
      ? (ctx!.business!['owner_name'] as String)
      : ((ctx?.profile?['full_name'] as String?) ?? 'Owner');
  final phone = (ctx?.business?['phone'] as String?) ?? '';
  final email =
      (ctx?.business?['email'] as String?) ??
      (ctx?.profile?['email'] as String?) ??
      '';
  final subState = (ctx?.subscriptionState ?? 'trial').toUpperCase();

  final buffer = StringBuffer();
  buffer.writeln('Hello Dukania Team 👋,');
  buffer.writeln();
  if (customReason != null && customReason.isNotEmpty) {
    buffer.writeln(customReason);
  } else {
    buffer.writeln(
      'I am currently on $subState subscription and would like to get assistance / upgrade my plan.',
    );
  }
  buffer.writeln();
  buffer.writeln('📋 *Store & User Details:*');
  buffer.writeln('• *Store Name:* $storeName');
  buffer.writeln('• *Owner Name:* $ownerName');
  if (phone.isNotEmpty) buffer.writeln('• *Phone Number:* $phone');
  if (email.isNotEmpty) buffer.writeln('• *Email:* $email');
  buffer.writeln('• *Current Status:* $subState');

  final message = buffer.toString();
  final fromSettings = (number ?? '').isNotEmpty
      ? number!
      : (ctx?.supportWhatsApp ?? '');
  final configured = fromSettings.replaceAll(RegExp(r'[^0-9]'), '');
  final number0 = configured.isNotEmpty ? configured : supportWhatsAppNumber;
  final encodedMsg = Uri.encodeComponent(message);

  // 1. Native WhatsApp App URI scheme
  final whatsappAppUri = Uri.parse(
    'whatsapp://send?phone=$number0&text=$encodedMsg',
  );
  // 2. Short Web URL (wa.me)
  final waMeUri = Uri.parse('https://wa.me/$number0?text=$encodedMsg');
  // 3. Direct API Web URL (api.whatsapp.com)
  final apiUri = Uri.parse(
    'https://api.whatsapp.com/send?phone=$number0&text=$encodedMsg',
  );

  try {
    if (await canLaunchUrl(whatsappAppUri)) {
      await launchUrl(whatsappAppUri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {}

  try {
    if (await canLaunchUrl(waMeUri)) {
      await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {}

  try {
    await launchUrl(apiUri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) {
      showError(
        context,
        'Could not open WhatsApp ($e). Support phone: +$number0',
      );
    }
  }
}
