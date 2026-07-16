import 'dart:io';
import '../../core/walkthrough.dart';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../pos/pos_providers.dart';
import '../products/product_providers.dart';
import '../../core/theme.dart';

const _headers = [
  'Name*',
  'Category',
  'Brand',
  'Unit',
  'SKU',
  'Barcode',
  'HSN Code',
  'Purchase Price',
  'Selling Price*',
  'MRP',
  'GST %',
  'Opening Stock',
  'Low Stock Alert',
];

/// Strips thousands separators / currency symbol / stray percent sign so
/// "28,999", "₹28999" and "18%" (typed as literal text) all parse — throws
/// (via [double.parse]) if the remaining text isn't a plain number.
double parseImportNum(String raw) =>
    double.parse(raw.replaceAll(RegExp(r'[,₹%\s]'), ''));

/// Normalizes a template header cell for comparison — case/whitespace
/// insensitive, ignoring the "required" asterisk.
String normalizeImportHeader(String h) =>
    h.trim().toLowerCase().replaceAll('*', '');

/// Null if the GST rate is valid; otherwise the row-error message to show.
/// A value strictly between 0 and 1 is almost certainly a percent-formatted
/// Excel cell read back as its raw fraction (Excel stores an "18%" cell's
/// underlying value as 0.18, not 18 — the % is only a display format).
String? gstRateError(double gst) {
  if (gst < 0 || gst > 28) return 'GST % must be 0–28';
  if (gst > 0 && gst < 1) {
    return 'GST % looks like a fraction ($gst) — the cell may be '
        'percentage-formatted in Excel. Enter GST as a plain number like 18, '
        'not 18%.';
  }
  return null;
}

class _ImportRow {
  _ImportRow(this.rowNumber, this.values);

  final int rowNumber;
  final Map<String, dynamic> values;
  final List<String> errors = [];

  bool get valid => errors.isEmpty;
}

/// Excel product import (PRD 7.6).
class ExcelImportScreen extends ConsumerStatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  ConsumerState<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends ConsumerState<ExcelImportScreen> {
  List<_ImportRow> _rows = [];
  bool _parsing = false;
  bool _importing = false;
  int _imported = 0;
  String? _fileName;

