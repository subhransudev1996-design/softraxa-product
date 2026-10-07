#!/usr/bin/env python3
"""Builds the starter-product migrations from supabase/seed/master_products/*.txt.

  python supabase/seed/build_master_seed.py          -> writes the migrations
  python supabase/seed/build_master_seed.py --check  -> only checks the files

Each .txt file is one kind of shop:

  # type: grocery
  ## Category name | Unit | HSN | GST        <- defaults for the lines below
  Product name | Brand | Unit | HSN | GST | flag=value ...

After the name every field is optional ("" = use the section's value):
  Brand, Unit, HSN, GST.  Flags: serial=1 (IMEI/serial), pieces=1 (cut
  lengths), warranty=12 (months), bulk=Box:12 (a bigger unit and how many
  of the unit it holds), decimal=1.
A "?" after a GST rate (5?) means "my best knowledge, ask the accountant";
those sections are listed in REVIEW_gst.md.

No prices, ever: the list never holds them.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'master_products')
MIG = os.path.join(os.path.dirname(HERE), 'migrations')

TYPES = {'mobile', 'mobile_repair', 'garment', 'hardware', 'electrical', 'car_workshop',
         'bike_garage', 'other', 'grocery', 'stationery', 'cosmetics'}
# Mirror of master_unit_info() in migration 0066.
UNITS = {'piece', 'kg', 'gram', 'metre', 'litre', 'box', 'dozen', 'set', 'pair', 'packet', 'bag',
         'bundle', 'roll', 'carton', 'bottle', 'can', 'tube', 'sheet', 'rod', 'coil', 'strip', 'unit',
         'number', 'millilitre', 'centimetre', 'millimetre', 'foot', 'inch', 'yard', 'square foot',
         'square metre', 'running foot', 'running metre', 'cubic foot', 'cubic metre', 'quintal',
         'tonne'}
GST = {0, 3, 5, 12, 18, 28, 40}

# Which migration each file goes into (kept small enough to paste).
GROUPS = [
    ('0067_starter_products_stores.sql', 'grocery, stationery and cosmetics shops',
     ['grocery', 'stationery', 'cosmetics']),
    ('0068_starter_products_mobile.sql', 'mobile shops and mobile repair',
     ['mobile', 'mobile_repair']),
    ('0069_starter_products_garment.sql', 'garment shops', ['garment']),
    ('0070_starter_products_hardware.sql', 'hardware shops', ['hardware']),
    ('0071_starter_products_electrical.sql', 'electrical shops', ['electrical']),
    ('0072_starter_products_car_bike.sql', 'car workshops and bike garages',
     ['car_workshop', 'bike_garage']),
]


def name_key(s):
    # same as master_name_key() in 0057
    return re.sub(r'[\s!-/:-@\[-`{-~]+', ' ', s.lower()).strip()


def parse(path):
    typ = os.path.splitext(os.path.basename(path))[0]
    rows, section, review = [], None, []
    for n, raw in enumerate(open(path, encoding='utf-8').read().splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith('# type:'):
            typ = line.split(':', 1)[1].strip()
            continue
        if line.startswith('#') and not line.startswith('##'):
            continue
        parts = [p.strip() for p in line.lstrip('#').split('|')]
        flags = {}
        pos = []
        for p in parts:
            m = re.fullmatch(r'(serial|pieces|warranty|bulk|decimal)=(.+)', p)
            if m:
                flags[m.group(1)] = m.group(2)
            else:
                pos.append(p)
        if line.startswith('##'):
            pos += [''] * (4 - len(pos))
            gst = pos[3]
            if gst.endswith('?'):
                gst = gst[:-1]
                review.append((typ, pos[0], gst))
            section = {'category': pos[0], 'unit': pos[1], 'hsn': pos[2], 'gst': gst, 'flags': flags}
            continue
        if section is None:
            raise SystemExit(f'{path}:{n}: product before any ## section')
        pos += [''] * (5 - len(pos))
        name, brand, unit, hsn, gst = pos[:5]
        if gst.endswith('?'):
            gst = gst[:-1]
            if (typ, section['category'], gst) not in review:
                review.append((typ, section['category'], gst))
        f = dict(section['flags'])
        f.update(flags)
        row = {
            'name': re.sub(r'\s+', ' ', name),
            'brand': brand,
            'category': section['category'],
            'unit_name': unit or section['unit'],
            'hsn_code': hsn or section['hsn'],
            'gst': gst or section['gst'],
            'business_type': typ,
            'flags': f,
            'where': f'{os.path.basename(path)}:{n}',
        }
        rows.append(row)
    return typ, rows, review


def validate(rows):
    seen, problems = {}, []
    for r in rows:
        w = r['where']
        try:
            r['name'].encode('ascii')
        except UnicodeEncodeError:
            problems.append(f'{w}: non-ASCII character in the name "{r["name"]}"')
        if len(name_key(r['name'])) < 3:
            problems.append(f'{w}: name too short "{r["name"]}"')
        k = name_key(r['name'])
        if k in seen:
            problems.append(f'{w}: "{r["name"]}" repeats {seen[k]}')
        seen[k] = w
        if r['business_type'] not in TYPES:
            problems.append(f'{w}: unknown shop type {r["business_type"]}')
        if not r['category']:
            problems.append(f'{w}: no category')
        if r['unit_name'].lower() not in UNITS:
            problems.append(f'{w}: unknown unit "{r["unit_name"]}"')
        if r['hsn_code'] and not re.fullmatch(r'[0-9]{4}([0-9]{2}){0,2}', r['hsn_code']):
            problems.append(f'{w}: bad HSN "{r["hsn_code"]}"')
        try:
            g = float(r['gst'])
        except ValueError:
            problems.append(f'{w}: GST missing or not a number for "{r["name"]}"')
            continue
        if g not in GST:
            problems.append(f'{w}: unusual GST rate {g}')
        r['gst'] = g
        bulk = r['flags'].get('bulk')
        if bulk and not re.fullmatch(r'[A-Za-z ]+:[0-9.]+', bulk):
            problems.append(f'{w}: bulk must look like Box:12')
    return problems


def to_json(r):
    d = {'name': r['name'], 'category': r['category'], 'unit_name': r['unit_name'],
         'gst_rate': int(r['gst']) if float(r['gst']).is_integer() else r['gst'],
         'business_type': r['business_type']}
    if r['brand']:
        d['brand'] = r['brand']
    if r['hsn_code']:
        d['hsn_code'] = r['hsn_code']
    f = r['flags']
    if f.get('serial') == '1':
        d['track_serial'] = True
    if f.get('pieces') == '1':
        d['track_pieces'] = True
    if f.get('warranty'):
        d['warranty_months'] = int(f['warranty'])
    if f.get('decimal') == '1':
        d['allow_decimal'] = True
    if f.get('bulk'):
        unit, factor = f['bulk'].split(':')
        d['secondary_unit_name'] = unit.strip()
        d['conversion_factor'] = float(factor)
    return d


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    check_only = '--check' in sys.argv
    by_type, review, allrows = {}, [], []
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith('.txt'):
            continue
        typ, rows, rev = parse(os.path.join(SRC, fn))
        by_type.setdefault(typ, []).extend(rows)
        review += rev
        allrows += rows
    problems = validate(allrows)
    for t in sorted(by_type):
        print(f'{t:14} {len(by_type[t]):5} products')
    print(f'{"total":14} {len(allrows):5}')
    if problems:
        print('\nPROBLEMS:')
        print('\n'.join(problems[:60]))
        if len(problems) > 60:
            print(f'... and {len(problems) - 60} more')
        sys.exit(1)
    if check_only:
        return

    used = set()
    for fname, label, types in GROUPS:
        rows = [r for t in types for r in by_type.get(t, [])]
        used.update(types)
        body = ',\n'.join('  ' + json.dumps(to_json(r), ensure_ascii=True, separators=(', ', ': '))
                          for r in rows)
        sql = f"""-- ============================================================
