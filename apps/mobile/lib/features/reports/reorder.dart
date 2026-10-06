import '../../core/i18n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

export '../../core/whatsapp_helper.dart' show whatsAppNumber;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/file_export.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

// ---------------- pure helpers (tested) ----------------

/// One low-stock product (or variant) on the reorder list.
class ReorderItem {
  ReorderItem({
    required this.product,
    this.variant,
    required this.stock,
    required this.alert,
  }) : qty = suggestedReorderQty(stock, alert, allowDecimal: _allowDecimal(product));

  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;
  final double stock;
  final double alert;
  double qty;
  bool selected = true;
  String? lastSupplierId;
  String lastSupplierName = '';
  String? lastDate; // purchase_date of the latest purchase, yyyy-mm-dd

  static bool _allowDecimal(Map<String, dynamic> p) =>
      (p['units'] as Map?)?['allow_decimal'] == true;

  String get productId => product['id'] as String;
  String? get variantId => variant?['id'] as String?;
  String get key => '$productId/${variantId ?? ''}';
  bool get allowDecimal => _allowDecimal(product);
  String get unit => (product['units'] as Map?)?['short_name'] as String? ?? '';
  String get name => variant == null
      ? product['name'] as String? ?? ''
      : '${product['name']} — ${variant!['name']}';
}

/// How much to order: enough to get back to twice the alert level, so the
/// shop isn't reordering again a week later. Whole units unless the unit
/// allows decimals (kg, litre…); never less than one unit.
double suggestedReorderQty(double stock, double alert, {bool allowDecimal = false}) {
  final need = alert * 2 - stock;
  if (allowDecimal) {
    final q = (need * 10).ceil() / 10;
    return q < 1 ? 1 : q;
  }
  final q = need.ceil().toDouble();
  return q < 1 ? 1 : q;
}

/// Products/variants at or below their low-stock alert. Same rule as the
/// Low stock report and the dashboard count: a variant uses its own alert
/// level, inheriting the product's; a variant product's parent row is skipped.
List<ReorderItem> lowStockItems(List rows) {
  final out = <ReorderItem>[];
  for (final r in rows) {
    final p = Map<String, dynamic>.from(r as Map);
    final variants = [
      for (final v in List<Map<String, dynamic>>.from(p['product_variants'] as List? ?? []))
        if (v['is_active'] == true) v,
    ];
    if (p['has_variants'] == true && variants.isNotEmpty) {
      for (final v in variants) {
        final alert = toDouble(v['low_stock_qty'] ?? p['low_stock_qty']);
        final stock = toDouble(v['current_stock']);
        if (alert > 0 && stock <= alert) {
          out.add(ReorderItem(product: p, variant: v, stock: stock, alert: alert));
        }
      }
    } else {
      final alert = toDouble(p['low_stock_qty']);
      final stock = toDouble(p['current_stock']);
      if (alert > 0 && stock <= alert) {
        out.add(ReorderItem(product: p, stock: stock, alert: alert));
      }
    }
  }
  return out;
}

/// Fills in who each item was last bought from, given purchase_items rows
/// with an embedded `purchases(supplier_id, supplier_name, purchase_date)`.
void applyLastSuppliers(List<ReorderItem> items, List rows) {
  final byKey = {for (final i in items) i.key: i};
  final byProduct = <String, List<ReorderItem>>{};
  for (final i in items) {
    byProduct.putIfAbsent(i.productId, () => []).add(i);
  }
  for (final r in rows) {
    final pur = r['purchases'] as Map?;
    if (pur == null || pur['supplier_id'] == null) continue;
    final date = '${pur['purchase_date']}';
    // An exact variant match wins; a product-level line covers all its variants.
    final targets = r['variant_id'] != null
        ? [if (byKey['${r['product_id']}/${r['variant_id']}'] != null) byKey['${r['product_id']}/${r['variant_id']}']!]
        : byProduct[r['product_id']] ?? const <ReorderItem>[];
    for (final t in targets) {
      if (t.lastDate == null || date.compareTo(t.lastDate!) > 0) {
        t.lastDate = date;
        t.lastSupplierId = pur['supplier_id'] as String;
        t.lastSupplierName = pur['supplier_name'] as String? ?? '';
      }
    }
  }
}

