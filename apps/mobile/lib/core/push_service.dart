import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase_providers.dart';

/// Fire-and-forget push registration retriggered whenever the app context
/// resolves with a business — watch this from the root widget.
final pushRegistrationProvider = Provider<void>((ref) {
  final ctx = ref.watch(appContextProvider).value;
  if (ctx?.businessId != null) {
    Future.microtask(() => PushService.register(ref));
  }
});

/// FCM push registration — Android only (firebase_messaging has no
/// Windows/Linux backend, and desktop already has the in-app bell; iOS
/// would additionally need an APNs setup this app doesn't have).
///
/// Initialised manually from .env keys instead of google-services.json so
/// the app builds and runs identically with or without a Firebase project:
/// if the FIREBASE_* keys are absent, everything here is a silent no-op.
/// Delivery itself is done by the `push-alerts` Supabase Edge Function,
/// which reads the tokens this registers into `device_tokens`.
class PushService {
  PushService._();

  static bool _registered = false;

  static bool get _configured =>
      (dotenv.env['FIREBASE_API_KEY'] ?? '').isNotEmpty &&
      (dotenv.env['FIREBASE_APP_ID'] ?? '').isNotEmpty &&
      (dotenv.env['FIREBASE_SENDER_ID'] ?? '').isNotEmpty &&
      (dotenv.env['FIREBASE_PROJECT_ID'] ?? '').isNotEmpty;

  /// Idempotent: call whenever the app context is ready (login, refresh) —
  /// only the first successful call per launch does work. Never throws:
  /// push is an enhancement, not a dependency, so any failure (no Play
  /// services, permission denied, offline) just means no push.
  static Future<void> register(Ref ref) async {
    if (_registered || kIsWeb || !Platform.isAndroid || !_configured) return;
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      final userId = ref.read(supabaseProvider).auth.currentUser?.id;
      if (businessId == null || userId == null) return;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: dotenv.env['FIREBASE_API_KEY']!,
            appId: dotenv.env['FIREBASE_APP_ID']!,
            messagingSenderId: dotenv.env['FIREBASE_SENDER_ID']!,
            projectId: dotenv.env['FIREBASE_PROJECT_ID']!,
          ),
        );
      }

      final messaging = FirebaseMessaging.instance;
      // Android 13+ runtime notification permission; a denial just means
      // silent delivery — the token is still registered.
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null) return;

      await _saveToken(ref, token, businessId, userId);
      _registered = true;

      FirebaseMessaging.instance.onTokenRefresh.listen((fresh) {
        _saveToken(ref, fresh, businessId, userId);
      });
    } catch (_) {
      // Missing Play services, network issues, etc — push simply stays off.
    }
  }

  static Future<void> _saveToken(
    Ref ref,
    String token,
    String businessId,
    String userId,
  ) async {
    try {
      await ref.read(supabaseProvider).from('device_tokens').upsert({
        'business_id': businessId,
        'user_id': userId,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (_) {
      // Table missing (migration 0027 not applied) or offline — ignore.
    }
  }
}
