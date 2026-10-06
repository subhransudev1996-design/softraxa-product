import '../../core/i18n.dart';
import 'day_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'dashboard_desktop.dart';

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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Phone: once the purple header scrolls up, a purple strip covers the
  /// status bar so the cards don't slide under the clock and battery.
  final _scrolled = ValueNotifier(false);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(dashboardStatsProvider);
    final invoices = ref.watch(recentInvoicesProvider);
    final appContext = ref.watch(appContextProvider).value;
    final s = stats.value;
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final list = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(recentInvoicesProvider);
        ref.invalidate(salesTrendProvider);
        ref.invalidate(topProductsProvider);
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
    );
    if (isDesktop) {
      return Scaffold(backgroundColor: AppColors.canvas, body: list);
    }
    final statusBar = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons on the purple header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth == 0) _scrolled.value = n.metrics.pixels > 8;
                return false;
              },
              child: list,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusBar,
              child: ValueListenableBuilder<bool>(
                valueListenable: _scrolled,
                builder: (context, scrolled, _) => AnimatedOpacity(
                  opacity: scrolled ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const ColoredBox(color: AppColors.primaryDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stock is valued at purchase price; ₹0 usually means purchase prices
/// are missing, so the card says so. Staff who may not see costs get
/// null from the server and see a dash, not a misleading ₹0.
String _stockValue(Map<String, dynamic>? s) => s == null
    ? '…'
    : s['stock_value'] == null
    ? '—'
    : moneyCompact(s['stock_value'] as num?);

String _stockValueTitle(Map<String, dynamic>? s) =>
    s != null && s['stock_value'] != null && toDouble(s['stock_value']) == 0
    ? t('Stock value · add costs')
    : 'Stock value (cost)';

/// Desktop KPI cards: all in one row, equal widths.
Widget _statRow(List<Widget> cards) {
  return SizedBox(
    height: 84,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in cards.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: c),
        ],
      ],
    ),
  );
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
        // A GridView adds the status bar height as top padding unless told
        // not to — that was the empty gap above the stat cards.
        padding: EdgeInsets.zero,
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
        ? EmptyState(
            icon: Icons.receipt_long,
            message: t('No invoices yet.\nCreate your first bill!'),
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
                          appContext?.businessName ?? t('My Shop'),
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
                          onPressed: () => showDaySummary(context),
                          icon: const Icon(Icons.insights_outlined, size: 18),
                          label: Text(t('Today\'s summary')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/products/new'),
                          icon: const Icon(Icons.add_box_outlined, size: 18),
                          label: Text(t('Add Product')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/purchases/new'),
                          icon: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 18,
                          ),
                          label: Text(t('New Purchase')),
                        ),
                        CoachTarget(
                          page: 'home',
                          id: 'new_bill',
                          child: FilledButton.icon(
                            onPressed: () => context.go('/pos'),
                            icon: const Icon(Icons.receipt_long, size: 18),
                            label: Text(t('New Bill')),
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
                              child: Text(t('Retry')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : CoachTarget(
                      page: 'home',
                      id: 'stats',
                      child: _statRow([
                        _StatCard(
                          title: t('Today\'s Sale'),
                          value: s == null
                              ? '…'
                              : money(s!['today_sales'] as num?),
                          icon: Icons.point_of_sale_rounded,
                          color: AppColors.primary,
                          onTap: () => context.push('/invoices'),
                        ),
                        if (appContext?.canViewProfit ?? true)
                          _StatCard(
                            title: t('Today\'s Profit'),
                            value: s == null
                                ? '…'
                                : moneyCompact(s!['today_profit'] as num?),
                            icon: Icons.trending_up_rounded,
                            color: AppColors.teal,
                            onTap: () => context.push('/invoices'),
                          ),
                        _StatCard(
                          title: _stockValueTitle(s),
                          value: _stockValue(s),
                          icon: Icons.warehouse_rounded,
                          color: AppColors.indigo,
                          onTap: () => context.push('/stock'),
                        ),
                        _StatCard(
                          title: t('Low / Out of Stock'),
                          value: s == null
                              ? '…'
                              : '${s!['low_stock_count']} / ${s!['out_of_stock_count']}',
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.orange,
                          onTap: () => context.push('/stock?filter=low'),
                        ),
                        _StatCard(
                          title: t('To Collect'),
                          value: s == null
                              ? '…'
                              : moneyCompact(s!['customer_due_total'] as num?),
                          icon: Icons.south_west_rounded,
                          color: AppColors.green,
                          onTap: () => context.push('/customers'),
                        ),
                        _StatCard(
                          title: t('To Pay'),
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

              // ---- sales trend + best sellers (report viewers only) ----
              if (appContext?.canViewReports ?? false) ...[
                const SizedBox(
                  height: 320,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 2, child: SalesTrendPanel()),
                      SizedBox(width: 16),
                      Expanded(child: TopProductsPanel()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              CoachTarget(
                page: 'home',
                id: 'recent',
                child: RecentInvoicesPanel(
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
                            appContext?.businessName ?? t('My Shop'),
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
                              fontSize: 13,
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
                        tooltip: t('Notifications'),
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
                        tooltip: t('Scan barcode'),
                        onTap: () => context.push('/scan'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _HeaderIconButton(
                      icon: Icons.help_outline,
                      tooltip: t('App walkthrough'),
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
                    fontSize: 12,
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
                              t('Profit {v1}', {'v1': moneyCompact(s!['today_profit'] as num?)}),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
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
                      t('{v1} {v2} today', {'v1': s!['today_invoice_count'], 'v2': s!['today_invoice_count'] == 1 ? 'invoice' : 'invoices'}),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
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
                    label: t('New Bill'),
                    onTap: () => context.go('/pos'),
                  ),
                  _QuickAction(
                    icon: Icons.add_box_rounded,
                    color: AppColors.indigo,
                    label: t('Add Product'),
                    onTap: () => context.push('/products/new'),
                  ),
                  _QuickAction(
                    icon: Icons.shopping_cart_rounded,
                    color: AppColors.green,
                    label: t('Purchase'),
                    onTap: () => context.push('/purchases/new'),
                  ),
                  _QuickAction(
                    icon: Icons.insights_rounded,
                    color: AppColors.orange,
                    label: t('Summary'),
                    onTap: () => showDaySummary(context),
                  ),
                  if (!isDesktopPlatform)
                    _QuickAction(
                      icon: Icons.qr_code_scanner,
                      color: AppColors.purple,
                      label: t('Scan'),
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
                          child: Text(t('Retry')),
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
                      title: _stockValueTitle(s),
                      value: _stockValue(s),
                      icon: Icons.warehouse_rounded,
                      color: AppColors.indigo,
                      onTap: () => context.push('/stock'),
                    ),
                    _StatCard(
                      title: t('Low / Out of Stock'),
                      value: s == null
                          ? '…'
                          : '${s!['low_stock_count']} / ${s!['out_of_stock_count']}',
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.orange,
                      onTap: () => context.push('/stock?filter=low'),
                    ),
                    _StatCard(
                      title: t('To Collect'),
                      value: s == null
                          ? '…'
                          : moneyCompact(s!['customer_due_total'] as num?),
                      icon: Icons.south_west_rounded,
                      color: AppColors.green,
                      onTap: () => context.push('/customers'),
                    ),
                    _StatCard(
                      title: t('To Pay'),
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
              Text(t('Recent invoices'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton(
                onPressed: () => context.push('/invoices'),
                child: Text(t('View all')),
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
                  t('Your subscription ends {when}', {'when': when}),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(height: 2),
                Text(t('Renew now so billing doesn\'t stop.'),
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
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
            child: Text(t('Renew')),
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
    final expiry = DateTime.tryParse(
      subscription?['expiry_date'] as String? ?? '',
    );
    final daysLeft = expiry?.difference(DateTime.now()).inDays;
    const ink = Color(0xFF8C5400);
    // One compact row: the trial shouldn't push the shop's numbers down.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE1A8)),
      ),
      child: Row(
        children: [
          const IconChip(
            Icons.timer_outlined,
            color: AppColors.orange,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  daysLeft == null
                      ? t('Free trial')
                      : daysLeft <= 0
                      ? t('Free trial ends today')
                      : 'Free trial · $daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                Text(
                  t('Ends {v1}', {'v1': dateStr(subscription?['expiry_date'])}),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF996300),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t('Ask on WhatsApp'),
            onPressed: () => launchWhatsAppContact(context, appContext),
            icon: const Icon(
              Icons.chat_outlined,
              size: 20,
              color: Color(0xFF128C3E),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ink),
            onPressed: () => context.push('/subscription/plans'),
            child: Text(t('View plans')),
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
      borderRadius: BorderRadius.circular(isDesktopPlatform ? 10 : 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isDesktopPlatform ? 10 : 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isDesktopPlatform ? 10 : 18),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
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
                  fontSize: 12.5,
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
    final displayName = name.isEmpty ? t('Walk-in customer') : name;
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
                    '${invoice['invoice_no']}  •  ${shortDateTimeStr(invoice['invoice_date'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
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
