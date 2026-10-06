"""Builds assets/i18n/<code>.json from the translation parts in
tool/i18n_src/<code>_*.json.

  python tool/i18n_build.py          -> builds every language found

Keeps only texts the app really uses (tool/i18n_keys.py), reports parts
whose English key doesn't match any app text (a typo would otherwise be
silently ignored) and translations that lost a {placeholder}.
"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from i18n_keys import keys, I18N  # noqa: E402

SRC = os.path.join(HERE, 'i18n_src')


def main():
    app = set(keys())
    codes = sorted({os.path.basename(p).split('_')[0] for p in glob.glob(os.path.join(SRC, '*_*.json'))})
    ok = True
    for code in codes:
        merged = {}
        for part in sorted(glob.glob(os.path.join(SRC, f'{code}_*.json'))):
            merged.update(json.load(open(part, encoding='utf-8')))
        unknown = [k for k in merged if k not in app]
        lost = [k for k, v in merged.items()
                if set(re.findall(r'\{\w+\}', k)) != set(re.findall(r'\{\w+\}', v))]
        out = {k: merged[k] for k in sorted(merged) if k in app and merged[k].strip()}
        json.dump(out, open(os.path.join(I18N, f'{code}.json'), 'w', encoding='utf-8'),
                  ensure_ascii=False, indent=1, sort_keys=True)
        print(f'{code}: {len(out)}/{len(app)} texts'
              + (f', {len(unknown)} unknown keys' if unknown else '')
              + (f', {len(lost)} lost placeholders' if lost else ''))
        for k in unknown[:10]:
            print('   unknown:', k)
        for k in lost:
            print('   placeholder:', k)
        ok = ok and not lost
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
