import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network.dart';

/// Crash reporting (Sentry). Off unless SENTRY_DSN is set in .env, so dev
/// machines and forks run without it.
///
/// Privacy (LAUNCH_SPECIFICATION, ops): reports carry the shop ID and role
/// only — no customer names, phones, emails or GSTINs. Those are masked in
/// every message before an event leaves the device.
bool get crashReportingEnabled => _enabled;
bool _enabled = false;

/// Starts Sentry (when configured) and runs [appRunner] inside it so
/// uncaught Flutter and async errors are reported.
Future<void> initCrashReporting(AppRunner appRunner) async {
  final dsn = dotenv.env['SENTRY_DSN'] ?? '';
  if (dsn.isEmpty) {
    await appRunner();
    return;
  }
  _enabled = true;
  await SentryFlutter.init((options) {
    options.dsn = dsn;
    final env = dotenv.env['SENTRY_ENVIRONMENT'] ?? '';
    options.environment = env.isNotEmpty
        ? env
        : (kReleaseMode ? 'production' : 'debug');
    options.sendDefaultPii = false;
    options.attachScreenshot = false;
    // print()/debugPrint output can contain bill or customer data.
    options.enablePrintBreadcrumbs = false;
    options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
    options.beforeSend = _beforeSend;
    options.beforeBreadcrumb = _beforeBreadcrumb;
  }, appRunner: appRunner);
}

/// Tags later reports with the signed-in shop, or clears it on logout.
void setCrashReportingShop({String? businessId, String? role}) {
  if (!_enabled) return;
  Sentry.configureScope((scope) {
    if (businessId == null) {
      scope.removeTag('business_id');
      scope.removeTag('role');
    } else {
      scope.setTag('business_id', businessId);
      if (role != null) scope.setTag('role', role);
    }
  });
}

/// Errors that are part of normal use, not bugs: no connection, the
/// server refusing a request (permission, business rule, APPROVAL_REQUIRED,
/// duplicate or invalid data) and sign-in failures.
@visibleForTesting
bool isExpectedError(Object? error) {
  if (error == null) return false;
  if (isNetworkError(error)) return true;
  if (error is AuthException) return true;
  if (error is PostgrestException) {
    final code = error.code ?? '';
    // P0xxx: raised by our SQL functions; 42501: RLS / privilege;
    // 23xxx: constraint violations the user can fix. Anything else
    // (e.g. 42883 missing function) means app and database are out of step.
    return code.startsWith('P0') || code == '42501' || code.startsWith('23');
  }
  return false;
}

final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
final _gstin = RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b');
final _phone = RegExp(r'(\+?91[\s-]?)?\b[6-9]\d{9}\b');

/// Masks personal data in a string sent to Sentry.
@visibleForTesting
String scrubPii(String text) => text
    .replaceAll(_email, '[email]')
    .replaceAll(_gstin, '[gstin]')
    .replaceAll(_phone, '[phone]');

SentryEvent? _beforeSend(SentryEvent event, Hint hint) {
  if (isExpectedError(event.throwable)) return null;
  event.user = null;
  event.request = null;
  final message = event.message;
  if (message != null) {
    message.formatted = scrubPii(message.formatted);
    message.params = null;
  }
  for (final e in event.exceptions ?? const <SentryException>[]) {
    final value = e.value;
    if (value != null) e.value = scrubPii(value);
  }
  return event;
}

Breadcrumb? _beforeBreadcrumb(Breadcrumb? crumb, Hint hint) {
  if (crumb == null) return null;
  final message = crumb.message;
  if (message != null) crumb.message = scrubPii(message);
  final data = crumb.data;
  if (data != null) {
    crumb.data = data.map((key, value) {
      if (value is! String) return MapEntry(key, value);
      // REST query strings hold filter values (names, phones).
      final v = key == 'url' ? value.split('?').first : value;
      return MapEntry(key, scrubPii(v));
    });
  }
  return crumb;
}
