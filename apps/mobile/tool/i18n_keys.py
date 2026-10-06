"""Lists every English text the app passes to t('...').

  python tool/i18n_keys.py            -> prints the count, writes tool/i18n_keys.json
  python tool/i18n_keys.py --check    -> lists texts each language file is missing

assets/i18n/<code>.json maps the English text (exactly as written in the
code, after Dart escapes) to its translation. Untranslated texts show in
English, so a missing entry is never an error — this only reports gaps.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
LIB = os.path.join(APP, 'lib')
I18N = os.path.join(APP, 'assets', 'i18n')

# t('...') with a plain single-quoted literal (adjacent literals aren't used).
CALL = re.compile(r"\bt\(\s*'((?:[^'\\\n]|\\.)*)'")


def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', "'": "'", '"': '"', '\\': '\\', '$': '$'}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def keys():
    found = set()
    for dp, _, files in os.walk(LIB):
        for fn in files:
            if fn.endswith('.dart'):
                src = open(os.path.join(dp, fn), encoding='utf-8').read()
                for m in CALL.finditer(src):
                    found.add(unescape(m.group(1)))
    return sorted(found)


if __name__ == '__main__':
    ks = keys()
    if '--check' in sys.argv:
        for fn in sorted(os.listdir(I18N)):
            if not fn.endswith('.json') or fn.startswith('.'):
                continue
            data = json.load(open(os.path.join(I18N, fn), encoding='utf-8'))
            missing = [k for k in ks if not data.get(k)]
            bad = [k for k, v in data.items()
                   if v and set(re.findall(r'\{\w+\}', k)) != set(re.findall(r'\{\w+\}', v))]
            print(f'{fn}: {len(ks) - len(missing)}/{len(ks)} translated'
                  f'{", placeholder mismatch: " + str(len(bad)) if bad else ""}')
    else:
        json.dump(ks, open(os.path.join(HERE, 'i18n_keys.json'), 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=0)
        print(len(ks), 'texts')
