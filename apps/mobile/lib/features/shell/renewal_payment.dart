import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// SOFTRAXA's UPI details, this shop's plan name and any payment still
/// being checked (get_payment_info, migrations 0053 and 0055). Works while
/// blocked. No prices: SOFTRAXA tells each shop its renewal amount.
final paymentInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final res = await ref.watch(supabaseProvider).rpc('get_payment_info');
  return Map<String, dynamic>.from((res ?? const {}) as Map);
});

/// Renewal without a payment gateway: the owner pays SOFTRAXA by UPI (QR or
/// UPI ID) the amount SOFTRAXA told them, then reports it with the UTR.
/// SOFTRAXA checks its UPI app and renews; "Check again" unlocks the app.
class RenewalPaymentCard extends ConsumerStatefulWidget {
  const RenewalPaymentCard({super.key});

  @override
  ConsumerState<RenewalPaymentCard> createState() => _RenewalPaymentCardState();
}

class _RenewalPaymentCardState extends ConsumerState<RenewalPaymentCard> {
  // No amount in the link: the owner types what SOFTRAXA asked for.
  String _upiLink(String upi, String payee, String shop) => Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: {
      'pa': upi,
      'pn': payee,
      'cu': 'INR',
      'tn': 'Dukania $shop',
    },
  ).toString();

  Future<void> _reportPayment() async {
    final amount = TextEditingController();
    final utr = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('I\'ve paid')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: t('Amount paid ₹ *')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: utr,
                decoration: InputDecoration(
                  labelText: t('UPI reference (UTR) *'),
                  helperText: t('12-digit number in your UPI app\'s payment details'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: t('Note (optional)')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Send')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'submit_renewal_claim',
            params: {
              'p_amount': double.tryParse(amount.text.trim()) ?? 0,
              'p_reference': utr.text.trim(),
              'p_note': note.text.trim(),
            },
          );
      ref.invalidate(paymentInfoProvider);
      if (mounted) {
        showSuccess(
          context,
          t('Sent — you\'ll be unlocked as soon as SOFTRAXA confirms it'),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appContext = ref.watch(appContextProvider).value;
    if (!(appContext?.isOwner ?? false)) {
      return Text(t('Ask the shop owner to renew the subscription.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.inkSoft),
      );
    }
    final info = ref.watch(paymentInfoProvider);
    return info.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
      error: (e, _) => Text(friendlyError(e), textAlign: TextAlign.center),
      data: (d) {
        final upi = d['upi_id'] as String? ?? '';
        final payee = d['payee_name'] as String? ?? 'SOFTRAXA';
        final support = d['support_whatsapp'] as String? ?? '';
        final planName = (d['plan'] as Map?)?['name'] as String?;
        final pending = d['pending_claim'] as Map?;
        final rejected = d['last_rejected'] as Map?;
        final shop = appContext?.businessName ?? '';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('Renew your subscription'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (pending != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.indigo.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'We\'re checking your payment of ${money(pending['amount'] as num?)} '
                      '(UTR ${pending['reference']}). The app unlocks as soon as SOFTRAXA '
                      'confirms it — tap Check again.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                if (rejected != null && pending == null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Your payment with UTR ${rejected['reference']} couldn\'t be confirmed: '
                    '${rejected['reason']}',
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                ],
                if (planName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    t('Plan: {planName}', {'planName': planName}),
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                ],
                const SizedBox(height: 12),
                if (upi.isEmpty)
                  Text(t('Contact SOFTRAXA on WhatsApp to renew.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoft),
                  )
                else ...[
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                        data: _upiLink(upi, payee, shop),
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan with any UPI app and pay $payee the renewal amount '
                    'SOFTRAXA shared with you',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SelectableText(
                        upi,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        tooltip: t('Copy UPI ID'),
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: upi));
                          showSuccess(context, t('UPI ID copied'));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _reportPayment,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(t('I\'ve paid')),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => launchWhatsAppContact(
                    context,
                    appContext,
                    number: support,
                    customReason:
                        'I want to renew my Dukania subscription. '
                        'Please tell me the renewal amount.',
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(t('Ask SOFTRAXA the amount on WhatsApp')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
