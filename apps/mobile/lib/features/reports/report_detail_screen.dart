import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import 'report_charts.dart';

/// Groups purchase rows by calendar day (ascending) for the purchases-report
/// trend chart — the `purchases` table has no server-side by-day aggregate,
/// so this happens client-side without touching the query/RPC contract.
List<ChartPoint> purchasesByDay(List rows) {
  final byDay = <String, double>{};
  for (final r in rows) {
    final day = dateStr(r['purchase_date']);
    if (day.isEmpty) continue;
    byDay[day] = (byDay[day] ?? 0) + toDouble(r['total']);
  }
  final days = byDay.keys.toList()
    ..sort((a, b) => DateFormatDay.parse(a).compareTo(DateFormatDay.parse(b)));
  return [for (final d in days) (d, byDay[d]!)];
}

/// Tiny "dd MMM yyyy" parser matching [dateStr]'s output, used only to sort
/// the already-formatted day labels chronologically.
class DateFormatDay {
  static DateTime parse(String s) {
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final parts = s.split(' ');
    if (parts.length != 3) return DateTime(1970);
    final day = int.tryParse(parts[0]) ?? 1;
    final month = months[parts[1]] ?? 1;
    final year = int.tryParse(parts[2]) ?? 1970;
    return DateTime(year, month, day);
  }
}

/// Merges GST output/input rows into one sorted list of rate slabs, so the
/// grouped bar chart can show output vs input tax side by side per rate —
/// the RPC returns each side as an independent list that may not share the
/// same set of rates.
({List<ChartPoint> output, List<ChartPoint> input}) gstByRate(
  List output,
  List input,
) {
  final rates = <double>{};
  final outByRate = <double, double>{};
  final inByRate = <double, double>{};
  for (final r in output) {
    final rate = toDouble(r['gst_rate']);
    rates.add(rate);
    outByRate[rate] = (outByRate[rate] ?? 0) + toDouble(r['tax_amount']);
  }
  for (final r in input) {
    final rate = toDouble(r['gst_rate']);
    rates.add(rate);
    inByRate[rate] = (inByRate[rate] ?? 0) + toDouble(r['tax_amount']);
  }
  final sorted = rates.toList()..sort();
  return (
    output: [for (final r in sorted) ('${qty(r)}%', outByRate[r] ?? 0)],
    input: [for (final r in sorted) ('${qty(r)}%', inByRate[r] ?? 0)],
  );
}

/// Top-N points by value, descending — keeps ranking bar charts readable
/// when the underlying table has far more rows than fit on screen.
List<ChartPoint> topN(List<ChartPoint> points, int n) {
  final sorted = List<ChartPoint>.from(points)
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return sorted.take(n).toList();
}

class ReportQuery {
  const ReportQuery(this.type, this.from, this.to);
  final String type;
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is ReportQuery &&
      other.type == type &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(type, from, to);
}