/// The supplier most of the low items were last bought from (null if none).
String? likelySupplier(List<ReorderItem> items) {
  final count = <String, int>{};
  for (final i in items) {
    if (i.lastSupplierId != null) count[i.lastSupplierId!] = (count[i.lastSupplierId!] ?? 0) + 1;
  }
  if (count.isEmpty) return null;
  return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

/// WhatsApp-ready text of the order.
String reorderMessage({
  required String supplierName,
  required String shopName,
  required String shopPhone,
  required List<ReorderItem> items,
}) {
  final b = StringBuffer();
  b.writeln(supplierName.isEmpty ? 'Namaste,' : 'Namaste $supplierName ji,');
  b.writeln('Please send the following items:');
  b.writeln();
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    b.writeln('${i + 1}. ${it.name} — ${qty(it.qty)} ${it.unit}'.trimRight());
  }
  b.writeln();
  b.write('— $shopName');
  if (shopPhone.isNotEmpty) b.write(', $shopPhone');
  return b.toString();
}

/// The order as an A4 PDF (purchase order, no prices).
Future<Uint8List> buildReorderPdf({
  required Map<String, dynamic> business,
  required Map<String, dynamic>? supplier,
  required List<ReorderItem> items,
}) async {
  final doc = pw.Document();
  final small = const pw.TextStyle(fontSize: 9);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  business['name'] as String? ?? '',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                if ((business['address'] as String? ?? '').isNotEmpty)
                  pw.Text(business['address'] as String, style: small),
                if ((business['phone'] as String? ?? '').isNotEmpty)
                  pw.Text(t('Phone: {v1}', {'v1': business['phone']}), style: small),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('PURCHASE ORDER',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(t('Date: {v1}', {'v1': dateStr(DateTime.now())}), style: small),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        if (supplier != null) ...[
          pw.Text('To', style: small),
          pw.Text(
            supplier['name'] as String? ?? '',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if ((supplier['phone'] as String? ?? '').isNotEmpty)
            pw.Text(t('Phone: {v1}', {'v1': supplier['phone']}), style: small),
          pw.SizedBox(height: 14),
        ],
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(),
            2: const pw.FixedColumnWidth(90),
          },
          cellAlignments: {0: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight},
          headers: ['#', 'Item', 'Quantity'],
          data: [
            for (var i = 0; i < items.length; i++)
              ['${i + 1}', items[i].name, '${qty(items[i].qty)} ${items[i].unit}'.trim()],
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Text('Please confirm availability and rates.', style: small),
      ],
    ),
  );
  return doc.save();
}

// ---------------- screen ----------------

final _reorderDataProvider = FutureProvider.autoDispose<
    ({List<ReorderItem> items, List<Map<String, dynamic>> suppliers})>((ref) async {
  final client = ref.watch(supabaseProvider);
  final rows = await client
      .from('products')
      .select(
        'id, name, current_stock, low_stock_qty, has_variants, purchase_price, gst_rate, '
        'track_serial, secondary_unit_name, conversion_factor, units(short_name, allow_decimal), '
        'product_variants(id, name, current_stock, low_stock_qty, purchase_price, is_active)',
      )
      .eq('is_active', true)
      .order('name', ascending: true)
      .limit(1000);
  final items = lowStockItems(rows);
  final suppliers = List<Map<String, dynamic>>.from(
    await client.from('suppliers').select('id, name, phone').eq('is_active', true).order('name'),
  );
  if (items.isNotEmpty) {
    final history = await client
        .from('purchase_items')
        .select('product_id, variant_id, purchases!inner(supplier_id, supplier_name, purchase_date)')
        .inFilter('product_id', items.map((i) => i.productId).toSet().toList())
        .limit(3000);
    applyLastSuppliers(items, history);
  }
  return (items: items, suppliers: suppliers);
});

/// Reorder low-stock items from a supplier: send the order on WhatsApp,
/// print or share it as a PDF, or open it as a purchase when the goods come.
class ReorderScreen extends ConsumerStatefulWidget {
  const ReorderScreen({super.key});

