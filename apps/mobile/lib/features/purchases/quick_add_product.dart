import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_refresh.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../products/product_providers.dart';

/// A small "new product" dialog for the purchase screen: name, unit, prices
/// and GST, without leaving the purchase. Typing a name offers products from
/// the shared list; picking one fills its unit, GST, HSN, category and brand.
/// Returns the new product's id. No opening stock: the purchase brings it in.
Future<String?> showQuickAddProduct(BuildContext context, {String name = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _QuickAddProduct(initialName: name),
  );
}

class _QuickAddProduct extends ConsumerStatefulWidget {
  const _QuickAddProduct({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_QuickAddProduct> createState() => _QuickAddProductState();
}

class _QuickAddProductState extends ConsumerState<_QuickAddProduct> {
  static const _gstRates = [0.0, 3.0, 5.0, 12.0, 18.0, 28.0, 40.0];

  late final _name = TextEditingController(text: widget.initialName);
  final _purchase = TextEditingController();
  final _selling = TextEditingController();
  String? _unitId;
  double _gst = 0;

  // Details taken from the shared list when a suggestion is picked.
  Map<String, dynamic>? _master;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _timer;
  bool _filling = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_nameChanged);
    if (widget.initialName.trim().length >= 3) _search(widget.initialName);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _purchase.dispose();
    _selling.dispose();
    super.dispose();
  }

  void _nameChanged() {
    if (_filling) return;
    // Typing again after a pick: it is a different product now.
    if (_master != null) setState(() => _master = null);
    _timer?.cancel();
    final text = _name.text.trim();
    if (text.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  Future<void> _search(String text) async {
    try {
      final res = await ref
          .read(supabaseProvider)
          .rpc(
            'search_master_products',
            params: {'p_query': text, 'p_limit': 5},
          );
      if (!mounted || _master != null) return;
      setState(
        () => _suggestions = [
          for (final m in (res as List? ?? const []))
            Map<String, dynamic>.from(m as Map),
        ],
      );
    } catch (_) {
      // Offline or no shared list: just no suggestions.
    }
  }

  Future<void> _pick(Map<String, dynamic> m) async {
    try {
      final res = await ref
          .read(supabaseProvider)
          .rpc('use_master_product', params: {'p_master': m['id']});
      final d = Map<String, dynamic>.from(res as Map);
      ref.invalidate(categoriesProvider);
      ref.invalidate(brandsProvider);
      ref.invalidate(unitsProvider);
      await ref.read(unitsProvider.future);
      if (!mounted) return;
      final gst = (d['gst_rate'] as num?)?.toDouble();
      _filling = true;
      setState(() {
        _master = d;
        _suggestions = [];
        _name.text = d['name'] as String? ?? _name.text;
        _unitId = d['unit_id'] as String? ?? _unitId;
        if (gst != null && _gstRates.contains(gst)) _gst = gst;
      });
      _filling = false;
    } catch (e) {
      _filling = false;
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final selling = double.tryParse(_selling.text.trim());
    if (name.length < 2) {
      showError(context, t('Enter the product name'));
      return;
    }
    if (selling == null || selling <= 0) {
      showError(context, t('Enter the selling price'));
      return;
    }
    setState(() => _busy = true);
    try {
      final m = _master;
      final row = <String, dynamic>{
        'business_id': ref.read(appContextProvider).value?.businessId,
        'name': name,
        'unit_id': _unitId,
        'purchase_price': double.tryParse(_purchase.text.trim()) ?? 0,
        'selling_price': selling,
        'gst_rate': _gst,
        if (m != null) ...{
          'master_product_id': m['master_product_id'],
          'category_id': m['category_id'],
          'brand_id': m['brand_id'],
          'hsn_code': m['hsn_code'] ?? '',
          'barcode': m['barcode'] ?? '',
          'track_serial': m['track_serial'] == true,
          'track_pieces': m['track_pieces'] == true,
          'warranty_months': m['warranty_months'],
          'secondary_unit_name': m['secondary_unit_name'],
          'conversion_factor': m['conversion_factor'],
        },
      };
      final inserted = await ref
          .read(supabaseProvider)
          .from('products')
          .insert(row)
          .select('id')
          .single();
      invalidateStockData(ref);
      if (mounted) Navigator.pop(context, inserted['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider).value ?? const [];
    // Default to Piece, as the full product form does.
    if (_unitId == null && units.isNotEmpty) {
      final piece = units.where((u) => u['name'] == 'Piece');
      _unitId = (piece.isNotEmpty ? piece.first : units.first)['id'] as String;
    }
    final unitIds = {for (final u in units) u['id']};
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    return AlertDialog(
      title: Text(t('Add new product')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t('Product name *')),
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  t('From the product list — tap to fill the details'),
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
                for (final s in _suggestions)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    title: Text(s['name'] as String? ?? ''),
                    subtitle: Text(
                      [
                        s['brand'] as String? ?? '',
                        s['category'] as String? ?? '',
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    onTap: () => _pick(s),
                  ),
              ],
              if (_master != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t(
                      'Category, brand, HSN and GST filled from the product list',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.green,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: unitIds.contains(_unitId) ? _unitId : null,
                key: ValueKey('unit_$_unitId'),
                decoration: InputDecoration(labelText: t('Unit')),
                items: [
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _purchase,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: money,
                      decoration: InputDecoration(
                        labelText: t('Purchase price ₹'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _selling,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: money,
                      decoration: InputDecoration(
                        labelText: t('Selling price ₹ *'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                key: ValueKey('gst_$_gst'),
                initialValue: _gst,
                decoration: InputDecoration(labelText: t('GST %')),
                items: [
                  for (final r in _gstRates)
                    DropdownMenuItem(
                      value: r,
                      child: Text('${r.toStringAsFixed(0)}%'),
                    ),
                ],
                onChanged: (v) => setState(() => _gst = v ?? 0),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'More details (barcode, MRP, variants) can be added later from Products.',
                ),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('Cancel')),
        ),
        FilledButton(
          style: dialogActionStyle,
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Add to purchase')),
        ),
      ],
    );
  }
}
