/// GST filing from the shop's own bills: the GSTR-1 file the GST portal
/// accepts (Returns → GSTR-1 → Prepare Offline → Upload), the GSTR-3B
/// set-off (which credit pays which tax, and the cash left to pay), and
/// matching the portal's GSTR-2B against the purchases entered.
///
/// The JSON follows the portal's GSTR-1 format: sections b2b, b2cl, b2cs,
/// nil, cdnr, cdnur, hsn (hsn_b2b / hsn_b2c from May 2025) and doc_issue;
/// dates day-first (dd-mm-yyyy), places of supply as the 2-digit state
/// code, amounts to the paisa, credit notes unsigned. Kept apart from the
/// screens so it's tested on its own.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import 'gst_export.dart';

double _r2(Object? v) => (toDouble(v) * 100).roundToDouble() / 100;

String _portalDate(Object? v) {
  final d = v is DateTime ? v : DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : DateFormat('dd-MM-yyyy').format(d);
}

String _pos(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.length >= 2 ? s.substring(0, 2) : s;
}

/// The return period as the portal writes it: "092026".
String gstPeriod(DateTime month) => DateFormat('MMyyyy').format(month);

/// One line's tax amounts as the portal lists them: IGST for an
/// inter-state supply, CGST + SGST within the state.
Map<String, dynamic> _itemDetails(
  Map<String, dynamic> r, {
  required bool inter,
}) => {
  'txval': _r2(r['taxable_value']),
  'rt': toDouble(r['gst_rate']),
  if (inter) 'iamt': _r2(r['igst_amount']),
  if (!inter) 'camt': _r2(r['cgst_amount']),
  if (!inter) 'samt': _r2(r['sgst_amount']),
  'csamt': _r2(r['cess_amount']),
};

bool _isInter(Map<String, dynamic> r) {
  if (r['inter'] is bool) return r['inter'] as bool;
  return toDouble(r['igst_amount']).abs() > 0 &&
      toDouble(r['cgst_amount']) == 0 &&
      toDouble(r['sgst_amount']) == 0;
}

/// Rows grouped by [key], in first-seen order.
Map<String, List<Map<String, dynamic>>> _groupBy(
  List<Map<String, dynamic>> rows,
  String Function(Map<String, dynamic>) key,
) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    out.putIfAbsent(key(r), () => []).add(r);
  }
  return out;
}

List<Map<String, dynamic>> _items(
  List<Map<String, dynamic>> rows, {
  required bool inter,
}) => [
  for (var i = 0; i < rows.length; i++)
    {'num': i + 1, 'itm_det': _itemDetails(rows[i], inter: inter)},
];

