import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// A customer's agreed prices (customer_prices, migration 0043). They are
/// the default price for that customer at the POS (D15).
final customerPricesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, customerId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('customer_prices')
          .select(
            'id, price, note, product_id, variant_id, products(name, selling_price), '
            'product_variants(name, selling_price)',
          )
          .eq('customer_id', customerId)
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows);
    });

class CustomerPricesSection extends ConsumerWidget {
  const CustomerPricesSection({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(appContextProvider).value?.canEditPrices ?? false;
    final prices = ref.watch(customerPricesProvider(customerId));
    final rows = prices.value ?? const [];
    if (!canEdit && rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel(t('Agreed prices'))),
            if (canEdit)
              TextButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('Add')),
              ),
          ],
        ),
        if (rows.isEmpty)
          Text(t('No agreed prices — this customer pays the normal price.'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          )
        else
          Card(
            child: Column(
              children: [
                for (final r in rows)
                  ListTile(
                    dense: true,
                    title: Text(_name(r)),
                    subtitle: Text(
                      'Normal ${money(toDouble((r['product_variants'] as Map?)?['selling_price'] ?? (r['products'] as Map?)?['selling_price']))}'
                      '${(r['note'] as String? ?? '').isNotEmpty ? ' • ${r['note']}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          money(r['price'] as num?),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (canEdit)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: t('Remove agreed price'),
                            onPressed: () => _remove(context, ref, r),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _name(Map<String, dynamic> r) {
    final p = (r['products'] as Map?)?['name'] ?? '';
    final v = (r['product_variants'] as Map?)?['name'];
    return v == null ? '$p' : '$p ($v)';
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> r,
  ) async {
    final ok = await confirmDialog(
      context,
      title: t('Remove agreed price?'),
      message:
          t('{v1} will go back to the normal price for this customer.', {'v1': _name(r)}),
      confirmText: t('Remove'),
    );
    if (!ok) return;
    try {
      await ref
          .read(supabaseProvider)
          .from('customer_prices')
          .delete()
          .eq('id', r['id'] as String);
      ref.invalidate(customerPricesProvider(customerId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final picked =
        await showDialog<
          ({Map<String, dynamic> product, Map<String, dynamic>? variant})
        >(context: context, builder: (_) => const _ProductChooser());
    if (picked == null || !context.mounted) return;
    final normal = toDouble(
      picked.variant?['selling_price'] ?? picked.product['selling_price'],
    );
    final price = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${picked.product['name']}${picked.variant == null ? '' : ' (${picked.variant!['name']})'}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: t('Agreed price ₹'),
                helperText:
                    t('Normal price {v1} — same basis (incl. GST)', {'v1': money(normal)}),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: t('Note (optional)')),
            ),
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
    final value = double.tryParse(price.text.trim()) ?? 0;
    if (ok != true || value <= 0) return;
    try {
      await ref.read(supabaseProvider).from('customer_prices').upsert({
        'business_id': ref.read(appContextProvider).value?.businessId,
        'customer_id': customerId,
        'product_id': picked.product['id'],
        'variant_id': picked.variant?['id'],
        'price': value,
        'note': note.text.trim(),
      }, onConflict: 'customer_id,product_id,variant_id');
      ref.invalidate(customerPricesProvider(customerId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Search a product (and variant) to give an agreed price for.
class _ProductChooser extends ConsumerStatefulWidget {
  const _ProductChooser();

  @override
  ConsumerState<_ProductChooser> createState() => _ProductChooserState();
}

class _ProductChooserState extends ConsumerState<_ProductChooser> {
  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _product;

  Future<void> _search(String q) async {
    final rows = await ref
        .read(supabaseProvider)
        .from('products')
        .select(
          'id, name, selling_price, has_variants, product_variants(id, name, selling_price, is_active)',
        )
        .eq('is_active', true)
        .ilike('name', '%${q.trim()}%')
        .order('name', ascending: true)
        .limit(30);
    if (mounted) {
      setState(() => _results = List<Map<String, dynamic>>.from(rows));
    }
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final variants = product == null
        ? const <Map<String, dynamic>>[]
        : [
            for (final v in List<Map<String, dynamic>>.from(
              product['product_variants'] as List? ?? const [],
            ))
              if (v['is_active'] != false) v,
          ];
    return AlertDialog(
      title: Text(product == null ? t('Choose product') : 'Choose variant'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: product == null
            ? Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: t('Search products'),
                    ),
                    onChanged: _search,
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final p in _results)
                          ListTile(
                            dense: true,
                            title: Text('${p['name']}'),
                            trailing: Text(money(p['selling_price'] as num?)),
                            onTap: () {
                              final hasVariants =
                                  p['has_variants'] == true &&
                                  (p['product_variants'] as List? ?? const [])
                                      .isNotEmpty;
                              if (hasVariants) {
                                setState(() => _product = p);
                              } else {
                                Navigator.pop(context, (
                                  product: p,
                                  variant: null,
                                ));
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : ListView(
                children: [
                  for (final v in variants)
                    ListTile(
                      dense: true,
                      title: Text('${v['name']}'),
                      trailing: Text(
                        money(
                          (v['selling_price'] ?? product['selling_price'])
                              as num?,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, (
                        product: product,
                        variant: v,
                      )),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('Cancel')),
        ),
      ],
    );
  }
}
