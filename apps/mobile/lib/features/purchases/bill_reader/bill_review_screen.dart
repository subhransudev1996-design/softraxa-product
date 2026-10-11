import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/i18n.dart';
import '../../../core/supabase_providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../pos/pos_providers.dart' show posProductColumns;
import '../../suppliers/suppliers.dart';
import '../purchase_form_screen.dart' show showPurchaseProductPicker;
import '../quick_add_product.dart';
import 'bill_match.dart';
import 'bill_parser.dart';
import 'pdf_words.dart';
import 'sheet_rows.dart';

/// A line read from the bill, checked by the shop, for the purchase form.
class BillReadLine {
  const BillReadLine({
    required this.product,
    this.variant,
    required this.qty,
    required this.price,
    required this.gstRate,
    this.serials = const [],
  });

  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  /// In the product's own unit.
  final double qty;

  /// Per unit of the product, before GST, discounts taken off.
  final double price;
  final double gstRate;

  /// IMEI / serial numbers printed under the item on the bill.
  final List<String> serials;
}

class BillReadResult {
  const BillReadResult({
    this.supplier,
    this.billNo = '',
    this.date,
    required this.lines,
    this.discount = 0,
    this.extraCharges = 0,
  });

  final Map<String, dynamic>? supplier;
  final String billNo;
  final DateTime? date;
  final List<BillReadLine> lines;

  /// The bill's total less what its lines come to: a bill discount, or
  /// charges (freight…), when the shop chose to carry it over.
  final double discount;
  final double extraCharges;
}

/// "Read supplier bill": pick the supplier's PDF or Excel/CSV bill, check
/// what was read, and get its lines for the purchase. Null when cancelled.
Future<BillReadResult?> readSupplierBill(
  BuildContext context, {
  Map<String, dynamic>? supplier,
}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'xlsx', 'xls', 'csv'],
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  Uint8List? bytes = file.bytes;
  if (bytes == null && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null || !context.mounted) return null;
  final data = bytes;
  return Navigator.of(context).push<BillReadResult>(
    MaterialPageRoute(
      builder: (_) => BillReviewScreen(
        bytes: data,
        fileName: file.name,
        supplier: supplier,
      ),
    ),
  );
}

/// How a line's product was found.
enum _Found { remembered, code, suggested, none }

class _Line {
  _Line(this.bill);

  final BillLine bill;
  Map<String, dynamic>? product;
  Map<String, dynamic>? variant;
  _Found found = _Found.none;

  /// In the bill's units, free ones included.
  double qty = 0;

  /// Per unit on the bill, before GST, discounts taken off.
  double price = 0;

  /// Null: the product's own GST rate.
  double? gst;

  /// How many of the product's units one unit on the bill is.
  double factor = 1;
  bool skip = false;

  String get key => billItemKey(bill.name);
  double get gstRate => gst ?? toDouble(product?['gst_rate']);
  double get value => qty * price;
  double get total => value * (1 + gstRate / 100);
  double get baseQty => qty * factor;
  double get basePrice => factor > 0 ? price / factor : price;
  Map? get _units => product?['units'] as Map?;
  String get unitName => _units?['short_name'] as String? ?? '';
  bool get wholeOnly => product != null && _units?['allow_decimal'] != true;
  bool get notWhole =>
      wholeOnly && (baseQty - baseQty.roundToDouble()).abs() > 1e-6;

  /// Ready to add without a look.
  bool get ready =>
      product != null &&
      (found == _Found.remembered || found == _Found.code) &&
      bill.agrees &&
      !notWhole;

  String get productLabel {
    final p = product;
    if (p == null) return '';
    final v = variant?['name'] as String? ?? '';
    return v.isEmpty ? '${p['name']}' : '${p['name']} ($v)';
  }
}

class BillReviewScreen extends ConsumerStatefulWidget {
  const BillReviewScreen({
    super.key,
    required this.bytes,
    required this.fileName,
    this.supplier,
  });

  final Uint8List bytes;
  final String fileName;
  final Map<String, dynamic>? supplier;

  @override
  ConsumerState<BillReviewScreen> createState() => _BillReviewScreenState();
}