-- {fname}
-- Starter products for {label}.
--
-- Fills the master list so a new shop can pick its products instead of
-- typing them (Add product -> search, or "Suggested products"). Names,
-- brands, categories, units, HSN and GST rates only — never prices.
-- Run AFTER 0066. Safe to run again: an entry that is already in the list
-- (same name) is left exactly as it is, so nothing SOFTRAXA has corrected is
-- overwritten. Generated by supabase/seed/build_master_seed.py from
-- supabase/seed/master_products/ — change those files, not this one.
-- ============================================================
select count(*) filter (where r = 'added') as added,
       count(*) filter (where r = 'skipped') as already_there
from (
  select public.master_upsert(e.value, false, false) as r
  from jsonb_array_elements($json$[
{body}
  ]$json$::jsonb) as e
) x;
"""
        with open(os.path.join(MIG, fname), 'w', encoding='utf-8', newline='\n') as f:
            f.write(sql)
        print(f'wrote {fname}: {len(rows)} products, {len(sql) // 1024} KB')
    left = set(by_type) - used
    if left:
        print('NOT IN ANY MIGRATION:', ', '.join(sorted(left)))
        sys.exit(1)

    with open(os.path.join(SRC, 'REVIEW_gst.md'), 'w', encoding='utf-8') as f:
        f.write('# GST rates to confirm with the accountant\n\n'
                'These sections carry my best knowledge of the rates in force after the '
                'September 2025 GST changes, but I am not certain. Check them before the '
                'products go to shops (correct in the admin page: edit, or download the list, '
                'fix the sheet and upload it again).\n\n')
        for typ, cat, gst in review:
            f.write(f'- {typ}: **{cat}** — set to {gst}%\n')
        f.write('\nEverything else was set from rates I am fairly sure of; a quick look by the '
                'accountant over the whole list is still wise. HSN codes are left blank where '
                'the code depends on the exact material.\n')
    print(f'{len(review)} sections to review -> REVIEW_gst.md')


if __name__ == '__main__':
    main()
