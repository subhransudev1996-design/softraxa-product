import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/platform.dart';
import 'core/branding.dart';
import 'core/crash_reporting.dart';
import 'core/desktop_titlebar.dart';
import 'core/i18n.dart';
import 'core/network.dart';
import 'core/push_service.dart';
import 'core/router.dart';
import 'core/supabase_providers.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'core/windows_data_move.dart';
import 'features/app_lock/app_lock.dart';
import 'features/app_lock/lock_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/offline/offline_service.dart';
import 'features/pos/pos_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 1.0.15 renamed the Windows program's company; bring its data along.
  await moveOldWindowsData();
  await dotenv.load(fileName: '.env');
  // Everything after .env loads runs inside Sentry (when SENTRY_DSN is
  // set) so start-up failures are reported too.
  await initCrashReporting(_start);
}

Future<void> _start() async {
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  // Time limits and fail-fast while the server is out of reach, so offline
  // billing doesn't wait on hanging requests (core/network.dart).
  final httpClient = AppHttpClient();
  Reachability.instance.setProbe(
    () => httpClient.probe(Uri.parse('$supabaseUrl/auth/v1/health')),
  );
  try {
    final net = await Connectivity().checkConnectivity();
    if (net.contains(ConnectivityResult.none)) Reachability.instance.markDown();
  } catch (_) {}
  await Supabase.initialize(
    url: supabaseUrl,
    httpClient: httpClient,
    // The legacy anon key is accepted here too; SUPABASE_ANON_KEY is kept
    // as a fallback so existing .env files keep working.
    publishableKey:
        dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ??
        dotenv.env['SUPABASE_ANON_KEY'] ??
        '',
    // Implicit flow: password-reset and signup links carry the session in
    // the link itself, so the website can finish them in any browser. With
    // the default (PKCE) a link only works on the phone that asked for it,
    // and opening it in the browser failed.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );
  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1300, 820),
      minimumSize: Size(1040, 680),
      center: true,
      title: kAppName, // taskbar / Alt-Tab label only
      // Native caption bar is hidden — DesktopTitleBar (in MaterialApp's
      // builder below) replaces it with in-app chrome.
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  await loadSavedThemeMode(); // desktop-only; no-op on phones
  await loadSavedLanguage();
  await loadAppLock(); // locked from the first frame when it is on
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  late final AppLifecycleListener _lifecycle;
  Timer? _contextTimer;
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    // Start the offline service (connectivity listener + pending bill sync).
    final offline = ref.read(offlineServiceProvider);
    Future.microtask(offline.syncPendingBills);

    // Server reachable again (even on the same mobile data, with no
    // network change): send the offline bills and refresh what was loaded
    // from the device while offline.
    Reachability.instance.onBackOnline(() {
      offline.syncPendingBills();
      ref.read(appContextProvider.notifier).refreshSilently();
      ref.invalidate(pricingRightsProvider);
      ref.invalidate(posProductsProvider);
    });
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        Reachability.instance.markDown();
      } else if (Reachability.instance.isDown) {
        Reachability.instance.checkNow();
      }
    });

    // Changes made in the admin panel (renewal, suspension, plan, features)
    // reach an app that stays open: on return to the app and every 30 min.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final notifier = ref.read(appContextProvider.notifier);
        notifier.checkSessionStillActive();
        notifier.refreshSilently(ifOlderThan: const Duration(minutes: 2));
      },
    );
    // A staff login the owner signed out ends within about a minute.
    _sessionTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => ref.read(appContextProvider.notifier).checkSessionStillActive(),
    );
    _contextTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => ref.read(appContextProvider.notifier).refreshSilently(),
    );

    // When the user opens a password-reset link, Supabase fires a
    // passwordRecovery event — prompt them to set a new password.
    _authSub = ref.read(supabaseProvider).auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.signedOut) {
        ref.read(appLockProvider.notifier).onSignedOut();
      }
      if (state.event == AuthChangeEvent.signedIn) {
        signedOutByOwner.value = false;
      }
      if (state.event == AuthChangeEvent.passwordRecovery) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) showSetNewPasswordDialog(ctx, ref);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _netSub?.cancel();
    _lifecycle.dispose();
    _contextTimer?.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Registers this device's FCM token once login + business context are
    // ready (no-op on desktop or when FIREBASE_* env keys are absent).
    ref.watch(pushRegistrationProvider);
    // Crash reports carry the shop ID and role (nothing else about the user).
    ref.listen(appContextProvider, (_, next) {
      final ctx = next.value;
      setCrashReportingShop(businessId: ctx?.businessId, role: ctx?.role);
    });
    final router = ref.watch(routerProvider);
    final dark = ref.watch(darkModeProvider);
    final language = ref.watch(languageProvider);
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark: dark, desktop: isDesktopPlatform),
      routerConfig: router,
      // Flutter's own texts (date picker, copy/paste) in the app language;
      // our texts come from t() (core/i18n.dart).
      locale: Locale(language),
      supportedLocales: appLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // AppColors' mode-dependent neutrals are plain static fields — no
      // widget depends on them reactively — so a theme toggle must force
      // the whole tree to rebuild. Keying the subtree on the mode does
      // exactly that (route state lives in GoRouter and survives).
      builder: (context, child) {
        // The app lock covers the screens (not the PC title bar, so the
        // window can still be moved or closed).
        final content = AppLockGate(child: child ?? const SizedBox());
        return KeyedSubtree(
          // Language too: t() is read at build time, so a new language
          // needs every screen rebuilt.
          key: ValueKey('$dark-$language'),
          child: isDesktopPlatform
              ? Column(
                  children: [
                    const DesktopTitleBar(),
                    Expanded(child: content),
                  ],
                )
              : content,
        );
      },
    );
  }
}
