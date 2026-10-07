import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/business_category.dart';
import '../../core/data_refresh.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'product_providers.dart';

/// What the "Add" button sends for the ticked products (up to 100 at a time,
/// the database's limit). Every ticked product needs a selling price above 0;
/// returns null while one is missing so the screen can say so.
List<Map<String, dynamic>>? suggestedItemsPayload(
  Iterable<String> ids,
  Map<String, String> prices,
  Map<String, String> stock,
) {
  final items = <Map<String, dynamic>>[];
  for (final id in ids) {
    final price = double.tryParse((prices[id] ?? '').trim());
    if (price == null || price <= 0) return null;
    final open = double.tryParse((stock[id] ?? '').trim());
    items.add({
      'master_id': id,
      'selling_price': price,
      if (open != null && open > 0) 'opening_stock': open,
    });
  }
  return items;
}

/// Browse the shared product list for the shop's kind of shop, tick many
/// products, give each its selling price and add them in one go. The list
/// carries names, units, HSN and GST only; prices are always the shop's own.
class SuggestedProductsScreen extends ConsumerStatefulWidget {
  const SuggestedProductsScreen({super.key});

  @override
  ConsumerState<SuggestedProductsScreen> createState() =>
      _SuggestedProductsScreenState();
}

class _SuggestedProductsScreenState
    extends ConsumerState<SuggestedProductsScreen> {
  static const _pageSize = 100;

  final _search = TextEditingController();
  Timer? _debounce;

  String _type = ''; // blank = the shop's own kind, '*' = every kind
  String _category = '';
  String _query = '';

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _categories = [];
  String _mine = '';
  int _total = 0;
  bool _loading = true;
  bool _moreLoading = false;
  String? _error;
  int _generation = 0; // drops answers to searches that are already outdated

  // Ticked products (kept while filters change) and what was typed for them.
  final Map<String, Map<String, dynamic>> _ticked = {};
  final Map<String, TextEditingController> _price = {};
  final Map<String, TextEditingController> _stock = {};
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final c in [..._price.values, ..._stock.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final gen = ++_generation;
    setState(() {
      if (more) {
        _moreLoading = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final res = await ref.read(supabaseProvider).rpc(
        'browse_master_products',
        params: {
          'p_type': _type,
          'p_category': _category,
          'p_query': _query,
          'p_limit': _pageSize,
          'p_offset': more ? _rows.length : 0,
        },
      );
      if (!mounted || gen != _generation) return;
      final d = Map<String, dynamic>.from(res as Map);
      List<Map<String, dynamic>> list(String key) => [
        for (final r in (d[key] as List? ?? const []))
          Map<String, dynamic>.from(r as Map),
      ];
      setState(() {
        _rows = more ? [..._rows, ...list('rows')] : list('rows');
        _types = list('types');
        _categories = list('categories');
        _mine = d['mine'] as String? ?? '';
        _total = (d['total'] as num?)?.toInt() ?? _rows.length;
        _loading = false;
        _moreLoading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
        _moreLoading = false;
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      _load();
    });
  }

  void _toggle(Map<String, dynamic> m, bool on) {
    final id = m['id'] as String;
    setState(() {
      if (on) {
        _ticked[id] = m;
        _price.putIfAbsent(id, TextEditingController.new);
        _stock.putIfAbsent(id, TextEditingController.new);
      } else {
        _ticked.remove(id);
        _price.remove(id)?.dispose();
        _stock.remove(id)?.dispose();
      }
    });
  }

  Future<void> _add() async {
    final ids = _ticked.keys.toList();
    final items = suggestedItemsPayload(
      ids,
      {for (final e in _price.entries) e.key: e.value.text},
      {for (final e in _stock.entries) e.key: e.value.text},
    );
    if (items == null) {
      showError(context, t('Enter a selling price for every ticked product'));
      return;
    }
    setState(() => _adding = true);
    var added = 0;
    var skipped = 0;
    try {
      final client = ref.read(supabaseProvider);
      for (var i = 0; i < items.length; i += 100) {
        final chunk = items.sublist(i, i + 100 > items.length ? items.length : i + 100);
        final res = await client.rpc(
          'add_products_from_master',
          params: {'p_items': chunk},
        );
        final d = Map<String, dynamic>.from(res as Map);
        added += (d['added'] as num?)?.toInt() ?? 0;
        skipped += (d['skipped'] as num?)?.toInt() ?? 0;
        // Those sent are in the shop now (or were already): stop offering them.
        for (final item in chunk) {
          final id = item['master_id'] as String;
          _ticked.remove(id);
          _price.remove(id)?.dispose();
          _stock.remove(id)?.dispose();
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    invalidateStockData(ref);
    ref.invalidate(categoriesProvider);
    ref.invalidate(brandsProvider);
    ref.invalidate(unitsProvider);
    if (!mounted) return;
    setState(() => _adding = false);
    if (added > 0 || skipped > 0) {
      showSuccess(
        context,
        skipped == 0
            ? t('{added} products added', {'added': added})
            : t('{added} added, {skipped} were already in your list', {
                'added': added,
                'skipped': skipped,
              }),
      );
    }
    await _load();
  }

  String _typeLabel(String key) => categoryOf(key).label;

  @override
  Widget build(BuildContext context) {
    final ownKey = _type.isEmpty ? _mine : _type;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Suggested products')),
      ),
      bottomNavigationBar: _ticked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _adding ? null : _add,
                  icon: _adding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check),
                  label: Text(
                    t('Add {n} products', {'n': _ticked.length}),
                  ),
                ),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchField(
              controller: _search,
              hint: t('Search by name or brand'),
              onChanged: _onSearch,
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (_mine.isNotEmpty)
                  _chip(
                    t('My shop: {kind}', {'kind': _typeLabel(_mine)}),
                    _type.isEmpty,
                    () => _setType(''),
                  ),
                for (final ty in _types)
                  if ((ty['type'] as String) != _mine)
                    _chip(
                      '${_typeLabel(ty['type'] as String)} (${ty['count']})',
                      _type == ty['type'],
                      () => _setType(ty['type'] as String),
                    ),
                _chip(t('Everything'), _type == '*', () => _setType('*')),
              ],
            ),
          ),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip(t('All categories'), _category.isEmpty, () => _setCategory('')),
                  for (final c in _categories)
                    _chip(
                      '${c['category']} (${c['count']})',
                      _category == c['category'],
                      () => _setCategory(c['category'] as String),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t('Tick what you sell, enter your selling price, then add them all. Products you already have are not shown.'),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ),
          ),
          Expanded(child: _body(ownKey)),
        ],
      ),
    );
  }

  void _setType(String v) {
    if (_type == v) return;
    _type = v;
    _category = '';
    _load();
  }

  void _setCategory(String v) {
    if (_category == v) return;
    _category = v;
    _load();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
    child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
  );

  Widget _body(String ownKey) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(t('Try again'))),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: t('Nothing found. Try another word, a category, or "Everything".'),
      );
    }
    final canMore = _rows.length < _total;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _rows.length + (canMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _rows.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: _moreLoading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => _load(more: true),
                      child: Text(
                        t('Show more ({n} left)', {'n': _total - _rows.length}),
                      ),
                    ),
            ),
          );
        }
        return _row(_rows[i]);
      },
    );
  }

  Widget _row(Map<String, dynamic> m) {
    final id = m['id'] as String;
    final on = _ticked.containsKey(id);
    final unit = (m['unit_name'] as String? ?? '');
    final rate = (m['gst_rate'] as num?)?.toDouble();
    final gst = rate == null
        ? ''
        : 'GST ${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}%';
    final detail = [
      m['brand'] as String? ?? '',
      m['category'] as String? ?? '',
      unit,
      gst,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: on ? AppColors.primary : AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Column(
          children: [
            CheckboxListTile(
              value: on,
              onChanged: (v) => _toggle(m, v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(
                m['name'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(detail, style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
            ),
            if (on)
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 0, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _price[id],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        decoration: InputDecoration(
                          labelText: t('Selling price'),
                          prefixText: '₹ ',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _stock[id],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        decoration: InputDecoration(
                          labelText: t('Stock (optional)'),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
