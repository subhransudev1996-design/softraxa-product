import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_permissions.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/import/excel_import_screen.dart';
import '../features/invoices/invoice_detail_screen.dart';
import '../features/invoices/invoices_screen.dart';
import '../features/jobcards/job_card_detail_screen.dart';
import '../features/jobcards/job_card_form_screen.dart';
import '../features/jobcards/job_cards_screen.dart';
import '../features/offline/offline_bills_screen.dart';
import 'splash_screen.dart';
import 'theme.dart';
import '../features/onboarding/business_setup_screen.dart';
import '../features/pos/pos_screen.dart';
import '../features/pos/scan_screen.dart';
import '../features/products/master_data_screen.dart';
import '../features/products/product_detail_screen.dart';
import '../features/products/product_form_screen.dart';
import '../features/products/products_screen.dart';
import '../features/purchases/purchase_form_screen.dart';
import '../features/purchases/purchases_screen.dart';
import '../features/reports/gst_returns_screen.dart';
import '../features/reports/report_detail_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/returns/held_goods_screen.dart';
import '../features/returns/returns.dart';
import '../features/services/services_screen.dart';
import '../features/shell/blocked_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/shell/more_screen.dart';
import '../features/staff/staff_screen.dart';
import '../features/stock/stock_screens.dart';
import '../features/subscription/plans_screen.dart';
import '../features/suppliers/suppliers.dart';
import '../features/support/support_screen.dart';
import 'platform.dart';
import 'supabase_providers.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, _) => notifyListeners());
    _ref.listen(appContextProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
}

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(appContextProvider);
    return BrandSplash(
      trailing: !ctx.hasError
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 40, color: Colors.white70),
                const SizedBox(height: 10),
                const Text('Could not load your account.',
                    style: TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryDark,
                      minimumSize: const Size(160, 46)),
                  onPressed: () =>
                      ref.read(appContextProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                  child: const Text('Logout',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
    );
  }
}

/// Desktop swaps screens with no transition — like switching sections in
/// real desktop software — instead of the mobile push animation, which made
/// every sidebar click look like the app was launching again. Mobile keeps
/// the standard Material page transition.
Page<void> _page(BuildContext context, GoRouterState state, Widget child) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint
    ? NoTransitionPage<void>(key: state.pageKey, child: child)
    : MaterialPage<void>(key: state.pageKey, child: child);