/// The GSTR-1 file for [fp] ("MMYYYY") from the app's GSTR-1 data.
/// [iffOnly]: the Invoice Furnishing Facility of a quarterly filer's first
/// two months — B2B invoices and their credit notes only.
Map<String, dynamic> buildGstr1Json(
  GstReturnData data, {
  required String gstin,
  required String fp,
  bool iffOnly = false,
}) {
  final out = <String, dynamic>{'gstin': gstin.trim().toUpperCase(), 'fp': fp};

  // B2B — by buyer, then invoice, one item per rate.
  final b2b = <Map<String, dynamic>>[];
  for (final buyer in _groupBy(
    data.section('b2b'),
    (r) => '${r['gstin']}',
  ).entries) {
    final invoices = <Map<String, dynamic>>[];
    for (final inv in _groupBy(
      buyer.value,
      (r) => '${r['invoice_no']}',
    ).entries) {
      final first = inv.value.first;
      final inter = _isInter(first);
      invoices.add({
        'inum': '${first['invoice_no']}',
        'idt': _portalDate(first['invoice_date']),
        'val': _r2(first['invoice_value']),
        'pos': _pos(first['place_of_supply']),
        'rchrg': 'N',
        'inv_typ': 'R',
        'itms': _items(inv.value, inter: inter),
      });
    }
    b2b.add({'ctin': buyer.key.toUpperCase(), 'inv': invoices});
  }
  if (b2b.isNotEmpty) out['b2b'] = b2b;

  // Credit notes to registered buyers.
  final cdnr = <Map<String, dynamic>>[];
  for (final buyer in _groupBy(
    data.section('cdnr'),
    (r) => '${r['gstin']}',
  ).entries) {
    final notes = <Map<String, dynamic>>[];
    for (final note in _groupBy(
      buyer.value,
      (r) => '${r['note_no']}',
    ).entries) {
      final first = note.value.first;
      final inter = _isInter(first);
      notes.add({
        'ntty': first['note_type'] ?? 'C',
        'nt_num': '${first['note_no']}',
        'nt_dt': _portalDate(first['note_date']),
        'val': _r2(toDouble(first['note_value']).abs()),
        'pos': _pos(first['place_of_supply']),
        'rchrg': 'N',
        'inv_typ': 'R',
        'itms': _items(note.value, inter: inter),
      });
    }
    cdnr.add({'ctin': buyer.key.toUpperCase(), 'nt': notes});
  }
  if (cdnr.isNotEmpty) out['cdnr'] = cdnr;

  if (iffOnly) return out;

  // B2C large — inter-state, by state.
  final b2cl = <Map<String, dynamic>>[];
  for (final state in _groupBy(
    data.section('b2cl'),
    (r) => _pos(r['place_of_supply']),
  ).entries) {
    final invoices = <Map<String, dynamic>>[];
    for (final inv in _groupBy(
      state.value,
      (r) => '${r['invoice_no']}',
    ).entries) {
      final first = inv.value.first;
      invoices.add({
        'inum': '${first['invoice_no']}',
        'idt': _portalDate(first['invoice_date']),
        'val': _r2(first['invoice_value']),
        'itms': _items(inv.value, inter: true),
      });
    }
    b2cl.add({'pos': state.key, 'inv': invoices});
  }
  if (b2cl.isNotEmpty) out['b2cl'] = b2cl;

  // B2C small — one row per state and rate.
  final b2cs = <Map<String, dynamic>>[];
  for (final r in data.section('b2cs')) {
    if (_r2(r['taxable_value']) == 0) continue;
    final inter = r['supply_type'] == 'INTER';
    b2cs.add({
      'sply_ty': inter ? 'INTER' : 'INTRA',
      'rt': toDouble(r['gst_rate']),
      'typ': 'OE',
      'pos': _pos(r['place_of_supply']),
      'txval': _r2(r['taxable_value']),
      if (inter) 'iamt': _r2(r['igst_amount']),
      if (!inter) 'camt': _r2(r['cgst_amount']),
      if (!inter) 'samt': _r2(r['sgst_amount']),
      'csamt': _r2(r['cess_amount']),
    });
  }
  if (b2cs.isNotEmpty) out['b2cs'] = b2cs;

  // Table 8 — nil-rated, exempt, non-GST.
  final nil = [
    for (final r in data.section('nil'))
      if (_r2(r['nil_amount']) != 0 ||
          _r2(r['exempt_amount']) != 0 ||
          _r2(r['non_gst_amount']) != 0)
        {
          'sply_ty': '${r['supply_type']}',
          'nil_amt': math.max(0.0, _r2(r['nil_amount'])),
          'expt_amt': math.max(0.0, _r2(r['exempt_amount'])),
          'ngsup_amt': math.max(0.0, _r2(r['non_gst_amount'])),
        },
  ];
  if (nil.isNotEmpty) out['nil'] = {'inv': nil};

  // Credit notes for B2C large invoices.
  final cdnur = <Map<String, dynamic>>[];
  for (final note in _groupBy(
    data.section('cdnur'),
    (r) => '${r['note_no']}',
  ).entries) {
    final first = note.value.first;
    cdnur.add({
      'typ': first['ur_type'] ?? 'B2CL',
      'ntty': first['note_type'] ?? 'C',
      'nt_num': '${first['note_no']}',
      'nt_dt': _portalDate(first['note_date']),
      'val': _r2(toDouble(first['note_value']).abs()),
      'pos': _pos(first['place_of_supply']),
      'itms': _items(note.value, inter: true),
    });
  }
  if (cdnur.isNotEmpty) out['cdnur'] = cdnur;

  // Table 12 — HSN summary, B2B and B2C apart from May 2025.
  List<Map<String, dynamic>> hsnRows(String supply) {
    final rows = <Map<String, dynamic>>[];
    for (final r in data.hsn(supply)) {
      final code = '${r['hsn_code'] ?? ''}'.trim();
      if (code.isEmpty) continue; // can't be reported without its code
      final services = code.startsWith('99');
      final desc = '${r['description'] ?? ''}'.trim();
      rows.add({
        'num': rows.length + 1,
        'hsn_sc': code,
        if (desc.isNotEmpty)
          'desc': desc.length > 30 ? desc.substring(0, 30) : desc,
        'uqc': services ? 'NA' : '${r['uqc'] ?? 'OTH'}',
        'qty': services ? 0 : math.max(0.0, _r2(r['quantity'])),
        'rt': toDouble(r['gst_rate']),
        'txval': _r2(r['taxable_value']),
        'iamt': _r2(r['igst_amount']),
        'camt': _r2(r['cgst_amount']),
        'samt': _r2(r['sgst_amount']),
        'csamt': _r2(r['cess_amount']),
      });
    }
    return rows;
  }

  final hsnB2b = hsnRows('B2B'), hsnB2c = hsnRows('B2C');
  final split =
      int.parse(fp.substring(2)) * 100 + int.parse(fp.substring(0, 2)) >=
      202505;
  if (split) {
    if (hsnB2b.isNotEmpty || hsnB2c.isNotEmpty) {
      out['hsn'] = {
        if (hsnB2b.isNotEmpty) 'hsn_b2b': hsnB2b,
        if (hsnB2c.isNotEmpty) 'hsn_b2c': hsnB2c,
      };
    }
  } else {
    final all = [...hsnB2b, ...hsnB2c];
    for (var i = 0; i < all.length; i++) {
      all[i]['num'] = i + 1;
    }
    if (all.isNotEmpty) out['hsn'] = {'data': all};
  }

  // Table 13 — documents issued, by kind and series.
  final docs = _groupBy(data.section('docs'), (r) => '${r['doc_num']}');
  final docDet = [
    for (final kind in docs.entries)
      {
        'doc_num': int.tryParse(kind.key) ?? 1,
        'docs': [
          for (var i = 0; i < kind.value.length; i++)
            {
              'num': i + 1,
              'from': '${kind.value[i]['from_no']}',
              'to': '${kind.value[i]['to_no']}',
              'totnum': toDouble(kind.value[i]['total']).round(),
              'cancel': toDouble(kind.value[i]['cancelled']).round(),
              'net_issue':
                  toDouble(kind.value[i]['total']).round() -
                  toDouble(kind.value[i]['cancelled']).round(),
            },
        ],
      },
  ];
  if (docDet.isNotEmpty) out['doc_issue'] = {'doc_det': docDet};

  return out;
}

