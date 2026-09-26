import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/gst.dart';

/// One month (or range) of GST data, as returned by get_gstr1, get_gstr3b
/// and get_purchase_register (migration 0040).
class GstReturnData {
  const GstReturnData({
    required this.gstr1,
    required this.gstr3b,
    required this.purchaseRegister,
  });

  final Map<String, dynamic> gstr1;
  final Map<String, dynamic> gstr3b;
  final List<Map<String, dynamic>> purchaseRegister;

  List<Map<String, dynamic>> section(String key) =>
      List<Map<String, dynamic>>.from(gstr1[key] as List? ?? const []);

  List<Map<String, dynamic>> hsn(String supply) => [
    for (final r in section('hsn'))
      if (r['supply'] == supply) r,
  ];

  /// Number of distinct documents in a GSTR-1 section (rows are per rate).
  int documentCount(String key) {
    final field = key.startsWith('cdn') ? 'note_no' : 'invoice_no';
    return {for (final r in section(key)) r[field]}.length;
  }

  Map<String, dynamic> _map(String key) =>
      Map<String, dynamic>.from(gstr3b[key] as Map? ?? const {});

  Map<String, dynamic> get outward => _map('outward_taxable');
  Map<String, dynamic> get itc => _map('itc_available');

  /// Output tax minus input tax credit, per head, before the portal's
  /// set-off order is applied (negative = credit carried forward).
  ({double igst, double cgst, double sgst}) get netPayable => (
    igst: toDouble(outward['igst_amount']) - toDouble(itc['igst_amount']),
    cgst: toDouble(outward['cgst_amount']) - toDouble(itc['cgst_amount']),
    sgst: toDouble(outward['sgst_amount']) - toDouble(itc['sgst_amount']),
  );

  Map<String, dynamic> get warnings =>
      Map<String, dynamic>.from(gstr1['warnings'] as Map? ?? const {});

  int get warningCount =>
      warnings.values.fold(0, (s, v) => s + ((v as num?)?.toInt() ?? 0));
}

/// GST portal date format, e.g. 05-Sep-2026.
String gstDate(Object? v) {
  if (v == null) return '';
  final d = v is DateTime ? v : DateTime.tryParse('$v');
  return d == null ? '$v' : DateFormat('dd-MMM-yyyy').format(d);
}

/// GST portal place-of-supply format, e.g. 29-Karnataka.
String gstPos(Object? code) {
  final c = '${code ?? ''}';
  final name = gstStates[c];
  return name == null ? c : '$c-$name';
}

