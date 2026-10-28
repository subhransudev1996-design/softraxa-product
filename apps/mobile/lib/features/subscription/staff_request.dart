import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import 'plans_screen.dart';

/// The owner asks Dukania for more staff logins (request_staff_login,
/// migration 0097). It arrives as a support request; Dukania agrees the
/// price on WhatsApp — the app shows none — and adding the logins answers
/// and closes it.
Future<void> askForStaffLogins(BuildContext context, WidgetRef ref) async {
  var count = 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(t('More staff logins')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                'Your plan\'s logins are all in use. Ask Dukania to add more — we\'ll confirm on WhatsApp.',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(t('How many'))),
                IconButton(
                  onPressed: count > 1 ? () => setLocal(() => count--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: count < 5 ? () => setLocal(() => count++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Send request')),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref
        .read(supabaseProvider)
        .rpc('request_staff_login', params: {'p_count': count});
    ref.invalidate(plansForAppProvider);
    if (context.mounted) {
      showSuccess(context, t('Request sent — Dukania will contact you'));
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