/// The file's text, as the portal reads it.
String gstr1JsonText(Map<String, dynamic> json) => jsonEncode(json);

/// HSN summary rows left out of the file because they have no HSN code.
int hsnRowsWithoutCode(GstReturnData data) => [
  ...data.hsn('B2B'),
  ...data.hsn('B2C'),
].where((r) => '${r['hsn_code'] ?? ''}'.trim().isEmpty).length;

// ---------------------------------------------------------------------------
// GSTR-3B set-off
// ---------------------------------------------------------------------------

/// IGST, CGST and SGST amounts.
class TaxHeads {
  const TaxHeads(this.igst, this.cgst, this.sgst);

  final double igst, cgst, sgst;

  double get total => igst + cgst + sgst;

  @override
  String toString() => 'IGST $igst CGST $cgst SGST $sgst';
}

/// What the credit pays and what is left: [cash] to pay, [carryForward]
/// credit left for next month, [used] credit used per head of credit.
class SetOffResult {
  const SetOffResult({
    required this.cash,
    required this.carryForward,
    required this.used,
  });

  final TaxHeads cash;
  final TaxHeads carryForward;
  final TaxHeads used;
}

/// Pays this month's tax from the input tax credit the way the law orders
/// it (sections 49 / 49A, rule 88A): IGST credit first — against IGST,
/// then CGST and SGST (where they would otherwise need cash first) — then
/// CGST credit against CGST, then IGST; SGST credit against SGST, then
/// IGST. CGST credit never pays SGST, nor SGST credit CGST. Negative tax
/// (more credit notes than sales) counts as none.
SetOffResult gstSetOff(TaxHeads liability, TaxHeads credit) {
  double p(double v) => v < 0 ? 0 : v;
  var li = p(liability.igst), lc = p(liability.cgst), ls = p(liability.sgst);
  var ci = p(credit.igst), cc = p(credit.cgst), cs = p(credit.sgst);
  final ci0 = ci, cc0 = cc, cs0 = cs;

  // IGST credit: IGST first.
  var u = math.min(ci, li);
  li -= u;
  ci -= u;
  // Then CGST / SGST, first where their own credit falls short.
  var needC = math.max(0.0, lc - cc), needS = math.max(0.0, ls - cs);
  if (ci > 0 && needC + needS > 0) {
    final toC = needC + needS <= ci ? needC : ci * needC / (needC + needS);
    final toS = needC + needS <= ci ? needS : ci - toC;
    lc -= toC;
    ls -= toS;
    ci -= toC + toS;
  }
  // Any IGST credit left must still be used before CGST / SGST credit.
  u = math.min(ci, lc);
  lc -= u;
  ci -= u;
  u = math.min(ci, ls);
  ls -= u;
  ci -= u;
  // CGST credit: CGST, then IGST.
  u = math.min(cc, lc);
  lc -= u;
  cc -= u;
  u = math.min(cc, li);
  li -= u;
  cc -= u;
  // SGST credit: SGST, then IGST.
  u = math.min(cs, ls);
  ls -= u;
  cs -= u;
  u = math.min(cs, li);
  li -= u;
  cs -= u;

  double r(double v) => (v * 100).roundToDouble() / 100;
  return SetOffResult(
    cash: TaxHeads(r(li), r(lc), r(ls)),
    carryForward: TaxHeads(r(ci), r(cc), r(cs)),
    used: TaxHeads(r(ci0 - ci), r(cc0 - cc), r(cs0 - cs)),
  );
}

