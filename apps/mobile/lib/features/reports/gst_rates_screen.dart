import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data_refresh.dart';
import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// GST 2.0 (22 September 2025): the 12% and 28% rates went for almost all
/// goods — most 12% goods to 5%, most 28% goods to 18%, a few luxury and
/// sin goods to 40%. Products still at 12% / 28% are listed so the shop
/// can move them; nothing changes without the shop choosing.
final oldGstRateProductsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('products')
          .select('id, name, gst_rate, hsn_code')
          .eq('is_active', true)
          .eq('gst_category', 'taxable')
          .inFilter('gst_rate', [12, 28])
          .order('name', ascending: true)
          .limit(2000);
      return List<Map<String, dynamic>>.from(rows);
    });

/// "N products are still at 12% or 28%" — on the GST screens of a regular
/// GST shop, with a way to review them.
class GstRatesBanner extends ConsumerWidget {
  const GstRatesBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appContextProvider).value;
    if (app == null || !app.gstEnabled) return const SizedBox.shrink();
    final count = ref.watch(oldGstRateProductsProvider).value?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Card(
      color: AppColors.orange.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.update, color: AppColors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t(
                  '{v1} products are still at 12% or 28% GST. From 22 Sep 2025 most goods moved to 5% or 18%.',
                  {'v1': count},
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const GstRatesScreen())),
              child: Text(t('Review')),
            ),
          ],
        ),
      ),
    );
  }
}

class GstRatesScreen extends ConsumerStatefulWidget {
  const GstRatesScreen({super.key});

  @override
  ConsumerState<GstRatesScreen> createState() => _GstRatesScreenState();
}

class _GstRatesScreenState extends ConsumerState<GstRatesScreen> {
  final Set<String> _selected = {};
  bool _busy = false;

  Future<void> _apply(double rate) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final ok = await confirmDialog(
      context,
      title: t('Change GST rate'),
      message: t(
        'Set {v1} products to {v2}% GST? New bills use the new rate; bills already made stay as they are.',
        {'v1': ids.length, 'v2': qty(rate)},
      ),
      confirmText: t('Change'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final client = ref.read(supabaseProvider);
      for (var i = 0; i < ids.length; i += 200) {
        await client
            .from('products')
            .update({'gst_rate': rate})
            .inFilter('id', ids.sublist(i, (i + 200).clamp(0, ids.length)));
      }
      ref.invalidate(oldGstRateProductsProvider);
      invalidateStockData(ref);
      if (mounted) {
        setState(() => _selected.clear());
        showSuccess(
          context,
          t('{v1} products now at {v2}% GST', {
            'v1': ids.length,
            'v2': qty(rate),
          }),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(oldGstRateProductsProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(t('GST rates (GST 2.0)'))),
      body: AsyncView(
        value: products,
        onRetry: () => ref.invalidate(oldGstRateProductsProvider),
        builder: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.check_circle_outline,
              message: t(
                'No products at 12% or 28% — your rates are up to date.',
              ),
            );
          }
          final allSelected = _selected.length == rows.length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  t(
                    'Check each product\'s new rate with its HSN code — most 12% goods are now 5%, most 28% goods 18%, and luxury / tobacco goods 40%. Ask your accountant if unsure.',
                  ),
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ),
              CheckboxListTile(
                value: allSelected,
                title: Text(t('Select all ({v1})', {'v1': rows.length})),
                onChanged: (v) => setState(() {
                  _selected.clear();
                  if (v == true) {
                    _selected.addAll(rows.map((r) => r['id'] as String));
                  }
                }),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final p = rows[i];
                    final id = p['id'] as String;
                    return CheckboxListTile(
                      value: _selected.contains(id),
                      title: Text(p['name'] as String? ?? ''),
                      subtitle: Text(
                        [
                          t('Now {v1}%', {'v1': qty(toDouble(p['gst_rate']))}),
                          if ('${p['hsn_code'] ?? ''}'.isNotEmpty)
                            'HSN ${p['hsn_code']}',
                        ].join(' · '),
                      ),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('{v1} selected — set to', {'v1': _selected.length}),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final r in const [5.0, 18.0, 40.0])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilledButton(
                    onPressed: _busy || _selected.isEmpty
                        ? null
                        : () => _apply(r),
                    child: Text('${qty(r)}%'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