  Future<void> _downloadSample() async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow([for (final h in _headers) TextCellValue(h)]);
    sheet.appendRow([
      TextCellValue('Samsung Galaxy A55 8/128'),
      TextCellValue('Smartphones'),
      TextCellValue('Samsung'),
      TextCellValue('Piece'),
      TextCellValue('SGA55-8128'),
      TextCellValue('8901234567890'),
      TextCellValue('8517'),
      DoubleCellValue(26000),
      DoubleCellValue(28999),
      DoubleCellValue(30999),
      DoubleCellValue(18),
      DoubleCellValue(5),
      DoubleCellValue(2),
    ]);
    sheet.appendRow([
      TextCellValue('Cotton T-Shirt Blue XL'),
      TextCellValue('T-Shirts'),
      TextCellValue('Local'),
      TextCellValue('Piece'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('6109'),
      DoubleCellValue(150),
      DoubleCellValue(299),
      DoubleCellValue(399),
      DoubleCellValue(5),
      DoubleCellValue(20),
      DoubleCellValue(5),
    ]);
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/product_import_sample.xlsx');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Product import sample'),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _parsing = true;
      _rows = [];
      _imported = 0;
      _fileName = result.files.single.name;
    });

    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first]!;

      String cellStr(List<Data?> row, int i) =>
          i < row.length ? (row[i]?.value?.toString() ?? '').trim() : '';

      // Guard against a reordered/edited template: parsing is positional
      // (index-based), so if the header row doesn't match the sample
      // exactly, every downstream field would silently shift instead of
      // erroring — check this up front rather than importing garbage.
      if (sheet.rows.isEmpty) {
        throw Exception('This file has no rows.');
      }
      final headerRow = sheet.rows[0];
      for (var i = 0; i < _headers.length; i++) {
        final actual = cellStr(headerRow, i);
        if (normalizeImportHeader(actual) !=
            normalizeImportHeader(_headers[i])) {
          throw Exception(
            'This doesn\'t look like the sample template — column ${i + 1} '
            'should be "${_headers[i]}" but found '
            '"${actual.isEmpty ? '(empty)' : actual}". Please use the '
            'downloaded sample file and don\'t reorder its columns.',
          );
        }
      }

      // existing products for duplicate check (PRD 7.6)
      final client = ref.read(supabaseProvider);
      final existing = List<Map<String, dynamic>>.from(
        await client.from('products').select('name, sku, barcode'),
      );
      final existingNames = {
        for (final p in existing) (p['name'] as String).trim().toLowerCase(),
      };
      final existingSkus = {
        for (final p in existing)
          if ((p['sku'] as String? ?? '').trim().isNotEmpty)
            (p['sku'] as String).trim(),
      };
      final existingBarcodes = {
        for (final p in existing)
          if ((p['barcode'] as String? ?? '').isNotEmpty)
            p['barcode'] as String,
      };

      final seenNames = <String>{};
      final seenSkus = <String>{};
      final seenBarcodes = <String>{};
      final parsed = <_ImportRow>[];

      // A cell that's non-empty but fails to parse must be a row error, not
      // a silent 0 — otherwise a malformed price/stock cell imports as if
      // the user meant zero, with no indication anything was wrong.
      double numOrZero(
        List<Data?> row,
        int i,
        String label,
        List<String> errors,
      ) {
        final raw = cellStr(row, i);
        if (raw.isEmpty) return 0;
        try {
          return parseImportNum(raw);
        } catch (_) {
          errors.add('$label is not a valid number: "$raw"');
          return 0;
        }
      }

      for (var r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final name = cellStr(row, 0);
        if (name.isEmpty &&
            cellStr(row, 8).isEmpty &&
            cellStr(row, 5).isEmpty) {
          continue; // fully empty row
        }
        final errors = <String>[];
        final sellingRaw = cellStr(row, 8);
        double? sellingPrice;
        if (sellingRaw.isEmpty) {
          errors.add('Selling price is required');
        } else {
          try {
            sellingPrice = parseImportNum(sellingRaw);
          } catch (_) {
            errors.add('Selling price is not a valid number: "$sellingRaw"');
          }
        }
        final gstRate = numOrZero(row, 10, 'GST %', errors);

        final item = _ImportRow(r + 1, {
          'name': name,
          'category': cellStr(row, 1),
          'brand': cellStr(row, 2),
          'unit': cellStr(row, 3),
          'sku': cellStr(row, 4),
          'barcode': cellStr(row, 5),
          'hsn_code': cellStr(row, 6),
          'purchase_price': numOrZero(row, 7, 'Purchase price', errors),
          'selling_price': sellingPrice ?? 0,
          'mrp': numOrZero(row, 9, 'MRP', errors),
          'gst_rate': gstRate,
          'opening_stock': numOrZero(row, 11, 'Opening stock', errors),
          'low_stock_qty': numOrZero(row, 12, 'Low stock alert', errors),
        });
        item.errors.addAll(errors);

        // validation (PRD 7.6)
        if (name.isEmpty) item.errors.add('Name is required');
        final gstError = gstRateError(gstRate);
        if (gstError != null) item.errors.add(gstError);
        final lowerName = name.toLowerCase();
        if (existingNames.contains(lowerName)) {
          item.errors.add('Duplicate: product already exists');
        }
        if (seenNames.contains(lowerName)) {
          item.errors.add('Duplicate name in this file');
        }
        final sku = item.values['sku'] as String;
        if (sku.isNotEmpty) {
          if (existingSkus.contains(sku)) {
            item.errors.add('Duplicate: SKU already exists');
          }
          if (seenSkus.contains(sku)) {
            item.errors.add('Duplicate SKU in this file');
          }
          seenSkus.add(sku);
        }
        final barcode = item.values['barcode'] as String;
        if (barcode.isNotEmpty) {
          if (existingBarcodes.contains(barcode)) {
            item.errors.add('Duplicate: barcode already exists');
          }
          if (seenBarcodes.contains(barcode)) {
            item.errors.add('Duplicate barcode in this file');
          }
          seenBarcodes.add(barcode);
        }
        seenNames.add(lowerName);
        parsed.add(item);
      }
      setState(() => _rows = parsed);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _import() async {
    final valid = _rows.where((r) => r.valid).toList();
    if (valid.isEmpty) return;
    setState(() => _importing = true);
    final client = ref.read(supabaseProvider);
    final businessId = ref.read(appContextProvider).value?.businessId;

    try {
      // resolve/create categories, brands, units
      Future<Map<String, String>> lookup(String table) async {
        final rows = await client.from(table).select('id, name');
        return {
          for (final r in rows)
            (r['name'] as String).toLowerCase(): r['id'] as String,
        };
      }

      final categories = await lookup('categories');
      final brands = await lookup('brands');
      final units = await lookup('units');

      Future<String?> resolve(
        String table,
        Map<String, String> cache,
        String name,
      ) async {
        if (name.isEmpty) return null;
        final key = name.toLowerCase();
        if (cache.containsKey(key)) return cache[key];
        final inserted = await client
            .from(table)
            .insert({'business_id': businessId, 'name': name})
            .select('id')
            .single();
        cache[key] = inserted['id'] as String;
        return cache[key];
      }

      var count = 0;
      var failCount = 0;
      for (final row in valid) {
        final v = row.values;
        try {
          final inserted = await client
              .from('products')
              .insert({
                'business_id': businessId,
                'name': v['name'],
                'sku': v['sku'],
                'barcode': v['barcode'],
                'hsn_code': v['hsn_code'],
                'category_id': await resolve(
                  'categories',
                  categories,
                  v['category'] as String,
                ),
                'brand_id': await resolve(
                  'brands',
                  brands,
                  v['brand'] as String,
                ),
                'unit_id': await resolve('units', units, v['unit'] as String),
                'purchase_price': v['purchase_price'],
                'selling_price': v['selling_price'],
                'mrp': v['mrp'],
                'gst_rate': v['gst_rate'],
                'low_stock_qty': v['low_stock_qty'],
              })
              .select('id')
              .single();
          final stock = v['opening_stock'] as double;
          if (stock > 0) {
            await client.rpc(
              'add_opening_stock',
              params: {
                'p_product_id': inserted['id'],
                'p_variant_id': null,
                'p_quantity': stock,
              },
            );
          }
          count++;
          // Remove the row the instant it succeeds — so a retry after a
          // later row's failure can't re-insert an already-committed row
          // as a duplicate (imports aren't transactional across rows).
          if (mounted) {
            setState(() {
              _imported = count;
              _rows = _rows.where((r) => r.rowNumber != row.rowNumber).toList();
            });
          }
        } catch (e) {
          failCount++;
          row.errors
            ..clear()
            ..add('Import failed: ${friendlyError(e)}');
          if (mounted) setState(() {});
        }
      }

      ref.invalidate(productsProvider);
      ref.invalidate(posProductsProvider);
      if (mounted) {
        if (failCount == 0) {
          showSuccess(context, '$count products imported');
        } else {
          showError(
            context,
            '$count imported, $failCount failed — see the rows below for details.',
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _rows.where((r) => r.valid).length;
    final errorCount = _rows.length - validCount;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Excel import'), actions: const [GuideButton('import')]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How it works',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample Excel file\n'
                    '2. Fill in your products (one per row)\n'
                    '3. Upload the file here\n'
                    '4. Fix any errors shown, then import',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: CoachTarget(page: 'import', id: 'template', child: OutlinedButton.icon(
                          onPressed: _downloadSample,
                          icon: const Icon(Icons.download),
                          label: const Text('Sample file'),
                        )),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CoachTarget(page: 'import', id: 'upload', child: FilledButton.icon(
                          onPressed: _parsing ? null : _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: Text(_parsing ? 'Reading…' : 'Choose file'),
                        )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_fileName != null && _rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(
                  errorCount == 0 ? Icons.check_circle : Icons.warning_amber,
                  color: errorCount == 0 ? AppColors.green : AppColors.orange,
                ),
                title: Text(_fileName!),
                subtitle: Text(
                  '$validCount ready to import'
                  '${errorCount > 0 ? ' • $errorCount rows with errors (will be skipped)' : ''}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final row in _rows)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    row.valid
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: row.valid ? AppColors.green : AppColors.red,
                    size: 20,
                  ),
                  title: Text('Row ${row.rowNumber}: ${row.values['name']}'),
                  subtitle: row.valid
                      ? Text(
                          '₹${row.values['selling_price']} • GST ${row.values['gst_rate']}% • Stock ${row.values['opening_stock']}',
                          style: const TextStyle(fontSize: 12),
                        )
                      : Text(
                          row.errors.join('\n'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.red,
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _importing || validCount == 0 ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check),
              label: Text(
                _importing
                    ? 'Importing… $_imported/$validCount'
                    : 'Import $validCount products',
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
