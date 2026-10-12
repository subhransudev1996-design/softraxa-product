import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// True when [error] means "couldn't reach the server" (so an offline
/// fallback applies) rather than "the server refused the request" (which
/// must be shown to the user and never silently queued).
bool isNetworkError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  final msg = error.toString();
  return msg.contains('SocketException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('TimeoutException') ||
      msg.contains('ClientException') ||
      msg.contains('Connection refused') ||
      msg.contains('Connection closed') ||
      msg.contains('Connection reset') ||
      msg.contains('Network is unreachable') ||
      msg.contains('AuthRetryableFetchException') ||
      msg.contains(ServerUnreachable.marker);
}

/// Thrown at once, without trying, while the server is known to be out of
/// reach — so screens fall back to the device's saved data immediately
/// instead of each waiting out its own timeout. Deliberately an [Error],
/// not an Exception: Supabase's data library retries every Exception on a
/// read three times (waiting 1 + 2 + 4 seconds) but lets Errors through.
/// The app's offline fallbacks catch everything, and [isNetworkError]
/// recognises it.
class ServerUnreachable extends Error {
  ServerUnreachable([this.uri]);
  final Uri? uri;
  static const marker = 'Server unreachable';
  @override
  String toString() => '$marker (offline)';
}

/// Whether the server can be reached right now.
///
/// A shop's "offline" is mostly mobile data that is on but has no signal:
/// requests then hang instead of failing. So the first request that fails
/// or times out marks the server down; while down, requests fail at once
/// and a light check runs every few seconds; the first answer marks it up
/// again and tells [onBackOnline] listeners (offline bills sync then, even
/// though the phone never switched networks).
class Reachability {
  Reachability._();
  static final instance = Reachability._();

  /// How often the server is checked while down.
  static Duration probeEvery = const Duration(seconds: 10);

  final ValueNotifier<bool> down = ValueNotifier(false);
  final List<VoidCallback> _onBack = [];
  Timer? _timer;
  Future<bool> Function()? _probe;
  bool _probing = false;

  /// Registers how to check the server (set up with the HTTP client).
  void setProbe(Future<bool> Function() probe) => _probe = probe;

  /// Called once each time the server becomes reachable again.
  void onBackOnline(VoidCallback listener) => _onBack.add(listener);

  bool get isDown => down.value;

  void markDown() {
    if (down.value) return;
    down.value = true;
    _timer?.cancel();
    _timer = Timer.periodic(probeEvery, (_) => checkNow());
  }

  void markUp() {
    if (!down.value) return;
    down.value = false;
    _timer?.cancel();
    _timer = null;
    for (final l in List.of(_onBack)) {
      try {
        l();
      } catch (_) {}
    }
  }

  /// Checks the server now (also on a network change); true if reachable.
  Future<bool> checkNow() async {
    final probe = _probe;
    if (probe == null || _probing) return !down.value;
    _probing = true;
    try {
      final ok = await probe();
      ok ? markUp() : markDown();
      return ok;
    } finally {
      _probing = false;
    }
  }

  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    down.value = false;
    _onBack.clear();
    _probe = null;
    _probing = false;
  }
}

/// Testing aid, compiled in only with
/// `--dart-define=SIMULATE_NO_SIGNAL=<file path>`: while that file exists,
/// every request hangs like a phone with data on and no signal.
const _noSignalFile = String.fromEnvironment('SIMULATE_NO_SIGNAL');
bool get _simulatedNoSignal =>
    _noSignalFile.isNotEmpty && File(_noSignalFile).existsSync();

/// The app's HTTP client for Supabase: every request gets a time limit,
/// a failure to connect marks the server down, and while it is down
/// requests fail at once (see [Reachability]).
class AppHttpClient extends http.BaseClient {
  AppHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 30),
    this.uploadTimeout = const Duration(minutes: 2),
    Reachability? reachability,
  }) : _inner = inner ?? http.Client(),
       _reach = reachability ?? Reachability.instance;

  final http.Client _inner;
  final Reachability _reach;

  /// Until the server starts answering (headers) for normal calls.
  final Duration timeout;

  /// For file uploads/downloads (logos, product photos).
  final Duration uploadTimeout;

  /// Asks the server for anything at all; any HTTP answer means reachable.
  Future<bool> probe(Uri url) async {
    try {
      final res =
          await (_simulatedNoSignal
                  ? Completer<http.StreamedResponse>().future
                  : _inner.send(http.Request('GET', url)))
              .timeout(const Duration(seconds: 6));
      await res.stream.drain<void>();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_reach.isDown) throw ServerUnreachable(request.url);
    final limit = request.url.path.contains('/storage/v1/')
        ? uploadTimeout
        : timeout;
    try {
      return await (_simulatedNoSignal
              ? Completer<http.StreamedResponse>().future
              : _inner.send(request))
          .timeout(limit);
    } catch (e) {
      if (isNetworkError(e)) _reach.markDown();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

/// For calls on the billing path (product search, customer search, prices):
/// a short time limit, since the device's saved data is the fallback, and
/// a network failure marks the server down so the next calls don't wait.
Future<T> quickCall<T>(
  Future<T> call, {
  Duration limit = const Duration(seconds: 6),
}) async {
  try {
    return await call.timeout(limit);
  } catch (e) {
    if (isNetworkError(e)) Reachability.instance.markDown();
    rethrow;
  }
}
