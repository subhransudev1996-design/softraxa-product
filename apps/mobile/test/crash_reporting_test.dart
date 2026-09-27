import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/crash_reporting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('isExpectedError', () {
    test('drops offline and server refusals', () {
      expect(isExpectedError(const SocketException('no route')), isTrue);
      expect(
        isExpectedError(
          const PostgrestException(
            message: 'APPROVAL_REQUIRED []',
            code: 'P0001',
          ),
        ),
        isTrue,
      );
      expect(
        isExpectedError(
          const PostgrestException(message: 'rls', code: '42501'),
        ),
        isTrue,
      );
      expect(
        isExpectedError(
          const PostgrestException(message: 'dup', code: '23505'),
        ),
        isTrue,
      );
      expect(isExpectedError(const AuthException('Invalid login')), isTrue);
    });

    test('keeps real bugs', () {
      expect(isExpectedError(StateError('boom')), isFalse);
      expect(
        isExpectedError(
          const PostgrestException(message: 'no function', code: '42883'),
        ),
        isFalse,
      );
      expect(isExpectedError(null), isFalse);
    });
  });

  test('scrubPii masks phones, emails and GSTINs', () {
    final out = scrubPii(
      'Ramesh +91 9876543210 ramesh@shop.in GSTIN 27AAPFU0939F1ZV bill 1234',
    );
    expect(out, isNot(contains('9876543210')));
    expect(out, isNot(contains('ramesh@shop.in')));
    expect(out, isNot(contains('27AAPFU0939F1ZV')));
    expect(out, contains('[phone]'));
    expect(out, contains('[email]'));
    expect(out, contains('[gstin]'));
    expect(out, contains('bill 1234'));
  });
}
