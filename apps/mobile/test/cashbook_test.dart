import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/route_permissions.dart';
import 'package:softraxa_inventory/core/supabase_providers.dart';
import 'package:softraxa_inventory/features/cashbook/cashbook_screen.dart';

AppContext _ctx(String role, [Map<String, dynamic>? permissions]) => AppContext(
  profile: {'role': role},
  business: {'id': 'b1', 'is_active': true},
  features: const {},
  subscription: null,
  permissions: permissions,
);

void main() {
  group('closing difference (D34 example: expected 1,800)', () {
    test('counted 1,750 is short by 50', () {
      expect(varianceLabel(1750 - 1800), contains('Short by'));
      expect(varianceLabel(1750 - 1800), contains('50'));
    });
    test('an exact count matches; more is excess', () {
      expect(varianceLabel(0), 'Matches');
      expect(varianceLabel(20), contains('Excess'));
    });
  });

  test('manual cash kinds cover owner, bank and other movements', () {
    expect(cashEntryKinds.keys, containsAll(['owner_in', 'owner_out', 'bank_deposit', 'bank_withdrawal']));
  });

  test('only the cash permission (or owner) opens the cashbook', () {
    expect(permissionRedirect('/cashbook', _ctx('owner')), isNull);
    expect(permissionRedirect('/cashbook', _ctx('staff', {'can_manage_cash': true})), isNull);
    expect(permissionRedirect('/cashbook', _ctx('staff', {'can_create_invoice': true})), '/home');
  });
}