/// Builds the accountant's workbook: a summary sheet, GSTR-1 sections in the
/// GST offline-tool column order (tax amounts added after the official
/// columns), GSTR-3B and the purchase register.
Uint8List buildGstWorkbook({
  required GstReturnData data,
  required String businessName,
  required String gstin,
  required DateTime from,
  required DateTime to,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  CellValue t(Object? v) => TextCellValue('${v ?? ''}');
  CellValue n(Object? v) => DoubleCellValue(toDouble(v));

  void sheet(String name, List<String> headers, List<List<CellValue>> rows) {
    final s = excel[name];
    s.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final r in rows) {
      s.appendRow(r);
    }
  }

  // ---------- Summary ----------
  final out = data.outward;
  final itc = data.itc;
  final net = data.netPayable;
  final w = data.warnings;
  sheet('Summary', ['Item', 'Value'], [
    [t('Business'), t(businessName)],
    [t('GSTIN'), t(gstin)],
    [t('Period'), t('${gstDate(from)} to ${gstDate(to)}')],
    [t(''), t('')],
    [t('B2B invoices'), n(data.documentCount('b2b'))],
    [t('B2C large invoices'), n(data.documentCount('b2cl'))],
    [t('B2C small (rows)'), n(data.section('b2cs').length)],
    [t('Credit notes — registered'), n(data.documentCount('cdnr'))],
    [t('Credit notes — unregistered'), n(data.documentCount('cdnur'))],
    [t(''), t('')],
    [t('Outward taxable value'), n(out['taxable_value'])],
    [t('Output IGST'), n(out['igst_amount'])],
    [t('Output CGST'), n(out['cgst_amount'])],
    [t('Output SGST'), n(out['sgst_amount'])],
    [t('Input tax credit IGST'), n(itc['igst_amount'])],
    [t('Input tax credit CGST'), n(itc['cgst_amount'])],
    [t('Input tax credit SGST'), n(itc['sgst_amount'])],
    [t('Net IGST (before set-off)'), n(net.igst)],
    [t('Net CGST (before set-off)'), n(net.cgst)],
    [t('Net SGST (before set-off)'), n(net.sgst)],
    [t(''), t('')],
    [t('Taxed lines without HSN'), n(w['lines_without_hsn'])],
    [t('Invalid customer GSTINs (treated as B2C)'), n(w['invalid_customer_gstins'])],
    [t(''), t('')],
    [
      t('Note'),
      t(
        'Prepared by Dukania from your bills. Your accountant should '
        'review these figures before filing.',
      ),
    ],
  ]);

  // ---------- GSTR-1 ----------
  sheet(
    'b2b',
    [
      'GSTIN/UIN of Recipient', 'Receiver Name', 'Invoice Number',
      'Invoice date', 'Invoice Value', 'Place Of Supply', 'Reverse Charge',
      'Applicable % of Tax Rate', 'Invoice Type', 'E-Commerce GSTIN', 'Rate',
      'Taxable Value', 'Cess Amount', 'Integrated Tax', 'Central Tax',
      'State/UT Tax',
    ],
    [
      for (final r in data.section('b2b'))
        [
          t(r['gstin']), t(r['receiver_name']), t(r['invoice_no']),
          t(gstDate(r['invoice_date'])), n(r['invoice_value']),
          t(gstPos(r['place_of_supply'])), t(r['reverse_charge']), t(''),
          t(r['invoice_type']), t(''), n(r['gst_rate']),
          n(r['taxable_value']), n(r['cess_amount']), n(r['igst_amount']),
          n(r['cgst_amount']), n(r['sgst_amount']),
        ],
    ],
  );
  sheet(
    'b2cl',
    [
      'Invoice Number', 'Invoice date', 'Invoice Value', 'Place Of Supply',
      'Applicable % of Tax Rate', 'Rate', 'Taxable Value', 'Cess Amount',
      'E-Commerce GSTIN', 'Integrated Tax',
    ],
    [
      for (final r in data.section('b2cl'))
        [
          t(r['invoice_no']), t(gstDate(r['invoice_date'])),
          n(r['invoice_value']), t(gstPos(r['place_of_supply'])), t(''),
          n(r['gst_rate']), n(r['taxable_value']), n(r['cess_amount']), t(''),
          n(r['igst_amount']),
        ],
    ],
  );
  sheet(
    'b2cs',
    [
      'Type', 'Place Of Supply', 'Applicable % of Tax Rate', 'Rate',
      'Taxable Value', 'Cess Amount', 'E-Commerce GSTIN', 'Integrated Tax',
      'Central Tax', 'State/UT Tax',
    ],
    [
      for (final r in data.section('b2cs'))
        [
          t(r['type']), t(gstPos(r['place_of_supply'])), t(''),
          n(r['gst_rate']), n(r['taxable_value']), n(r['cess_amount']), t(''),
          n(r['igst_amount']), n(r['cgst_amount']), n(r['sgst_amount']),
        ],
    ],
  );
  sheet(
    'cdnr',
    [
      'GSTIN/UIN of Recipient', 'Receiver Name', 'Note Number', 'Note Date',
      'Note Type', 'Place Of Supply', 'Reverse Charge', 'Note Supply Type',
      'Note Value', 'Applicable % of Tax Rate', 'Rate', 'Taxable Value',
      'Cess Amount', 'Original Invoice Number', 'Original Invoice Date',
      'Integrated Tax', 'Central Tax', 'State/UT Tax',
    ],
    [
      for (final r in data.section('cdnr'))
        [
          t(r['gstin']), t(r['receiver_name']), t(r['note_no']),
          t(gstDate(r['note_date'])), t(r['note_type']),
          t(gstPos(r['place_of_supply'])), t(r['reverse_charge']),
          t(r['note_supply_type']), n(r['note_value']), t(''),
          n(r['gst_rate']), n(r['taxable_value']), n(r['cess_amount']),
          t(r['invoice_no']), t(gstDate(r['invoice_date'])),
          n(r['igst_amount']), n(r['cgst_amount']), n(r['sgst_amount']),
        ],
    ],
  );
  sheet(
    'cdnur',
    [
      'UR Type', 'Note Number', 'Note Date', 'Note Type', 'Place Of Supply',
      'Note Value', 'Applicable % of Tax Rate', 'Rate', 'Taxable Value',
      'Cess Amount', 'Original Invoice Number', 'Original Invoice Date',
      'Integrated Tax',
    ],
    [
      for (final r in data.section('cdnur'))
        [
          t(r['ur_type']), t(r['note_no']), t(gstDate(r['note_date'])),
          t(r['note_type']), t(gstPos(r['place_of_supply'])),
          n(r['note_value']), t(''), n(r['gst_rate']), n(r['taxable_value']),
          n(r['cess_amount']), t(r['invoice_no']),
          t(gstDate(r['invoice_date'])), n(r['igst_amount']),
        ],
    ],
  );
  const hsnHeaders = [
    'HSN', 'Description', 'UQC', 'Total Quantity', 'Total Value', 'Rate',
    'Taxable Value', 'Integrated Tax Amount', 'Central Tax Amount',
    'State/UT Tax Amount', 'Cess Amount',
  ];
  List<List<CellValue>> hsnRows(String supply) => [
    for (final r in data.hsn(supply))
      [
        t(r['hsn_code']), t(r['description']), t(r['uqc']), n(r['quantity']),
        n(r['total_value']), n(r['gst_rate']), n(r['taxable_value']),
        n(r['igst_amount']), n(r['cgst_amount']), n(r['sgst_amount']),
        n(r['cess_amount']),
      ],
  ];
  sheet('hsn(b2b)', hsnHeaders, hsnRows('B2B'));
  sheet('hsn(b2c)', hsnHeaders, hsnRows('B2C'));
  sheet(
    'docs',
    ['Nature of Document', 'Sr. No. From', 'Sr. No. To', 'Total Number', 'Cancelled'],
    [
      for (final r in data.section('docs'))
        if (((r['total'] as num?) ?? 0) > 0)
          [
            t(r['nature']), t(r['from_no']), t(r['to_no']), n(r['total']),
            n(r['cancelled']),
          ],
    ],
  );

  // ---------- GSTR-3B ----------
  final nil = Map<String, dynamic>.from(
    data.gstr3b['outward_nil_exempt'] as Map? ?? const {},
  );
  sheet(
    'GSTR-3B',
    ['Table', 'Description', 'Taxable value', 'Integrated Tax', 'Central Tax', 'State/UT Tax'],
    [
      [
        t('3.1(a)'), t('Outward taxable supplies'), n(out['taxable_value']),
        n(out['igst_amount']), n(out['cgst_amount']), n(out['sgst_amount']),
      ],
      [
        t('3.1(c)'), t('Nil rated / exempted'), n(nil['taxable_value']),
        n(0), n(0), n(0),
      ],
      for (final r in List<Map<String, dynamic>>.from(
        data.gstr3b['inter_state_unregistered'] as List? ?? const [],
      ))
        [
          t('3.2'),
          t('Inter-state to unregistered — ${gstPos(r['place_of_supply'])}'),
          n(r['taxable_value']), n(r['igst_amount']), n(0), n(0),
        ],
      [
        t('4(A)(5)'), t('All other ITC (registered suppliers, net of debit notes)'),
        n(0), n(itc['igst_amount']), n(itc['cgst_amount']), n(itc['sgst_amount']),
      ],
      [
        t('—'), t('Tax on purchases from unregistered suppliers (no ITC)'),
        n(0), n(data.gstr3b['tax_on_unregistered_purchases']), n(0), n(0),
      ],
    ],
  );

  // ---------- Purchase register ----------
  sheet(
    'Purchase register',
    [
      'Type', 'Date', 'Our No.', 'Supplier Bill No.', 'Supplier',
      'Supplier GSTIN', 'Supplier State', 'Rate', 'Taxable Value',
      'Integrated Tax', 'Central Tax', 'State/UT Tax', 'Bill Total',
    ],
    [
      for (final r in data.purchaseRegister)
        [
          t(r['doc_type']), t(gstDate(r['doc_date'])), t(r['doc_no']),
          t(r['supplier_bill_no']), t(r['supplier_name']),
          t(r['supplier_gstin']), t(gstPos(r['supplier_state'])),
          n(r['gst_rate']), n(r['taxable_value']), n(r['igst_amount']),
          n(r['cgst_amount']), n(r['sgst_amount']), n(r['bill_total']),
        ],
    ],
  );

  excel.setDefaultSheet('Summary');
  if (defaultSheet != null && defaultSheet != 'Summary') {
    excel.delete(defaultSheet);
  }
  return Uint8List.fromList(excel.encode()!);
}
