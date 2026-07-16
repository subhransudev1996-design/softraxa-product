import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/offline/offline_service.dart';
import 'formatters.dart';
import 'supabase_providers.dart';
import 'theme.dart';

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
final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final items = <AppNotification>[];

  try {
    final stats =
        await client.rpc('get_dashboard_stats') as Map<String, dynamic>;
    final out = (stats['out_of_stock_count'] as num?)?.toInt() ?? 0;
    final low = (stats['low_stock_count'] as num?)?.toInt() ?? 0;
    if (out > 0) {
      items.add(AppNotification(
        icon: Icons.error_outline,
        color: AppColors.red,
        title: 'Out of stock',
        subtitle: '$out product${out == 1 ? '' : 's'} at zero stock',
        route: '/stock',
      ));
    }
    if (low > 0) {
      items.add(AppNotification(
        icon: Icons.warning_amber_outlined,
        color: AppColors.orange,
        title: 'Low stock',
        subtitle: '$low product${low == 1 ? '' : 's'} below alert level',
        route: '/stock',
      ));
    }
  } catch (_) {}

  try {
    final rows = await client
        .from('job_cards')
        .select('id')
        .not('status', 'in', '(delivered,cancelled,returned_unrepaired)')
        .lte('expected_delivery', ymd(DateTime.now())) as List;
    if (rows.isNotEmpty) {
      items.add(AppNotification(
        icon: Icons.build_outlined,
        color: AppColors.indigo,
        title: 'Jobs due for delivery',
        subtitle:
            '${rows.length} job card${rows.length == 1 ? '' : 's'} due today or overdue',
        route: '/job-cards',
      ));
    }
  } catch (_) {}

  try {
    final pending = await ref.watch(offlineServiceProvider).pendingCount();
    if (pending > 0) {
      items.add(AppNotification(
        icon: Icons.wifi_off_outlined,
        color: AppColors.purple,
        title: 'Offline bills waiting',
        subtitle: '$pending bill${pending == 1 ? '' : 's'} not yet synced',
        route: '/offline-bills',
      ));
    }
  } catch (_) {}

  return items;
});
