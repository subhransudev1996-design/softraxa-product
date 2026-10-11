import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Opens an .xlsx file. The excel package only follows sheet links written
/// relative to xl/ (as Excel does); files made by other tools (Python,
/// some billing software) write them as "/xl/worksheets/sheet1.xml" and the
/// package crashes with a null check. Those links are rewritten first.
Excel decodeExcel(List<int> bytes) => Excel.decodeBytes(fixSheetLinks(bytes));

List<int> fixSheetLinks(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return bytes; // not a zip — let the excel package report it
  }
  const relsName = 'xl/_rels/workbook.xml.rels';
  final rels = zip.findFile(relsName);
  if (rels == null) return bytes;
  final text = utf8.decode(rels.content as List<int>, allowMalformed: true);
  if (!text.contains('Target="/xl/')) return bytes;
  final fixed = utf8.encode(text.replaceAll('Target="/xl/', 'Target="'));
  final out = Archive();
  for (final f in zip.files) {
    out.addFile(
      f.name == relsName
          ? ArchiveFile(relsName, fixed.length, fixed)
          : ArchiveFile(f.name, f.size, f.content),
    );
  }
  return ZipEncoder().encode(out) ?? bytes;
}
