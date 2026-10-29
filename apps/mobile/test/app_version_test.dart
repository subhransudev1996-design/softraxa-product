import 'package:flutter_test/flutter_test.dart';
import 'package:dukania/core/app_version.dart';

void main() {
  test('version shows with its build number', () {
    expect(formatAppVersion('1.0.7', '8'), '1.0.7 (8)');
    expect(formatAppVersion('1.0.7', ''), '1.0.7');
    expect(formatAppVersion('1.0.7', '1.0.7'), '1.0.7');
  });
}
