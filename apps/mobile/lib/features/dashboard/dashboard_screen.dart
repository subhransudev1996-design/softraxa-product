import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/notifications.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';
import '../shell/renewal_payment.dart';

final dashboardStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final client = ref.watch(supabaseProvider);
    return await client.rpc('get_dashboard_stats') as Map<String, dynamic>;
  },
);

final recentInvoicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final rows = await client
          .from('invoices')
          .select(
            'id, invoice_no, invoice_type, customer_name, total, payment_status, invoice_date, is_cancelled',
          )
          .order('invoice_date', ascending: false)
          .limit(8);
      return List<Map<String, dynamic>>.from(rows);
    });

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final invoices = ref.watch(recentInvoicesProvider);
    final appContext = ref.watch(appContextProvider).value;
    final s = stats.value;
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardStatsProvider);
          ref.invalidate(recentInvoicesProvider);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (isDesktop)
              _DesktopDashboard(
                appContext: appContext,
                stats: stats,
                invoices: invoices,
                s: s,
                onRetryStats: () => ref.invalidate(dashboardStatsProvider),
                onRetryInvoices: () => ref.invalidate(recentInvoicesProvider),
              )
            else
              _MobileDashboard(
                appContext: appContext,
                stats: stats,
                invoices: invoices,
                s: s,
                onRetryStats: () => ref.invalidate(dashboardStatsProvider),
                onRetryInvoices: () => ref.invalidate(recentInvoicesProvider),
              ),
          ],
        ),
      ),
    );
  }
}

/// Responsive stat-tile grid: picks a column count (2..[maxColumns]) from
/// available width and sizes tiles to a fixed target height, instead of a
/// hardcoded phone-width aspect ratio that turns into huge empty boxes once
/// stretched across a desktop window.
Widget _statGrid(List<Widget> cards, {int maxColumns = 4}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      const targetHeight = 92.0;
      final crossAxisCount = (constraints.maxWidth / 220).floor().clamp(
        2,
        maxColumns,
      );
      final cardWidth =
          (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
          crossAxisCount;
      final aspectRatio = cardWidth / targetHeight;
      return GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
        children: cards,
      );
    },
  );
}

Widget _recentInvoicesCard(
  BuildContext context, {
  required AsyncValue<List<Map<String, dynamic>>> invoices,
  required VoidCallback onRetry,
}) {
  return AsyncView(
    value: invoices,
    onRetry: onRetry,
    builder: (rows) => rows.isEmpty
        ? const EmptyState(
            icon: Icons.receipt_long,
            message: 'No invoices yet.\nCreate your first bill!',
          )
        : Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: softShadow(),
            ),
            child: Column(
              children: [
                for (final inv in rows) ...[
                  _InvoiceTile(invoice: inv),
                  if (inv != rows.last)
                    const Divider(indent: 68, endIndent: 16),
                ],
              ],
            ),
          ),
  );
}

// ==================== desktop: functional top bar + dense KPI row ====================
//
// Deliberately NOT the mobile gradient hero card — business software
// (reference: Vyapar Desktop) uses a slim, functional header with the
// business name/date on the left and real primary actions on the right,
// leaving the vertical space for actual data instead of brand chrome.

