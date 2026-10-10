import '../app_lock/app_lock_settings.dart';
import '../../core/i18n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/app_version.dart';
import '../../core/crash_reporting.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../approvals/approvals_screen.dart';
import '../support/ticket_thread_screen.dart';

/// App shell.
///
/// Narrow screens (phones) keep the Vyapar-style bottom bar with a raised
/// center "New Bill" action. Wide screens (desktop) switch to a persistent
/// left sidebar that surfaces every section directly instead of burying
/// them under "More" — same routes, same branches, just different chrome
/// around the same `navigationShell`.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return isWide
        ? _DesktopShell(navigationShell: navigationShell)
        : _MobileShell(navigationShell: navigationShell);
  }
}

/// Wraps a screen that's pushed *outside* the shell's tab branches (e.g.
/// Invoices, Customers, a product detail page) so the desktop sidebar stays
/// visible there too, instead of disappearing the moment you navigate off
/// one of the 5 tab roots. No-op on phone widths. Applied centrally in
/// `router.dart` rather than inside each individual screen.
Widget withDesktopSidebar(
  BuildContext context,
  String currentPath,
  Widget child,
) {
  if (MediaQuery.sizeOf(context).width < kDesktopBreakpoint) return child;
  return Scaffold(
    body: Row(
      children: [
        AppSidebar(currentPath: currentPath),
        Expanded(child: child),
      ],
    ),
  );
}

