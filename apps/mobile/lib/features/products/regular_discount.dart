import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'product_providers.dart';

/// Sets the regular discount % (0094) on many products at once: every
/// product, one publisher's, or one category's. Bills fill it in on each
/// line; the cashier can still change it.
Future<void> showRegularDiscountSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final client = ref.read(supabaseProvider);
  List<Map<String, dynamic>> publishers;
  List<Map<String, dynamic>> categories;
  try {
    publishers = List<Map<String, dynamic>>.from(
      await client.rpc('product_publishers') as List,
    );
    categories = await ref.read(categoriesProvider.future);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;

  var scope = publishers.isNotEmpty ? 'publisher' : 'all';
  String? publisher;
  String? categoryId;
  final pct = TextEditingController();
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        String rangeOf(Map<String, dynamic> p) {
          final lo = toDouble(p['min_pct']);
          final hi = toDouble(p['max_pct']);
          final now = lo == hi ? '${qty(lo)}%' : '${qty(lo)}–${qty(hi)}%';
          return t('{v1} products, now {v2}', {'v1': p['products'], 'v2': now});
        }

        return AlertDialog(
          title: Text(t('Regular discount')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(
                      'The discount every bill takes off these products by itself. The cashier can still change it on a bill.',
                    ),
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      if (publishers.isNotEmpty)
                        ButtonSegment(
                          value: 'publisher',
                          label: Text(t('Publisher')),
                        ),
                      ButtonSegment(
                        value: 'category',
                        label: Text(t('Category')),
                      ),
                      ButtonSegment(value: 'all', label: Text(t('All'))),
                    ],
                    selected: {scope},
                    onSelectionChanged: (v) => setLocal(() => scope = v.first),
                  ),
                  const SizedBox(height: 12),
                  if (scope == 'publisher')
                    DropdownButtonFormField<String>(
                      initialValue: publisher,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: t('Publisher')),
                      items: [
                        for (final p in publishers)
                          DropdownMenuItem(
                            value: p['publisher'] as String,
                            child: Text(
                              '${p['publisher']} · ${rangeOf(p)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => publisher = v),
                    ),
                  if (scope == 'category')
                    DropdownButtonFormField<String>(
                      initialValue: categoryId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: t('Category')),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(c['name'] as String? ?? ''),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => categoryId = v),
                    ),
                  if (scope == 'all')
                    Text(
                      t('Every product in the shop.'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pct,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t('Regular discount %'),
                      helperText: t('0 takes the discount off.'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: busy
                  ? null
                  : () async {
                      final v = double.tryParse(pct.text.trim());
                      if (v == null || v < 0 || v >= 100) {
                        showError(ctx, t('Enter a discount from 0 to 99%'));
                        return;
                      }
                      if (scope == 'publisher' && publisher == null) {
                        showError(ctx, t('Choose the publisher'));
                        return;
                      }
                      if (scope == 'category' && categoryId == null) {
                        showError(ctx, t('Choose the category'));
                        return;
                      }
                      setLocal(() => busy = true);
                      try {
                        final n = await client.rpc(
                          'set_regular_discount',
                          params: {
                            'p_pct': v,
                            'p_publisher': scope == 'publisher'
                                ? publisher
                                : '',
                            'p_category_id': scope == 'category'
                                ? categoryId
                                : null,
                          },
                        );
                        ref.invalidate(productsProvider);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        showSuccess(
                          context,
                          t('Regular discount set on {v1} products', {'v1': n}),
                        );
                      } catch (e) {
                        setLocal(() => busy = false);
                        if (ctx.mounted) showError(ctx, e);
                      }
                    },
              child: Text(t('Save')),
            ),
          ],
        );
      },
    ),
  );
}
