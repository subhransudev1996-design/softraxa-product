import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/network.dart';

void main() {
  group('isNetworkError — only unreachable-server errors allow offline fallback', () {
    test('socket, timeout and DNS failures are network errors', () {
      expect(isNetworkError(const SocketException('no route')), isTrue);
      expect(isNetworkError(TimeoutException('slow')), isTrue);
      expect(isNetworkError(Exception('Failed host lookup: x.supabase.co')), isTrue);
      expect(isNetworkError(Exception('ClientException: Connection closed')), isTrue);
    });

    test('server refusals are not network errors, so they are never queued', () {
      expect(
        isNetworkError(Exception(
          'PostgrestException(message: You don\'t have permission to create bills, code: 42501)',
        )),
        isFalse,
      );
      expect(
        isNetworkError(Exception(
          'PostgrestException(message: Monthly invoice limit (100) reached for your plan)',
        )),
        isFalse,
      );
      expect(isNetworkError(Exception('Serial 123 is already sold')), isFalse);
    });
  });
}