// ==================== mobile: bottom bar + FAB ====================

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  // branch indexes: 0 home, 1 pos, 2 products, 3 reports, 4 more
  void _go(int branch) => navigationShell.goBranch(
    branch,
    initialLocation: branch == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    // The bottom bar hides under the keyboard; the round New Bill button
    // must too, or it floats over the screen (and the bill's totals).
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: navigationShell,
      extendBody: false,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: keyboardOpen
          ? null
          : SizedBox(
              width: 64,
              height: 64,
              child: CoachTarget(
                page: 'home',
                id: 'new_bill',
                child: FloatingActionButton(
                  heroTag: 'new_bill_fab',
                  onPressed: () => _go(1),
                  tooltip: t('New Bill'),
                  elevation: current == 1 ? 1 : 4,
                  shape: const CircleBorder(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          boxShadow: softShadow(20),
        ),
        child: BottomAppBar(
          color: AppColors.card,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 66,
          padding: EdgeInsets.zero,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: t('Home'),
                selected: current == 0,
                onTap: () => _go(0),
              ),
              _NavItem(
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                label: t('Products'),
                selected: current == 2,
                onTap: () => _go(2),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 38),
                  child: Text(
                    t('New Bill'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart,
                label: t('Reports'),
                selected: current == 3,
                onTap: () => _go(3),
              ),
              _NavItem(
                icon: Icons.widgets_outlined,
                activeIcon: Icons.widgets,
                label: t('More'),
                selected: current == 4,
                onTap: () => _go(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.inkSoft;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(selected ? activeIcon : icon, color: color, size: 23),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== desktop: persistent dark sidebar ====================
//
// Business/POS desktop software (reference: Vyapar Desktop) uses a dark
// left nav to read as "real" desktop software rather than a phone screen
// stretched wide — a light sidebar visually blends into the light content
// area and loses that identity.
//
// This sidebar is a single reusable widget (`AppSidebar`) rendered in two
// places: inside `_DesktopShell` (wrapping the 5 tab branches) and via
// `withDesktopSidebar` (wrapping every other pushed screen — see
// router.dart) so it never disappears on desktop. It navigates purely by
// path (`context.go`), not by shell branch index, so it doesn't need to
// know whether it's currently inside the shell or not.

const _sidebarBg = Color(0xFF14162B);
const _sidebarMuted = Color(0xFF9A9FC0);
const _sidebarActiveBg = Color(0x3A7C3AED); // AppColors.primary @ ~23% alpha

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(currentPath: currentPath),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appContext = ref.watch(appContextProvider).value;
    final features = appContext;
    final pendingApprovals = ref.watch(pendingApprovalCountProvider).value ?? 0;
    final supportUnread = ref.watch(supportUnreadProvider).value ?? 0;
    final collapsed = ref.watch(sidebarCollapsedProvider);
    // Prefix match so a detail/edit page (e.g. /invoices/abc123) still
    // highlights its parent section (/invoices) in the sidebar.
    bool isActive(String route) =>
        currentPath == route || currentPath.startsWith('$route/');

    Widget railTile({
      required IconData icon,
      IconData? activeIcon,
      required String label,
      required String route,
      Color? color,
    }) {
      return _RailTile(
        icon: icon,
        activeIcon: activeIcon,
        label: label,
        selected: isActive(route),
        color: color,
        foregroundColor: _sidebarMuted,
        selectedBackground: _sidebarActiveBg,
        selectedForeground: Colors.white,
        onTap: () => context.go(route),
      );
    }

    // A group of links under a heading that folds away. A group holding
    // the current page always shows it.
    List<Widget> section(String label, List<(String, Widget)> tiles) {
      if (tiles.isEmpty) return const [];
      final open =
          !collapsed.contains(label) || tiles.any((t) => isActive(t.$1));
      return [
        _SidebarSectionLabel(
          label,
          open: open,
          onTap: () =>
              ref.read(sidebarCollapsedProvider.notifier).toggle(label),
        ),
        if (open) ...tiles.map((t) => t.$2),
      ];
    }

    (String, Widget) link({
      required IconData icon,
      required String label,
      required String route,
      Color? color,
    }) =>
        (route, railTile(icon: icon, label: label, route: route, color: color));

    return Container(
      width: 236,
      color: _sidebarBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go('/pos'),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: Text(t('New Bill')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              children: [
                railTile(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: t('Dashboard'),
                  route: '/home',
                ),
                railTile(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  label: t('Products'),
                  route: '/products',
                ),
                railTile(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: t('Reports'),
                  route: '/reports',
                ),
                ...section(t('Sales'), [
                  link(
                    icon: Icons.receipt_long_outlined,
                    label: t('All invoices'),
                    route: '/invoices',
                  ),
                  link(
                    icon: Icons.assignment_return_outlined,
                    label: t('Sale returns'),
                    route: '/sale-returns',
                  ),
                  link(
                    icon: Icons.people_outline,
                    label: t('Customers'),
                    route: '/customers',
                  ),
                  // D18: the owner's approval inbox; staff see their requests.
                  link(
                    icon: Icons.verified_user_outlined,
                    label: (appContext?.isOwner ?? false)
                        ? (pendingApprovals > 0
                              ? 'Approvals ($pendingApprovals)'
                              : 'Approvals')
                        : 'My approval requests',
                    route: '/approvals',
                    color: pendingApprovals > 0 ? AppColors.red : null,
                  ),
                ]),
                ...section(t('Inventory'), [
                  link(
                    icon: Icons.warehouse_outlined,
                    label: t('Stock'),
                    route: '/stock',
                  ),
                  link(
                    icon: Icons.shopping_cart_outlined,
                    label: t('Purchases'),
                    route: '/purchases',
                  ),
                  link(
                    icon: Icons.assignment_return_outlined,
                    label: t('Purchase returns'),
                    route: '/purchase-returns',
                  ),
                  link(
                    icon: Icons.local_shipping_outlined,
                    label: t('Suppliers'),
                    route: '/suppliers',
                  ),
                  if (features?.featureOn('excel_import') ?? true)
                    link(
                      icon: Icons.upload_file_outlined,
                      label: t('Import products'),
                      route: '/import',
                    ),
                ]),
                if ((features?.featureOn('service_module') ?? true) &&
                    (appContext?.category.jobCards ?? true))
                  ...section(t('Services'), [
                    link(
                      icon: Icons.build_outlined,
                      label: t('Service catalog'),
                      route: '/services',
                    ),
                    link(
                      icon: Icons.assignment_outlined,
                      label: t('Job cards'),
                      route: '/job-cards',
                    ),
                  ]),
                ...section(t('Money'), [
                  if (appContext?.canManageCash ?? false)
                    link(
                      icon: Icons.point_of_sale_outlined,
                      label: t('Cashbook & day closing'),
                      route: '/cashbook',
                    ),
                  if (features?.featureOn('expense_module') ?? true)
                    link(
                      icon: Icons.payments_outlined,
                      label: t('Expenses'),
                      route: '/expenses',
                    ),
                ]),
                if (appContext?.isOwner == true)
                  ...section(t('Store management'), [
                    link(
                      icon: Icons.badge_outlined,
                      label: t('Staff & permissions'),
                      route: '/staff',
                    ),
                    link(
                      icon: Icons.workspace_premium_outlined,
                      label: t('Your plan'),
                      route: '/subscription/plans',
                    ),
                  ]),
                ...section(t('Other'), [
                  link(
                    icon: Icons.sync_outlined,
                    label: t('Pending offline bills'),
                    route: '/offline-bills',
                  ),
                  link(
                    icon: Icons.support_agent_outlined,
                    label: supportUnread > 0
                        ? 'Support ($supportUnread new)'
                        : 'Support',
                    route: '/support',
                    color: supportUnread > 0 ? AppColors.red : null,
                  ),
                  link(
                    icon: Icons.settings_outlined,
                    label: t('Business settings'),
                    route: '/settings/business',
                  ),
                  // Opens a dialog, not a page.
                  (
                    '#app-lock',
                    _RailTile(
                      icon: Icons.lock_outline,
                      label: t('App lock'),
                      foregroundColor: _sidebarMuted,
                      selectedBackground: _sidebarActiveBg,
                      selectedForeground: Colors.white,
                      onTap: () => showAppLockSettings(context),
                    ),
                  ),
                ]),
                if (kDebugMode && crashReportingEnabled)
                  _RailTile(
                    icon: Icons.bug_report_outlined,
                    label: t('Verify Sentry setup'),
                    selected: false,
                    color: AppColors.orange,
                    foregroundColor: _sidebarMuted,
                    selectedBackground: _sidebarActiveBg,
                    selectedForeground: Colors.white,
                    // Debug builds only: throws a test error for Sentry.
                    onTap: () => throw StateError('This is test exception'),
                  ),
              ],
            ),
          ),
          if (appContext != null) _SidebarFooter(appContext: appContext),
        ],
      ),
    );
  }
}

/// Sidebar groups the user folded away (in memory; all open at start
/// except the rarely used ones).
final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, Set<String>>(
      SidebarCollapsedNotifier.new,
    );

class SidebarCollapsedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {'Services', 'Money', 'Store management', 'Other'};

  void toggle(String label) => state = state.contains(label)
      ? ({...state}..remove(label))
      : {...state, label};
}

/// Who is logged in, the shop and its plan — at the bottom of the sidebar.
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.appContext});

  final AppContext appContext;

  @override
  Widget build(BuildContext context) {
    final name = (appContext.profile?['full_name'] as String?)?.trim() ?? '';
    final roleLabel = switch (appContext.role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      _ => 'Staff',
    };
    final state = appContext.subscriptionState;
    final plan =
        ((appContext.subscription?['plan'] as Map?)?['name'] as String?) ??
        (state == 'trial' ? t('Free trial') : '');
    final expiry = DateTime.tryParse(
      appContext.subscription?['expiry_date'] as String? ?? '',
    );
    final daysLeft = expiry?.difference(DateTime.now()).inDays;
    final planLine = [
      if (plan.isNotEmpty) plan,
      if (daysLeft != null && daysLeft >= 0 && daysLeft <= 30)
        '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
    ].join(' · ');
    final shop = appContext.businessName;
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      child: InkWell(
        onTap: appContext.isOwner
            ? () => context.go('/subscription/plans')
            : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Text(
                  (name.isNotEmpty ? name : shop).characters.firstOrNull
                          ?.toUpperCase() ??
                      '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isNotEmpty ? name : shop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      planLine.isEmpty ? roleLabel : '$roleLabel · $planLine',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: state == 'trial' || (daysLeft ?? 99) <= 7
                            ? const Color(0xFFFBBF24)
                            : _sidebarMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final v = ref.watch(appVersionProvider).value ?? '';
                        return v.isEmpty
                            ? const SizedBox.shrink()
                            : Text(
                                t('App version {v1}', {'v1': v}),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: _sidebarMuted,
                                  fontSize: 11,
                                ),
                              );
                      },
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

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel(this.label, {this.open = true, this.onTap});

  final String label;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: _sidebarMuted,
                  ),
                ),
              ),
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: _sidebarMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.activeIcon,
    this.selected = false,
    this.color,
    this.foregroundColor,
    this.selectedBackground,
    this.selectedForeground,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool selected;
  final Color? color;
  // Nullable because their fallbacks are the mode-dependent (non-const)
  // AppColors neutrals, which can't be default parameter values.
  final Color? foregroundColor;
  final Color? selectedBackground;
  final Color? selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selFg = selectedForeground ?? AppColors.primary;
    final baseFg = foregroundColor ?? AppColors.ink;
    final fg = color ?? (selected ? selFg : baseFg);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: selected
            ? (selectedBackground ?? AppColors.primarySoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected ? (activeIcon ?? icon) : icon,
                  size: 19,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
