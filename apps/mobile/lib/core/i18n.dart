import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App languages: code, name in its own script, name in English.
/// English is the source; every other language is a translation file in
/// assets/i18n/<code>.json mapping the English text to its translation.
const appLanguages = <(String, String, String)>[
  ('en', 'English', 'English'),
  ('hi', 'हिन्दी', 'Hindi'),
  ('bn', 'বাংলা', 'Bengali'),
  ('mr', 'मराठी', 'Marathi'),
  ('te', 'తెలుగు', 'Telugu'),
  ('ta', 'தமிழ்', 'Tamil'),
  ('gu', 'ગુજરાતી', 'Gujarati'),
  ('kn', 'ಕನ್ನಡ', 'Kannada'),
  ('or', 'ଓଡ଼ିଆ', 'Odia'),
  ('ml', 'മലയാളം', 'Malayalam'),
  ('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
];

const _kLanguagePrefKey = 'app_language';

String _language = 'en';
Map<String, String> _strings = const {};

/// The language the app is showing now.
String get currentLanguage => _language;

/// The text in the app's language. [en] is the English text exactly as
/// written in the code; anything not translated yet shows in English.
/// Placeholders are written {name} and filled from [args]:
///   t('Bill moved to {name}', {'name': customer})
String t(String en, [Map<String, Object?>? args]) {
  var s = _strings[en] ?? en;
  if (args != null) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}

/// Swaps in a language's translations (English needs none). A missing or
/// broken file leaves the app in English rather than failing.
Future<void> loadLanguage(String code, {AssetBundle? bundle}) async {
  if (code == 'en' || !appLanguages.any((l) => l.$1 == code)) {
    _language = 'en';
    _strings = const {};
    return;
  }
  try {
    final raw = await (bundle ?? rootBundle).loadString('assets/i18n/$code.json');
    final map = (jsonDecode(raw) as Map).map(
      (k, v) => MapEntry(k as String, v as String),
    );
    _strings = {
      for (final e in map.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value,
    };
    _language = code;
  } catch (_) {
    _language = 'en';
    _strings = const {};
  }
}

/// For tests: use these translations directly.
@visibleForTesting
void debugSetTranslations(String code, Map<String, String> strings) {
  _language = code;
  _strings = strings;
}

/// Load the saved language before runApp so the first screen is already
/// in it.
Future<void> loadSavedLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await loadLanguage(prefs.getString(_kLanguagePrefKey) ?? 'en');
  } catch (_) {
    await loadLanguage('en');
  }
}

/// The chosen language. Changing it reloads the translations and rebuilds
/// the whole app (main.dart keys the tree on it, like dark mode).
final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);

class LanguageNotifier extends Notifier<String> {
  @override
  String build() => _language;

  Future<void> set(String code) async {
    await loadLanguage(code);
    state = _language;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLanguagePrefKey, _language);
    } catch (_) {}
  }
}

/// Locales for Flutter's own texts (date picker, copy/paste menu).
List<Locale> get appLocales => [for (final l in appLanguages) Locale(l.$1)];

/// Lets the user pick the app language.
Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final current = ref.read(languageProvider);
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(t('App language')),
      children: [
        for (final l in appLanguages)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, l.$1),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: l.$1 == current
                      ? const Icon(Icons.check, size: 20)
                      : null,
                ),
                Expanded(
                  child: Text(l.$2, style: const TextStyle(fontSize: 16)),
                ),
                if (l.$1 != 'en')
                  Text(l.$3, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    ),
  );
  if (code != null && code != current) {
    await ref.read(languageProvider.notifier).set(code);
  }
}
