import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_export.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import 'renewal_payment.dart';

/// Shown when the subscription is expired or the account is suspended.
/// An expired shop's owner can pay SOFTRAXA by UPI right here (0053).
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appContext = ref.watch(appContextProvider).value;
    final state = appContext?.subscriptionState ?? 'expired';
    final suspended = state == 'suspended';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    suspended ? Icons.block : Icons.timer_off_outlined,
                    size: 56,
                    color: AppColors.red,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    suspended ? 'Account suspended' : 'Subscription expired',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    suspended
                        ? 'Your account has been suspended. Please contact support to reactivate it.'
                        : 'Renew to continue billing. Your data is safe.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                  if (!suspended) ...[
                    const SizedBox(height: 20),
                    const RenewalPaymentCard(),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () {
                      ref.invalidate(paymentInfoProvider);
                      ref.read(appContextProvider.notifier).refresh();
                    },
                    child: const Text('Check again'),
                  ),
                  // The shop's data stays theirs after expiry (migration 0050).
                  if (appContext?.isOwner ?? false)
                    TextButton.icon(
                      onPressed: () => exportAllData(context, ref),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export all my data'),
                    ),
                  TextButton(
                    onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
