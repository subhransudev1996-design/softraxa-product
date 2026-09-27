import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/business_category.dart';
import '../../core/data_refresh.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import 'product_providers.dart';
import 'variant_sheet.dart';
import '../../core/theme.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existing, this.initialBarcode});

  final Map<String, dynamic>? existing;
  final String? initialBarcode;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.existing?['name'] ?? '',
  );
  late final _sku = TextEditingController(text: widget.existing?['sku'] ?? '');
  late final _barcode = TextEditingController(
    text: widget.existing?['barcode'] ?? widget.initialBarcode ?? '',
  );
  late final _hsn = TextEditingController(
    text: widget.existing?['hsn_code'] ?? '',
  );
  late final _purchase = TextEditingController(
    text: _num(widget.existing?['purchase_price']),
  );
  late final _selling = TextEditingController(
    text: _num(widget.existing?['selling_price']),
  );
  late final _mrp = TextEditingController(text: _num(widget.existing?['mrp']));
  late final _wholesale = TextEditingController(
    text: _num(widget.existing?['wholesale_price']),
  );
  late final _wholesaleMinQty = TextEditingController(
    text: _num(widget.existing?['wholesale_min_qty']),
  );
  late final _opening = TextEditingController();
  late final _lowStock = TextEditingController(
    text: _num(widget.existing?['low_stock_qty']),
  );
  late final _warranty = TextEditingController(
    text: _num(widget.existing?['warranty_months']),
  );
  late final _description = TextEditingController(
    text: widget.existing?['description'] ?? '',
  );
  late final _secondaryUnitName = TextEditingController(
    text: widget.existing?['secondary_unit_name'] as String? ?? '',
  );
  late final _conversionFactor = TextEditingController(
    text: _num(widget.existing?['conversion_factor']),
  );

  String? _categoryId;
  String? _brandId;
  String? _unitId;
  late DateTime? _expiryDate = widget.existing?['expiry_date'] == null
      ? null
      : DateTime.tryParse(widget.existing!['expiry_date'] as String);
  late double _gstRate =
      (widget.existing?['gst_rate'] as num?)?.toDouble() ?? 18;
  late bool _hasVariants = widget.existing?['has_variants'] == true;
  late bool _trackSerial = widget.existing?['track_serial'] == true;
  late bool _trackPieces = widget.existing?['track_pieces'] == true;
  final List<VariantDraft> _variants = [];
  final List<String> _serials = [];
  final TextEditingController _singleImeiInput = TextEditingController();
  bool _busy = false;

  static String _num(dynamic v) =>
      v == null || (v is num && v == 0) ? '' : v.toString();

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?['category_id'] as String?;
    _brandId = widget.existing?['brand_id'] as String?;
    _unitId = widget.existing?['unit_id'] as String?;
  }

  Future<void> _quickAddMaster(
    String table, {
    required void Function(String id) onAdded,
  }) async {
    final name = TextEditingController();
    final shortName = TextEditingController();
    final label = switch (table) {
      'categories' => 'category',
      'brands' => 'brand',
      _ => 'unit',
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (table == 'units') ...[
              const SizedBox(height: 12),
              TextField(
                controller: shortName,
                decoration: const InputDecoration(
                  labelText: 'Short name (pcs, kg…)',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmedName = name.text.trim();
    if (saved != true || trimmedName.isEmpty) return;

    try {
      final client = ref.read(supabaseProvider);
      final businessId = ref.read(appContextProvider).value?.businessId;
      if (businessId == null) return;

      // Check existing loaded list first (case-insensitive)
      final existingList = switch (table) {
        'categories' => ref.read(categoriesProvider).value ?? [],
        'brands' => ref.read(brandsProvider).value ?? [],
        _ => ref.read(unitsProvider).value ?? [],
      };

      final existingMatch = existingList.firstWhere(
        (item) =>
            (item['name'] as String?)?.trim().toLowerCase() ==
            trimmedName.toLowerCase(),
        orElse: () => {},
      );

      if (existingMatch.isNotEmpty) {
        final existingId = existingMatch['id'] as String;
        if (mounted) {
          onAdded(existingId);
          showSuccess(
            context,
            '${label[0].toUpperCase()}${label.substring(1)} "$trimmedName" already exists',
          );
        }
        return;
      }

      // Check DB in case it exists in database but wasn't in loaded list
      final existingInDb = await client
          .from(table)
          .select('id, name')
          .eq('business_id', businessId)
          .ilike('name', trimmedName)
          .maybeSingle();

      if (existingInDb != null) {
        final existingId = existingInDb['id'] as String;
        switch (table) {
          case 'categories':
            ref.invalidate(categoriesProvider);
            await ref.read(categoriesProvider.future);
          case 'brands':
            ref.invalidate(brandsProvider);
            await ref.read(brandsProvider.future);
          default:
            ref.invalidate(unitsProvider);
            await ref.read(unitsProvider.future);
        }
        if (mounted) {
          onAdded(existingId);
          showSuccess(
            context,
            '${label[0].toUpperCase()}${label.substring(1)} "$trimmedName" already exists',
          );
        }
        return;
      }

      final row = {
        'business_id': businessId,
        'name': trimmedName,
        if (table == 'units') 'short_name': shortName.text.trim(),
      };
      final inserted = await client
          .from(table)
          .insert(row)
          .select('id')
          .single();
      final newId = inserted['id'] as String;
      switch (table) {
        case 'categories':
          ref.invalidate(categoriesProvider);
          await ref.read(categoriesProvider.future);
        case 'brands':
          ref.invalidate(brandsProvider);
          await ref.read(brandsProvider.future);
        default:
          ref.invalidate(unitsProvider);
          await ref.read(unitsProvider.future);
      }
      if (mounted) {
        onAdded(newId);
        showSuccess(context, 'New $label "$trimmedName" added');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _scanBarcode() async {
    final code = isDesktopPlatform
        ? await promptBarcode(context, title: 'Enter barcode')
        : await context.push<String>('/scan?mode=return');
    if (!mounted) return;
    if (code != null && code.isNotEmpty) {
      setState(() => _barcode.text = code);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasVariants && !isEdit && _variants.isEmpty) {
      showError(context, 'Add at least one variant, or turn variants off');
      return;
    }
    if (_secondaryUnitName.text.trim().isNotEmpty &&
        (double.tryParse(_conversionFactor.text) ?? 0) <= 0) {
      showError(
        context,
        'Enter how many base units make one ${_secondaryUnitName.text.trim()} (e.g. 1 Bag = 50 kg)',
      );
      return;
    }
    setState(() => _busy = true);
    final client = ref.read(supabaseProvider);
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      final row = {
        'business_id': businessId,
        'name': _name.text.trim(),
        'sku': _sku.text.trim(),
        'barcode': _barcode.text.trim(),
        'hsn_code': _hsn.text.trim(),
        'category_id': _categoryId,
        'brand_id': _brandId,
        'unit_id': _unitId,
        'purchase_price': double.tryParse(_purchase.text) ?? 0,
        'selling_price': double.tryParse(_selling.text) ?? 0,
        'mrp': double.tryParse(_mrp.text) ?? 0,
        'wholesale_price': double.tryParse(_wholesale.text),
        'wholesale_min_qty': double.tryParse(_wholesaleMinQty.text),
        'gst_rate': _gstRate,
        'low_stock_qty': double.tryParse(_lowStock.text) ?? 0,
        'warranty_months': int.tryParse(_warranty.text),
        'description': _description.text.trim(),
        'has_variants': _hasVariants,
        'track_serial': _trackSerial,
        'track_pieces': _trackPieces,
        'expiry_date': _expiryDate == null ? null : ymd(_expiryDate!),
        // Secondary (bulk) unit is display/entry-only; stock stays in the
        // base unit. Only saved when both label and a valid factor are set.
        'secondary_unit_name': _secondaryUnitName.text.trim().isEmpty
            ? null
            : _secondaryUnitName.text.trim(),
        'conversion_factor': _secondaryUnitName.text.trim().isEmpty
            ? null
            : double.tryParse(_conversionFactor.text),
      };

      late String productId;

      if (isEdit) {
        productId = widget.existing!['id'] as String;
        await client.from('products').update(row).eq('id', productId);
      } else {
        final inserted = await client
            .from('products')
            .insert(row)
            .select('id')
            .single();
        productId = inserted['id'] as String;

        if (_hasVariants) {
          for (final draft in _variants) {
            final vRow = await client
                .from('product_variants')
                .insert({...draft.toRow(productId), 'business_id': businessId})
                .select('id')
                .single();
            if (draft.openingStock > 0) {
              await client.rpc(
                'add_opening_stock',
                params: {
                  'p_product_id': productId,
                  'p_variant_id': vRow['id'],
                  'p_quantity': draft.openingStock,
                },
              );
            }
          }
        } else {
          final opening = double.tryParse(_opening.text) ?? 0;
          if (opening > 0) {
            await client.rpc(
              'add_opening_stock',
              params: {
                'p_product_id': productId,
                'p_variant_id': null,
                'p_quantity': opening,
              },
            );
          }
        }
      }

      if (_trackSerial && _serials.isNotEmpty) {
        await client.rpc(
          'add_product_serials',
          params: {
            'p_product_id': productId,
            'p_variant_id': null,
            'p_serials': _serials,
          },
        );
      }

      invalidateStockData(ref); // new/edited product: POS, stock, dashboard
      if (mounted) {
        showSuccess(context, isEdit ? 'Product updated' : 'Product added');
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
    final categories = ref.watch(categoriesProvider).value ?? [];
    final brands = ref.watch(brandsProvider).value ?? [];
    final units = ref.watch(unitsProvider).value ?? [];
    final businessType =
        ref.watch(appContextProvider).value?.business?['business_type']
            as String? ??
        'other';

    final selectedCategory = categories.any((c) => c['id'] == _categoryId)
        ? _categoryId
        : null;
    final selectedBrand = brands.any((b) => b['id'] == _brandId)
        ? _brandId
        : null;
    final selectedUnit = units.any((u) => u['id'] == _unitId) ? _unitId : null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(isEdit ? 'Edit product' : 'Add product'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Product name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SectionLabel('Classification'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('category_$selectedCategory'),
                    // isExpanded: a dropdown sizes itself to its WIDEST menu
                    // item, so one long name overflows the half-width field.
                    isExpanded: true,
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final c in categories)
                        DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(
                            c['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Add category',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _quickAddMaster(
                    'categories',
                    onAdded: (id) => setState(() => _categoryId = id),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('brand_$selectedBrand'),
                    isExpanded: true,
                    initialValue: selectedBrand,
                    decoration: const InputDecoration(labelText: 'Brand'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final b in brands)
                        DropdownMenuItem(
                          value: b['id'] as String,
                          child: Text(
                            b['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _brandId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Add brand',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _quickAddMaster(
                    'brands',
                    onAdded: (id) => setState(() => _brandId = id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('unit_$selectedUnit'),
                    isExpanded: true,
                    initialValue: selectedUnit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final u in units)
                        DropdownMenuItem(
                          value: u['id'] as String,
                          child: Text(
                            '${u['name']} (${u['short_name']})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _unitId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Add unit',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _quickAddMaster(
                    'units',
                    onAdded: (id) => setState(() => _unitId = id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _secondaryUnitName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Bulk unit (optional)',
                      helperText: 'e.g. Bag, Box, Rod',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _conversionFactor,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '= how many units?',
                      helperText: '1 Bag = 50 kg → 50',
                    ),
                  ),
                ),
              ],
            ),
            const SectionLabel('Codes'),
            TextFormField(
              controller: _sku,
              decoration: const InputDecoration(
                labelText: 'SKU / product code',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              decoration: InputDecoration(
                labelText: 'Barcode',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanBarcode,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hsn,
              decoration: const InputDecoration(
                labelText: 'HSN code (for GST invoice)',
              ),
            ),
            const SectionLabel('Pricing'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _purchase,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Purchase price ₹',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _selling,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Selling price ₹ *',
                    ),
                    validator: (v) =>
                        !_hasVariants && (double.tryParse(v ?? '') == null)
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _mrp,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'MRP ₹'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              initialValue: _gstRate,
              decoration: const InputDecoration(labelText: 'GST %'),
              items: const [
                DropdownMenuItem(value: 0.0, child: Text('0% (Exempt)')),
                DropdownMenuItem(value: 3.0, child: Text('3%')),
                DropdownMenuItem(value: 5.0, child: Text('5%')),
                DropdownMenuItem(value: 12.0, child: Text('12%')),
                DropdownMenuItem(value: 18.0, child: Text('18%')),
                DropdownMenuItem(value: 28.0, child: Text('28%')),
              ],
              onChanged: (v) => setState(() => _gstRate = v ?? 0),
            ),
            if (categoryOf(businessType).bulkPricing) ...[
              const SectionLabel('Bulk pricing (optional)'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _wholesale,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Wholesale price ₹',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _wholesaleMinQty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Min qty for wholesale',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SectionLabel('Stock'),
            Row(
              children: [
                if (!isEdit && !_hasVariants) ...[
                  Expanded(
                    child: TextFormField(
                      controller: _opening,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Opening stock',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: TextFormField(
                    controller: _lowStock,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Low stock alert qty',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Optional expiry — drives the bell's expired/near-expiry alerts.
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expiryDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) {
                  setState(() => _expiryDate = picked);
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Expiry date (optional)',
                  helperText: 'Alerts appear when expired or within 30 days',
                  suffixIcon: _expiryDate == null
                      ? const Icon(Icons.event_outlined)
                      : IconButton(
                          tooltip: 'Clear expiry date',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _expiryDate = null),
                        ),
                ),
                child: Text(_expiryDate == null ? '—' : dateStr(_expiryDate)),
              ),
            ),
            const SectionLabel('Options'),
            SwitchListTile(
              value: _trackSerial,
              contentPadding: EdgeInsets.zero,
              title: const Text('Track IMEI / serial numbers'),
              subtitle: const Text('For mobiles & electronics'),
              onChanged: (v) => setState(() => _trackSerial = v),
            ),
            SwitchListTile(
              value: _trackPieces,
              contentPadding: EdgeInsets.zero,
              title: const Text('Track cut pieces'),
              subtitle: const Text('Rods, sheets, rolls — sold as cut lengths'),
              onChanged: (v) => setState(() => _trackPieces = v),
            ),
            if (_trackSerial) ...[
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IMEI / Serial Numbers',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add or scan unique IMEI numbers for individual stock units.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _singleImeiInput,
                              decoration: const InputDecoration(
                                labelText: 'Enter or scan IMEI / Serial',
                                isDense: true,
                              ),
                              onSubmitted: (v) {
                                final imei = v.trim();
                                if (imei.isNotEmpty &&
                                    !_serials.contains(imei)) {
                                  setState(() {
                                    _serials.add(imei);
                                    _singleImeiInput.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: () async {
                              final code = isDesktopPlatform
                                  ? await promptBarcode(
                                      context,
                                      title: 'Enter IMEI',
                                    )
                                  : await context.push<String>(
                                      '/scan?mode=return',
                                    );
                              if (code != null &&
                                  code.isNotEmpty &&
                                  !_serials.contains(code)) {
                                setState(() => _serials.add(code));
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              final imei = _singleImeiInput.text.trim();
                              if (imei.isNotEmpty && !_serials.contains(imei)) {
                                setState(() {
                                  _serials.add(imei);
                                  _singleImeiInput.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      if (_serials.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final imei in _serials)
                              Chip(
                                avatar: const Icon(Icons.qr_code, size: 14),
                                label: Text(
                                  imei,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onDeleted: () =>
                                    setState(() => _serials.remove(imei)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _warranty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Warranty (months)',
                  ),
                ),
              ),
            ],
            if (!isEdit)
              SwitchListTile(
                value: _hasVariants,
                contentPadding: EdgeInsets.zero,
                title: const Text('This product has variants'),
                subtitle: const Text('Size, color, RAM/storage etc.'),
                onChanged: (v) => setState(() => _hasVariants = v),
              ),
            if (!isEdit && _hasVariants) ...[
              const SectionLabel('Variants'),
              for (var i = 0; i < _variants.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_variants[i].name),
                    subtitle: Text(
                      'Stock: ${_variants[i].openingStock}  •  ₹${_variants[i].sellingPrice ?? _selling.text}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.red,
                      ),
                      onPressed: () => setState(() => _variants.removeAt(i)),
                    ),
                    onTap: () async {
                      final updated = await showVariantSheet(
                        context,
                        businessType: businessType,
                        existing: _variants[i],
                      );
                      if (updated != null) {
                        setState(() => _variants[i] = updated);
                      }
                    },
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final draft = await showVariantSheet(
                    context,
                    businessType: businessType,
                  );
                  if (draft != null) setState(() => _variants.add(draft));
                },
                icon: const Icon(Icons.add),
                label: const Text('Add variant'),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Add product'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
