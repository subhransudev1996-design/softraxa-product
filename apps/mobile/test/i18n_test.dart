import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/i18n.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, String> files;
  @override
  Future<ByteData> load(String key) async {
    final s = files[key];
    if (s == null) throw StateError('missing $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(s)));
  }
}

void main() {
  tearDown(() => loadLanguage('en'));

  test('English is the text itself; placeholders are filled', () {
    expect(t('New Bill'), 'New Bill');
    expect(t('Bill moved to {name}', {'name': 'Ramesh'}), 'Bill moved to Ramesh');
  });

  test('a loaded language translates; untranslated text stays English', () async {
    await loadLanguage(
      'or',
      bundle: _Bundle({
        'assets/i18n/or.json': jsonEncode({
          'New Bill': 'ନୂଆ ବିଲ୍',
          'Bill moved to {name}': 'ବିଲ୍ {name} ଙ୍କୁ ଗଲା',
          'Empty': '',
        }),
      }),
    );
    expect(currentLanguage, 'or');
    expect(t('New Bill'), 'ନୂଆ ବିଲ୍');
    expect(t('Bill moved to {name}', {'name': 'Ramesh'}), 'ବିଲ୍ Ramesh ଙ୍କୁ ଗଲା');
    expect(t('Empty'), 'Empty'); // blank translation → English
    expect(t('Not translated yet'), 'Not translated yet');
  });

  test('a missing or broken file leaves the app in English', () async {
    await loadLanguage('ta', bundle: _Bundle({}));
    expect(currentLanguage, 'en');
    await loadLanguage('hi', bundle: _Bundle({'assets/i18n/hi.json': '{oops'}));
    expect(currentLanguage, 'en');
    await loadLanguage('xx');
    expect(currentLanguage, 'en');
  });

  test('every language has a name and a Flutter locale', () {
    expect(appLanguages.length, 11);
    expect(appLocales.map((l) => l.languageCode), contains('or'));
  });
}
