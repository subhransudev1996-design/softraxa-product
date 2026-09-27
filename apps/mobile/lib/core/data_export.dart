import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'file_export.dart';
import 'supabase_providers.dart';
import 'widgets.dart';

/// Full business data export for the owner (LAUNCH_SPECIFICATION
/// "Exports"; migration 0050). Works after the subscription has expired
/// too — the shop's data stays theirs. One Excel sheet per table.
Future<void> exportAllData(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('Preparing your data export…')),
  );
  try {
    final data = Map<String, dynamic>.from(
      await ref.read(supabaseProvider).rpc('export_business_data') as Map,
    );
    final business = Map<String, dynamic>.from(data['business'] as Map);
    final bytes = buildExportWorkbook(data);
    final name = (business['name'] as String? ?? 'shop').replaceAll(
      RegExp(r'[^A-Za-z0-9]+'),
      '_',
    );
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final message = await saveOrShareFile(
      bytes,
      'Dukania_${name}_$date.xlsx',
      subject: 'Dukania data export — ${business['name']}',
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Builds the workbook: a "business" sheet (field, value), then one sheet
/// per table with a column per field.
Uint8List buildExportWorkbook(Map<String, dynamic> data) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();

  CellValue cell(Object? v) => switch (v) {
    null => TextCellValue(''),
    num n => DoubleCellValue(n.toDouble()),
    bool b => TextCellValue(b ? 'yes' : 'no'),
    Map() || List() => TextCellValue(jsonEncode(v)),
    _ => TextCellValue('$v'),
  };

  final business = Map<String, dynamic>.from(data['business'] as Map? ?? {});
  final info = excel['business'];
  info.appendRow([TextCellValue('Field'), TextCellValue('Value')]);
  info.appendRow([TextCellValue('exported_at'), cell(data['exported_at'])]);
  for (final e in business.entries) {
    info.appendRow([TextCellValue(e.key), cell(e.value)]);
  }

  final tables =
      data.keys
          .where(
            (k) => k != 'business' && k != 'exported_at' && data[k] is List,
          )
          .toList()
        ..sort();
  for (final table in tables) {
    final rows = List<Map<String, dynamic>>.from(
      (data[table] as List).map((r) => Map<String, dynamic>.from(r as Map)),
    );
    if (rows.isEmpty) continue;
    // Every field that appears in any row, in first-seen order.
    final headers = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!headers.contains(k)) headers.add(k);
      }
    }
    // Excel sheet names: at most 31 characters.
    final sheet = excel[table.length > 31 ? table.substring(0, 31) : table];
    sheet.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final r in rows) {
      sheet.appendRow([for (final h in headers) cell(r[h])]);
    }
  }

  excel.setDefaultSheet('business');
  if (defaultSheet != null && defaultSheet != 'business') {
    excel.delete(defaultSheet);
  }
  return Uint8List.fromList(excel.encode()!);
}
