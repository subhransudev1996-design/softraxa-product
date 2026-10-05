import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../pos/cart.dart' show toBaseQty, roundOffFor;
import '../pos/pos_providers.dart' show posProductColumns;
import '../suppliers/suppliers.dart';
import 'purchase_providers.dart';
import '../../core/theme.dart';

class _PurchaseLine {
  _PurchaseLine({
    required this.productId,
    this.variantId,
    required this.name,
    this.variantName = '',
    required this.qty,
    required this.price,
    this.gstRate = 0,
    this.trackSerial = false,
    this.allowDecimal = false,
    this.unitName = '',
    this.secondaryUnitName,
    this.conversionFactor,
  });

  final String productId;
  final String? variantId;
  final String name;
  final String variantName;
  double qty; // always in the BASE unit
  double price; // per BASE unit, tax-exclusive entry
  double gstRate;
  final bool trackSerial;
  final bool allowDecimal;
  final String unitName;
  final String? secondaryUnitName; // e.g. Bag when base is kg
  final double? conversionFactor; // 1 secondary = X base units
  List<String> serialNos = [];

  double get taxable => qty * price;
  double get tax => taxable * gstRate / 100;
  double get total => taxable + tax;
}

/// Add purchase bill (PRD 7.12).
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({
    super.key,
    this.initialSupplierId,
    this.initialItems,
  });

  final String? initialSupplierId;

  /// Lines to start with, e.g. from the low-stock reorder list:
  /// `{'product': {...}, 'variant': {...}?, 'qty': num}`.
  final List<Map<String, dynamic>>? initialItems;

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  Map<String, dynamic>? _supplier;
  final _billNo = TextEditingController();
  final _discount = TextEditingController();
  final _extraCharges = TextEditingController();
  final _paid = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  String _paymentMode = 'cash';
  final List<_PurchaseLine> _lines = [];
  bool _busy = false;
  bool _paidTouched = false;
  bool _discountIsPercent = false;

  double get _subtotal => _lines.fold(0, (s, l) => s + l.taxable);
  double get _tax => _lines.fold(0, (s, l) => s + l.tax);

  /// Resolved ₹ discount, whichever unit was typed into `_discount`.
  double get _discountAmount {
    final raw = double.tryParse(_discount.text) ?? 0;
    return _discountIsPercent ? (_subtotal + _tax) * raw / 100 : raw;
  }

  double get _grandBeforeRound =>
      _subtotal +
      _tax -
      _discountAmount +
      (double.tryParse(_extraCharges.text) ?? 0);
  double get _roundOff => roundOffFor(_grandBeforeRound);
  double get _total => _grandBeforeRound + _roundOff;
  double get _paidAmount =>
      _paidTouched ? (double.tryParse(_paid.text) ?? 0) : _total;

  @override
  void initState() {
    super.initState();
    if (widget.initialSupplierId != null) _loadSupplier();
    for (final it in widget.initialItems ?? const <Map<String, dynamic>>[]) {
      _lines.add(
        _lineFor(
          Map<String, dynamic>.from(it['product'] as Map),
          it['variant'] == null
              ? null
              : Map<String, dynamic>.from(it['variant'] as Map),
          qty: toDouble(it['qty']) > 0 ? toDouble(it['qty']) : 1,
        ),
      );
    }
  }

  _PurchaseLine _lineFor(
    Map<String, dynamic> product,
    Map<String, dynamic>? variant, {
    double qty = 1,
  }) => _PurchaseLine(
    productId: product['id'] as String,
    variantId: variant?['id'] as String?,
    name: product['name'] as String,
    variantName: variant?['name'] as String? ?? '',
    qty: qty,
    price: toDouble(variant?['purchase_price'] ?? product['purchase_price']),
    gstRate: toDouble(product['gst_rate']),
    trackSerial: product['track_serial'] == true,
    allowDecimal: (product['units'] as Map?)?['allow_decimal'] == true,
    unitName: (product['units'] as Map?)?['short_name'] as String? ?? '',
    secondaryUnitName: product['secondary_unit_name'] as String?,
    conversionFactor: (product['conversion_factor'] as num?)?.toDouble(),
  );

  Future<void> _loadSupplier() async {
    final row = await ref
        .read(supabaseProvider)
        .from('suppliers')
        .select()
        .eq('id', widget.initialSupplierId!)
        .maybeSingle();
    if (row != null && mounted) {
      setState(() => _supplier = Map<String, dynamic>.from(row));
    }
  }

  Future<void> _pickSupplier() async {
    final suppliers =
        ref.read(suppliersProvider).value ??
        List<Map<String, dynamic>>.from(
          await ref
              .read(supabaseProvider)
              .from('suppliers')
              .select()
              .eq('is_active', true)
              .order('name', ascending: true),
        );
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Select supplier',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      final created = await showSupplierForm(ctx, ref);
                      if (created != null && ctx.mounted) {
                        Navigator.pop(ctx, created);
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in suppliers)
                    ListTile(
                      title: Text(s['name'] as String),
                      subtitle: Text(s['phone'] as String? ?? ''),
                      onTap: () => Navigator.pop(ctx, s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _supplier = selected);
  }

  Future<void> _addProduct() async {
    final search = TextEditingController();
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ProductPicker(searchController: search),
      ),
    );
    if (selected == null || !mounted) return;

    final product = selected['product'] as Map<String, dynamic>;
    final variant = selected['variant'] as Map<String, dynamic>?;
    setState(() => _lines.add(_lineFor(product, variant)));
    // Jump straight into qty/price entry for the new line.
    if (mounted) _editLine(_lines.length - 1);
  }

  Future<void> _editLine(int index) async {
    final line = _lines[index];
    final qtyC = TextEditingController(text: qty(line.qty).replaceAll(',', ''));
    final priceC = TextEditingController(text: line.price.toStringAsFixed(2));
    final gstC = TextEditingController(text: line.gstRate.toStringAsFixed(0));
    final serialsC = TextEditingController(text: line.serialNos.join('\n'));
    final factor = line.conversionFactor ?? 0;
    final hasSecondary = line.secondaryUnitName != null && factor > 0;
    // When true, the qty/price fields are in the secondary (bulk) unit —
    // e.g. Bags — and get converted to base units (kg) on save.
    var inSecondary = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(line.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSecondary) ...[
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(line.unitName)),
                      ButtonSegment(
                        value: true,
                        label: Text(
                          '${line.secondaryUnitName} (${qty(factor)} ${line.unitName})',
                        ),
                      ),
                    ],
                    selected: {inSecondary},
                    onSelectionChanged: (s) {
                      final toSecondary = s.first;
                      if (toSecondary == inSecondary) return;
                      // Convert whatever is currently typed between units.
                      final q = double.tryParse(qtyC.text);
                      final p = double.tryParse(priceC.text);
                      if (toSecondary) {
                        if (q != null) {
                          qtyC.text = qty(q / factor).replaceAll(',', '');
                        }
                        if (p != null) {
                          priceC.text = (p * factor).toStringAsFixed(2);
                        }
                      } else {
                        if (q != null) {
                          qtyC.text = qty(q * factor).replaceAll(',', '');
                        }
                        if (p != null) {
                          priceC.text = (p / factor).toStringAsFixed(2);
                        }
                      }
                      setDialogState(() => inSecondary = toSecondary);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyC,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: hasSecondary
                              ? 'Qty (${inSecondary ? line.secondaryUnitName : line.unitName})'
                              : 'Qty${line.unitName.isEmpty ? '' : ' (${line.unitName})'}',
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
                        decoration: const InputDecoration(
                          labelText: 'Price ₹ (excl. GST)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gstC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'GST %'),
                ),
                if (line.trackSerial) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: serialsC,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'IMEI / serial numbers (one per line)',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    var newQty = double.tryParse(qtyC.text) ?? line.qty;
    var newPrice = double.tryParse(priceC.text) ?? line.price;
    if (inSecondary) {
      // Convert entered bulk units to base units for storage/stock.
      newQty = toBaseQty(newQty, factor);
      newPrice = newPrice / factor;
    }
    if (!line.allowDecimal && newQty % 1 != 0) {
      showError(
        context,
        '${line.name} is stocked in whole ${line.unitName.isEmpty ? 'units' : line.unitName} — quantity must come to a whole number',
      );
      newQty = line.qty;
    }
    setState(() {
      line.qty = newQty;
      line.price = newPrice;
      line.gstRate = double.tryParse(gstC.text) ?? line.gstRate;
      line.serialNos = serialsC.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      showError(context, 'Add at least one product');
      return;
    }
    final creditLimit = _supplier?['credit_limit'] == null
        ? null
        : toDouble(_supplier!['credit_limit']);
    if (creditLimit != null) {
      final due = (_total - _paidAmount).clamp(0, double.infinity);
      final projectedDue = toDouble(_supplier?['due_amount']) + due;
      if (projectedDue > creditLimit) {
        final proceed = await confirmDialog(
          context,
          title: 'Credit limit exceeded',
          message:
              '${_supplier?['name']}\'s due would become ${money(projectedDue)}, '
              'above their credit limit of ${money(creditLimit)}. Continue anyway?',
          confirmText: 'Continue',
        );
        if (!proceed) return;
      }
    }
    setState(() => _busy = true);
    try {
      final payload = {
        'supplier_id': _supplier?['id'],
        'supplier_name': _supplier?['name'] ?? '',
        'bill_no': _billNo.text.trim(),
        'purchase_date': ymd(_date),
        'discount_amount': double.parse(_discountAmount.toStringAsFixed(2)),
        'extra_charges': double.tryParse(_extraCharges.text) ?? 0,
        'round_off': double.parse(_roundOff.toStringAsFixed(2)),
        'paid_amount': _paidAmount,
        'payment_mode': _paymentMode,
        'notes': _notes.text.trim(),
        'items': [
          for (final l in _lines)
            {
              'product_id': l.productId,
              'variant_id': l.variantId,
              'product_name':
                  '${l.name}${l.variantName.isNotEmpty ? ' (${l.variantName})' : ''}',
              'quantity': l.qty,
              'unit_price': l.price,
              'discount_amount': 0,
              'gst_rate': l.gstRate,
              'tax_amount': double.parse(l.tax.toStringAsFixed(2)),
              'line_total': double.parse(l.total.toStringAsFixed(2)),
              'serial_nos': l.serialNos,
            },
        ],
      };
      final res =
          await ref
                  .read(supabaseProvider)
                  .rpc('create_purchase', params: {'payload': payload})
              as Map<String, dynamic>;
      ref.invalidate(purchasesProvider);
      invalidateStockData(ref);
      ref.invalidate(suppliersProvider);
      if (mounted) {
        showSuccess(context, 'Purchase ${res['purchase_no']} saved');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = (_total - _paidAmount).clamp(0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Add purchase'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(_supplier?['name'] as String? ?? 'Select supplier'),
              subtitle: _supplier == null
                  ? const Text('Optional, needed for due tracking')
                  : Text(_supplier!['phone'] as String? ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickSupplier,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _billNo,
                  decoration: const InputDecoration(
                    labelText: 'Supplier bill no.',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Text(dateStr(_date)),
                  ),
                ),
              ),
            ],
          ),
          const SectionLabel('Products'),
          for (var i = 0; i < _lines.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _editLine(i),
                title: Text(
                  '${_lines[i].name}${_lines[i].variantName.isNotEmpty ? ' (${_lines[i].variantName})' : ''}',
                ),
                subtitle: Text(
                  '${qty(_lines[i].qty)} × ${money(_lines[i].price)}'
                  '${_lines[i].gstRate > 0 ? ' + GST ${qty(_lines[i].gstRate)}%' : ''}'
                  '${_lines[i].trackSerial ? '\n${_lines[i].serialNos.length} serial(s) entered' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      money(_lines[i].total),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.red,
                      ),
                      onPressed: () => setState(() => _lines.removeAt(i)),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _addProduct,
            icon: const Icon(Icons.add),
            label: const Text('Add product'),
          ),
          const SectionLabel('Charges'),
          AmountOrPercentField(
            controller: _discount,
            isPercent: _discountIsPercent,
            label: 'Discount',
            onModeChanged: (v) => setState(() => _discountIsPercent = v),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extraCharges,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Extra charges ₹'),
            onChanged: (_) => setState(() {}),
          ),
          const SectionLabel('Payment'),
          Wrap(
            spacing: 8,
            children: [
              for (final mode in const [
                ('cash', 'Cash'),
                ('upi', 'UPI'),
                ('card', 'Card'),
                ('credit', 'Credit'),
                ('other', 'Bank/Other'),
              ])
                ChoiceChip(
                  label: Text(mode.$2),
                  selected: _paymentMode == mode.$1,
                  onSelected: (_) => setState(() {
                    _paymentMode = mode.$1;
                    // Credit means "nothing paid yet": the 0 shown in the field must
                    // count, otherwise the purchase saves as fully paid and no due is kept.
                    _paidTouched = mode.$1 == 'credit';
                    _paid.text = mode.$1 == 'credit'
                        ? '0'
                        : _total.toStringAsFixed(2);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paid,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Paid amount ₹',
              hintText: _total.toStringAsFixed(2),
            ),
            onChanged: (_) => setState(() => _paidTouched = true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _row('Subtotal (excl. GST)', money(_subtotal)),
                  _row('GST', money(_tax)),
                  if (_discountAmount > 0)
                    _row('Discount', '- ${money(_discountAmount)}'),
                  _row('Round off', money(_roundOff), color: AppColors.inkSoft),
                  _row('Total', money(_total), bold: true),
                  if (due > 0)
                    _row(
                      'Due to supplier',
                      money(due),
                      color: AppColors.purple,
                    ),
                ],
              ),
            ),
          ),
          if (due > 0 && _supplier?['credit_limit'] != null)
            Builder(
              builder: (context) {
                final creditLimit = toDouble(_supplier!['credit_limit']);
                final projectedDue = toDouble(_supplier?['due_amount']) + due;
                if (projectedDue <= creditLimit) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: AppColors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'This purchase exceeds the supplier\'s credit limit of ${money(creditLimit)} '
                          '(due would be ${money(projectedDue)}).',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Save purchase • ${money(_total)}'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Product picker bottom sheet used by purchase & return forms.
class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.searchController});

  final TextEditingController searchController;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String search) async {
    try {
      final client = ref.read(supabaseProvider);
      var query = client
          .from('products')
          .select(posProductColumns)
          .eq('is_active', true);
      if (search.isNotEmpty) {
        query = query.or(
          'name.ilike.%$search%,sku.ilike.%$search%,barcode.ilike.%$search%',
        );
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('name', ascending: true).limit(100),
      );
      if (mounted) {
        setState(() {
          _products = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _select(Map<String, dynamic> product) async {
    final variants = List<Map<String, dynamic>>.from(
      product['product_variants'] as List? ?? [],
    )..removeWhere((v) => v['is_active'] == false);
    if (product['has_variants'] == true && variants.isNotEmpty) {
      final variant = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final v in variants)
                ListTile(
                  title: Text(v['name'] as String),
                  onTap: () => Navigator.pop(ctx, v),
                ),
            ],
          ),
        ),
      );
      if (variant == null || !mounted) return;
      Navigator.pop(context, {'product': product, 'variant': variant});
    } else {
      Navigator.pop(context, {'product': product, 'variant': null});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              controller: widget.searchController,
              hint: 'Search product',
              autofocus: true,
              onChanged: _load,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    controller: scrollController,
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final p = _products[i];
                      return ListTile(
                        title: Text(p['name'] as String),
                        subtitle: Text(
                          'Stock: ${qty(toDouble(p['current_stock']))} • Purchase: ${money(p['purchase_price'] as num?)}',
                        ),
                        onTap: () => _select(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
