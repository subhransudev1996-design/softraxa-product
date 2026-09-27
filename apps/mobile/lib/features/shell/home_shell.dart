import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/crash_reporting.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../approvals/approvals_screen.dart';

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

    return Scaffold(
      body: navigationShell,
      extendBody: false,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 64,
        height: 64,
        child: CoachTarget(
          page: 'home',
          id: 'new_bill',
          child: FloatingActionButton(
            heroTag: 'new_bill_fab',
            onPressed: () => _go(1),
            tooltip: 'New Bill',
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
                label: 'Home',
                selected: current == 0,
                onTap: () => _go(0),
              ),
              _NavItem(
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                label: 'Products',
                selected: current == 2,
                onTap: () => _go(2),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 38),
                  child: Text(
                    'New Bill',
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
                label: 'Reports',
                selected: current == 3,
                onTap: () => _go(3),
              ),
              _NavItem(
                icon: Icons.widgets_outlined,
                activeIcon: Icons.widgets,
                label: 'More',
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

    return Container(
      width: 264,
      color: _sidebarBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go('/pos'),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('New Bill'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                railTile(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Dashboard',
                  route: '/home',
                ),
                railTile(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  label: 'Products',
                  route: '/products',
                ),
                railTile(
                  icon: Icons.bar_chart_outlined,
                  activeIcon: Icons.bar_chart,
                  label: 'Reports',
                  route: '/reports',
                ),
                const _SidebarSectionLabel('Sales'),
                railTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'All invoices',
                  route: '/invoices',
                ),
                railTile(
                  icon: Icons.assignment_return_outlined,
                  label: 'Sale returns',
                  route: '/sale-returns',
                ),
                railTile(
                  icon: Icons.people_outline,
                  label: 'Customers',
                  route: '/customers',
                ),
                // D18: the owner's approval inbox; staff see their requests.
                railTile(
                  icon: Icons.verified_user_outlined,
                  label: (appContext?.isOwner ?? false)
                      ? (pendingApprovals > 0
                            ? 'Approvals ($pendingApprovals)'
                            : 'Approvals')
                      : 'My approval requests',
                  route: '/approvals',
                  color: pendingApprovals > 0 ? AppColors.red : null,
                ),
                const _SidebarSectionLabel('Inventory'),
                railTile(
                  icon: Icons.warehouse_outlined,
                  label: 'Stock',
                  route: '/stock',
                ),
                railTile(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Purchases',
                  route: '/purchases',
                ),
                railTile(
                  icon: Icons.assignment_return_outlined,
                  label: 'Purchase returns',
                  route: '/purchase-returns',
                ),
                railTile(
                  icon: Icons.local_shipping_outlined,
                  label: 'Suppliers',
                  route: '/suppliers',
                ),
                if (features?.featureOn('excel_import') ?? true)
                  railTile(
                    icon: Icons.upload_file_outlined,
                    label: 'Import products',
                    route: '/import',
                  ),
                if (features?.featureOn('service_module') ?? true) ...[
                  const _SidebarSectionLabel('Services'),
                  railTile(
                    icon: Icons.build_outlined,
                    label: 'Service catalog',
                    route: '/services',
                  ),
                  railTile(
                    icon: Icons.assignment_outlined,
                    label: 'Job cards',
                    route: '/job-cards',
                  ),
                ],
                const _SidebarSectionLabel('Money'),
                if (appContext?.canManageCash ?? false)
                  railTile(
                    icon: Icons.point_of_sale_outlined,
                    label: 'Cashbook & day closing',
                    route: '/cashbook',
                  ),
                if (features?.featureOn('expense_module') ?? true)
                  railTile(
                    icon: Icons.payments_outlined,
                    label: 'Expenses',
                    route: '/expenses',
                  ),
                if (appContext?.isOwner == true) ...[
                  const _SidebarSectionLabel('Store management'),
                  railTile(
                    icon: Icons.badge_outlined,
                    label: 'Staff & permissions',
                    route: '/staff',
                  ),
                  railTile(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Subscription plans',
                    route: '/subscription/plans',
                  ),
                ],
                const _SidebarSectionLabel('Other'),
                railTile(
                  icon: Icons.sync_outlined,
                  label: 'Pending offline bills',
                  route: '/offline-bills',
                ),
                railTile(
                  icon: Icons.support_agent_outlined,
                  label: 'Support',
                  route: '/support',
                ),
                railTile(
                  icon: Icons.settings_outlined,
                  label: 'Business settings',
                  route: '/settings/business',
                ),
                if (kDebugMode && crashReportingEnabled)
                  _RailTile(
                    icon: Icons.bug_report_outlined,
                    label: 'Verify Sentry setup',
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: _sidebarMuted,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected
            ? (selectedBackground ?? AppColors.primarySoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? (activeIcon ?? icon) : icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
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
