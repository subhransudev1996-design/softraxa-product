import '../../core/i18n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/business_category.dart';
import '../../core/data_refresh.dart';
import '../stock/pack_qty_input.dart';
import 'alternatives.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import 'pack_pricing.dart';
import 'product_providers.dart';
import 'variant_builder.dart';
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
  late final _opening =
      TextEditingController(); // loose units when a bulk unit is set
  late final _openingPacks = TextEditingController();
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
  late final _packPrice = TextEditingController(
    text: _num(widget.existing?['pack_price']),
  );

  /// What one bulk unit costs to buy. Not stored: it is the purchase price
  /// x units in the bulk unit, typed here so the per-unit price follows.
  late final _packCost = TextEditingController(
    text: priceText(
      packPriceFor(
        (widget.existing?['purchase_price'] as num?)?.toDouble(),
        (widget.existing?['conversion_factor'] as num?)?.toDouble(),
      ),
    ),
  );

  /// The per-unit selling price was filled from the bulk selling price, so
  /// it keeps following it until the owner types their own.
  bool _sellingFromPack = false;

  String? _categoryId;
  int _manageVisits = 0; // rebuilds the dropdowns after Edit or delete
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

  /// Full length of one new piece (1 rod = 12 ft). New stock is split into
  /// pieces of this length by the server (0064).
  late final _pieceLength = TextEditingController(
    text: _num(widget.existing?['piece_length']),
  );
  final List<VariantDraft> _variants = [];

  /// The shop's alternatives of this product (migration 0074): id + name.
  List<Map<String, dynamic>> _alternatives = [];
  bool _alternativesChanged = false;
  final List<String> _serials = [];
  final TextEditingController _singleImeiInput = TextEditingController();
  bool _busy = false;

  // The shared product list (migration 0057): while a NEW product's name is
  // typed, matching products are offered; picking one fills in everything
  // except prices and stock.
  static const _gstRates = [0.0, 3.0, 5.0, 12.0, 18.0, 28.0, 40.0];
  Timer? _searchTimer;
  List<Map<String, dynamic>> _suggestions = [];
  String? _masterProductId;
  bool _filling = false;

  /// Something was typed or chosen and not saved yet.
  bool _dirty = false;

  Future<void> _confirmLeave() async {
    final leave = await confirmDialog(
      context,
      title: t('Discard this product?'),
      message: t('What you entered has not been saved.'),
      confirmText: t('Discard'),
    );
    if (leave && mounted) {
      setState(() => _dirty = false);
      context.pop();
    }
  }

  static String _pct(dynamic v) {
    final n = (v as num?) ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
  }

  static String _num(dynamic v) =>
      v == null || (v is num && v == 0) ? '' : v.toString();

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.existing?['category_id'] as String?;
    _brandId = widget.existing?['brand_id'] as String?;
    _unitId = widget.existing?['unit_id'] as String?;
    if (isEdit) _loadAlternatives();
    if (!isEdit) {
      _name.addListener(_onNameChanged);
      final code = widget.initialBarcode ?? '';
      if (code.isNotEmpty) _searchMaster(code);
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onNameChanged() {
    if (_filling || _masterProductId != null) return;
    _searchTimer?.cancel();
    final text = _name.text.trim();
    if (text.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _searchTimer = Timer(
      const Duration(milliseconds: 350),
      () => _searchMaster(text),
    );
  }

  Future<void> _searchMaster(String query) async {
    try {
      final res = await ref
          .read(supabaseProvider)
          .rpc(
            'search_master_products',
            params: {'p_query': query, 'p_limit': 6},
          );
      if (!mounted || _masterProductId != null) return;
      setState(() {
        _suggestions = [
          for (final m in (res as List? ?? const []))
            Map<String, dynamic>.from(m as Map),
        ];
      });
    } catch (_) {
      // Offline, or a database without the shared list: just no suggestions.
    }
  }

  /// Fill the form from a product in the shared list. The shop's category,
  /// brand and unit are created if missing (use_master_product).
  Future<void> _pickMaster(Map<String, dynamic> m) async {
    try {
      final res = await ref
          .read(supabaseProvider)
          .rpc('use_master_product', params: {'p_master': m['id']});
      final d = Map<String, dynamic>.from(res as Map);
      ref.invalidate(categoriesProvider);
      ref.invalidate(brandsProvider);
      ref.invalidate(unitsProvider);
      await Future.wait([
        ref.read(categoriesProvider.future),
        ref.read(brandsProvider.future),
        ref.read(unitsProvider.future),
      ]);
      if (!mounted) return;
      final gst = (d['gst_rate'] as num?)?.toDouble();
      _filling = true;
      setState(() {
        _masterProductId = d['master_product_id'] as String?;
        _suggestions = [];
        _name.text = d['name'] as String? ?? _name.text;
        if (_barcode.text.trim().isEmpty) {
          _barcode.text = d['barcode'] as String? ?? '';
        }
        _hsn.text = d['hsn_code'] as String? ?? '';
        if (gst != null && _gstRates.contains(gst)) _gstRate = gst;
        _categoryId = d['category_id'] as String?;
        _brandId = d['brand_id'] as String?;
        _unitId = d['unit_id'] as String?;
        _secondaryUnitName.text = d['secondary_unit_name'] as String? ?? '';
        _conversionFactor.text = _num(d['conversion_factor']);
        _trackSerial = d['track_serial'] == true;
        _trackPieces = d['track_pieces'] == true;
        _warranty.text = _num(d['warranty_months']);
        if (_description.text.trim().isEmpty) {
          _description.text = d['description'] as String? ?? '';
        }
      });
      _filling = false;
      showSuccess(context, t('Details filled in — add your prices and stock'));
    } catch (e) {
      _filling = false;
      if (mounted) showError(context, e);
    }
  }

  static const _manage = '__manage__';

  /// The last entry of the Category / Brand / Unit lists: opens the screen
  /// where they are renamed or deleted (tab 0, 1, 2), then reloads them.
  DropdownMenuItem<String> _manageItem() => DropdownMenuItem(
    value: _manage,
    child: Row(
      children: [
        Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            t('Edit or delete…'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.primary),
          ),
        ),
      ],
    ),
  );

  Future<void> _openManage(int tab) async {
    // The dropdown shows the old choice again while the screen is open.
    setState(() => _manageVisits++);
    await context.push('/products/master-data?tab=$tab');
    if (!mounted) return;
    ref.invalidate(categoriesProvider);
    ref.invalidate(brandsProvider);
    ref.invalidate(unitsProvider);
    setState(() => _manageVisits++);
  }

  Future<void> _loadAlternatives() async {
    try {
      final rows = await loadLinkedAlternatives(
        ref,
        widget.existing!['id'] as String,
      );
      if (mounted) setState(() => _alternatives = rows);
    } catch (_) {
      // Offline, or a database without alternatives: the section stays empty.
    }
  }

  Future<void> _addAlternative() async {
    final picked = await pickAlternativeProduct(
      context,
      excludeIds: {
        if (isEdit) widget.existing!['id'] as String,
        for (final a in _alternatives) a['id'] as String,
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _alternatives = [..._alternatives, picked];
      _alternativesChanged = true;
      _dirty = true;
    });
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
        title: Text(t('Add {label}', {'label': label})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t('Name')),
            ),
            if (table == 'units') ...[
              const SizedBox(height: 12),
              TextField(
                controller: shortName,
                decoration: InputDecoration(
                  labelText: t('Short name (pcs, kg…)'),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Save')),
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
            t('{v1}{v2} "{trimmedName}" already exists', {
              'v1': label[0].toUpperCase(),
              'v2': label.substring(1),
              'trimmedName': trimmedName,
            }),
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
            t('{v1}{v2} "{trimmedName}" already exists', {
              'v1': label[0].toUpperCase(),
              'v2': label.substring(1),
              'trimmedName': trimmedName,
            }),
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
        showSuccess(
          context,
          t('New {label} "{trimmedName}" added', {
            'label': label,
            'trimmedName': trimmedName,
          }),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _scanBarcode() async {
    final code = isDesktopPlatform
        ? await promptBarcode(context, title: t('Enter barcode'))
        : await context.push<String>('/scan?mode=return');
    if (!mounted) return;
    if (code != null && code.isNotEmpty) {
      setState(() => _barcode.text = code);
    }
  }

  double? get _packSize => double.tryParse(_conversionFactor.text);

  bool get _showPackPrices =>
      _secondaryUnitName.text.trim().isNotEmpty && !_hasVariants;

  /// Opening stock is typed as full bulk units + loose units.
  bool get _openingInPacks => _showPackPrices && (_packSize ?? 0) > 0;

  /// Opening stock in base units, whichever way it was typed.
  double get _openingQty => _openingInPacks
      ? packQtyTotal(_openingPacks.text, _opening.text, _packSize!) ?? 0
      : double.tryParse(_opening.text) ?? 0;

  /// Bulk cost typed -> per-unit purchase price (Rs 1600 a 50 kg bag -> Rs 32).
  void _packCostChanged() {
    final unit = perUnitPrice(double.tryParse(_packCost.text), _packSize);
    if (unit != null) _purchase.text = priceText(unit);
    setState(() {});
  }

  /// Bulk selling price typed -> per-unit selling price, while that is empty
  /// or still the one filled from here.
  void _packPriceChanged() {
    final unit = perUnitPrice(double.tryParse(_packPrice.text), _packSize);
    if (unit != null && (_sellingFromPack || _selling.text.trim().isEmpty)) {
      _selling.text = priceText(unit);
      _sellingFromPack = true;
    }
    setState(() {});
  }

  /// Units in the bulk unit changed: the bulk prices stay as typed and the
  /// per-unit prices follow.
  void _packSizeChanged() {
    if (_packCost.text.trim().isNotEmpty) {
      final unit = perUnitPrice(double.tryParse(_packCost.text), _packSize);
      if (unit != null) _purchase.text = priceText(unit);
    }
    if (_sellingFromPack) {
      final unit = perUnitPrice(double.tryParse(_packPrice.text), _packSize);
      if (unit != null) _selling.text = priceText(unit);
    }
    setState(() {});
  }

  String _packCostHint() {
    final unit = perUnitPrice(double.tryParse(_packCost.text), _packSize);
    final base = _unitShort();
    return unit == null
        ? 'Fills the purchase price per $base'
        : '= ${money(unit)} per $base';
  }

  String _unitShort() {
    final units = ref.read(unitsProvider).value ?? const [];
    for (final u in units) {
      if (u['id'] == _unitId) return u['short_name'] as String? ?? 'unit';
    }
    return 'unit';
  }

  /// What the pack price means, with this product's numbers.
  String _packPriceHint() {
    final unit = _secondaryUnitName.text.trim();
    final size = double.tryParse(_conversionFactor.text) ?? 0;
    final piece = double.tryParse(_selling.text) ?? 0;
    final pack = double.tryParse(_packPrice.text);
    if (pack != null && pack > 0) {
      return 'Bill 1 $unit at ${money(pack)}, single units at ${money(piece)}';
    }
    return size > 0 && piece > 0
        ? 'Empty = ${qty(size)} × ${money(piece)} = ${money(size * piece)}'
        : 'Empty = price per unit × units in the $unit';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasVariants && !isEdit && _variants.isEmpty) {
      showError(context, t('Add at least one variant, or turn variants off'));
      return;
    }
    if (_secondaryUnitName.text.trim().isNotEmpty &&
        (double.tryParse(_conversionFactor.text) ?? 0) <= 0) {
      showError(
        context,
        t('Enter how many base units make one {v1} (e.g. 1 Bag = 50 kg)', {
          'v1': _secondaryUnitName.text.trim(),
        }),
      );
      return;
    }
    setState(() => _busy = true);
    final client = ref.read(supabaseProvider);
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      final row = {
        'business_id': businessId,
        if (!isEdit && _masterProductId != null)
          'master_product_id': _masterProductId,
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
        'piece_length': _trackPieces
            ? double.tryParse(_pieceLength.text.trim()) ?? 0
            : 0,
        'expiry_date': _expiryDate == null ? null : ymd(_expiryDate!),
        // Secondary (bulk) unit is display/entry-only; stock stays in the
        // base unit. Only saved when both label and a valid factor are set.
        'secondary_unit_name': _secondaryUnitName.text.trim().isEmpty
            ? null
            : _secondaryUnitName.text.trim(),
        'conversion_factor': _secondaryUnitName.text.trim().isEmpty
            ? null
            : double.tryParse(_conversionFactor.text),
        // Own price for a whole bulk unit (migration 0061): a Box of 10
        // cigarettes at ₹95 while one piece is ₹10.
        'pack_price': _secondaryUnitName.text.trim().isEmpty || _hasVariants
            ? null
            : double.tryParse(_packPrice.text),
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

        if (_hasVariants && _variants.isNotEmpty) {
          // All in one insert; rows come back in the order sent.
          final rows = List<Map<String, dynamic>>.from(
            await client
                .from('product_variants')
                .insert([
                  for (final d in _variants)
                    {...d.toRow(productId), 'business_id': businessId},
                ])
                .select('id'),
          );
          for (var i = 0; i < rows.length && i < _variants.length; i++) {
            if (_variants[i].openingStock > 0) {
              await client.rpc(
                'add_opening_stock',
                params: {
                  'p_product_id': productId,
                  'p_variant_id': rows[i]['id'],
                  'p_quantity': _variants[i].openingStock,
                },
              );
            }
          }
        } else {
          final opening = _openingQty;
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

      if (_alternativesChanged) {
        await saveLinkedAlternatives(ref, productId, [
          for (final a in _alternatives) a['id'] as String,
        ]);
      }

      invalidateStockData(ref); // new/edited product: POS, stock, dashboard
      _dirty = false;
      if (mounted) {
        showSuccess(
          context,
          isEdit ? t('Product updated') : t('Product added'),
        );
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
    // Variant fields are suggested from the product name and category.
    final categoryName =
        categories.firstWhere(
              (c) => c['id'] == _categoryId,
              orElse: () => const <String, dynamic>{},
            )['name']
            as String? ??
        '';
    final selectedBrand = brands.any((b) => b['id'] == _brandId)
        ? _brandId
        : null;
    final selectedUnit = units.any((u) => u['id'] == _unitId) ? _unitId : null;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          leading: GoRouter.of(context).canPop()
              ? BackButton(
                  onPressed: () => _dirty ? _confirmLeave() : context.pop(),
                )
              : null,
          title: Text(isEdit ? t('Edit product') : 'Add product'),
        ),
        body: Form(
          key: _formKey,
          onChanged: () {
            if (!_dirty) setState(() => _dirty = true);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t('Product name *')),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? t('Required') : null,
              ),
              if (_suggestions.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t(
                                  'In the product list — tap to fill in the details',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: t('Not in the list'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setState(() => _suggestions = []),
                            ),
                          ],
                        ),
                      ),
                      for (final m in _suggestions)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text(m['name'] as String? ?? ''),
                          subtitle: Text(
                            [
                              if ((m['brand'] as String? ?? '').isNotEmpty)
                                m['brand'],
                              if ((m['category'] as String? ?? '').isNotEmpty)
                                m['category'],
                              if ((m['hsn_code'] as String? ?? '').isNotEmpty)
                                'HSN ${m['hsn_code']}',
                              'GST ${_pct(m['gst_rate'])}%',
                            ].join(' · '),
                          ),
                          onTap: () => _pickMaster(m),
                        ),
                    ],
                  ),
                ),
              SectionLabel(t('Classification')),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'category_${selectedCategory}_$_manageVisits',
                      ),
                      // isExpanded: a dropdown sizes itself to its WIDEST menu
                      // item, so one long name overflows the half-width field.
                      isExpanded: true,
                      initialValue: selectedCategory,
                      decoration: InputDecoration(labelText: t('Category')),
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
                        _manageItem(),
                      ],
                      onChanged: (v) => v == _manage
                          ? _openManage(0)
                          : setState(() => _categoryId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: t('Add category'),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _quickAddMaster(
                      'categories',
                      onAdded: (id) => setState(() => _categoryId = id),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('brand_${selectedBrand}_$_manageVisits'),
                      isExpanded: true,
                      initialValue: selectedBrand,
                      decoration: InputDecoration(labelText: t('Brand')),
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
                        _manageItem(),
                      ],
                      onChanged: (v) => v == _manage
                          ? _openManage(1)
                          : setState(() => _brandId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: t('Add brand'),
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
                      key: ValueKey('unit_${selectedUnit}_$_manageVisits'),
                      isExpanded: true,
                      initialValue: selectedUnit,
                      decoration: InputDecoration(labelText: t('Unit')),
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
                        _manageItem(),
                      ],
                      onChanged: (v) => v == _manage
                          ? _openManage(2)
                          : setState(() => _unitId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: t('Add unit'),
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
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: t('Bulk unit (optional)'),
                        helperText: t('e.g. Bag, Box, Rod'),
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
                      decoration: InputDecoration(
                        labelText: t('= how many units?'),
                        helperText:
                            (_packSize ?? 0) > 0 &&
                                _secondaryUnitName.text.trim().isNotEmpty
                            ? '1 ${_secondaryUnitName.text.trim()} = ${qty(_packSize!)} ${_unitShort()}'
                            : t('e.g. 1 Bag = 50 kg → 50'),
                      ),
                      onChanged: (_) => _packSizeChanged(),
                    ),
                  ),
                ],
              ),
              if (_showPackPrices) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _packCost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: t('Purchase price of 1 {v1} ₹', {
                            'v1': _secondaryUnitName.text.trim(),
                          }),
                          helperText: _packCostHint(),
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _packCostChanged(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _packPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: t('Selling price of 1 {v1} ₹', {
                            'v1': _secondaryUnitName.text.trim(),
                          }),
                          helperText: _packPriceHint(),
                          helperMaxLines: 2,
                        ),
                        onChanged: (_) => _packPriceChanged(),
                      ),
                    ),
                  ],
                ),
                if (packMarginText(
                      double.tryParse(_packCost.text),
                      double.tryParse(_packPrice.text),
                      _secondaryUnitName.text.trim(),
                      gstRate: _gstRate,
                    )
                    case final margin?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      margin,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: margin.startsWith('Loss')
                            ? AppColors.red
                            : AppColors.green,
                      ),
                    ),
                  ),
              ],
              SectionLabel(t('Codes')),
              TextFormField(
                controller: _sku,
                decoration: InputDecoration(labelText: t('SKU / product code')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                decoration: InputDecoration(
                  labelText: t('Barcode'),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanBarcode,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hsn,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('HSN code (for GST invoice)'),
                  helperText: t('Needed on bills to GST-registered customers'),
                ),
                // Same rule as the database (migration 0048).
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty ||
                          RegExp(r'^[0-9]{4}([0-9]{2}){0,2}$').hasMatch(t)
                      ? null
                      : '4, 6 or 8 digits';
                },
              ),
              SectionLabel(t('Pricing')),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _purchase,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _showPackPrices
                            ? 'Purchase price per ${_unitShort()} ₹'
                            : 'Purchase price ₹',
                      ),
                      onChanged: (_) {
                        if (!_showPackPrices) return;
                        _packCost.text = priceText(
                          packPriceFor(
                            double.tryParse(_purchase.text),
                            _packSize,
                          ),
                        );
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _selling,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _showPackPrices
                            ? 'Selling price per ${_unitShort()} ₹ *'
                            : 'Selling price ₹ *',
                      ),
                      onChanged: (_) => _sellingFromPack = false,
                      validator: (v) =>
                          !_hasVariants && (double.tryParse(v ?? '') == null)
                          ? t('Required')
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
                      decoration: InputDecoration(labelText: t('MRP ₹')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                initialValue: _gstRate,
                decoration: InputDecoration(labelText: t('GST %')),
                items: [
                  DropdownMenuItem(value: 0.0, child: Text(t('0% (Exempt)'))),
                  DropdownMenuItem(value: 3.0, child: Text('3%')),
                  DropdownMenuItem(value: 5.0, child: Text('5%')),
                  DropdownMenuItem(value: 12.0, child: Text('12%')),
                  DropdownMenuItem(value: 18.0, child: Text('18%')),
                  DropdownMenuItem(value: 28.0, child: Text('28%')),
                ],
                onChanged: (v) => setState(() => _gstRate = v ?? 0),
              ),
              if (categoryOf(businessType).bulkPricing) ...[
                SectionLabel(t('Bulk pricing (optional)')),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _wholesale,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: t('Wholesale price ₹'),
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
                        decoration: InputDecoration(
                          labelText: t('Min qty for wholesale'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SectionLabel(t('Alternative products')),
              Text(
                t(
                  'Offered on New Bill and in job cards when this product is chosen or out of stock. Works both ways.',
                ),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final a in _alternatives)
                    InputChip(
                      label: Text(a['name'] as String? ?? ''),
                      onDeleted: () => setState(() {
                        _alternatives = [
                          for (final x in _alternatives)
                            if (x['id'] != a['id']) x,
                        ];
                        _alternativesChanged = true;
                        _dirty = true;
                      }),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(t('Add alternative')),
                    onPressed: _addAlternative,
                  ),
                ],
              ),
              SectionLabel(t('Stock')),
              if (!isEdit && _openingInPacks) ...[
                Text(
                  t('Opening stock'),
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 6),
                PackQtyInput(
                  packs: _openingPacks,
                  loose: _opening,
                  packName: _secondaryUnitName.text.trim(),
                  unitShort: _unitShort(),
                  factor: _packSize!,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  if (!isEdit && !_hasVariants && !_openingInPacks) ...[
                    Expanded(
                      child: TextFormField(
                        controller: _opening,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: t('Opening stock'),
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
                      decoration: InputDecoration(
                        labelText: t('Low stock alert qty'),
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
                    labelText: t('Expiry date (optional)'),
                    helperText: t(
                      'Alerts appear when expired or within 30 days',
                    ),
                    suffixIcon: _expiryDate == null
                        ? const Icon(Icons.event_outlined)
                        : IconButton(
                            tooltip: t('Clear expiry date'),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _expiryDate = null),
                          ),
                  ),
                  child: Text(_expiryDate == null ? '—' : dateStr(_expiryDate)),
                ),
              ),
              SectionLabel(t('Options')),
              SwitchListTile(
                value: _trackSerial,
                contentPadding: EdgeInsets.zero,
                title: Text(t('Track IMEI / serial numbers')),
                subtitle: Text(t('For mobiles & electronics')),
                onChanged: (v) => setState(() => _trackSerial = v),
              ),
              SwitchListTile(
                value: _trackPieces,
                contentPadding: EdgeInsets.zero,
                title: Text(t('Sold in cut lengths')),
                subtitle: Text(
                  t(
                    'Rods, pipes, wire, cloth — the app keeps count of full pieces and leftovers by itself',
                  ),
                ),
                onChanged: (v) => setState(() {
                  _trackPieces = v;
                  // A bulk unit like "1 Rod = 12 ft" is usually the length.
                  if (v &&
                      _pieceLength.text.trim().isEmpty &&
                      _secondaryUnitName.text.trim().isNotEmpty) {
                    _pieceLength.text = _conversionFactor.text.trim();
                  }
                }),
              ),
              if (_trackPieces) ...[
                TextFormField(
                  controller: _pieceLength,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: t('Full length of 1 piece ({v1})', {
                      'v1': _unitShort(),
                    }),
                    helperText: t(
                      '1 rod = 12 ft → 12. New stock is split into full pieces. Empty = each purchase is one piece (wire coil).',
                    ),
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_trackSerial) ...[
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('IMEI / Serial Numbers'),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t(
                            'Add or scan unique IMEI numbers for individual stock units.',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _singleImeiInput,
                                decoration: InputDecoration(
                                  labelText: t('Enter or scan IMEI / Serial'),
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
                                        title: t('Enter IMEI'),
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
                                if (imei.isNotEmpty &&
                                    !_serials.contains(imei)) {
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
                                    style: const TextStyle(fontSize: 13),
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
                    decoration: InputDecoration(
                      labelText: t('Warranty (months)'),
                    ),
                  ),
                ),
              ],
              if (!isEdit)
                SwitchListTile(
                  value: _hasVariants,
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('This product has variants')),
                  subtitle: Text(t('Size, color, RAM/storage etc.')),
                  onChanged: (v) => setState(() => _hasVariants = v),
                ),
              if (!isEdit && _hasVariants) ...[
                SectionLabel(
                  _variants.isEmpty
                      ? t('Variants')
                      : t('{v1} variants', {'v1': _variants.length}),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final made = await showVariantBuilder(
                      context,
                      businessType: businessType,
                      productName: _name.text,
                      categoryName: categoryName,
                      productCode: _sku.text.trim().isNotEmpty
                          ? _sku.text.trim()
                          : _name.text.trim(),
                      productPrice: double.tryParse(_selling.text.trim()),
                      drafts: _variants,
                    );
                    if (made != null) {
                      setState(
                        () => _variants
                          ..clear()
                          ..addAll(made),
                      );
                    }
                  },
                  icon: const Icon(Icons.grid_view_rounded),
                  label: Text(
                    _variants.isEmpty
                        ? t('Choose sizes & colours')
                        : t('Change sizes & colours'),
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _variants.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(_variants[i].name),
                      subtitle: Text(
                        t('Stock: {v1}  •  ₹{v2}', {
                          'v1': _variants[i].openingStock,
                          'v2': _variants[i].sellingPrice ?? _selling.text,
                        }),
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
                          productName: _name.text,
                          categoryName: categoryName,
                          siblings: [for (final v in _variants) v.attributes],
                        );
                        if (updated != null) {
                          setState(() => _variants[i] = updated);
                        }
                      },
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final draft = await showVariantSheet(
                        context,
                        businessType: businessType,
                        productName: _name.text,
                        categoryName: categoryName,
                        siblings: [for (final v in _variants) v.attributes],
                      );
                      if (draft != null) setState(() => _variants.add(draft));
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t('Add one variant')),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('Description (optional)'),
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
                    : Text(isEdit ? t('Save changes') : 'Add product'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
