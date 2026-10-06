import '../../core/i18n.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

// Desktop dashboard panels: a 30-day sales chart, the best sellers and the
// latest bills as a table. Data comes from the same report functions the
// Reports screen uses (get_sales_report, get_product_sales_report).

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Sales per day for the last 30 days, days without sales as zero.
final salesTrendProvider = FutureProvider.autoDispose<List<(DateTime, double)>>(
  (ref) async {
    final client = ref.watch(supabaseProvider);
    final to = _today();
    final from = to.subtract(const Duration(days: 29));
    final d =
        await client.rpc(
              'get_sales_report',
              params: {'p_from': ymd(from), 'p_to': ymd(to)},
            )
            as Map<String, dynamic>;
    final byDay = <String, double>{
      for (final r in (d['by_day'] as List? ?? []))
        '${r['day']}'.substring(0, 10): toDouble(r['sales']),
    };
    return [
      for (var i = 0; i < 30; i++)
        (
          from.add(Duration(days: i)),
          byDay[ymd(from.add(Duration(days: i)))] ?? 0,
        ),
    ];
  },
);

/// The five products with the most sales in the last 30 days.
final topProductsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final client = ref.watch(supabaseProvider);
      final to = _today();
      final rows =
          await client.rpc(
                'get_product_sales_report',
                params: {
                  'p_from': ymd(to.subtract(const Duration(days: 29))),
                  'p_to': ymd(to),
                },
              )
              as List;
      final list = List<Map<String, dynamic>>.from(rows)
        ..sort(
          (a, b) => toDouble(b['revenue']).compareTo(toDouble(a['revenue'])),
        );
      return list.take(5).toList();
    });

/// A white panel with a title row.
class DashPanel extends StatelessWidget {
  const DashPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

class SalesTrendPanel extends ConsumerWidget {
  const SalesTrendPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(salesTrendProvider);
    final total = trend.value?.fold<double>(0, (s, p) => s + p.$2);
    return DashPanel(
      title: t('Sales — last 30 days'),
      subtitle: total == null ? ' ' : 'Total ${money(total)}',
      action: TextButton(
        onPressed: () => context.push('/reports'),
        child: Text(t('Reports')),
      ),
      child: AsyncView(
        value: trend,
        onRetry: () => ref.invalidate(salesTrendProvider),
        builder: (points) => _SalesLine(points: points),
      ),
    );
  }
}

class _SalesLine extends StatelessWidget {
  const _SalesLine({required this.points});

  final List<(DateTime, double)> points;

  @override
  Widget build(BuildContext context) {
    final maxV = points.fold<double>(0, (m, p) => p.$2 > m ? p.$2 : m);
    final top = maxV <= 0 ? 1000.0 : maxV * 1.2;
    final dayFmt = DateFormat('d MMM');
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: top,
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: top / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: top / 4,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(
                      moneyCompact(v),
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                // Weekly labels counted back from today, so the last
                // label is today and none overlap.
                final i = v.round();
                if (i < 0 ||
                    i >= points.length ||
                    v != i ||
                    (points.length - 1 - i) % 7 != 0) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    dayFmt.format(points[i].$1),
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${dayFmt.format(points[s.x.round()].$1)}\n${money(s.y)}',
                  TextStyle(
                    color: AppColors.card,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].$2),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TopProductsPanel extends ConsumerWidget {
  const TopProductsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(topProductsProvider);
    return DashPanel(
      title: t('Top products'),
      subtitle: t('By sales, last 30 days'),
      child: AsyncView(
        value: top,
        onRetry: () => ref.invalidate(topProductsProvider),
        builder: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Text(t('No sales in the last 30 days.'),
                style: TextStyle(color: AppColors.inkSoft),
              ),
            );
          }
          final best = toDouble(rows.first['revenue']);
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r['product_name']}'
                        '${(r['variant_name'] as String? ?? '').isNotEmpty ? ' (${r['variant_name']})' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      money(r['revenue'] as num?),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: best <= 0 ? 0 : toDouble(r['revenue']) / best,
                          minHeight: 6,
                          color: AppColors.primary,
                          backgroundColor: AppColors.primarySoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 64,
                      child: Text(
                        t('{v1} sold', {'v1': qty(r['qty_sold'] as num?)}),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Latest bills as a table: Invoice · Customer · Date · Amount · Status.
class RecentInvoicesPanel extends StatelessWidget {
  const RecentInvoicesPanel({
    super.key,
    required this.invoices,
    required this.onRetry,
  });

  final AsyncValue<List<Map<String, dynamic>>> invoices;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      color: AppColors.inkSoft,
    );
    Widget cols(List<Widget> c) => Row(
      children: [
        SizedBox(width: 150, child: c[0]),
        Expanded(child: c[1]),
        SizedBox(width: 190, child: c[2]),
        SizedBox(
          width: 130,
          child: Align(alignment: Alignment.centerRight, child: c[3]),
        ),
        SizedBox(
          width: 120,
          child: Align(alignment: Alignment.centerRight, child: c[4]),
        ),
      ],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(t('Recent bills'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/invoices'),
                  child: Text(t('View all')),
                ),
              ],
            ),
          ),
          Container(
            color: AppColors.canvas,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            child: cols([
              Text(t('INVOICE'), style: head),
              Text(t('CUSTOMER'), style: head),
              Text(t('DATE'), style: head),
              Text(t('AMOUNT'), style: head),
              Text(t('STATUS'), style: head),
            ]),
          ),
          AsyncView(
            value: invoices,
            onRetry: onRetry,
            builder: (rows) => rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(t('No bills yet — create your first bill with New Bill.'),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final (i, inv) in rows.indexed) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.line),
                        InkWell(
                          onTap: () => context.push('/invoices/${inv['id']}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 11,
                            ),
                            child: cols([
                              Text(
                                '${inv['invoice_no']}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                ((inv['customer_name'] as String?) ?? '')
                                        .trim()
                                        .isEmpty
                                    ? t('Walk-in customer')
                                    : (inv['customer_name'] as String).trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                dateTimeStr(inv['invoice_date']),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                              Text(
                                money(inv['total'] as num?),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              StatusChip(
                                inv['is_cancelled'] == true
                                    ? 'cancelled'
                                    : (inv['payment_status'] as String? ?? ''),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