  @override
  ConsumerState<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends ConsumerState<ReorderScreen> {
  String? _supplierId;
  bool _initialised = false;
  bool _busy = false;
  final _qtyControllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _init(List<ReorderItem> items) {
    if (_initialised) return;
    _initialised = true;
    _supplierId = likelySupplier(items);
    _selectFor(items);
  }

  /// Ticks the items last bought from the chosen supplier — or everything
  /// when no supplier is chosen or none of the items came from them.
  void _selectFor(List<ReorderItem> items) {
    final fromThem = items.where((i) => i.lastSupplierId == _supplierId).toList();
    for (final i in items) {
      i.selected = _supplierId == null || fromThem.isEmpty || i.lastSupplierId == _supplierId;
    }
  }

  TextEditingController _qtyC(ReorderItem it) => _qtyControllers.putIfAbsent(
    it.key,
    () => TextEditingController(text: qty(it.qty).replaceAll(',', '')),
  );

  Map<String, dynamic>? _supplier(List<Map<String, dynamic>> suppliers) {
    for (final s in suppliers) {
      if (s['id'] == _supplierId) return s;
    }
    return null;
  }

  List<ReorderItem> _chosen(List<ReorderItem> items) =>
      [for (final i in items) if (i.selected && i.qty > 0) i];

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsApp(List<ReorderItem> chosen, Map<String, dynamic>? supplier) async {
    final business = ref.read(appContextProvider).value?.business ?? {};
    final text = reorderMessage(
      supplierName: supplier?['name'] as String? ?? '',
      shopName: business['name'] as String? ?? '',
      shopPhone: business['phone'] as String? ?? '',
      items: chosen,
    );
    await sendWhatsAppText(
      supplier?['phone'] as String? ?? '',
      text,
      subject: 'Order',
    );
  }

  Future<Uint8List> _pdf(List<ReorderItem> chosen, Map<String, dynamic>? supplier) => buildReorderPdf(
    business: ref.read(appContextProvider).value?.business ?? {},
    supplier: supplier,
    items: chosen,
  );

  String _fileName(Map<String, dynamic>? supplier) =>
      'Order_${(supplier?['name'] as String? ?? 'supplier').replaceAll(' ', '_')}_${ymd(DateTime.now())}.pdf';

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_reorderDataProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(leading: appBarBack(context), title: Text(t('Reorder low stock'))),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(_reorderDataProvider),
        builder: (d) {
          final items = d.items;
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2_outlined,
              message: t('Nothing is low on stock right now.'),
            );
          }
          _init(items);
          final supplier = _supplier(d.suppliers);
          final chosen = _chosen(items);
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        DropdownButtonFormField<String?>(
                          initialValue: _supplierId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t('Order from supplier'),
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                          ),
                          items: [
                            DropdownMenuItem<String?>(value: null, child: Text(t('No supplier (just the list)'))),
                            for (final s in d.suppliers)
                              DropdownMenuItem<String?>(
                                value: s['id'] as String,
                                child: Text(
                                  (s['phone'] as String? ?? '').isEmpty ? '${s['name']}' : '${s['name']} · ${s['phone']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _supplierId = v;
                            _selectFor(items);
                          }),
                        ),
                        const SizedBox(height: 6),
                        Text(t('Items last bought from this supplier are ticked. Change any quantity before sending.'),
                          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: Column(
                            children: [
                              for (final it in items) _row(it),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _actions(chosen, supplier),
            ],
          );
        },
      ),
    );
  }

  Widget _row(ReorderItem it) {
    final sub = [
      'Stock ${qty(it.stock)} ${it.unit} · alert ${qty(it.alert)}'.trim(),
      if (it.lastSupplierName.isNotEmpty) 'last from ${it.lastSupplierName}',
    ].join(' · ');
    return InkWell(
      onTap: () => setState(() => it.selected = !it.selected),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            Checkbox(value: it.selected, onChanged: (v) => setState(() => it.selected = v ?? false)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(sub, style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _qtyC(it),
                enabled: it.selected,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(isDense: true, labelText: t('Order'), suffixText: it.unit),
                onChanged: (v) => setState(() => it.qty = double.tryParse(v) ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(List<ReorderItem> chosen, Map<String, dynamic>? supplier) {
    final enabled = chosen.isNotEmpty && !_busy;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                chosen.isEmpty ? t('Tick the items to order') : '${chosen.length} item${chosen.length == 1 ? '' : 's'} to order',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    onPressed: enabled ? () => _run(() => _whatsApp(chosen, supplier)) : null,
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(t('Send on WhatsApp')),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled
                        ? () => _run(() async {
                            final bytes = await _pdf(chosen, supplier);
                            await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName(supplier));
                          })
                        : null,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(t('Print')),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled
                        ? () => _run(() async {
                            final message = await saveOrShareFile(
                              await _pdf(chosen, supplier),
                              _fileName(supplier),
                              subject: 'Order',
                            );
                            if (message != null && mounted) showSuccess(context, message);
                          })
                        : null,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(t('Share PDF')),
                  ),
                  if (ref.watch(appContextProvider).value?.canManagePurchases ?? false)
                    OutlinedButton.icon(
                      onPressed: enabled
                          ? () => context.push(
                              _supplierId == null ? '/purchases/new' : '/purchases/new?supplier=$_supplierId',
                              extra: [
                                for (final i in chosen) {'product': i.product, 'variant': i.variant, 'qty': i.qty},
                              ],
                            )
                          : null,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text(t('Goods came? Add purchase')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
