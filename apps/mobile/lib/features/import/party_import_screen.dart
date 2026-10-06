import '../../core/i18n.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customer_providers.dart';
import '../suppliers/suppliers.dart' show suppliersProvider;
import 'excel_import_screen.dart' show normalizeImportHeader, parseImportNum;

/// Customer or supplier import from Excel, with opening balances
/// (LAUNCH_SPECIFICATION onboarding "Migration from paper"; migration
/// 0051). Owner only. The server skips parties that already exist and
/// reports bad rows without stopping the others.
class PartyImportScreen extends ConsumerStatefulWidget {
  const PartyImportScreen({super.key, required this.suppliers});

  final bool suppliers;

  @override
  ConsumerState<PartyImportScreen> createState() => _PartyImportScreenState();
}

class _Row {
  _Row(this.number, this.values);
  final int number;
  final Map<String, dynamic> values;
  final List<String> errors = [];
}

class _PartyImportScreenState extends ConsumerState<PartyImportScreen> {
  List<_Row> _rows = [];
  String? _fileName;
  bool _busy = false;
  Map<String, dynamic>? _result;
  DateTime _asOf = DateTime.now().subtract(const Duration(days: 1));

  String get _what => widget.suppliers ? 'suppliers' : 'customers';

  List<String> get _headers => [
    'Name*',
    'Phone',
    'GSTIN',
    'Address',
    'State code',
    if (!widget.suppliers) 'Credit limit',
    'Opening balance',
  ];

  Future<void> _downloadSample() async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow([for (final h in _headers) TextCellValue(h)]);
    sheet.appendRow([
      TextCellValue(widget.suppliers ? 'Sharma Distributors' : 'Ravi Kumar'),
      TextCellValue('9876543210'),
      TextCellValue(''),
      TextCellValue('Main Road'),
      TextCellValue('21'),
      if (!widget.suppliers) DoubleCellValue(10000),
      DoubleCellValue(2500),
    ]);
    if (!widget.suppliers) {
      sheet.appendRow([
        TextCellValue('Meena (paid advance)'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(-500),
      ]);
    }
    final message = await saveOrShareFile(
      Uint8List.fromList(excel.encode()!),
      '${_what}_import_sample.xlsx',
    );
    if (message != null && mounted) showSuccess(context, message);
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (picked == null || picked.files.single.path == null) return;
    setState(() {
      _busy = true;
      _rows = [];
      _result = null;
      _fileName = picked.files.single.name;
    });
    try {
      final bytes = await File(picked.files.single.path!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first]!;
      String cell(List<Data?> row, int i) =>
          i < row.length ? (row[i]?.value?.toString() ?? '').trim() : '';

      if (sheet.rows.isEmpty) throw Exception('This file has no rows.');
      for (var i = 0; i < _headers.length; i++) {
        final actual = cell(sheet.rows[0], i);
        if (normalizeImportHeader(actual) !=
            normalizeImportHeader(_headers[i])) {
          throw Exception(
            'Column ${i + 1} should be "${_headers[i]}" but found '
            '"${actual.isEmpty ? t('(empty)') : actual}". Please use the sample file '
            'and don\'t reorder its columns.',
          );
        }
      }

      final rows = <_Row>[];
      for (var r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.every((c) => (c?.value?.toString() ?? '').trim().isEmpty)) {
          continue;
        }
        var col = 0;
        final values = <String, dynamic>{
          'name': cell(row, col++),
          'phone': cell(row, col++),
          'gst_number': cell(row, col++).toUpperCase(),
          'address': cell(row, col++),
          'state_code': cell(row, col++),
        };
        final item = _Row(r + 1, values);
        double? number(String label) {
          final raw = cell(row, col++);
          if (raw.isEmpty) return null;
          try {
            return parseImportNum(raw);
          } catch (_) {
            item.errors.add('$label "$raw" is not a number');
            return null;
          }
        }

        if (!widget.suppliers) values['credit_limit'] = number('Credit limit');
        values['opening_balance'] = number('Opening balance') ?? 0;
        if ((values['name'] as String).isEmpty) {
          item.errors.add('Name is missing');
        }
        final gstin = values['gst_number'] as String;
        if (gstin.isNotEmpty && gstinError(gstin) != null) {
          item.errors.add(gstinError(gstin)!);
        }
        if (widget.suppliers && (values['opening_balance'] as double) < 0) {
          item.errors.add(
            'Opening balance for a supplier must be what you owe (not negative)',
          );
        }
        rows.add(item);
      }
      setState(() => _rows = rows);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final good = _rows.where((r) => r.errors.isEmpty).toList();
    if (good.isEmpty) return;
    setState(() => _busy = true);
    try {
      final res = await ref
          .read(supabaseProvider)
          .rpc(
            widget.suppliers ? 'import_suppliers' : 'import_customers',
            params: {
              'p_rows': [for (final r in good) r.values],
              'p_as_of': ymd(_asOf),
            },
          );
      setState(() => _result = Map<String, dynamic>.from(res as Map));
      if (widget.suppliers) {
        ref.invalidate(suppliersProvider);
      } else {
        ref.invalidate(customersProvider);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(now.year - 5),
      lastDate: now.subtract(const Duration(days: 1)),
    );
    if (d != null) setState(() => _asOf = d);
  }

  @override
  Widget build(BuildContext context) {
    final good = _rows.where((r) => r.errors.isEmpty).length;
    final result = _result;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text('Import $_what'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Download the sample file and fill in your $_what\n'
                    '2. Opening balance: what ${widget.suppliers ? t('you owe them') : 'they owe you'}'
                    '${widget.suppliers ? '' : ' (a minus amount = advance they paid you)'}\n'
                    '3. Choose the file, check the rows, then import',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: Text('Balances as of ${dateStr(_asOf)}'),
                    subtitle: Text(
                      widget.suppliers
                          ? t('Paid off first by your next supplier payments')
                          : 'Due after your payment terms from this date; '
                                'receipts settle it first',
                    ),
                    trailing: Text(t('Change')),
                    onTap: _pickDate,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _downloadSample,
                          icon: const Icon(Icons.download),
                          label: Text(t('Sample file')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: Text(t('Choose file')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (result != null) ...[
            SectionLabel(t('Result')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${result['created']} imported',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.green,
                      ),
                    ),
                    for (final s in List.from(result['skipped'] as List? ?? []))
                      Text(
                        'Row ${s['row']} ${s['name']}: skipped — ${s['reason']}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    for (final e in List.from(result['errors'] as List? ?? []))
                      Text(
                        'Row ${e['row']} ${e['name']}: ${friendlyError(e['error'] ?? '')}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.red,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_rows.isNotEmpty) ...[
            SectionLabel(
              '${_fileName ?? t('File')}: $good ready, ${_rows.length - good} with errors',
            ),
            Card(
              child: Column(
                children: [
                  for (final r in _rows)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        r.errors.isEmpty
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: r.errors.isEmpty
                            ? AppColors.green
                            : AppColors.red,
                        size: 20,
                      ),
                      title: Text('Row ${r.number}: ${r.values['name']}'),
                      subtitle: Text(
                        r.errors.isNotEmpty
                            ? r.errors.join(' • ')
                            : 'Opening ${money(r.values['opening_balance'] as num?)}'
                                  '${(r.values['phone'] as String).isEmpty ? '' : ' • ${r.values['phone']}'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: r.errors.isEmpty
                              ? AppColors.inkSoft
                              : AppColors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || good == 0 || result != null ? null : _import,
              child: Text(_busy ? t('Importing…') : 'Import $good $_what'),
            ),
          ],
        ],
      ),
    );
  }
}
