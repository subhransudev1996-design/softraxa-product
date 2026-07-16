import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/platform.dart';
import 'core/branding.dart';
import 'core/desktop_titlebar.dart';
import 'core/push_service.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'features/offline/offline_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
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
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  @override
  void initState() {
    super.initState();
    // Start the offline service (connectivity listener + pending bill sync).
    final offline = ref.read(offlineServiceProvider);
    Future.microtask(offline.syncPendingBills);
  }

  @override
  Widget build(BuildContext context) {
    // Registers this device's FCM token once login + business context are
    // ready (no-op on desktop or when FIREBASE_* env keys are absent).
    ref.watch(pushRegistrationProvider);
    final router = ref.watch(routerProvider);
    final dark = ref.watch(darkModeProvider);
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark: dark),
      routerConfig: router,
      // AppColors' mode-dependent neutrals are plain static fields — no
      // widget depends on them reactively — so a theme toggle must force
      // the whole tree to rebuild. Keying the subtree on the mode does
      // exactly that (route state lives in GoRouter and survives).
      builder: (context, child) {
        final content = child ?? const SizedBox();
        return KeyedSubtree(
          key: ValueKey(dark),
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