/// GSTR-3B with reverse charge (migration 0080): tax the shop pays itself
/// on rent or freight can't be paid from credit, so it is added to the cash
/// in full — and, once paid, it is credit (table 4(A)(3)) that pays the
/// tax on sales along with the purchase credit.
SetOffResult gstr3bSetOff({
  required TaxHeads sales,
  required TaxHeads credit,
  required TaxHeads reverseCharge,
}) {
  final r = gstSetOff(
    sales,
    TaxHeads(
      credit.igst + reverseCharge.igst,
      credit.cgst + reverseCharge.cgst,
      credit.sgst + reverseCharge.sgst,
    ),
  );
  double p(double v) => v < 0 ? 0 : v;
  double round(double v) => (v * 100).roundToDouble() / 100;
  return SetOffResult(
    cash: TaxHeads(
      round(r.cash.igst + p(reverseCharge.igst)),
      round(r.cash.cgst + p(reverseCharge.cgst)),
      round(r.cash.sgst + p(reverseCharge.sgst)),
    ),
    carryForward: r.carryForward,
    used: r.used,
  );
}

// ---------------------------------------------------------------------------
// GSTR-2B
// ---------------------------------------------------------------------------

/// A supplier's invoice (or note) as GSTR-2B lists it.
class Gstr2bDoc {
  const Gstr2bDoc({
    required this.supplierGstin,
    required this.supplierName,
    required this.number,
    required this.date,
    required this.value,
    required this.taxable,
    required this.igst,
    required this.cgst,
    required this.sgst,
    required this.itcAvailable,
    this.reason = '',
    this.noteType,
  });

