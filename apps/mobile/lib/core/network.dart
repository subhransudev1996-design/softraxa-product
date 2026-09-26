import 'dart:async';
import 'dart:io';

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
      msg.contains('AuthRetryableFetchException');
}
