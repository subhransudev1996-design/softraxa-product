import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform.dart';
import 'theme.dart';

const _kThemePrefKey = 'desktop_theme_mode'; // 'light' | 'dark'

/// Whether dark mode is on. Desktop-only feature — on phones this is
/// always false and [DarkModeNotifier.set] is a no-op, so the mobile
/// app keeps its light theme unconditionally.
final darkModeProvider = NotifierProvider<DarkModeNotifier, bool>(
  DarkModeNotifier.new,
);

class DarkModeNotifier extends Notifier<bool> {
  @override
  bool build() => AppColors.isDark;

  Future<void> toggle() => set(!state);

  Future<void> set(bool dark) async {
    if (!isDesktopPlatform) return;
    AppColors.setMode(dark: dark);
    state = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePrefKey, dark ? 'dark' : 'light');
  }
}

/// Load the saved mode before runApp so the first frame is already
/// in the right palette (no light-mode flash on a dark-mode machine).
Future<void> loadSavedThemeMode() async {
  if (!isDesktopPlatform) return;
  final prefs = await SharedPreferences.getInstance();
  AppColors.setMode(dark: prefs.getString(_kThemePrefKey) == 'dark');
}