class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({
    required this.appContext,
    required this.stats,
    required this.invoices,
    required this.s,
    required this.onRetryStats,
    required this.onRetryInvoices,
  });

  final dynamic appContext;
  final AsyncValue<Map<String, dynamic>> stats;
  final AsyncValue<List<Map<String, dynamic>>> invoices;
  final Map<String, dynamic>? s;
  final VoidCallback onRetryStats;
  final VoidCallback onRetryInvoices;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- top bar: identity + real primary actions ----
              // Expanded+Wrap (not a plain Row) so the action buttons never
              // overflow/clip on narrower desktop windows — they wrap onto a
              // second line, right-aligned, instead.
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                    ),
                    child: const Icon(
                      Icons.storefront,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appContext?.businessName ?? 'My Shop',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          dateStr(DateTime.now()),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        const GuideButton('home'),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/products/new'),
                          icon: const Icon(Icons.add_box_outlined, size: 18),
                          label: const Text('Add Product'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/purchases/new'),
                          icon: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 18,
                          ),
                          label: const Text('New Purchase'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                        ),
                        CoachTarget(
                          page: 'home',
                          id: 'new_bill',
                          child: FilledButton.icon(
                            onPressed: () => context.go('/pos'),
                            icon: const Icon(Icons.receipt_long, size: 18),
                            label: const Text('New Bill'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (appContext != null && appContext.subscriptionState == 'trial')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _TrialBanner(subscription: appContext.subscription),
                ),
              if (appContext != null && _daysLeft(appContext) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _ExpiryBanner(daysLeft: _daysLeft(appContext)!),
                ),

              const SizedBox(height: 24),

              // ---- KPI row (today's sale/profit surfaced here, not in a hero) ----
              stats.hasError
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              friendlyError(stats.error!),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: onRetryStats,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : CoachTarget(
                      page: 'home',
                      id: 'stats',
                      child: _statGrid(maxColumns: 6, [
                        _StatCard(
                          title: "Today's Sale",
                          value: s == null
                              ? '…'
                              : money(s!['today_sales'] as num?),
                          icon: Icons.point_of_sale_rounded,
                          color: AppColors.primary,
                          onTap: () => context.push('/invoices'),
                        ),
                        if (appContext?.canViewProfit ?? true)
                          _StatCard(
                            title: "Today's Profit",
                            value: s == null
                                ? '…'
                                : moneyCompact(s!['today_profit'] as num?),
                            icon: Icons.trending_up_rounded,
                            color: AppColors.teal,
                            onTap: () => context.push('/invoices'),
                          ),
                        _StatCard(
                          title: 'Stock Value',
                          value: s == null
                              ? '…'
                              : moneyCompact(s!['stock_value'] as num?),
                          icon: Icons.warehouse_rounded,
                          color: AppColors.indigo,
                          onTap: () => context.push('/stock'),
                        ),
                        _StatCard(
                          title: 'Low / Out of Stock',
                          value: s == null
                              ? '…'
                              : '${s!['low_stock_count']} / ${s!['out_of_stock_count']}',
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.orange,
                          onTap: () => context.push('/stock?filter=low'),
                        ),
                        _StatCard(
                          title: 'To Collect',
                          value: s == null
                              ? '…'
                              : moneyCompact(s!['customer_due_total'] as num?),
                          icon: Icons.south_west_rounded,
                          color: AppColors.green,
                          onTap: () => context.push('/customers'),
                        ),
                        _StatCard(
                          title: 'To Pay',
                          value: s == null
                              ? '…'
                              : moneyCompact(s!['supplier_due_total'] as num?),
                          icon: Icons.north_east_rounded,
                          color: AppColors.red,
                          onTap: () => context.push('/suppliers'),
                        ),
                      ]),
                    ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent invoices',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => context.push('/invoices'),
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CoachTarget(
                page: 'home',
                id: 'recent',
                child: _recentInvoicesCard(
                  context,
                  invoices: invoices,
                  onRetry: onRetryInvoices,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== mobile: gradient hero + quick actions ====================

class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({
    required this.appContext,
    required this.stats,
    required this.invoices,
    required this.s,
    required this.onRetryStats,
    required this.onRetryInvoices,
  });

  final dynamic appContext;
  final AsyncValue<Map<String, dynamic>> stats;
  final AsyncValue<List<Map<String, dynamic>>> invoices;
  final Map<String, dynamic>? s;
  final VoidCallback onRetryStats;
  final VoidCallback onRetryInvoices;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ============ gradient header ============
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryDark,
                AppColors.primary,
                Color(0xFFA78BFA),
              ],
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.storefront,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appContext?.businessName ?? 'My Shop',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            dateStr(DateTime.now()),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Alerts bell: low/out-of-stock, expired & near-expiry
                    // products, jobs due, unsynced offline bills. Desktop
                    // windows already have the same bell in the title bar.
                    Consumer(
                      builder: (context, ref, _) => _HeaderIconButton(
                        icon: Icons.notifications_none,
                        tooltip: 'Notifications',
                        badge:
                            ref.watch(notificationsProvider).value?.length ?? 0,
                        onTap: () => showNotificationsDialog(
                          context,
                          ref,
                          navigate: (route) => context.push(route),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // mobile_scanner has no Windows/Linux backend — hide the
                    // camera shortcut on desktop instead of opening a dead
                    // scanner. Desktop scanning happens via POS's search field
                    // (hardware wedge or typed code), same as everywhere else.
                    if (!isDesktopPlatform) ...[
                      _HeaderIconButton(
                        icon: Icons.qr_code_scanner,
                        tooltip: 'Scan barcode',
                        onTap: () => context.push('/scan'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _HeaderIconButton(
                      icon: Icons.help_outline,
                      tooltip: 'App walkthrough',
                      onTap: () => showWalkthrough(context, 'home'),
                    ),
                    // auto-opens the welcome tour on first launch
                    const _WelcomeTourTrigger(),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  "TODAY'S SALE",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        s == null ? '—' : money(s!['today_sales'] as num?),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    if (s != null && (appContext?.canViewProfit ?? true))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.trending_up,
                              color: Colors.white,
                              size: 15,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Profit ${moneyCompact(s!['today_profit'] as num?)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (s != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${s!['today_invoice_count']} ${s!['today_invoice_count'] == 1 ? 'invoice' : 'invoices'} today',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ============ trial banner ============
        if (appContext != null && appContext.subscriptionState == 'trial')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _TrialBanner(subscription: appContext.subscription),
          ),
        if (appContext != null && _daysLeft(appContext) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _ExpiryBanner(daysLeft: _daysLeft(appContext)!),
          ),

        // ============ quick actions ============
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: CoachTarget(
            page: 'home',
            id: 'quick_actions',
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: softShadow(),
              ),
              child: Row(
                children: [
                  _QuickAction(
                    icon: Icons.receipt_long,
                    color: AppColors.primary,
                    label: 'New Bill',
                    onTap: () => context.go('/pos'),
                  ),
                  _QuickAction(
                    icon: Icons.add_box_rounded,
                    color: AppColors.indigo,
                    label: 'Add Product',
                    onTap: () => context.push('/products/new'),
                  ),
                  _QuickAction(
                    icon: Icons.shopping_cart_rounded,
                    color: AppColors.green,
                    label: 'Purchase',
                    onTap: () => context.push('/purchases/new'),
                  ),
                  if (!isDesktopPlatform)
                    _QuickAction(
                      icon: Icons.qr_code_scanner,
                      color: AppColors.purple,
                      label: 'Scan',
                      onTap: () => context.push('/scan'),
                    ),
                ],
              ),
            ),
          ),
        ),

        // ============ stat grid ============
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: stats.hasError
              ? Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          friendlyError(stats.error!),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: onRetryStats,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : CoachTarget(
                  page: 'home',
                  id: 'stats',
                  child: _statGrid([
                    _StatCard(
                      title: 'Stock Value',
                      value: s == null
                          ? '…'
                          : moneyCompact(s!['stock_value'] as num?),
                      icon: Icons.warehouse_rounded,
                      color: AppColors.indigo,
                      onTap: () => context.push('/stock'),
                    ),
                    _StatCard(
                      title: 'Low / Out of Stock',
                      value: s == null
                          ? '…'
                          : '${s!['low_stock_count']} / ${s!['out_of_stock_count']}',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.orange,
                      onTap: () => context.push('/stock?filter=low'),
                    ),
                    _StatCard(
                      title: 'To Collect',
                      value: s == null
                          ? '…'
                          : moneyCompact(s!['customer_due_total'] as num?),
                      icon: Icons.south_west_rounded,
                      color: AppColors.green,
                      onTap: () => context.push('/customers'),
                    ),
                    _StatCard(
                      title: 'To Pay',
                      value: s == null
                          ? '…'
                          : moneyCompact(s!['supplier_due_total'] as num?),
                      icon: Icons.north_east_rounded,
                      color: AppColors.red,
                      onTap: () => context.push('/suppliers'),
                    ),
                  ]),
                ),
        ),

        // ============ recent invoices ============
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent invoices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton(
                onPressed: () => context.push('/invoices'),
                child: const Text('View all'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: CoachTarget(
            page: 'home',
            id: 'recent',
            child: _recentInvoicesCard(
              context,
              invoices: invoices,
              onRetry: onRetryInvoices,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Red count bubble on the icon's corner (0 hides it) — used by the
  /// notifications bell.
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: badge > 0
                ? Badge(
                    label: Text(badge > 9 ? '9+' : '$badge'),
                    backgroundColor: AppColors.red,
                    child: Icon(icon, color: Colors.white, size: 22),
                  )
                : Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Days until a PAID subscription ends, when 7 or fewer (null otherwise).
/// Trials have their own banner.
int? _daysLeft(AppContext ctx) {
  if (ctx.subscriptionState != 'active') return null;
  final expiry = DateTime.tryParse(
    ctx.subscription?['expiry_date'] as String? ?? '',
  );
  if (expiry == null) return null;
  final now = DateTime.now();
  final days = DateTime(
    expiry.year,
    expiry.month,
    expiry.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  return days >= 0 && days <= 7 ? days : null;
}

/// "Your subscription ends in 3 days" with a way to pay now (the same UPI
/// card the expired screen shows).
class _ExpiryBanner extends ConsumerWidget {
  const _ExpiryBanner({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final when = daysLeft == 0
        ? 'today'
        : daysLeft == 1
        ? 'tomorrow'
        : 'in $daysLeft days';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const IconChip(Icons.event_busy, color: AppColors.red, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your subscription ends $when',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Renew now so billing doesn\'t stop.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useRootNavigator: true,
              useSafeArea: true,
              builder: (_) => const SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: RenewalPaymentCard(),
              ),
            ),
            child: const Text('Renew'),
          ),
        ],
      ),
    );
  }
}

class _TrialBanner extends ConsumerWidget {
  const _TrialBanner({this.subscription});
  final Map<String, dynamic>? subscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appContext = ref.watch(appContextProvider).value;
    final expiry = subscription?['expiry_date'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE1A8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(
                Icons.timer_outlined,
                color: AppColors.orange,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trial plan active — expires ${dateStr(expiry)}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8C5400),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Upgrade your plan to unlock full features & staff logins.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF996300)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8C5400),
                    side: const BorderSide(color: Color(0xFFFFD180)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: const Text(
                    'View Plans',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                  onPressed: () => context.push('/subscription/plans'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text(
                    'WhatsApp',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                  onPressed: () => launchWhatsAppContact(context, appContext),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              IconChip(icon, color: color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              IconChip(icon, color: color, size: 48),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context) {
    final name = (invoice['customer_name'] as String?)?.trim() ?? '';
    final displayName = name.isEmpty ? 'Walk-in customer' : name;
    // Built manually instead of ListTile: ListTile's trailing slot enforces
    // a fixed max height (~40px) independent of contentPadding, which a
    // 2-line trailing column (amount + status chip) overflows by ~1px under
    // Windows' font metrics (never surfaced on Android/iOS). A plain Row
    // with mainAxisSize.min columns sizes purely from content, so it can't
    // overflow against an invisible fixed constraint.
    return InkWell(
      onTap: () => context.push('/invoices/${invoice['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            InitialsAvatar(name.isEmpty ? 'W C' : name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${invoice['invoice_no']}  •  ${dateTimeStr(invoice['invoice_date'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(invoice['total'] as num?),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                StatusChip(
                  invoice['is_cancelled'] == true
                      ? 'cancelled'
                      : (invoice['payment_status'] as String? ?? ''),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Invisible: fires the one-time welcome tour after the first frame.
class _WelcomeTourTrigger extends StatefulWidget {
  const _WelcomeTourTrigger();

  @override
  State<_WelcomeTourTrigger> createState() => _WelcomeTourTriggerState();
}

class _WelcomeTourTriggerState extends State<_WelcomeTourTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWalkthrough(context, 'home');
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
