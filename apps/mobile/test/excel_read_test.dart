import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dukania/core/excel_read.dart';

/// An .xlsx whose workbook links its sheets as "/xl/worksheets/…", the way
/// Python's openpyxl and some billing software write it.
List<int> absoluteLinkFile() {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  sheet.appendRow([TextCellValue('Name*'), TextCellValue('Selling Price*')]);
  sheet.appendRow([TextCellValue('Exide XLTZ4A'), IntCellValue(1610)]);
  final zip = ZipDecoder().decodeBytes(excel.encode()!);
  final out = Archive();
  for (final f in zip.files) {
    if (f.name == 'xl/_rels/workbook.xml.rels') {
      final text = utf8
          .decode(f.content as List<int>)
          .replaceAll('Target="', 'Target="/xl/');
      final bytes = utf8.encode(text);
      out.addFile(ArchiveFile(f.name, bytes.length, bytes));
    } else {
      out.addFile(ArchiveFile(f.name, f.size, f.content));
    }
  }
  return ZipEncoder().encode(out)!;
}

void main() {
  test('reads a file whose sheets are linked as /xl/...', () {
    final bytes = absoluteLinkFile();
    final excel = decodeExcel(bytes);
    final rows = excel.tables.values.first.rows;
    expect(rows.length, 2);
    expect(rows[1][0]?.value.toString(), 'Exide XLTZ4A');
  });

  test('leaves a normal Excel file as it is', () {
    final excel = Excel.createExcel();
    excel[excel.getDefaultSheet()!].appendRow([TextCellValue('A')]);
    final bytes = excel.encode()!;
    expect(identical(fixSheetLinks(bytes), bytes), isTrue);
  });
}
