import 'package:flutter/material.dart';

import 'formatters.dart';

/// GST state codes (the first two digits of a GSTIN). '' means "not set".
/// Mirrors public.is_gst_state_code() in migration 0036.
const gstStates = <String, String>{
  '01': 'Jammu & Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '26': 'Dadra & Nagar Haveli and Daman & Diu',
  '27': 'Maharashtra',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman & Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
  '97': 'Other Territory',
};

/// "27 - Maharashtra", or '' when the code is empty/unknown.
String gstStateLabel(String? code) {
  final name = gstStates[code ?? ''];
  return name == null ? '' : '$code - $name';
}

/// State code implied by a GSTIN, or null if it doesn't start with a valid one.
String? stateFromGstin(String gstin) {
  final g = gstin.trim();
  if (g.length < 2) return null;
  final code = g.substring(0, 2);
  return gstStates.containsKey(code) ? code : null;
}

/// Dropdown for picking a GST state. [value] '' = not set.
class GstStateField extends StatelessWidget {
  const GstStateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'State',
    this.helperText,
    this.validator,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String? helperText;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // Keyed on value so an auto-fill from the GSTIN updates the field.
      key: ValueKey(value),
      initialValue: gstStates.containsKey(value) ? value : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label, helperText: helperText),
      validator: validator,
      items: [
        const DropdownMenuItem(value: '', child: Text('Not set')),
        for (final e in gstStates.entries)
          DropdownMenuItem(value: e.key, child: Text('${e.key} - ${e.value}')),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

/// CGST / SGST / IGST totals of invoice or purchase lines. Lines saved before
/// migration 0036 have no split stored, so their tax counts as CGST + SGST.
({double cgst, double sgst, double igst}) gstSplit(
  List<Map<String, dynamic>> items,
) {
  var cgst = 0.0, sgst = 0.0, igst = 0.0;
  for (final it in items) {
    final c = toDouble(it['cgst_amount']);
    final s = toDouble(it['sgst_amount']);
    final i = toDouble(it['igst_amount']);
    if (c == 0 && s == 0 && i == 0) {
      final tax = toDouble(it['tax_amount']);
      cgst += tax / 2;
      sgst += tax / 2;
    } else {
      cgst += c;
      sgst += s;
      igst += i;
    }
  }
  return (cgst: cgst, sgst: sgst, igst: igst);
}

/// Per-rate breakup rows for printed invoices: CGST/SGST at half the rate,
/// IGST at the full rate. Returns (label, amount) pairs.
List<(String, double)> gstBreakupRows(List<Map<String, dynamic>> items) {
  final cgst = <double, double>{};
  final sgst = <double, double>{};
  final igst = <double, double>{};
  for (final it in items) {
    final rate = toDouble(it['gst_rate']);
    if (rate <= 0) continue;
    final split = gstSplit([it]);
    if (split.igst != 0) {
      igst[rate] = (igst[rate] ?? 0) + split.igst;
    } else {
      cgst[rate] = (cgst[rate] ?? 0) + split.cgst;
      sgst[rate] = (sgst[rate] ?? 0) + split.sgst;
    }
  }
  return [
    for (final rate in cgst.keys) ...[
      ('CGST ${qty(rate / 2)}%', cgst[rate]!),
      ('SGST ${qty(rate / 2)}%', sgst[rate]!),
    ],
    for (final e in igst.entries) ('IGST ${qty(e.key)}%', e.value),
  ];
}
