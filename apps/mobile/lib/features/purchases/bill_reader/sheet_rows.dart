import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'pdf_words.dart' show PdfReadError;

/// The rows of a supplier's Excel (.xlsx) or CSV bill, as text cells. The
/// sheet with the most filled rows is taken (a workbook may have a cover
/// sheet).
List<List<String>> readSheetRows(Uint8List bytes, String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.xls')) {
    throw const PdfReadError(
      'This is an old Excel file (.xls). Open it in Excel and save it as .xlsx, then try again.',
    );
  }
  if (name.endsWith('.csv') || name.endsWith('.txt') || name.endsWith('.tsv')) {
    return parseCsv(utf8.decode(bytes, allowMalformed: true));
  }
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const PdfReadError(
      'This file could not be opened as an Excel sheet.',
    );
  }
  List<List<String>> best = const [];
  var bestFilled = -1;
  for (final sheet in excel.tables.values) {
    final rows = [
      for (final r in sheet.rows) [for (final c in r) _cellText(c?.value)],
    ];
    final filled = rows.where((r) => r.any((c) => c.isNotEmpty)).length;
    if (filled > bestFilled) {
      bestFilled = filled;
      best = rows;
    }
  }
  if (bestFilled <= 0) throw const PdfReadError('This sheet is empty.');
  return best;
}

String _cellText(CellValue? v) => switch (v) {
  null => '',
  DoubleCellValue(:final value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value',
  IntCellValue(:final value) => '$value',
  DateCellValue() => '${v.year}-${_two(v.month)}-${_two(v.day)}',
  DateTimeCellValue() => '${v.year}-${_two(v.month)}-${_two(v.day)}',
  _ => v.toString().trim(),
};

String _two(int n) => n.toString().padLeft(2, '0');

/// CSV text → rows. Quotes ("Ghee, 1 L"), doubled quotes inside them, and
/// a comma, semicolon or tab separator — whichever the first line uses
/// most.
List<List<String>> parseCsv(String text) {
  final firstLine = text.split('\n').first;
  final sep = [',', ';', '\t'].reduce(
    (a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b,
  );
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return rows;
}