class _BillReviewScreenState extends ConsumerState<BillReviewScreen> {
  bool _loading = true;
  String? _error;
  String _ownGstin = '';
  List<BillWord> _words = const [];
  ParsedBill? _bill;
  Map<String, BillCol> _overrides = {};
  bool _columnsChanged = false;
  Map<String, dynamic>? _supplier;
  final _billNo = TextEditingController();
  DateTime? _date;
  List<_Line> _lines = [];
  List<MatchProduct> _catalog = const [];
  final Map<String, Map<String, dynamic>> _full = {};
  Map<String, Map<String, dynamic>> _memory = {};
  bool? _carryDifference;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _load();
  }

  @override
  void dispose() {
    _billNo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final name = widget.fileName.toLowerCase();
      _words = name.endsWith('.pdf')
          ? await readPdfWords(widget.bytes)
          : [
              for (final (i, sheet) in readSheets(
                widget.bytes,
                widget.fileName,
              ).indexed)
                ...sheetWords(sheet, page: i),
            ];
      _ownGstin =
          ref.read(appContextProvider).value?.business?['gst_number']
              as String? ??
          '';
      var bill = parseBill(_words, ownGstin: _ownGstin);
      if (bill.lines.isEmpty) {
        throw PdfReadError(
          t(
            'No item lines could be found on this bill. If it is a PDF made by billing software, send it to support so we can learn its layout.',
          ),
        );
      }
      _supplier ??= await _supplierFor(bill);
      _catalog = await _loadCatalog();
      await _loadMemory(bill);
      if (_overrides.isNotEmpty) {
        bill = parseBill(_words, ownGstin: _ownGstin, overrides: _overrides);
      }
      _bill = bill;
      _billNo.text = bill.billNo;
      _date = bill.date;
      await _buildLines();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is PdfReadError ? e.message : friendlyError(e);
        });
      }
    }
  }

  /// The supplier whose GSTIN is on the bill, if the shop has them.
  Future<Map<String, dynamic>?> _supplierFor(ParsedBill bill) async {
    if (bill.gstins.isEmpty) return null;
    final rows = await ref
        .read(supabaseProvider)
        .from('suppliers')
        .select()
        .eq('is_active', true)
        .inFilter('gst_number', bill.gstins);
    if (rows.isEmpty) return null;
    // The first GSTIN on the bill is the seller's.
    for (final g in bill.gstins) {
      for (final r in rows) {
        if ('${r['gst_number']}'.toUpperCase() == g) {
          return Map<String, dynamic>.from(r);
        }
      }
    }
    return Map<String, dynamic>.from(rows.first);
  }

  /// The shop's active products, names only, for matching.
  Future<List<MatchProduct>> _loadCatalog() async {
    final client = ref.read(supabaseProvider);
    final out = <MatchProduct>[];
    for (var from = 0; from < 60000; from += 1000) {
      final rows = await client
          .from('products')
          .select(
            'id, name, sku, barcode, hsn_code, '
            'product_variants(id, name, sku, barcode, is_active)',
          )
          .eq('is_active', true)
          .order('id')
          .range(from, from + 999);
      out.addAll(rows.map(MatchProduct.fromRow));
      if (rows.length < 1000) break;
    }
    return out;
  }

  /// What the shop taught for these names and this supplier's columns.
  /// Reading still works without it (an older database, no permission).
  Future<void> _loadMemory(ParsedBill bill) async {
    _memory = {};
    try {
      final res = await ref
          .read(supabaseProvider)
          .rpc(
            'bill_memory',
            params: {
              'p_supplier': _supplier?['id'],
              'p_keys': {
                for (final l in bill.lines) billItemKey(l.name),
              }.take(500).toList(),
            },
          );
      final map = Map<String, dynamic>.from(res as Map);
      for (final it in (map['items'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(it as Map);
        _memory[m['key'] as String] = m;
      }
      final cols = Map<String, dynamic>.from(map['columns'] as Map? ?? {});
      _overrides = {
        for (final e in cols.entries)
          if (BillCol.values.any((c) => c.name == e.value))
            e.key: BillCol.values.byName(e.value as String),
      };
    } catch (_) {
      _overrides = {};
    }
  }

  Future<void> _fetchFull(Iterable<String> ids) async {
    final missing = ids.where((id) => !_full.containsKey(id)).toSet().toList();
    final client = ref.read(supabaseProvider);
    for (var i = 0; i < missing.length; i += 150) {
      final chunk = missing.sublist(i, (i + 150).clamp(0, missing.length));
      final rows = await client
          .from('products')
          .select(posProductColumns)
          .inFilter('id', chunk);
      for (final r in rows) {
        _full[r['id'] as String] = Map<String, dynamic>.from(r);
      }
    }
  }

  Map<String, dynamic>? _variantOf(Map<String, dynamic>? product, String? id) {
    if (product == null || id == null) return null;
    for (final v in (product['product_variants'] as List? ?? const [])) {
      if ((v as Map)['id'] == id) return Map<String, dynamic>.from(v);
    }
    return null;
  }

  /// One review line per bill line: the remembered product, else a barcode
  /// on the bill, else the closest name. [keep]: the shop's choices before
  /// the bill was read again (by name).
  Future<void> _buildLines({Map<String, _Line> keep = const {}}) async {
    final lines = <_Line>[];
    final ids = <String, (String, String?)>{};
    for (final b in _bill!.lines) {
      final l = _Line(b);
      final mem = _memory[l.key];
      if (mem != null) {
        ids[l.key] = (
          mem['product_id'] as String,
          mem['variant_id'] as String?,
        );
        l.found = _Found.remembered;
        l.factor = toDouble(mem['factor']) > 0 ? toDouble(mem['factor']) : 1;
      } else {
        final m = bestMatch(b.name, _catalog, code: b.code, hsn: b.hsn);
        if (m != null) {
          ids[l.key] = (m.productId, m.variantId);
          l.found = m.byCode ? _Found.code : _Found.suggested;
        }
      }
      lines.add(l);
    }
    await _fetchFull(ids.values.map((e) => e.$1));
    for (final l in lines) {
      l.qty = l.bill.stockQty;
      l.price = l.bill.unitCost;
      l.gst = l.bill.gstRate;
      final before = keep[l.key];
      if (before != null) {
        l
          ..product = before.product
          ..variant = before.variant
          ..found = before.found
          ..factor = before.factor
          ..skip = before.skip;
        continue;
      }
      final id = ids[l.key];
      final p = id == null ? null : _full[id.$1];
      if (p == null) {
        l.found = _Found.none;
        continue;
      }
      l.product = p;
      l.variant = _variantOf(p, id!.$2);
      if (l.found != _Found.remembered) {
        l.factor = defaultPackFactor(
          l.bill.unit,
          secondaryUnit: p['secondary_unit_name'] as String?,
          conversionFactor: (p['conversion_factor'] as num?)?.toDouble(),
          baseUnit: l.unitName,
        );
      }
    }
    _lines = lines;
  }

  // ---------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------

  List<_Line> get _used => _lines.where((l) => !l.skip).toList();
  double get _linesTotal => _used.fold(0, (s, l) => s + l.total);

  /// Bill total less the lines (positive: charges; negative: a discount).
  double? get _difference {
    final total = _bill?.total;
    if (total == null) return null;
    return total - _linesTotal;
  }

  bool get _differenceSmall {
    final d = _difference;
    final total = _bill?.total ?? 0;
    return d != null && d.abs() <= total * 0.05;
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _chooseSupplier() async {
    final client = ref.read(supabaseProvider);
    final suppliers = List<Map<String, dynamic>>.from(
      await client
          .from('suppliers')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true),
    );
    if (!mounted) return;
    final bill = _bill!;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t('Select supplier'),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add, color: AppColors.primary),
                title: Text(
                  bill.supplierName.isEmpty
                      ? t('Add new supplier')
                      : t('Add "{v1}" as a new supplier', {
                          'v1': bill.supplierName,
                        }),
                  style: const TextStyle(color: AppColors.primary),
                ),
                onTap: () async {
                  final created = await showSupplierForm(
                    ctx,
                    ref,
                    initial: {
                      'name': bill.supplierName,
                      'gst_number': bill.gstins.isEmpty
                          ? ''
                          : bill.gstins.first,
                    },
                  );
                  if (created != null && ctx.mounted) {
                    Navigator.pop(ctx, created);
                  }
                },
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in suppliers)
                      ListTile(
                        title: Text(s['name'] as String),
                        subtitle: Text(
                          [
                            s['phone'] as String? ?? '',
                            s['gst_number'] as String? ?? '',
                          ].where((x) => x.isNotEmpty).join(' · '),
                        ),
                        onTap: () => Navigator.pop(ctx, s),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _supplier = picked;
      _loading = true;
    });
    // That supplier's names and columns.
    final keep = {
      for (final l in _lines)
        if ((l.product != null && l.found != _Found.suggested) || l.skip)
          l.key: l,
    };
    await _loadMemory(_bill!);
    if (_overrides.isNotEmpty) {
      _bill = parseBill(_words, ownGstin: _ownGstin, overrides: _overrides);
    }
    await _buildLines(keep: keep);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _editColumns() async {
    final cols = [
      for (final c in _bill!.columns)
        BillColumn(c.label, c.left, c.right, c.role),
    ];
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    t('Columns on this bill'),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    t(
                      'Set what each column holds. This supplier\'s next bills are read the same way.',
                    ),
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final c in cols)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<BillCol>(
                                value: c.role,
                                items: [
                                  for (final r in BillCol.values)
                                    DropdownMenuItem(
                                      value: r,
                                      child: Text(_roleLabel(r)),
                                    ),
                                ],
                                onChanged: (r) {
                                  if (r != null) setSheet(() => c.role = r);
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(t('Cancel')),
                      ),
                      const Spacer(),
                      FilledButton(
                        style: dialogActionStyle,
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(t('Read again')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final keep = {
      for (final l in _lines)
        if (l.product != null || l.skip) l.key: l,
    };
    setState(() => _loading = true);
    _overrides = {for (final c in cols) c.key: c.role};
    _columnsChanged = true;
    final bill = parseBill(_words, ownGstin: _ownGstin, overrides: _overrides);
    _bill = ParsedBill(
      lines: bill.lines,
      columns: bill.columns,
      billNo: _billNo.text,
      date: _date,
      gstins: bill.gstins,
      supplierName: bill.supplierName,
      total: bill.total,
      foundHeader: bill.foundHeader,
    );
    await _buildLines(keep: keep);
    if (mounted) setState(() => _loading = false);
  }

  /// Choose (or add) the product a bill line is, inside the line sheet.
  Future<void> _pickProduct(
    _Line l,
    void Function(void Function()) setSheet,
  ) async {
    final firstWord = l.bill.name.split(RegExp(r'\s+')).first;
    final selected = await showPurchaseProductPicker(
      context,
      search: firstWord.length >= 3 ? firstWord : '',
      singleVariant: true,
    );
    if (selected == null || !mounted) return;
    Map<String, dynamic>? product;
    Map<String, dynamic>? variant;
    if (selected['new'] != null) {
      final id = await showQuickAddProduct(
        context,
        name: _tidyName(l.bill.name),
        purchasePrice: l.price,
        gstRate: l.gst,
      );
      if (id == null || !mounted) return;
      await _fetchFull([id]);
      product = _full[id];
    } else {
      product = Map<String, dynamic>.from(selected['product'] as Map);
      _full[product['id'] as String] = product;
      final v = selected['variant'];
      variant = v == null ? null : Map<String, dynamic>.from(v as Map);
    }
    if (product == null) return;
    final p = product;
    setSheet(() {
      l.product = p;
      l.variant = variant;
      l.found = _Found.remembered; // chosen by the shop
      l.factor = defaultPackFactor(
        l.bill.unit,
        secondaryUnit: p['secondary_unit_name'] as String?,
        conversionFactor: (p['conversion_factor'] as num?)?.toDouble(),
        baseUnit: l.unitName,
      );
    });
    setState(() {});
  }

  Future<void> _editLine(_Line l) async {
    final qtyC = TextEditingController(text: _plain(l.qty));
    final priceC = TextEditingController(text: l.price.toStringAsFixed(2));
    final gstC = TextEditingController(
      text: l.gst == null ? '' : _plain(l.gst!),
    );
    final factorC = TextEditingController(text: _plain(l.factor));
    final b = l.bill;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(b.name, style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    t('On the bill: {v1}', {'v1': _billText(b)}),
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                  if (!b.agrees) ...[
                    const SizedBox(height: 8),
                    _Note(
                      icon: Icons.warning_amber,
                      color: AppColors.orange,
                      text: t(
                        'The numbers on this line don\'t add up. Check the quantity and price against the bill.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        l.product == null
                            ? Icons.help_outline
                            : Icons.inventory_2_outlined,
                        color: l.product == null
                            ? AppColors.red
                            : AppColors.primary,
                      ),
                      title: Text(
                        l.product == null
                            ? t('Choose the product')
                            : l.productLabel,
                      ),
                      subtitle: Text(
                        l.product == null
                            ? t('Pick it from your products, or add it as new')
                            : t('Tap to change'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickProduct(l, setSheet),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyC,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: b.unit.isEmpty
                                ? t('Qty')
                                : t('Qty ({v1})', {'v1': b.unit}),
                            helperText: b.free > 0
                                ? t('{v1} free included', {
                                    'v1': _plain(b.free),
                                  })
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: priceC,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: t('Price ₹ (excl. GST)'),
                            helperText: t('After discount'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: gstC,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t('GST %'),
                      helperText: l.gst == null
                          ? t('Not on the bill: the product\'s own rate is used')
                          : null,
                    ),
                  ),
                  if (l.product != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          t('1 {v1} =', {
                            'v1': b.unit.isEmpty
                                ? t('unit on the bill')
                                : b.unit,
                          }),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: factorC,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.unitName.isEmpty
                                ? t('of your units')
                                : l.unitName,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        t(
                          'For a supplier who bills in boxes or cases: how many of your units come in one.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: l.skip,
                    title: Text(t('Leave this line out')),
                    subtitle: Text(
                      t('Not a product you stock (freight, a tax line…)'),
                    ),
                    onChanged: (v) => setSheet(() => l.skip = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('Done')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      l.qty = double.tryParse(qtyC.text.trim()) ?? l.qty;
      l.price = double.tryParse(priceC.text.trim()) ?? l.price;
      final g = gstC.text.trim();
      l.gst = g.isEmpty ? null : (double.tryParse(g) ?? l.gst);
      final f = double.tryParse(factorC.text.trim());
      if (f != null && f > 0) l.factor = f;
      // Looked at and kept: no longer only a suggestion.
      if (l.product != null && l.found == _Found.suggested) {
        l.found = _Found.remembered;
      }
    });
  }

  Future<void> _apply() async {
    final used = _used;
    if (used.isEmpty) {
      showError(context, t('Every line is left out — nothing to add'));
      return;
    }
    if (used.any((l) => l.product == null)) {
      showError(
        context,
        t('Choose the product for every line, or leave the line out'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'remember_bill',
            params: {
              'p_supplier': _supplier?['id'],
              'p_items': [
                for (final l in used)
                  {
                    'key': l.key,
                    'product_id': l.product!['id'],
                    'variant_id': l.variant?['id'],
                    'factor': l.factor,
                  },
              ],
              'p_columns': _columnsChanged && _bill!.columns.isNotEmpty
                  ? {for (final c in _bill!.columns) c.key: c.role.name}
                  : null,
            },
          );
    } catch (_) {
      // Remembering helps the next bill; this one goes on without it.
    }
    if (!mounted) return;
    final d = _difference ?? 0;
    final carry = (_carryDifference ?? _differenceSmall) && d.abs() > 1;
    Navigator.pop(
      context,
      BillReadResult(
        supplier: _supplier,
        billNo: _billNo.text.trim(),
        date: _date,
        lines: [
          for (final l in used)
            BillReadLine(
              product: l.product!,
              variant: l.variant,
              qty: l.baseQty,
              price: l.basePrice,
              gstRate: l.gstRate,
              serials: l.bill.serials,
            ),
        ],
        discount: carry && d < 0 ? -d : 0,
        extraCharges: carry && d > 0 ? d : 0,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(t('Read supplier bill')),
        actions: [
          if (bill != null && bill.columns.isNotEmpty && !_loading)
            TextButton.icon(
              onPressed: _editColumns,
              icon: const Icon(Icons.view_column_outlined),
              label: Text(t('Columns')),
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(t('Reading the bill…')),
                ],
              ),
            )
          : _error != null
          ? EmptyState(icon: Icons.description_outlined, message: _error!)
          : _body(bill!),
      bottomNavigationBar: _loading || _error != null ? null : _bottomBar(),
    );
  }

  Widget _body(ParsedBill bill) {
    final ready = _lines.where((l) => !l.skip && l.ready).length;
    final unmatched = _lines.where((l) => !l.skip && l.product == null).length;
    final check = _used.length - ready - unmatched;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _chooseSupplier,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: t('Supplier'),
                      suffixIcon: const Icon(Icons.chevron_right),
                    ),
                    child: Text(
                      _supplier?['name'] as String? ??
                          (bill.supplierName.isEmpty
                              ? t('Select supplier')
                              : t('On the bill: {v1} — tap to choose', {
                                  'v1': bill.supplierName,
                                })),
                      style: TextStyle(
                        color: _supplier == null ? AppColors.orange : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _billNo,
                        decoration: InputDecoration(
                          labelText: t('Supplier bill no.'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(labelText: t('Date')),
                          child: Text(
                            _date == null ? t('Not found') : dateStr(_date),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(text: t('{v1} ready', {'v1': ready}), color: AppColors.green),
            if (check > 0)
              _Chip(
                text: t('{v1} to check', {'v1': check}),
                color: AppColors.orange,
              ),
            if (unmatched > 0)
              _Chip(
                text: t('{v1} not matched', {'v1': unmatched}),
                color: AppColors.red,
              ),
          ],
        ),
        if (!bill.foundHeader) ...[
          const SizedBox(height: 12),
          _Note(
            icon: Icons.info_outline,
            color: AppColors.orange,
            text: t(
              'The item table\'s headings weren\'t recognised, so lines were picked out by their numbers. Check each one against the bill.',
            ),
          ),
        ],
        const SizedBox(height: 12),
        _totalCard(bill),
        const SizedBox(height: 4),
        for (final l in _lines) _lineTile(l),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _totalCard(ParsedBill bill) {
    final d = _difference;
    if (d == null) {
      return _Note(
        icon: Icons.info_outline,
        color: AppColors.inkSoft,
        text: t(
          'The bill\'s total wasn\'t found. The lines come to {v1} with GST — compare it with the bill.',
          {'v1': money(_linesTotal)},
        ),
      );
    }
    if (d.abs() <= 1) {
      return _Note(
        icon: Icons.check_circle_outline,
        color: AppColors.green,
        text: t('Bill total {v1} — the lines add up to it', {
          'v1': money(bill.total),
        }),
      );
    }
    final carry = _carryDifference ?? _differenceSmall;
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.orangeSoft,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: AppColors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('Bill total {v1}, the lines come to {v2}', {
                      'v1': money(bill.total),
                      'v2': money(_linesTotal),
                    }),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'A difference of {v1}: the bill may have a discount or charges (freight) of its own, or a line was read wrongly.',
                {'v1': money(d.abs())},
              ),
              style: const TextStyle(fontSize: 13),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: carry,
              title: Text(
                d < 0
                    ? t('Add {v1} to the purchase as a discount', {
                        'v1': money(-d),
                      })
                    : t('Add {v1} to the purchase as extra charges', {
                        'v1': money(d),
                      }),
              ),
              onChanged: (v) => setState(() => _carryDifference = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(_Line l) {
    final Color color;
    final String status;
    if (l.skip) {
      color = AppColors.inkSoft;
      status = t('Left out');
    } else if (l.product == null) {
      color = AppColors.red;
      status = t('Not matched — tap to choose');
    } else if (l.notWhole) {
      color = AppColors.orange;
      status = t('{v1} is counted in whole units — check the quantity', {
        'v1': l.unitName.isEmpty ? t('This product') : l.unitName,
      });
    } else if (!l.bill.agrees) {
      color = AppColors.orange;
      status = t('Numbers don\'t add up — check');
    } else if (l.found == _Found.suggested) {
      color = AppColors.orange;
      status = t('Suggested — check it is the right product');
    } else {
      color = AppColors.green;
      status = l.found == _Found.code ? t('Matched by barcode') : t('Matched');
    }
    final unit = l.bill.unit.isEmpty ? '' : ' ${l.bill.unit}';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => _editLine(l),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.product == null ? l.bill.name : l.productLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: l.skip ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (l.product != null)
                      Text(
                        t('On the bill: {v1}', {'v1': l.bill.name}),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '${_plain(l.qty)}$unit × ${money(l.price)}'
                      '${l.gstRate > 0 ? ' + GST ${_plain(l.gstRate)}%' : ''}'
                      '${l.product != null && l.factor != 1 ? '  ·  ${_plain(l.baseQty)} ${l.unitName}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (l.bill.serials.isNotEmpty)
                      Text(
                        'IMEI / S.No: ${l.bill.serials.join(', ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(status, style: TextStyle(fontSize: 12, color: color)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(l.total),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final used = _used;
    final missing = used.where((l) => l.product == null).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  missing == 1
                      ? t('Choose the product for 1 more line, or leave it out')
                      : t(
                          'Choose the product for {v1} more lines, or leave them out',
                          {'v1': missing},
                        ),
                  style: const TextStyle(fontSize: 13, color: AppColors.red),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving || missing > 0 || used.isEmpty
                    ? null
                    : _apply,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        used.length == 1
                            ? t('Add 1 line to the purchase')
                            : t('Add {v1} lines to the purchase', {
                                'v1': used.length,
                              }),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "10 Pcs × ₹550.00 · Disc 5% · GST 12% · ₹5,500.00" — the line as printed.
String _billText(BillLine b) {
  final parts = <String>[
    '${_plain(b.qty)}${b.free > 0 ? ' + ${_plain(b.free)}' : ''}'
        '${b.unit.isEmpty ? '' : ' ${b.unit}'}'
        '${b.rate != null ? ' × ${money(b.rate)}' : ''}',
    if (b.discPct != null) 'Disc ${_plain(b.discPct!)}%',
    if (b.discAmt != null) 'Disc ${money(b.discAmt)}',
    if (b.gstRate != null) 'GST ${_plain(b.gstRate!)}%',
    if (b.amount != null)
      money(b.amount)
    else if (b.taxable != null)
      money(b.taxable),
  ];
  return parts.join(' · ');
}

String _plain(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

/// "AMUL GHEE 1LTR TIN" → "Amul Ghee 1LTR Tin": a new product's name.
String _tidyName(String s) => s
    .split(RegExp(r'\s+'))
    .map((w) {
      if (w.isEmpty || RegExp(r'\d').hasMatch(w)) return w;
      if (w == w.toUpperCase() && w.length > 1) {
        return w[0] + w.substring(1).toLowerCase();
      }
      return w;
    })
    .join(' ');

String _roleLabel(BillCol r) => switch (r) {
  BillCol.sno => t('Serial no.'),
  BillCol.name => t('Item name'),
  BillCol.code => t('Item code / barcode'),
  BillCol.hsn => t('HSN'),
  BillCol.qty => t('Quantity'),
  BillCol.free => t('Free quantity'),
  BillCol.unit => t('Unit'),
  BillCol.rate => t('Rate'),
  BillCol.rateIncl => t('Rate with GST'),
  BillCol.mrp => t('MRP'),
  BillCol.disc => t('Discount %'),
  BillCol.discAmt => t('Discount ₹'),
  BillCol.taxable => t('Taxable value'),
  BillCol.gst => t('GST %'),
  BillCol.gstPart => t('CGST / SGST %'),
  BillCol.taxAmt => t('Tax amount'),
  BillCol.amount => t('Amount'),
  BillCol.ignore => t('Not needed'),
};

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 13, color: color)),
      ),
    ],
  );
}
