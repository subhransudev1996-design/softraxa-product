import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';

/// A single labeled data point for report charts.
typedef ChartPoint = (String label, double value);

/// Vertical bar chart for report data — day trends, top-N rankings, or
/// category breakdowns. Pass [points2] for a side-by-side second series
/// (e.g. GST output vs input tax per rate slab).
///
/// Horizontally scrollable so long date ranges / many categories never
/// squash into unreadable bars — it grows with the data instead.
class ReportBarChart extends StatelessWidget {
  const ReportBarChart({
    super.key,
    required this.points,
    this.points2,
    this.seriesLabel,
    this.series2Label,
    this.barColor = AppColors.teal,
    this.bar2Color = AppColors.orange,
    this.barColors,
    this.isMoney = true,
    this.height = 220,
  });

  final List<ChartPoint> points;
  final List<ChartPoint>? points2;
  final String? seriesLabel;
  final String? series2Label;
  final Color barColor;
  final Color bar2Color;

  /// Per-bar colors for series 1, indexed like [points] (e.g. a profit
  /// breakdown where some categories are gains and others are costs).
  /// Overrides [barColor] when provided; ignored for the second series.
  final List<Color>? barColors;

  /// Format tooltip values as currency (true) or a plain quantity (false).
  final bool isMoney;
  final double height;

  String _fmt(double v) => isMoney ? money(v) : qty(v);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final grouped = points2 != null && points2!.length == points.length;
    final barWidth = grouped ? 10.0 : 22.0;
    const groupSpace = 26.0;
    final chartWidth =
        (points.length * (barWidth * (grouped ? 2 : 1) + groupSpace)).clamp(
          240.0,
          double.infinity,
        );

    var maxV = 0.0;
    for (final p in points) {
      if (p.$2 > maxV) maxV = p.$2;
    }
    if (grouped) {
      for (final p in points2!) {
        if (p.$2 > maxV) maxV = p.$2;
      }
    }
    if (maxV <= 0) maxV = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (grouped)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Wrap(
              spacing: 16,
              children: [
                _legendDot(barColor, seriesLabel ?? 'Series 1'),
                _legendDot(bar2Color, series2Label ?? 'Series 2'),
              ],
            ),
          ),
        SizedBox(
          height: height,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: BarChart(
                BarChartData(
                  maxY: maxV * 1.2,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxV / 4,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppColors.line, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= points.length) {
                            return const SizedBox.shrink();
                          }
                          final label = points[i].$1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label.length > 10
                                  ? '${label.substring(0, 9)}…'
                                  : label,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.inkSoft,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppColors.ink,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = points[group.x.toInt()].$1;
                        final series = grouped
                            ? (rodIndex == 0 ? seriesLabel : series2Label)
                            : null;
                        return BarTooltipItem(
                          '$label\n${series != null ? '$series: ' : ''}${_fmt(rod.toY)}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: points[i].$2,
                            color: (barColors != null && i < barColors!.length)
                                ? barColors![i]
                                : barColor,
                            width: barWidth,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          if (grouped)
                            BarChartRodData(
                              toY: points2![i].$2,
                              color: bar2Color,
                              width: barWidth,
                              borderRadius: BorderRadius.circular(4),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// Donut chart with a side legend showing each slice's share of the total —
/// used for category breakdowns (e.g. expenses by category).
class ReportPieChart extends StatefulWidget {
  const ReportPieChart({super.key, required this.points});

  final List<ChartPoint> points;

  @override
  State<ReportPieChart> createState() => _ReportPieChartState();
}

class _ReportPieChartState extends State<ReportPieChart> {
  int? _touchedIndex;

  static const _palette = [
    AppColors.teal,
    AppColors.indigo,
    AppColors.orange,
    AppColors.purple,
    AppColors.pink,
    AppColors.green,
    AppColors.primary,
    AppColors.red,
  ];

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) return const SizedBox.shrink();
    final total = points.fold<double>(0, (s, p) => s + p.$2);
    if (total <= 0) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              pieTouchData: PieTouchData(
                touchCallback: (event, resp) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        resp == null ||
                        resp.touchedSection == null) {
                      _touchedIndex = null;
                      return;
                    }
                    _touchedIndex = resp.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              sections: [
                for (var i = 0; i < points.length; i++)
                  PieChartSectionData(
                    value: points[i].$2,
                    color: _palette[i % _palette.length],
                    radius: _touchedIndex == i ? 30 : 24,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < points.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          points[i].$1,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(points[i].$2 / total * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
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
}
