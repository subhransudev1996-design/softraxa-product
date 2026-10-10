import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'variant_matrix.dart';

/// A product's variants as a size × colour table: sizes across, colours
/// down, one box per variant. [cellBuilder] fills each box (stock to tap
/// when billing, a quantity box in purchases); a combination that wasn't
/// made shows a dash.
class VariantGridView extends StatelessWidget {
  const VariantGridView({
    super.key,
    required this.grid,
    required this.cellBuilder,
    this.cellWidth = 78,
  });

  final VariantGrid grid;
  final Widget Function(BuildContext context, Map<String, dynamic> variant)
  cellBuilder;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppColors.inkSoft,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: FixedColumnWidth(cellWidth),
        columnWidths: const {0: IntrinsicColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 10, 6),
                child: Text(grid.rows?.name ?? '', style: head),
              ),
              for (final c in grid.columns.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(c, textAlign: TextAlign.center, style: head),
                ),
            ],
          ),
          for (final r in grid.rowValues)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    r ?? grid.columns.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final c in grid.columns.values)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: grid.cell(r, c) == null
                        ? SizedBox(
                            height: 52,
                            child: Center(
                              child: Text(
                                '—',
                                style: TextStyle(color: AppColors.inkSoft),
                              ),
                            ),
                          )
                        : cellBuilder(context, grid.cell(r, c)!),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A box with a big number (stock) and an optional line under it (price),
/// coloured by stock: red when out, orange when low.
class VariantStockCell extends StatelessWidget {
  const VariantStockCell({
    super.key,
    required this.variant,
    this.subtitle,
    this.onTap,
  });

  final Map<String, dynamic> variant;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stock = toDouble(variant['current_stock']);
    final low = toDouble(variant['low_stock_qty']);
    final hidden = variant['is_active'] == false;
    final color = stock <= 0
        ? AppColors.red
        : (low > 0 && stock <= low ? AppColors.orange : AppColors.green);
    return Material(
      color: (hidden ? AppColors.inkSoft : color).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                qty(stock),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: hidden ? AppColors.inkSoft : color,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Billing: tap the size/colour box to add it. Shows stock in each box and
/// the price under it when it differs from the product's. Null when the
/// variants don't make a grid ([variantGridOf]) or nothing was picked.
Future<Map<String, dynamic>?> showVariantGridPicker(
  BuildContext context, {
  required Map<String, dynamic> product,
  required VariantGrid grid,
}) {
  final basePrice = toDouble(product['selling_price']);
  final body = VariantGridView(
    grid: grid,
    cellBuilder: (ctx, v) {
      final price = toDouble(v['selling_price'] ?? product['selling_price']);
      return VariantStockCell(
        variant: v,
        subtitle: (price - basePrice).abs() > 0.005 ? money(price) : null,
        onTap: () => Navigator.pop(ctx, v),
      );
    },
  );
  final title = t('Select variant — {v1}', {'v1': product['name']});
  final note = Text(
    t('Each box shows the stock. Tap one to add it.'),
    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
  );
  if (isWideLayout(context)) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [note, const SizedBox(height: 12), body],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
        ],
      ),
    );
  }
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            note,
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    ),
  );
}

/// Purchases: type how many came in, in each size/colour box, all at once.
/// Returns variant → quantity for the boxes filled; null when cancelled.
Future<List<(Map<String, dynamic>, double)>?> showVariantQtyGrid(
  BuildContext context, {
  required Map<String, dynamic> product,
  required VariantGrid grid,
}) {
  final ctrls = <String, TextEditingController>{};
  TextEditingController ctrl(Map<String, dynamic> v) =>
      ctrls.putIfAbsent(v['id'] as String, TextEditingController.new);

  return showDialog<List<(Map<String, dynamic>, double)>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final entered = [
          for (final r in grid.rowValues)
            for (final c in grid.columns.values)
              if (grid.cell(r, c) case final v?)
                if ((double.tryParse(ctrl(v).text.trim()) ?? 0) > 0)
                  (v, double.parse(ctrl(v).text.trim())),
        ];
        final total = entered.fold(0.0, (s, e) => s + e.$2);
        return AlertDialog(
          title: Text(t('How many came in? — {v1}', {'v1': product['name']})),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    'Type the quantity in each box. Leave empty what didn\'t come.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 12),
                VariantGridView(
                  grid: grid,
                  cellWidth: 70,
                  cellBuilder: (ctx, v) => TextField(
                    controller: ctrl(v),
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: qty(toDouble(v['current_stock'])),
                      helperText: ' ',
                      helperStyle: const TextStyle(fontSize: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t('Grey numbers are the stock now.'),
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: entered.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, entered),
              child: Text(
                entered.isEmpty
                    ? t('Add')
                    : t('Add {v1} lines ({v2} pcs)', {
                        'v1': entered.length,
                        'v2': qty(total),
                      }),
              ),
            ),
          ],
        );
      },
    ),
  );
}
