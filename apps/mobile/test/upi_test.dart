import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/upi.dart';

void main() {
  test('the UPI link carries the payee and the exact amount', () {
    final link = upiPayLink(
      upiId: ' sharmastore@okaxis ',
      payee: 'Sharma General Store',
      amount: 1249.5,
      note: 'Sharma General Store',
    );
    final uri = Uri.parse(link);
    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters['pa'], 'sharmastore@okaxis');
    expect(uri.queryParameters['pn'], 'Sharma General Store');
    expect(uri.queryParameters['am'], '1249.50');
    expect(uri.queryParameters['cu'], 'INR');
    expect(uri.queryParameters['tn'], 'Sharma General Store');
  });

  test('no note leaves tn out', () {
    final uri = Uri.parse(
      upiPayLink(upiId: 'a@ybl', payee: 'A', amount: 10),
    );
    expect(uri.queryParameters.containsKey('tn'), isFalse);
    expect(uri.queryParameters['am'], '10.00');
  });

  test('UPI ID format', () {
    expect(isValidUpiId('sharmastore@okaxis'), isTrue);
    expect(isValidUpiId('98765.43210@ybl'), isTrue);
    expect(isValidUpiId('sharmastore'), isFalse);
    expect(isValidUpiId('@okaxis'), isFalse);
  });
}
