import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../../core/theme.dart';

/// Shown when the subscription is expired or the account is suspended.
class BlockedScreen extends ConsumerWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appContext = ref.watch(appContextProvider).value;
    final state = appContext?.subscriptionState ?? 'expired';
    final suspended = state == 'suspended';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(suspended ? Icons.block : Icons.timer_off_outlined,
                  size: 64, color: AppColors.red),
              const SizedBox(height: 16),
              Text(
                suspended ? 'Account suspended' : 'Subscription expired',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                suspended
                    ? 'Your account has been suspended. Please contact support to reactivate it.'
                    : 'Your subscription has expired. Please contact us to renew and continue billing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => ref.read(appContextProvider.notifier).refresh(),
                child: const Text('Check again'),
              ),
              TextButton(
                onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