  final String supplierGstin, supplierName, number;
  final DateTime? date;
  final double value, taxable, igst, cgst, sgst;
  final bool itcAvailable;
  final String reason;

  /// 'C' / 'D' for a credit / debit note; null for an invoice.
  final String? noteType;

  double get tax => igst + cgst + sgst;
}

class Gstr2bFormatError implements Exception {
  const Gstr2bFormatError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The invoices and notes in a GSTR-2B JSON downloaded from the portal
/// (Returns → GSTR-2B → Download → JSON).
({String gstin, String period, List<Gstr2bDoc> docs}) parseGstr2b(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const Gstr2bFormatError('This is not a GSTR-2B JSON file.');
  }
  if (decoded is! Map) {
    throw const Gstr2bFormatError('This is not a GSTR-2B JSON file.');
  }
  final data = decoded['data'] is Map ? decoded['data'] as Map : decoded;
  final docdata = data['docdata'];
  if (docdata is! Map) {
    throw const Gstr2bFormatError(
      'This file has no invoices list (docdata). Download GSTR-2B as JSON from the GST portal.',
    );
  }
  DateTime? date(Object? v) {
    final s = '${v ?? ''}';
    final m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(s);
    return m == null
        ? null
        : DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  ({double taxable, double igst, double cgst, double sgst}) sums(Map doc) {
    final items = (doc['items'] ?? doc['itms']) as List? ?? const [];
    double t = 0, i = 0, c = 0, s = 0;
    for (final it in items) {
      final m = (it is Map && it['itm_det'] is Map)
          ? it['itm_det'] as Map
          : it as Map;
      t += toDouble(m['txval']);
      i += toDouble(m['igst'] ?? m['iamt']);
      c += toDouble(m['cgst'] ?? m['camt']);
      s += toDouble(m['sgst'] ?? m['samt']);
    }
    if (items.isEmpty) {
      t = toDouble(doc['txval']);
      i = toDouble(doc['igst']);
      c = toDouble(doc['cgst']);
      s = toDouble(doc['sgst']);
    }
    return (taxable: t, igst: i, cgst: c, sgst: s);
  }

  final docs = <Gstr2bDoc>[];
  for (final supplier in (docdata['b2b'] as List? ?? const [])) {
    final s = supplier as Map;
    for (final inv in (s['inv'] as List? ?? const [])) {
      final d = inv as Map;
      final a = sums(d);
      docs.add(
        Gstr2bDoc(
          supplierGstin: '${s['ctin'] ?? ''}'.toUpperCase(),
          supplierName: '${s['trdnm'] ?? ''}',
          number: '${d['inum'] ?? ''}',
          date: date(d['dt']),
          value: toDouble(d['val']),
          taxable: a.taxable,
          igst: a.igst,
          cgst: a.cgst,
          sgst: a.sgst,
          itcAvailable: '${d['itcavl'] ?? 'Y'}' != 'N',
          reason: '${d['rsn'] ?? ''}',
        ),
      );
    }
  }
  for (final supplier in (docdata['cdnr'] as List? ?? const [])) {
    final s = supplier as Map;
    for (final nt in (s['nt'] as List? ?? const [])) {
      final d = nt as Map;
      final a = sums(d);
      docs.add(
        Gstr2bDoc(
          supplierGstin: '${s['ctin'] ?? ''}'.toUpperCase(),
          supplierName: '${s['trdnm'] ?? ''}',
          number: '${d['ntnum'] ?? d['nt_num'] ?? ''}',
          date: date(d['dt']),
          value: toDouble(d['val']),
          taxable: a.taxable,
          igst: a.igst,
          cgst: a.cgst,
          sgst: a.sgst,
          itcAvailable: '${d['itcavl'] ?? 'Y'}' != 'N',
          reason: '${d['rsn'] ?? ''}',
          noteType: '${d['typ'] ?? 'C'}',
        ),
      );
    }
  }
  return (
    gstin: '${data['gstin'] ?? ''}',
    period: '${data['rtnprd'] ?? ''}',
    docs: docs,
  );
}

/// How a purchase bill and GSTR-2B compare.
enum ItcMatch {
  /// In both, the tax the same (to a rupee).
  matched,