/// Root navigator key — lets chrome that lives ABOVE the Navigator
/// (the desktop title bar) open dialogs/sheets with a valid context.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn = ref.read(supabaseProvider).auth.currentUser != null;
      final loc = state.matchedLocation;
      final atAuth =
          loc == '/login' || loc == '/signup' || loc == '/forgot-password';

      if (!loggedIn) return atAuth ? null : '/login';

      final ctxAsync = ref.read(appContextProvider);
      if (ctxAsync.isLoading || ctxAsync.hasError) {
        return loc == '/splash' ? null : '/splash';
      }
      final appCtx = ctxAsync.value!;
      if (!appCtx.hasBusiness) return loc == '/setup' ? null : '/setup';
      if (appCtx.isBlocked) return loc == '/blocked' ? null : '/blocked';
      if (atAuth || loc == '/splash' || loc == '/setup' || loc == '/blocked') {
        return '/home';
      }
      return permissionRedirect(loc, appCtx);
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(path: '/setup', builder: (_, _) => const BusinessSetupScreen()),
      GoRoute(path: '/blocked', builder: (_, _) => const BlockedScreen()),

      // ---- main shell with bottom navigation ----
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            _page(context, state, HomeShell(navigationShell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/products',
                builder: (_, _) => const ProductsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (_, _) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
            ],
          ),
        ],
      ),

      // ---- full-screen camera scanner: mobile-only, deliberately outside
      // the sidebar shell (covers the whole window by design) ----
      GoRoute(
        path: '/scan',
        builder: (_, state) =>
            ScanScreen(mode: state.uri.queryParameters['mode'] ?? 'pos'),
      ),

      // ---- secondary screens: one shared ShellRoute keeps a single
      // desktop sidebar mounted while these swap instantly beneath it
      // (no-transition pages on desktop). On mobile the shell is a
      // pass-through, so they push full-screen exactly as before. ----
      ShellRoute(
        pageBuilder: (context, state, child) => _page(
          context,
          state,
          withDesktopSidebar(context, state.uri.path, child),
        ),
        routes: [
          GoRoute(
            path: '/products/new',
            pageBuilder: (context, state) => _page(
              context,
              state,
              ProductFormScreen(
                initialBarcode: state.uri.queryParameters['barcode'],
              ),
            ),
          ),
          GoRoute(
            path: '/products/master-data',
            pageBuilder: (context, state) =>
                _page(context, state, const MasterDataScreen()),
          ),
          GoRoute(
            path: '/products/:id/edit',
            pageBuilder: (context, state) => _page(
              context,
              state,
              ProductFormScreen(existing: state.extra as Map<String, dynamic>?),
            ),
          ),
          GoRoute(
            path: '/products/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              ProductDetailScreen(productId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (context, state) =>
                _page(context, state, const InvoicesScreen()),
          ),
          GoRoute(
            // Reuses PosScreen itself (see cart.dart's editingInvoiceProvider)
            // so editing an existing bill gets the exact same product
            // search/scan/discount/stock-warning machinery as creating one —
            // just pre-loaded with that invoice's items and saving via
            // update_invoice instead of create_invoice.
            path: '/invoices/:id/edit',
            pageBuilder: (context, state) =>
                _page(context, state, const PosScreen()),
          ),
          GoRoute(
            path: '/invoices/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              InvoiceDetailScreen(
                invoiceId: state.pathParameters['id']!,
                justCreated: state.uri.queryParameters['new'] == '1',
              ),
            ),
          ),
          GoRoute(
            path: '/customers',
            pageBuilder: (context, state) =>
                _page(context, state, const CustomersScreen()),
          ),
          GoRoute(
            path: '/customers/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              CustomerDetailScreen(customerId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/suppliers',
            pageBuilder: (context, state) =>
                _page(context, state, const SuppliersScreen()),
          ),
          GoRoute(
            path: '/suppliers/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              SupplierDetailScreen(supplierId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/purchases',
            pageBuilder: (context, state) =>
                _page(context, state, const PurchasesScreen()),
          ),
          GoRoute(
            path: '/purchases/new',
            pageBuilder: (context, state) => _page(
              context,
              state,
              PurchaseFormScreen(
                initialSupplierId: state.uri.queryParameters['supplier'],
              ),
            ),
          ),
          GoRoute(
            path: '/purchases/:id/return',
            pageBuilder: (context, state) => _page(
              context,
              state,
              PurchaseReturnFormScreen(
                purchase: state.extra as Map<String, dynamic>,
              ),
            ),
          ),
          GoRoute(
            path: '/purchases/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              PurchaseDetailScreen(purchaseId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/purchase-returns',
            pageBuilder: (context, state) =>
                _page(context, state, const PurchaseReturnsScreen()),
          ),
          GoRoute(
            path: '/purchase-returns/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              PurchaseReturnDetailScreen(returnId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/sale-returns',
            pageBuilder: (context, state) =>
                _page(context, state, const SaleReturnsScreen()),
          ),
          GoRoute(
            path: '/sale-returns/new',
            pageBuilder: (context, state) => _page(
              context,
              state,
              SaleReturnFormScreen(
                invoice: state.extra as Map<String, dynamic>,
              ),
            ),
          ),
          // Exchange (D29): the POS, pre-set with the return as credit —
          // replacement items are picked with the normal billing screen.
          GoRoute(
            path: '/sale-returns/exchange',
            pageBuilder: (context, state) =>
                _page(context, state, const PosScreen()),
          ),
          GoRoute(
            path: '/sale-returns/held',
            pageBuilder: (context, state) =>
                _page(context, state, const HeldGoodsScreen()),
          ),
          GoRoute(
            path: '/sale-returns/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              SaleReturnDetailScreen(returnId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/stock',
            pageBuilder: (context, state) => _page(
              context,
              state,
              StockScreen(initialFilter: state.uri.queryParameters['filter']),
            ),
          ),
          GoRoute(
            path: '/stock/movements/:productId',
            pageBuilder: (context, state) => _page(
              context,
              state,
              StockMovementsScreen(
                productId: state.pathParameters['productId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (context, state) =>
                _page(context, state, const ExpensesScreen()),
          ),
          GoRoute(
            path: '/import',
            pageBuilder: (context, state) =>
                _page(context, state, const ExcelImportScreen()),
          ),
          GoRoute(
            path: '/offline-bills',
            pageBuilder: (context, state) =>
                _page(context, state, const OfflineBillsScreen()),
          ),
          GoRoute(
            path: '/support',
            pageBuilder: (context, state) =>
                _page(context, state, const SupportScreen()),
          ),
          GoRoute(
            path: '/settings/business',
            pageBuilder: (context, state) => _page(
              context,
              state,
              Consumer(
                builder: (context, ref, _) => BusinessSetupScreen(
                  existing: ref.watch(appContextProvider).value?.business,
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/reports/gst-returns',
            pageBuilder: (context, state) =>
                _page(context, state, const GstReturnsScreen()),
          ),
          GoRoute(
            path: '/reports/:type',
            pageBuilder: (context, state) => _page(
              context,
              state,
              ReportDetailScreen(type: state.pathParameters['type']!),
            ),
          ),
          GoRoute(
            path: '/services',
            pageBuilder: (context, state) =>
                _page(context, state, const ServicesScreen()),
          ),
          GoRoute(
            path: '/job-cards',
            pageBuilder: (context, state) =>
                _page(context, state, const JobCardsScreen()),
          ),
          GoRoute(
            path: '/job-cards/new',
            pageBuilder: (context, state) =>
                _page(context, state, const JobCardFormScreen()),
          ),
          GoRoute(
            path: '/job-cards/:id',
            pageBuilder: (context, state) => _page(
              context,
              state,
              JobCardDetailScreen(jobId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/staff',
            pageBuilder: (context, state) =>
                _page(context, state, const StaffScreen()),
          ),
          GoRoute(
            path: '/subscription/plans',
            pageBuilder: (context, state) =>
                _page(context, state, const PlansScreen()),
          ),
        ],
      ),
    ],
  );
});