/// Loads report data. Result shape:
/// { 'summary': [(label, value)], 'table': {'headers': [...], 'rows': [[...]]} }
final reportDataProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ReportQuery>((
  ref,
  q,
) async {
  final client = ref.watch(supabaseProvider);
  final from = ymd(q.from);
  final to = ymd(q.to);

  switch (q.type) {
    case 'sales':
      final d =
          await client.rpc(
                'get_sales_report',
                params: {'p_from': from, 'p_to': to},
              )
              as Map<String, dynamic>;
      return {
        'summary': [
          ('Total sales', money(d['total_sales'] as num?)),
          ('Invoices', '${d['invoice_count']}'),
          ('Collected', money(d['total_paid'] as num?)),
          ('Outstanding', money(d['total_due'] as num?)),
          ('GST collected', money(d['total_tax'] as num?)),
        ],
        'table': {
          'headers': ['Date', 'Invoices', 'Sales'],
          'rows': [
            for (final r in (d['by_day'] as List? ?? []))
              [
                dateStr(r['day']),
                '${r['invoices']}',
                money(r['sales'] as num?),
              ],
          ],
        },
        'chart': <ChartPoint>[
          for (final r in (d['by_day'] as List? ?? []))
            (dateStr(r['day']), toDouble(r['sales'])),
        ],
      };

    case 'products':
      final rows =
          await client.rpc(
                'get_product_sales_report',
                params: {'p_from': from, 'p_to': to},
              )
              as List;
      return {
        'summary': [('Products sold', '${rows.length}')],
        'table': {
          'headers': ['Product', 'Qty', 'Revenue', 'Profit'],
          'rows': [
            for (final r in rows)
              [
                '${r['product_name']}${(r['variant_name'] as String? ?? '').isNotEmpty ? ' (${r['variant_name']})' : ''}',
                qty(r['qty_sold'] as num?),
                money(r['revenue'] as num?),
                money(r['profit'] as num?),
              ],
          ],
        },
        'chart': <ChartPoint>[
          for (final r in rows)
            ('${r['product_name']}', toDouble(r['revenue'])),
        ],
      };

    case 'profit':
      final d =
          await client.rpc(
                'get_profit_report',
                params: {'p_from': from, 'p_to': to},
              )
              as Map<String, dynamic>;
      final netProfit = toDouble(d['net_profit']);
      return {
        'summary': [
          ('Sales', money(d['sales'] as num?)),
          ('Sale returns', '- ${money(d['sale_returns'] as num?)}'),
          ('Cost of goods', '- ${money(d['cogs'] as num?)}'),
          ('Gross profit', money(d['gross_profit'] as num?)),
          ('Expenses', '- ${money(d['expenses'] as num?)}'),
          ('Net profit', money(d['net_profit'] as num?)),
        ],
        'table': null,
        'chart': <ChartPoint>[
          ('Sales', toDouble(d['sales'])),
          ('Returns', toDouble(d['sale_returns'])),
          ('COGS', toDouble(d['cogs'])),
          ('Gross profit', toDouble(d['gross_profit'])),
          ('Expenses', toDouble(d['expenses'])),
          ('Net profit', netProfit),
        ],
        'chartColors': <Color>[
          AppColors.teal,
          AppColors.red,
          AppColors.orange,
          AppColors.green,
          AppColors.red,
          netProfit >= 0 ? AppColors.green : AppColors.red,
        ],
      };

    case 'stock':
      // Variant-aware, matching get_dashboard's stock_value formula:
      // non-variant products at product cost; each variant at its own
      // purchase_price, inheriting the product's when null.
      final rows = await client
          .from('products')
          .select(
            'name, current_stock, purchase_price, selling_price, has_variants, '
            'units(short_name), product_variants(name, current_stock, purchase_price, is_active)',
          )
          .eq('is_active', true)
          .order('name')
          .limit(1000);
      double totalValue = 0;
      final table = <List<String>>[];
      final chart = <ChartPoint>[];
      for (final r in rows) {
        final unit = (r['units'] as Map?)?['short_name'] as String?;
        final variants = [
          for (final v in List<Map<String, dynamic>>.from(
            r['product_variants'] as List? ?? [],
          ))
            if (v['is_active'] == true) v,
        ];
        if (r['has_variants'] == true && variants.isNotEmpty) {
          for (final v in variants) {
            final cost = v['purchase_price'] ?? r['purchase_price'];
            final value = toDouble(v['current_stock']) * toDouble(cost);
            totalValue += value;
            final label = '${r['name']} — ${v['name']}';
            table.add([
              label,
              qtyUnit(v['current_stock'] as num?, unit),
              money(cost as num?),
              money(value),
            ]);
            chart.add((label, value));
          }
        } else {
          final value =
              toDouble(r['current_stock']) * toDouble(r['purchase_price']);
          totalValue += value;
          table.add([
            r['name'] as String,
            qtyUnit(r['current_stock'] as num?, unit),
            money(r['purchase_price'] as num?),
            money(value),
          ]);
          chart.add((r['name'] as String, value));
        }
      }
      return {
        'summary': [
          ('Products', '${rows.length}'),
          ('Total stock value', money(totalValue)),
        ],
        'table': {
          'headers': ['Product', 'Stock', 'Cost', 'Value'],
          'rows': table,
        },
        'chart': chart,
      };

    case 'low_stock':
      // Variant-aware, matching get_dashboard's low_stock_count: for a
      // variant the alert level is its own low_stock_qty, inheriting the
      // product's when null; the parent row of a variant product is
      // skipped (its stock is just the variants' aggregate).
      final rows = await client
          .from('products')
          .select(
            'name, current_stock, low_stock_qty, has_variants, units(short_name), '
            'product_variants(name, current_stock, low_stock_qty, is_active)',
          )
          .eq('is_active', true)
          .order('name')
          .limit(1000);
      // (name, unit, stock, alert)
      final low = <(String, String?, num?, num?)>[];
      for (final r in rows) {
        final unit = (r['units'] as Map?)?['short_name'] as String?;
        final variants = [
          for (final v in List<Map<String, dynamic>>.from(
            r['product_variants'] as List? ?? [],
          ))
            if (v['is_active'] == true) v,
        ];
        if (r['has_variants'] == true && variants.isNotEmpty) {
          for (final v in variants) {
            final alert = v['low_stock_qty'] ?? r['low_stock_qty'];
            if (toDouble(alert) > 0 &&
                toDouble(v['current_stock']) <= toDouble(alert)) {
              low.add((
                '${r['name']} — ${v['name']}',
                unit,
                v['current_stock'] as num?,
                alert as num?,
              ));
            }
          }
        } else if (toDouble(r['low_stock_qty']) > 0 &&
            toDouble(r['current_stock']) <= toDouble(r['low_stock_qty'])) {
          low.add((
            r['name'] as String,
            unit,
            r['current_stock'] as num?,
            r['low_stock_qty'] as num?,
          ));
        }
      }
      return {
        'summary': [('Products low/out', '${low.length}')],
        'table': {
          'headers': ['Product', 'Stock', 'Alert level'],
          'rows': [
            for (final r in low) [r.$1, qtyUnit(r.$3, r.$2), qty(r.$4)],
          ],
        },
        'chart': <ChartPoint>[
          for (final r in low) (r.$1, toDouble(r.$4) - toDouble(r.$3)),
        ],
      };

    case 'customer_due':
      final rows = await client
          .from('customers')
          .select('name, phone, due_amount')
          .gt('due_amount', 0)
          .order('due_amount', ascending: false)
          .limit(1000);
      final total = rows.fold<double>(
        0,
        (s, r) => s + toDouble(r['due_amount']),
      );
      return {
        'summary': [
          ('Customers with due', '${rows.length}'),
          ('Total due', money(total)),
        ],
        'table': {
          'headers': ['Customer', 'Phone', 'Due'],
          'rows': [
            for (final r in rows)
              [
                r['name'] as String,
                r['phone'] as String? ?? '',
                money(r['due_amount'] as num?),
              ],
          ],
        },
        'chart': <ChartPoint>[
          for (final r in rows)
            (r['name'] as String, toDouble(r['due_amount'])),
        ],
      };

    case 'supplier_due':
      final rows = await client
          .from('suppliers')
          .select('name, phone, due_amount')
          .gt('due_amount', 0)
          .order('due_amount', ascending: false)
          .limit(1000);
      final total = rows.fold<double>(
        0,
        (s, r) => s + toDouble(r['due_amount']),
      );
      return {
        'summary': [
          ('Suppliers to pay', '${rows.length}'),
          ('Total payable', money(total)),
        ],
        'table': {
          'headers': ['Supplier', 'Phone', 'Payable'],
          'rows': [
            for (final r in rows)
              [
                r['name'] as String,
                r['phone'] as String? ?? '',
                money(r['due_amount'] as num?),
              ],
          ],
        },
        'chart': <ChartPoint>[
          for (final r in rows)
            (r['name'] as String, toDouble(r['due_amount'])),
        ],
      };

    case 'purchases':
      final rows = await client
          .from('purchases')
          .select(
            'purchase_no, supplier_name, purchase_date, total, paid_amount, payment_status',
          )
          .gte('purchase_date', from)
          .lte('purchase_date', to)
          .order('purchase_date', ascending: false)
          .limit(1000);
      final total = rows.fold<double>(0, (s, r) => s + toDouble(r['total']));
      return {
        'summary': [
          ('Purchases', '${rows.length}'),
          ('Total amount', money(total)),
        ],
        'table': {
          'headers': ['No.', 'Supplier', 'Date', 'Total', 'Status'],
          'rows': [
            for (final r in rows)
              [
                r['purchase_no'] as String,
                r['supplier_name'] as String? ?? '',
                dateStr(r['purchase_date']),
                money(r['total'] as num?),
                r['payment_status'] as String? ?? '',
              ],
          ],
        },
        'chart': purchasesByDay(rows),
      };

    case 'expenses':
      final d =
          await client.rpc(
                'get_expense_report',
                params: {'p_from': from, 'p_to': to},
              )
              as Map<String, dynamic>;
      return {
        'summary': [('Total expenses', money(d['total'] as num?))],
        'table': {
          'headers': ['Category', 'Entries', 'Amount'],
          'rows': [
            for (final r in (d['by_category'] as List? ?? []))
              [
                r['category'] as String,
                '${r['entries']}',
                money(r['amount'] as num?),
              ],
          ],
        },
        'chart': <ChartPoint>[
          for (final r in (d['by_category'] as List? ?? []))
            (r['category'] as String, toDouble(r['amount'])),
        ],
      };

    case 'gst':
      final d =
          await client.rpc(
                'get_gst_report',
                params: {'p_from': from, 'p_to': to},
              )
              as Map<String, dynamic>;
      final output = d['output_tax'] as List? ?? [];
      final input = d['input_tax'] as List? ?? [];
      final outTotal = output.fold<double>(
        0,
        (s, r) => s + toDouble(r['tax_amount']),
      );
      final inTotal = input.fold<double>(
        0,
        (s, r) => s + toDouble(r['tax_amount']),
      );
      final byRate = gstByRate(output, input);
      return {
        'summary': [
          ('Output tax (sales)', money(outTotal)),
          ('Input tax (purchases)', money(inTotal)),
          ('Net GST payable', money(outTotal - inTotal)),
        ],
        'table': {
          'headers': ['Type', 'Rate', 'Taxable value', 'Tax'],
          'rows': [
            for (final r in output)
              [
                'Sales',
                '${qty(r['gst_rate'] as num?)}%',
                money(r['taxable_value'] as num?),
                money(r['tax_amount'] as num?),
              ],
            for (final r in input)
              [
                'Purchase',
                '${qty(r['gst_rate'] as num?)}%',
                money(r['taxable_value'] as num?),
                money(r['tax_amount'] as num?),
              ],
          ],
        },
        'chart': byRate.output,
        'chart2': byRate.input,
      };

    default:
      throw Exception('Unknown report: ${q.type}');
  }
});

