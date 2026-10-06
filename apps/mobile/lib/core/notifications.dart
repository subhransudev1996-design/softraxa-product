import 'i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/offline/offline_service.dart';
import 'formatters.dart';
import 'supabase_providers.dart';
import 'theme.dart';
import 'widgets.dart';

/// Days ahead a product's expiry date starts counting as "expiring soon".
const kNearExpiryDays = 30;

/// Splits product expiry dates (yyyy-MM-dd strings) into how many are
/// already expired vs expiring within [kNearExpiryDays] of [now]. A date
/// equal to today counts as near-expiry, not expired — the stock is still
/// sellable today. Unparsable dates are skipped. Pure so the boundary
/// cases are unit-testable without a clock or a database.
({int expired, int nearExpiry}) expiryBuckets(
  List<String> expiryDates,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final cutoff = today.add(const Duration(days: kNearExpiryDays));
  var expired = 0, near = 0;
  for (final s in expiryDates) {
    final d = DateTime.tryParse(s);
    if (d == null) continue;
    final day = DateTime(d.year, d.month, d.day);
    if (day.isBefore(today)) {
      expired++;
    } else if (!day.isAfter(cutoff)) {
      near++;
    }
  }
  return (expired: expired, nearExpiry: near);
}

/// One actionable alert shown in the title-bar bell.
class AppNotification {
  const AppNotification({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;
}

/// Alerts computed from live data (no server-side notification store):
/// out-of-stock / low-stock products, job cards due for delivery, and
/// offline bills waiting to sync. Each section fails independently.
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((
  ref,
) async {
  final client = ref.watch(supabaseProvider);
  final items = <AppNotification>[];

  try {
    final stats =
        await client.rpc('get_dashboard_stats') as Map<String, dynamic>;
    final out = (stats['out_of_stock_count'] as num?)?.toInt() ?? 0;
    final low = (stats['low_stock_count'] as num?)?.toInt() ?? 0;
    if (out > 0) {
      items.add(
        AppNotification(
          icon: Icons.error_outline,
          color: AppColors.red,
          title: t('Out of stock'),
          subtitle: '$out product${out == 1 ? '' : 's'} at zero stock',
          route: '/stock',
        ),
      );
    }
    if (low > 0) {
      items.add(
        AppNotification(
          icon: Icons.warning_amber_outlined,
          color: AppColors.orange,
          title: t('Low stock'),
          subtitle: '$low product${low == 1 ? '' : 's'} below alert level',
          route: '/stock',
        ),
      );
    }
  } catch (_) {}

  // Expired / near-expiry products. Skipped harmlessly if migration 0026
  // (products.expiry_date) hasn't been applied yet — the query just errors
  // and this section is dropped, like any other failed section here.
  try {
    final now = DateTime.now();
    final rows =
        await client
                .from('products')
                .select('expiry_date')
                .eq('is_active', true)
                .not('expiry_date', 'is', null)
                .lte(
                  'expiry_date',
                  ymd(now.add(const Duration(days: kNearExpiryDays))),
                )
            as List;
    final buckets = expiryBuckets([
      for (final r in rows) (r as Map)['expiry_date'] as String,
    ], now);
    if (buckets.expired > 0) {
      items.add(
        AppNotification(
          icon: Icons.event_busy_outlined,
          color: AppColors.red,
          title: t('Expired products'),
          subtitle:
              '${buckets.expired} product${buckets.expired == 1 ? '' : 's'} past expiry date',
          route: '/products',
        ),
      );
    }
    if (buckets.nearExpiry > 0) {
      items.add(
        AppNotification(
          icon: Icons.schedule_outlined,
          color: AppColors.orange,
          title: t('Expiring soon'),
          subtitle:
              '${buckets.nearExpiry} product${buckets.nearExpiry == 1 ? '' : 's'} expiring within $kNearExpiryDays days',
          route: '/products',
        ),
      );
    }
  } catch (_) {}

  try {
    final rows =
        await client
                .from('job_cards')
                .select('id')
                .not(
                  'status',
                  'in',
                  '(delivered,cancelled,returned_unrepaired)',
                )
                .lte('expected_delivery', ymd(DateTime.now()))
            as List;
    if (rows.isNotEmpty) {
      items.add(
        AppNotification(
          icon: Icons.build_outlined,
          color: AppColors.indigo,
          title: t('Jobs due for delivery'),
          subtitle:
              '${rows.length} job card${rows.length == 1 ? '' : 's'} due today or overdue',
          route: '/job-cards',
        ),
      );
    }
  } catch (_) {}

  try {
    final pending = await ref.watch(offlineServiceProvider).pendingCount();
    if (pending > 0) {
      items.add(
        AppNotification(
          icon: Icons.wifi_off_outlined,
          color: AppColors.purple,
          title: t('Offline bills waiting'),
          subtitle: '$pending bill${pending == 1 ? '' : 's'} not yet synced',
          route: '/offline-bills',
        ),
      );
    }
  } catch (_) {}

  return items;
});

/// The notifications list dialog — shared by the desktop title-bar bell and
/// the mobile dashboard bell. [navigate] abstracts over how each host jumps
/// to an alert's screen (the title bar lives above the Navigator and goes
/// through the router directly; the dashboard pushes so the back arrow
/// returns here).
Future<void> showNotificationsDialog(
  BuildContext context,
  WidgetRef ref, {
  required void Function(String route) navigate,
}) {
  ref.invalidate(notificationsProvider);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Consumer(
      builder: (c, r, _) {
        final async = r.watch(notificationsProvider);
        return AlertDialog(
          title: Text(t('Notifications')),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          content: SizedBox(
            width: 380,
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load notifications: $e'),
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 40,
                            color: AppColors.green,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "All caught up — nothing needs your attention.",
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final n in items)
                          ListTile(
                            leading: IconChip(n.icon, color: n.color, size: 38),
                            title: Text(
                              n.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              n.subtitle,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () {
                              Navigator.pop(dialogCtx);
                              navigate(n.route);
                            },
                          ),
                      ],
                    ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(t('Close')),
            ),
          ],
        );
      },
    ),
  );
}
