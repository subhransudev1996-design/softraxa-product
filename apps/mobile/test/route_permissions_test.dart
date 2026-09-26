import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/route_permissions.dart';
import 'package:softraxa_inventory/core/supabase_providers.dart';

AppContext _ctx(String role, [Map<String, dynamic>? permissions]) => AppContext(
  profile: {'role': role},
  business: {'id': 'b1', 'is_active': true},
  features: const {},
  subscription: null,
  permissions: permissions,
);

void main() {
  final owner = _ctx('owner');
  final cashier = _ctx('staff', {
    'can_create_invoice': true,
    'can_record_payments': true,
  });

  test('owner can open every screen', () {
    for (final loc in [
      '/staff',
      '/reports/profit',
      '/purchases/new',
      '/sale-returns/new',
      '/expenses',
      '/invoices/abc/edit',
      '/products/new',
      '/settings/business',
    ]) {
      expect(permissionRedirect(loc, owner), isNull, reason: loc);
    }
  });

  test('cashier is kept out of screens they cannot use', () {
    for (final loc in [
      '/staff',
      '/subscription/plans',
      '/settings/business',
      '/reports/sales',
      '/purchases',
      '/purchases/new',
      '/suppliers/x',
      '/purchase-returns',
      '/sale-returns/new',
      '/expenses',
      '/invoices/abc/edit',
    ]) {
      expect(permissionRedirect(loc, cashier), '/home', reason: loc);
    }
  });

  test('cashier keeps billing, invoices, customers and the reports tab', () {
    for (final loc in [
      '/home',
      '/pos',
      '/invoices',
      '/invoices/abc',
      '/customers/c1',
      '/reports',
      '/products',
      '/stock',
    ]) {
      expect(permissionRedirect(loc, cashier), isNull, reason: loc);
    }
  });

  test('granted permissions open the matching screens', () {
    final buyer = _ctx('staff', {
      'can_manage_purchases': true,
      'can_view_reports': true,
      'can_create_invoice': false,
    });
    expect(permissionRedirect('/purchases/new', buyer), isNull);
    expect(permissionRedirect('/reports/gst', buyer), isNull);
    expect(permissionRedirect('/pos', buyer), '/home');
  });

  test('staff management is owner-only even if the flag is set', () {
    final staff = _ctx('staff', {'can_manage_staff': true});
    expect(staff.canManageStaff, isFalse);
    expect(permissionRedirect('/staff', staff), '/home');
  });
}