class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({super.key, required this.type});

  final String type;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  late DateTime _from;
  late DateTime _to;

  static const _titles = {
    'sales': 'Sales report',
    'products': 'Product-wise sales',
    'profit': 'Profit report',
    'stock': 'Stock report',
    'low_stock': 'Low stock report',
    'customer_due': 'Customer dues',
    'supplier_due': 'Supplier dues',
    'purchases': 'Purchase report',
    'expenses': 'Expense report',
    'gst': 'GST report',
  };

  bool get _hasDateFilter => ![
    'stock',
    'low_stock',
    'customer_due',
    'supplier_due',
  ].contains(widget.type);

  static const _chartTitles = {
    'sales': 'Daily sales',
    'products': 'Top products by revenue',
    'profit': 'Profit breakdown',
    'stock': 'Top stock value',
    'low_stock': 'Most urgent restocks',
    'customer_due': 'Top customer dues',
    'supplier_due': 'Top supplier dues',
    'purchases': 'Daily purchases',
    'expenses': 'Expenses by category',
    'gst': 'Output vs input tax by rate',
  };

  static const _rankedTypes = [
    'products',
    'stock',
    'customer_due',
    'supplier_due',
    'low_stock',
  ];

  /// Builds the report-appropriate chart (trend / ranking / breakdown / pie)
  /// from the numeric 'chart' data the provider computed alongside the
  /// display-formatted summary/table — returns null when there's nothing to
  /// plot so a malformed or missing shape never crashes the screen.
  Widget? _buildChart(Map<String, dynamic> d) {
    final chart = d['chart'];
    if (chart is! List || chart.isEmpty) return null;
    final points = chart.cast<ChartPoint>();
    final title = _chartTitles[widget.type];
    final ranked = _rankedTypes.contains(widget.type);
    final shown = ranked ? topN(points, 8) : points;

    Widget body;
    switch (widget.type) {
      case 'expenses':
        body = ReportPieChart(points: shown);
      case 'gst':
        final chart2 = d['chart2'];
        body = ReportBarChart(
          points: shown,
          points2: chart2 is List ? chart2.cast<ChartPoint>() : null,
          seriesLabel: 'Output tax',
          series2Label: 'Input tax',
        );
      case 'profit':
        final colors = d['chartColors'];
        body = ReportBarChart(
          points: shown,
          barColors: colors is List ? colors.cast<Color>() : null,
        );
      case 'low_stock':
        body = ReportBarChart(
          points: shown,
          isMoney: false,
          barColor: AppColors.red,
        );
      case 'customer_due':
        body = ReportBarChart(points: shown, barColor: AppColors.red);
      case 'supplier_due':
        body = ReportBarChart(points: shown, barColor: AppColors.orange);
      default:
        // sales, purchases (chronological trends), products, stock (rankings)
        body = ReportBarChart(points: shown);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            body,
            if (ranked && points.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing top ${shown.length} of ${points.length} — see full list below.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
  }

  Future<void> _exportPdf(Map<String, dynamic> data) async {
    final business = ref.read(appContextProvider).value?.business ?? {};
    final doc = pw.Document();
    final title = _titles[widget.type] ?? 'Report';
    final table = data['table'] as Map<String, dynamic>?;
    final summary = data['summary'] as List;

    doc.addPage(
      pw.MultiPage(
        build: (ctx) => [
          pw.Text(
            business['name'] as String? ?? '',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
          if (_hasDateFilter)
            pw.Text(
              '${dateStr(_from)} to ${dateStr(_to)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final s in summary)
                pw.Text(
                  '${(s as (String, String)).$1}: ${_pdfSafe(s.$2)}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          if (table != null)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headers: table['headers'] as List,
              data: [
                for (final row in table['rows'] as List)
                  [for (final cell in row as List) _pdfSafe('$cell')],
              ],
            ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: '${widget.type}_report_${ymd(DateTime.now())}.pdf',
    );
  }

  /// Default PDF fonts have no ₹ glyph — swap it for Rs.
  String _pdfSafe(String s) => s.replaceAll('₹', 'Rs. ');

  @override
  Widget build(BuildContext context) {
    final query = ReportQuery(widget.type, _from, _to);
    final data = ref.watch(reportDataProvider(query));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(_titles[widget.type] ?? 'Report'),
        actions: [
          if (data.hasValue)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: () => _exportPdf(data.value!),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_hasDateFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text('${dateStr(_from)} → ${dateStr(_to)}'),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: DateTimeRange(
                            start: _from,
                            end: _to,
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            _from = picked.start;
                            _to = picked.end;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.bolt),
                    tooltip: 'Quick ranges',
                    onSelected: (v) {
                      final now = DateTime.now();
                      setState(() {
                        switch (v) {
                          case 'today':
                            _from = DateTime(now.year, now.month, now.day);
                            _to = now;
                          case 'week':
                            _from = now.subtract(
                              Duration(days: now.weekday - 1),
                            );
                            _to = now;
                          case 'month':
                            _from = DateTime(now.year, now.month, 1);
                            _to = now;
                          case 'last_month':
                            _from = DateTime(now.year, now.month - 1, 1);
                            _to = DateTime(now.year, now.month, 0);
                        }
                      });
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'today', child: Text('Today')),
                      PopupMenuItem(value: 'week', child: Text('This week')),
                      PopupMenuItem(value: 'month', child: Text('This month')),
                      PopupMenuItem(
                        value: 'last_month',
                        child: Text('Last month'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: AsyncView(
              value: data,
              onRetry: () => ref.invalidate(reportDataProvider(query)),
              builder: (d) {
                final summary = d['summary'] as List;
                final table = d['table'] as Map<String, dynamic>?;
                final rows = table?['rows'] as List? ?? [];
                final chartCard = _buildChart(d);
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                for (final s in summary)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (s as (String, String)).$1,
                                          ),
                                        ),
                                        Text(
                                          s.$2,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (chartCard != null) ...[
                          const SizedBox(height: 12),
                          chartCard,
                        ],
                        if (table != null) ...[
                          const SizedBox(height: 12),
                          if (rows.isEmpty)
                            const EmptyState(
                              icon: Icons.table_chart_outlined,
                              message: 'No data for this period',
                            )
                          else
                            Card(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingTextStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  dataTextStyle: const TextStyle(fontSize: 12),
                                  columns: [
                                    for (final h in table['headers'] as List)
                                      DataColumn(label: Text('$h')),
                                  ],
                                  rows: [
                                    for (final row in rows)
                                      DataRow(
                                        cells: [
                                          for (final cell in row as List)
                                            DataCell(Text('$cell')),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
