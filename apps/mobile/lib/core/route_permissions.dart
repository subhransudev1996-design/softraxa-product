import 'supabase_providers.dart';

/// Screens a signed-in user may open, by staff permission. The database
/// enforces the same rules (migration 0037); this only keeps staff out of
/// screens whose every action would be refused. Returns the location to
/// redirect to, or null when [loc] is allowed.
String? permissionRedirect(String loc, AppContext c) {
  bool under(String prefix) => loc == prefix || loc.startsWith('$prefix/');

  final allowed = switch (loc) {
    _ when under('/staff') || under('/subscription') || under('/settings') =>
      c.isOwner,
    // The /reports tab itself shows a "no permission" notice instead (a tab
    // that bounces back to Home looks broken); individual reports are guarded.
    _ when loc.startsWith('/reports/') => c.canViewReports,
    _ when under('/purchases') || under('/purchase-returns') ||
        under('/suppliers') =>
      c.canManagePurchases,
    _ when under('/sale-returns') => c.canManageReturns,
    _ when under('/expenses') => c.canManageExpenses,
    _ when under('/services') || under('/job-cards') => c.canManageServices,
    _ when under('/import') ||
        loc == '/products/new' ||
        loc == '/products/master-data' ||
        (loc.startsWith('/products/') && loc.endsWith('/edit')) =>
      c.canManageProducts,
    _ when loc.startsWith('/invoices/') && loc.endsWith('/edit') =>
      c.canEditInvoices,
    _ when under('/pos') || under('/scan') => c.canCreateInvoice,
    _ => true,
  };
  return allowed ? null : '/home';
}
