import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestClient;
import 'package:softraxa_inventory/core/network.dart';

void main() {
  final reach = Reachability.instance;
  setUp(reach.reset);
  tearDown(reach.reset);

  test('a failed connection marks the server down; later calls fail at once', () async {
    var calls = 0;
    final client = AppHttpClient(
      inner: MockClient((_) async {
        calls++;
        throw const SocketException('Network is unreachable');
      }),
    );
    await expectLater(
      client.get(Uri.parse('https://x.supabase.co/rest/v1/products')),
      throwsA(isA<SocketException>()),
    );
    expect(reach.isDown, isTrue);

    await expectLater(
      client.get(Uri.parse('https://x.supabase.co/rest/v1/products')),
      throwsA(isA<ServerUnreachable>()),
    );
    expect(calls, 1, reason: 'the second call never went to the network');
    expect(isNetworkError(ServerUnreachable()), isTrue);
  });

  test('a hanging request times out and marks the server down', () async {
    final client = AppHttpClient(
      timeout: const Duration(milliseconds: 50),
      inner: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      client.get(Uri.parse('https://x.supabase.co/rest/v1/rpc/create_invoice')),
      throwsA(isA<TimeoutException>()),
    );
    expect(reach.isDown, isTrue);
  });

  test('a server refusal is not offline', () async {
    final client = AppHttpClient(
      inner: MockClient((_) async => http.Response('{"message":"no"}', 400)),
    );
    final res = await client.get(Uri.parse('https://x.supabase.co/rest/v1/x'));
    expect(res.statusCode, 400);
    expect(reach.isDown, isFalse);
  });

  test('the server answering again marks it up and tells listeners', () async {
    var serverUp = false;
    final client = AppHttpClient(
      inner: MockClient((_) async {
        if (!serverUp) throw const SocketException('no signal');
        return http.Response('{}', 200);
      }),
    );
    reach.setProbe(() => client.probe(Uri.parse('https://x.supabase.co/auth/v1/health')));
    var backs = 0;
    reach.onBackOnline(() => backs++);

    reach.markDown();
    expect(await reach.checkNow(), isFalse);
    expect(backs, 0);

    serverUp = true;
    expect(await reach.checkNow(), isTrue);
    expect(reach.isDown, isFalse);
    expect(backs, 1);

    final res = await client.get(Uri.parse('https://x.supabase.co/rest/v1/x'));
    expect(res.statusCode, 200);
  });

  test('Supabase reads fail at once while down (no 1+2+4 s retries)', () async {
    var calls = 0;
    final client = AppHttpClient(
      inner: MockClient((_) async {
        calls++;
        throw const SocketException('no signal');
      }),
    );
    final db = PostgrestClient('https://x.supabase.co/rest/v1', httpClient: client);
    reach.markDown();
    final watch = Stopwatch()..start();
    await expectLater(
      db.from('products').select(),
      throwsA(isA<ServerUnreachable>()),
    );
    expect(watch.elapsedMilliseconds, lessThan(500));
    expect(calls, 0);
  });

  test('the check repeats on its own while down', () async {
    Reachability.probeEvery = const Duration(milliseconds: 20);
    addTearDown(() => Reachability.probeEvery = const Duration(seconds: 10));
    var probes = 0;
    reach.setProbe(() async => ++probes >= 3);
    final back = Completer<void>();
    reach.onBackOnline(back.complete);
    reach.markDown();
    await back.future.timeout(const Duration(seconds: 2));
    expect(probes, 3);
    expect(reach.isDown, isFalse);
  });
}
