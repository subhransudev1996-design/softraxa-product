import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/approvals.dart';
import 'package:softraxa_inventory/core/widgets.dart';
import 'package:softraxa_inventory/features/approvals/approvals_screen.dart';

/// What PostgREST hands the app for a refused sale (migration 0044).
Exception refused(String json) => Exception(
  'PostgrestException(message: APPROVAL_REQUIRED $json, code: P0001, details: null, hint: null)',
);

void main() {
  group('APPROVAL_REQUIRED errors', () {
    test('exceptions are read from the error message', () {
      final ex = approvalExceptions(refused(
        '[{"kind": "overdue", "overdue_amount": 500, "bills": 1, "oldest_due": "2026-08-27", "new_due": 500}]',
      ));
      expect(ex, hasLength(1));
      expect(ex!.single['kind'], 'overdue');
    });

    test('other errors are not approvals', () {
      expect(approvalExceptions(Exception('Invoice not found')), isNull);
    });

    test('friendly message names what needs approval', () {
      final msg = friendlyError(refused(
        '[{"kind": "credit_limit", "limit": 1000, "exposure_after": 1500, "new_due": 1500}]',
      ));
      expect(msg, startsWith('Needs the owner\'s approval'));
      expect(msg, contains('limit'));
    });
  });

  group('describing exceptions', () {
    test('owner sees cost and loss for below-cost lines', () {
      final s = describeException({
        'kind': 'below_cost',
        'loss': 50,
        'lines': [
          {'product_name': 'Mixer', 'quantity': 1, 'price': 250, 'cost': 300},
        ],
      });
      expect(s, contains('cost'));
      expect(s, contains('loss'));
    });

    test('staff without profit permission get no cost (server strips it)', () {
      final s = describeException({
        'kind': 'below_cost',
        'lines': [
          {'product_name': 'Mixer', 'quantity': 1},
        ],
      });
      expect(s, 'Sold below cost: Mixer × 1');
    });

    test('discount over the limit', () {
      expect(
        describeException({'kind': 'discount', 'reduction': 100, 'pct': 10, 'limit_pct': 5}),
        contains('staff limit 5%'),
      );
    });
  });

  test('pending or approved requests past expiry show as expired (PD11)', () {
    final past = DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
    final future = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    expect(effectiveApprovalStatus({'status': 'pending', 'expires_at': past}), 'expired');
    expect(effectiveApprovalStatus({'status': 'approved', 'expires_at': future}), 'approved');
    expect(effectiveApprovalStatus({'status': 'consumed', 'expires_at': past}), 'consumed');
  });

  test('a rejected sale can be loaded back into the cart to revise', () {
    final cart = cartFromSalePayload({
      'discount_amount': 20,
      'items': [
        {
          'product_id': 'p1', 'product_name': 'Mixer', 'quantity': 2,
          'unit_price': 250, 'gst_rate': 0, 'discount_amount': 0,
        },
      ],
    });
    expect(cart.lines, hasLength(1));
    expect(cart.lines.single.price, 250);
    expect(cart.lines.single.qty, 2);
    expect(cart.billDiscount, 20);
  });
}