  /// In both, but the tax differs.
  differs,

  /// Entered as a purchase, but the supplier hasn't uploaded it: its
  /// credit can't be claimed yet.
  missingIn2b,

  /// The supplier uploaded it, but it isn't entered as a purchase.
  missingInBooks,

  /// In GSTR-2B with credit not available (e.g. time limit, place of
  /// supply).
  blocked,
}

class ItcRow {
  const ItcRow({
    required this.status,
    required this.supplierGstin,
    required this.supplierName,
    required this.billNo,
    this.date,
    this.booksTax = 0,
    this.portalTax = 0,
    this.reason = '',
  });

  final ItcMatch status;
  final String supplierGstin, supplierName, billNo;
  final DateTime? date;
  final double booksTax, portalTax;
  final String reason;
}

/// A bill number as written different ways ("RJSB/2627/08/0362" and
/// "rjsb-2627-8-362" are the same bill).
String normalizeBillNo(String s) => s
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
    .trim()
    .split(' ')
    .map(
      (p) => RegExp(r'^\d+$').hasMatch(p)
          ? p.replaceFirst(RegExp(r'^0+(?=\d)'), '')
          : p,
    )
    .join('');

/// Matches GSTR-2B invoices with the purchase register (registered
/// suppliers' bills only; debit notes and 2B's notes are left aside).
List<ItcRow> matchGstr2b(
  List<Gstr2bDoc> portal,
  List<Map<String, dynamic>> purchaseRegister,
) {
  // Purchase register rows are per bill and rate: one total per bill.
  final books =
      <
        String,
        ({String gstin, String name, String bill, DateTime? date, double tax})
      >{};
  for (final r in purchaseRegister) {
    if (r['doc_type'] != 'Purchase') continue;
    final gstin = '${r['supplier_gstin'] ?? ''}'.trim().toUpperCase();
    if (gstin.length != 15) continue;
    final bill = '${r['supplier_bill_no'] ?? ''}'.trim();
    final key =
        '$gstin|${normalizeBillNo(bill.isEmpty ? '${r['doc_no']}' : bill)}';
    final tax =
        toDouble(r['igst_amount']) +
        toDouble(r['cgst_amount']) +
        toDouble(r['sgst_amount']);
    final prev = books[key];
    books[key] = (
      gstin: gstin,
      name: '${r['supplier_name'] ?? ''}',
      bill: bill.isEmpty ? '${r['doc_no']}' : bill,
      date: DateTime.tryParse('${r['doc_date']}'),
      tax: (prev?.tax ?? 0) + tax,
    );
  }
  final out = <ItcRow>[];
  final seen = <String>{};
  for (final d in portal.where((d) => d.noteType == null)) {
    final key = '${d.supplierGstin}|${normalizeBillNo(d.number)}';
    final b = books[key];
    seen.add(key);
    ItcMatch status;
    if (!d.itcAvailable) {
      status = ItcMatch.blocked;
    } else if (b == null) {
      status = ItcMatch.missingInBooks;
    } else if ((b.tax - d.tax).abs() <= 1) {
      status = ItcMatch.matched;
    } else {
      status = ItcMatch.differs;
    }
    out.add(
      ItcRow(
        status: status,
        supplierGstin: d.supplierGstin,
        supplierName: d.supplierName.isNotEmpty
            ? d.supplierName
            : (b?.name ?? ''),
        billNo: d.number,
        date: d.date,
        booksTax: b?.tax ?? 0,
        portalTax: d.tax,
        reason: d.reason,
      ),
    );
  }
  for (final e in books.entries) {
    if (seen.contains(e.key)) continue;
    out.add(
      ItcRow(
        status: ItcMatch.missingIn2b,
        supplierGstin: e.value.gstin,
        supplierName: e.value.name,
        billNo: e.value.bill,
        date: e.value.date,
        booksTax: e.value.tax,
      ),
    );
  }
  return out;
}
