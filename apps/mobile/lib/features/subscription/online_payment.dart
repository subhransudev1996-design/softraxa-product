import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../shell/renewal_payment.dart';
import 'plans_screen.dart';

/// Online payment on dukania.in is switched on (migration 0105). False
/// before 0105 or offline — the buttons don't show.
final onlinePaymentsOnProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return (await ref.watch(supabaseProvider).rpc('online_payments_on')) ==
        true;
  } catch (_) {
    return false;
  }
});

const _site = 'https://www.dukania.in';

/// Opens dukania.in/pay (or /account, migration 0106) for this shop in the
/// browser with a 2-hour pay link (create_pay_link), so the owner doesn't
/// sign in again. When the owner comes back to the app the plan is fetched
/// again, so a paid plan shows straight away (the server turns it on as
/// soon as Razorpay confirms).
Future<void> openOnlinePayment(
  BuildContext context,
  WidgetRef ref, {
  String page = 'pay',
}) async {
  // Outlives this screen: the owner may come back to another one.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final token =
        await ref.read(supabaseProvider).rpc('create_pay_link') as String;
    final ok = await launchUrl(
      Uri.parse('$_site/$page?t=$token'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw Exception(t('Could not open the browser'));
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }

  void refresh() {
    unawaited(container.read(appContextProvider.notifier).refresh());
    container.invalidate(plansForAppProvider);
    container.invalidate(paymentInfoProvider);
  }

  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onResume: () {
      listener.dispose();
      refresh();
      // The payment may be confirmed a moment after the owner is back.
      Timer(const Duration(seconds: 6), refresh);
      Timer(const Duration(seconds: 20), refresh);
    },
  );
}

/// "Pay online" with a line about it, for the owner when it's switched on.
class PayOnlineButton extends ConsumerWidget {
  const PayOnlineButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(onlinePaymentsOnProvider).value ?? false;
    final isOwner = ref.watch(appContextProvider).value?.isOwner ?? false;
    if (!isOwner) return const SizedBox.shrink();
    final manage = TextButton.icon(
      onPressed: () => openOnlinePayment(context, ref, page: 'account'),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: Text(t('Manage my plan on dukania.in')),
    );
    if (!on) return manage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => openOnlinePayment(context, ref),
          icon: const Icon(Icons.lock_outline),
          label: Text(t('Pay online')),
        ),
        const SizedBox(height: 6),
        Text(
          t(
            'Renew, change plan or add logins by UPI, card or netbanking. Your plan turns on as soon as you pay.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5),
        ),
        manage,
      ],
    );
  }
}
