import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// SOFTRAXA's UPI details, this shop's plan prices and any payment still
/// being checked (get_payment_info, migration 0053). Works while blocked.
final paymentInfoProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final res = await ref.watch(supabaseProvider).rpc('get_payment_info');
  return Map<String, dynamic>.from((res ?? const {}) as Map);
});

/// Renewal without a payment gateway: the owner pays SOFTRAXA by UPI (QR or
/// UPI ID), then reports it with the UTR. SOFTRAXA checks its UPI app and
/// renews; "Check again" unlocks the app.
class RenewalPaymentCard extends ConsumerStatefulWidget {
  const RenewalPaymentCard({super.key});

  @override
  ConsumerState<RenewalPaymentCard> createState() => _RenewalPaymentCardState();
}

class _RenewalPaymentCardState extends ConsumerState<RenewalPaymentCard> {
  bool _yearly = false;

  String _upiLink(String upi, String payee, double amount, String shop) => Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: {
      'pa': upi,
      'pn': payee,
      if (amount > 0) 'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      'tn': 'Dukania $shop',
    },
  ).toString();

  Future<void> _reportPayment(double suggested) async {
    final amount = TextEditingController(
      text: suggested > 0 ? suggested.toStringAsFixed(0) : '',
    );
    final utr = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('I\'ve paid'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount paid ₹'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: utr,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'UPI reference (UTR) *',
                  helperText:
                      '12-digit number in your UPI app\'s payment details',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
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
          'Sent — you\'ll be unlocked as soon as SOFTRAXA confirms it',
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
      return Text(
        'Ask the shop owner to renew the subscription.',
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
        final plan = d['plan'] as Map?;
        final monthly = toDouble(plan?['monthly_price']);
        final yearly = toDouble(plan?['yearly_price']);
        final amount = _yearly && yearly > 0 ? yearly : monthly;
        final pending = d['pending_claim'] as Map?;
        final rejected = d['last_rejected'] as Map?;
        final shop = appContext?.businessName ?? '';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Renew your subscription',
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
                if (plan != null && monthly > 0 && yearly > 0) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text('${money(monthly)} / month'),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('${money(yearly)} / year'),
                      ),
                    ],
                    selected: {_yearly},
                    onSelectionChanged: (s) =>
                        setState(() => _yearly = s.first),
                  ),
                ],
                const SizedBox(height: 12),
                if (upi.isEmpty)
                  Text(
                    'Contact SOFTRAXA on WhatsApp to renew.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoft),
                  )
                else ...[
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                        data: _upiLink(upi, payee, amount, shop),
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    amount > 0
                        ? 'Scan with any UPI app to pay ${money(amount)} to $payee'
                        : 'Scan with any UPI app to pay $payee',
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
                        tooltip: 'Copy UPI ID',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: upi));
                          showSuccess(context, 'UPI ID copied');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _reportPayment(amount),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('I\'ve paid'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => launchWhatsAppContact(
                    context,
                    appContext,
                    number: support,
                    customReason:
                        'I have paid ${amount > 0 ? money(amount) : ''} for my Dukania renewal. '
                        'Sending the payment screenshot.',
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Send screenshot on WhatsApp'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
