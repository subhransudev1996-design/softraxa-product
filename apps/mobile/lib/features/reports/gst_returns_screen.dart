import '../../core/i18n.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'gst_export.dart';
import 'gst_filing.dart';
import 'gst_rates_screen.dart';

/// A text file the shop picks (a GSTR-2B JSON), as its name and text.
Future<({String name, String text})?> pickTextFile(
  List<String> extensions,
) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  var bytes = file.bytes;
  if (bytes == null && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null) return null;
  return (name: file.name, text: utf8.decode(bytes, allowMalformed: true));
}

/// A return period: a month, or a quarter (April–June, …).
typedef GstPeriod = ({DateTime from, DateTime to});

GstPeriod monthPeriod(DateTime month) => (
  from: DateTime(month.year, month.month, 1),
  to: DateTime(month.year, month.month + 1, 0),
);

GstPeriod quarterPeriod(DateTime anyDay) {
  final start = ((anyDay.month - 1) ~/ 3) * 3 + 1;
  return (
    from: DateTime(anyDay.year, start, 1),
    to: DateTime(anyDay.year, start + 3, 0),
  );
}

/// GSTR-1, GSTR-3B and the purchase register for a period (D40).
final gstReturnDataProvider = FutureProvider.autoDispose
    .family<GstReturnData, GstPeriod>((ref, period) async {
      final client = ref.watch(supabaseProvider);
      final params = {'p_from': ymd(period.from), 'p_to': ymd(period.to)};
      final results = await Future.wait([
        client.rpc('get_gstr1', params: params),
        client.rpc('get_gstr3b', params: params),
        client.rpc('get_purchase_register', params: params),
      ]);
      return GstReturnData(
        gstr1: Map<String, dynamic>.from(results[0] as Map),
        gstr3b: Map<String, dynamic>.from(results[1] as Map),
        purchaseRegister: List<Map<String, dynamic>>.from(
          results[2] as List? ?? const [],
        ),
      );
    });

/// A composition shop's figures for a period (migration 0079).
final compositionReturnProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, GstPeriod>((ref, period) async {
      final res = await ref
          .watch(supabaseProvider)
          .rpc(
            'get_composition_return',
            params: {'p_from': ymd(period.from), 'p_to': ymd(period.to)},
          );
      return Map<String, dynamic>.from(res as Map);
    });

const _frequencyKey = 'gst_return_quarterly';

class GstReturnsScreen extends ConsumerStatefulWidget {
  const GstReturnsScreen({super.key});

  @override
  ConsumerState<GstReturnsScreen> createState() => _GstReturnsScreenState();
}

class _GstReturnsScreenState extends ConsumerState<GstReturnsScreen> {
  // Returns are filed for the period just ended.
  late DateTime _anchor = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1, 1);
  }();
  bool _quarterly = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFrequency();
  }

  Future<void> _loadFrequency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getBool(_frequencyKey) ?? false;
      if (q != _quarterly && mounted) setState(() => _setQuarterly(q));
    } catch (_) {}
  }

  void _setQuarterly(bool q) {
    _quarterly = q;
    if (q) {
      // The quarter just ended.
      final now = DateTime.now();
      final thisQuarter = quarterPeriod(now).from;
      _anchor = DateTime(thisQuarter.year, thisQuarter.month - 3, 1);
    }
  }

  Future<void> _saveFrequency(bool q) async {
    setState(() => _setQuarterly(q));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_frequencyKey, q);
    } catch (_) {}
  }

  bool get _composition =>
      ref.read(appContextProvider).value?.business?['tax_preference'] ==
      'composition';

  GstPeriod get _period => _quarterly || _composition
      ? quarterPeriod(_anchor)
      : monthPeriod(_anchor);

  bool get _isRunning =>
      !DateTime.now().isAfter(_period.to.add(const Duration(days: 1)));

  void _shift(int by) {
    final step = _quarterly || _composition ? 3 : 1;
    setState(
      () => _anchor = DateTime(_anchor.year, _anchor.month + by * step, 1),
    );
  }

  String _periodLabel(GstPeriod p) {
    if (p.from.month == p.to.month) {
      return DateFormat('MMMM yyyy').format(p.from);
    }
    return '${DateFormat('MMM').format(p.from)} – ${DateFormat('MMM yyyy').format(p.to)}';
  }

  Map<String, dynamic> get _business =>
      ref.read(appContextProvider).value?.business ?? const {};

  String get _gstin =>
      (_business['gst_number'] as String? ?? '').trim().toUpperCase();

  Future<void> _save(Uint8List bytes, String name, String subject) async {
    final message = await saveOrShareFile(bytes, name, subject: subject);
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadJson(GstReturnData data) => _run(() async {
    if (!isValidGstin(_gstin)) {
      throw t(
        'Add your shop\'s GSTIN in business settings first — the file is made for it.',
      );
    }
    final fp = gstPeriod(_period.to);
    final json = buildGstr1Json(data, gstin: _gstin, fp: fp);
    await _save(
      Uint8List.fromList(utf8.encode(gstr1JsonText(json))),
      'GSTR1_${_gstin}_$fp.json',
      'GSTR-1 ${_periodLabel(_period)}',
    );
  });

  /// IFF: a quarterly filer's B2B invoices of one of the first two months.
  Future<void> _downloadIff(DateTime month) => _run(() async {
    if (!isValidGstin(_gstin)) {
      throw t(
        'Add your shop\'s GSTIN in business settings first — the file is made for it.',
      );
    }
    final data = await ref.read(
      gstReturnDataProvider(monthPeriod(month)).future,
    );
    final fp = gstPeriod(month);
    final json = buildGstr1Json(data, gstin: _gstin, fp: fp, iffOnly: true);
    await _save(
      Uint8List.fromList(utf8.encode(gstr1JsonText(json))),
      'IFF_${_gstin}_$fp.json',
      'IFF ${DateFormat('MMMM yyyy').format(month)}',
    );
  });

  Future<void> _downloadExcel(GstReturnData data) => _run(() async {
    final bytes = buildGstWorkbook(
      data: data,
      businessName: _business['name'] as String? ?? '',
      gstin: _gstin,
      from: _period.from,
      to: _period.to,
    );
    await _save(
      bytes,
      'GST_${_gstin.isEmpty ? 'returns' : _gstin}_${gstPeriod(_period.to)}.xlsx',
      'GST returns ${_periodLabel(_period)}',
    );
  });

  @override
  Widget build(BuildContext context) {
    final composition =
        ref.watch(appContextProvider).value?.business?['tax_preference'] ==
        'composition';
    final period = _period;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('GST returns')),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: t('How to file on the GST portal'),
            onPressed: () => _showHowToFile(context, composition: composition),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    if (!composition)
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(t('Monthly')),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(t('Quarterly (QRMP)')),
                          ),
                        ],
                        selected: {_quarterly},
                        onSelectionChanged: (s) => _saveFrequency(s.first),
                      ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: t('Previous'),
                          onPressed: () => _shift(-1),
                        ),
                        Expanded(
                          child: Text(
                            _periodLabel(period),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: t('Next'),
                          onPressed: _isRunning ? null : () => _shift(1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: composition
                    ? _CompositionView(period: period, running: _isRunning)
                    : _regular(period),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _regular(GstPeriod period) {
    final data = ref.watch(gstReturnDataProvider(period));
    return AsyncView(
      value: data,
      onRetry: () => ref.invalidate(gstReturnDataProvider(period)),
      builder: (d) {
        final checks = _checks(d);
        final blocking = checks
            .where((c) => c.severity == _Severity.error)
            .length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isRunning)
              _Notice(
                icon: Icons.info_outline,
                color: AppColors.indigo,
                text: t(
                  'This period is still running — figures will change until it ends.',
                ),
              ),
            const GstRatesBanner(),
            SectionLabel(t('Before you file')),
            _ChecksCard(checks: checks),
            SectionLabel(t('GSTR-1 — sales')),
            _Gstr1Card(data: d),
            SectionLabel(t('GSTR-3B — tax to pay')),
            _Gstr3bCard(data: d),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(t('GSTR-1 file for the GST portal')),
              onPressed: _busy ? null : () => _downloadJson(d),
            ),
            const SizedBox(height: 6),
            Text(
              blocking == 1
                  ? t(
                      'Fix the problem marked red first — the portal would reject it.',
                    )
                  : blocking > 1
                  ? t(
                      'Fix the {v1} problems marked red first — the portal would reject those lines.',
                      {'v1': blocking},
                    )
                  : t(
                      'Upload it on gst.gov.in: Returns Dashboard → GSTR-1 → Prepare Offline → Upload. Then file with OTP (EVC).',
                    ),
              style: TextStyle(
                fontSize: 13,
                color: blocking > 0 ? AppColors.red : AppColors.inkSoft,
              ),
            ),
            if (_quarterly) ...[
              const SizedBox(height: 12),
              Text(
                t(
                  'IFF — B2B invoices of the first two months, so your buyers get their credit early (optional):',
                ),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in [0, 1])
                    OutlinedButton.icon(
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text(
                        t('IFF {v1}', {
                          'v1': DateFormat('MMM yyyy').format(
                            DateTime(
                              period.from.year,
                              period.from.month + m,
                              1,
                            ),
                          ),
                        }),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _downloadIff(
                              DateTime(
                                period.from.year,
                                period.from.month + m,
                                1,
                              ),
                            ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(t('Match purchases with GSTR-2B')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GstItcMatchScreen(period: period),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: Text(t('Excel for your accountant')),
              onPressed: _busy ? null : () => _downloadExcel(d),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'E-invoice (IRN) is needed only above ₹5 crore turnover and is not supported yet.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  List<_Check> _checks(GstReturnData d) {
    final w = d.warnings;
    int n(String key) => (w[key] as num?)?.toInt() ?? 0;
    final digits = (d.gstr1['hsn_digits'] as num?)?.toInt() ?? 4;
    final out = <_Check>[];
    if (!isValidGstin(_gstin)) {
      out.add(
        _Check(
          _Severity.error,
          t('Your shop\'s GSTIN is missing or not valid'),
          t('Add it in business settings — returns are filed against it.'),
          action: () => context.push('/settings/business'),
        ),
      );
    }
    if (n('lines_without_hsn') > 0) {
      out.add(
        _Check(
          _Severity.error,
          t('{v1} bill lines have no HSN code', {'v1': n('lines_without_hsn')}),
          digits == 6
              ? t(
                  'Above ₹5 crore every line needs a 6-digit HSN. Add HSN codes to those products.',
                )
              : t(
                  'Bills to GST-registered buyers need an HSN code (4 digits or more). Add HSN codes to those products.',
                ),
          action: () => context.push('/products'),
        ),
      );
    }
    if (n('short_hsn_codes') > 0) {
      out.add(
        _Check(
          _Severity.error,
          t('{v1} bill lines have an HSN code shorter than {v2} digits', {
            'v1': n('short_hsn_codes'),
            'v2': digits,
          }),
          t('Correct the HSN codes of those products.'),
          action: () => context.push('/products'),
        ),
      );
    }
    if (n('untaxed_bills') > 0) {
      out.add(
        _Check(
          _Severity.error,
          t('{v1} bills sold GST items without GST', {
            'v1': n('untaxed_bills'),
          }),
          t(
            'Bills of supply or cash memos with taxable products worth {v1}. A GST-registered shop must give a tax invoice for these — ask your accountant how to correct them.',
            {'v1': money(toDouble(w['untaxed_value']))},
          ),
        ),
      );
    }
    if (n('b2cs_negative') > 0) {
      out.add(
        _Check(
          _Severity.warning,
          t('Returns are more than sales at {v1} rate(s)', {
            'v1': n('b2cs_negative'),
          }),
          t(
            'The portal may not accept a negative B2C total. Check the returns in this period.',
          ),
        ),
      );
    }
    if (n('invoices_without_state') > 0) {
      out.add(
        _Check(
          _Severity.warning,
          t('{v1} bills have no place of supply', {
            'v1': n('invoices_without_state'),
          }),
          t('Set your shop\'s state in business settings.'),
          action: () => context.push('/settings/business'),
        ),
      );
    }
    if (n('invalid_customer_gstins') > 0) {
      out.add(
        _Check(
          _Severity.warning,
          t('{v1} bills have a customer GSTIN that is not valid', {
            'v1': n('invalid_customer_gstins'),
          }),
          t(
            'They are reported as B2C, so the buyer gets no credit. Correct the customer\'s GSTIN.',
          ),
          action: () => context.push('/customers'),
        ),
      );
    }
    if (n('hsn_negative_quantity') > 0) {
      out.add(
        _Check(
          _Severity.info,
          t('{v1} HSN rows had more returned than sold', {
            'v1': n('hsn_negative_quantity'),
          }),
          t('Their quantity is reported as 0, as the portal requires.'),
        ),
      );
    }
    final noCode = hsnRowsWithoutCode(d);
    if (noCode > 0 && n('lines_without_hsn') == 0) {
      out.add(
        _Check(
          _Severity.info,
          t('{v1} HSN summary rows have no HSN code', {'v1': noCode}),
          t(
            'Sales to consumers without HSN are left out of the HSN summary. Adding HSN codes to your products keeps it complete.',
          ),
          action: () => context.push('/products'),
        ),
      );
    }
    return out;
  }

  void _showHowToFile(BuildContext context, {required bool composition}) {
    final steps = composition
        ? [
            t('Check the CMP-08 figures here for the quarter.'),
            t(
              'On gst.gov.in: Services → Returns → CMP-08 → choose the year and quarter.',
            ),
            t(
              'Enter the outward turnover and the tax shown here, pay any cash due, and file with OTP (EVC).',
            ),
            t(
              'Due by the 18th of the month after the quarter. GSTR-4 (the year) is due by 30 April.',
            ),
          ]
        : [
            t('Download the GSTR-1 file here (fix the red problems first).'),
            t(
              'On gst.gov.in: Services → Returns → Returns Dashboard → choose the year and period → Search.',
            ),
            t(
              'GSTR-1 tile → Prepare Offline → Upload → choose the file. Wait until it shows "Processed".',
            ),
            t(
              'Prepare Online → check the summary → Generate GSTR-1 Summary → File with OTP (EVC).',
            ),
            t(
              'GSTR-3B fills itself from GSTR-1. Compare it with the GSTR-3B figures here, check your credit against GSTR-2B, pay the cash due and file.',
            ),
            t(
              'Monthly: GSTR-1 by the 11th, GSTR-3B by the 20th. Quarterly: GSTR-1 by the 13th, GSTR-3B by the 22nd or 24th after the quarter.',
            ),
          ];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('How to file on the GST portal'),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(steps[i])),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                t(
                  'Dukania prepares the figures from your bills; the return is yours to check and file.',
                ),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

enum _Severity { error, warning, info }

class _Check {
  const _Check(this.severity, this.title, this.detail, {this.action});

  final _Severity severity;
  final String title, detail;
  final VoidCallback? action;
}

class _ChecksCard extends StatelessWidget {
  const _ChecksCard({required this.checks});

  final List<_Check> checks;

  @override
  Widget build(BuildContext context) {
    if (checks.isEmpty) {
      return _Notice(
        icon: Icons.check_circle_outline,
        color: AppColors.green,
        text: t('Everything the portal checks looks right for this period.'),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < checks.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: Icon(
                switch (checks[i].severity) {
                  _Severity.error => Icons.error_outline,
                  _Severity.warning => Icons.warning_amber_rounded,
                  _Severity.info => Icons.info_outline,
                },
                color: switch (checks[i].severity) {
                  _Severity.error => AppColors.red,
                  _Severity.warning => AppColors.orange,
                  _Severity.info => AppColors.indigo,
                },
              ),
              title: Text(
                checks[i].title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(checks[i].detail),
              trailing: checks[i].action == null
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: checks[i].action,
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

Widget _row(String label, String value, {bool bold = false, Color? color}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );

Widget _heads(String label, TaxHeads h, {bool bold = false, Color? color}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        _row('  IGST', money(h.igst), bold: bold, color: color),
        _row('  CGST', money(h.cgst), bold: bold, color: color),
        _row('  SGST', money(h.sgst), bold: bold, color: color),
      ],
    );

class _Gstr3bCard extends StatelessWidget {
  const _Gstr3bCard({required this.data});

  final GstReturnData data;

  @override
  Widget build(BuildContext context) {
    final out = data.outward;
    final itc = data.itc;
    final g3 = data.gstr3b;
    double v(String key) => toDouble((g3[key] as Map?)?['taxable_value']);
    final liability = TaxHeads(
      toDouble(out['igst_amount']),
      toDouble(out['cgst_amount']),
      toDouble(out['sgst_amount']),
    );
    final credit = TaxHeads(
      toDouble(itc['igst_amount']),
      toDouble(itc['cgst_amount']),
      toDouble(itc['sgst_amount']),
    );
    final rc = data.reverseCharge;
    final reverse = TaxHeads(
      toDouble(rc['igst_amount']),
      toDouble(rc['cgst_amount']),
      toDouble(rc['sgst_amount']),
    );
    final hasReverse = reverse.total > 0.005;
    final r = gstr3bSetOff(
      sales: liability,
      credit: credit,
      reverseCharge: reverse,
    );
    final inward = Map<String, dynamic>.from(
      g3['inward_nil_exempt'] as Map? ?? const {},
    );
    final interUnreg = List<Map<String, dynamic>>.from(
      g3['inter_state_unregistered'] as List? ?? const [],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              t('3.1(a) Taxable sales'),
              money(toDouble(out['taxable_value'])),
            ),
            _row(
              t('3.1(c) Nil-rated & exempt sales'),
              money(v('outward_nil_exempt')),
            ),
            if (hasReverse)
              _row(
                t('3.1(d) Expenses under reverse charge'),
                money(toDouble(rc['taxable_value'])),
              ),
            _row(t('3.1(e) Non-GST sales'), money(v('outward_non_gst'))),
            if (interUnreg.isNotEmpty)
              _row(
                t('3.2 Inter-state sales to consumers'),
                money(
                  interUnreg.fold<double>(
                    0,
                    (s, e) => s + toDouble(e['taxable_value']),
                  ),
                ),
              ),
            _row(
              t('5 Purchases with no GST (nil / exempt)'),
              money(toDouble(inward['inter']) + toDouble(inward['intra'])),
            ),
            const Divider(height: 20),
            _heads(t('Tax on sales'), liability),
            const SizedBox(height: 8),
            if (hasReverse) ...[
              _heads(t('3.1(d) Reverse charge tax — paid in cash'), reverse),
              const SizedBox(height: 8),
            ],
            _heads(t('4(A)(5) Input tax credit from purchases'), credit),
            if (hasReverse) ...[
              const SizedBox(height: 8),
              _heads(t('4(A)(3) Credit of the reverse charge tax'), reverse),
            ],
            const Divider(height: 20),
            _heads(t('Credit used'), r.used),
            const SizedBox(height: 8),
            _heads(
              t('Cash to pay'),
              r.cash,
              bold: true,
              color: AppColors.purple,
            ),
            _row(
              t('Total cash to pay'),
              money(r.cash.total),
              bold: true,
              color: AppColors.purple,
            ),
            if (r.carryForward.total > 0.005) ...[
              const SizedBox(height: 8),
              _heads(t('Credit carried to next period'), r.carryForward),
            ],
            const SizedBox(height: 8),
            Text(
              t(
                'Credit is used in the order the law sets (IGST first). Claim only the credit shown in your GSTR-2B — match it with the button below.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
            if (hasReverse) ...[
              const SizedBox(height: 6),
              Text(
                t(
                  'Reverse charge tax is paid in cash, not from credit — it is in the cash to pay. Once paid, it counts as credit in the same return.',
                ),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Gstr1Card extends StatelessWidget {
  const _Gstr1Card({required this.data});

  final GstReturnData data;

  @override
  Widget build(BuildContext context) {
    double taxable(String key) =>
        data.section(key).fold(0.0, (s, r) => s + toDouble(r['taxable_value']));
    final nil = data
        .section('nil')
        .fold<double>(
          0,
          (s, r) =>
              s +
              toDouble(r['nil_amount']) +
              toDouble(r['exempt_amount']) +
              toDouble(r['non_gst_amount']),
        );
    final docs = data.section('docs');
    final invoices = docs
        .where((r) => toDouble(r['doc_num']) == 1)
        .fold<double>(0, (s, r) => s + toDouble(r['total']));
    final rows = [
      (
        t('B2B — registered buyers'),
        t('{v1} invoices', {'v1': data.documentCount('b2b')}),
        taxable('b2b'),
      ),
      (
        t('B2C large — inter-state above ₹1 lakh'),
        t('{v1} invoices', {'v1': data.documentCount('b2cl')}),
        taxable('b2cl'),
      ),
      (
        t('B2C small — net of their credit notes'),
        t('{v1} rows', {'v1': data.section('b2cs').length}),
        taxable('b2cs'),
      ),
      (
        t('Credit notes — registered'),
        t('{v1} notes', {'v1': data.documentCount('cdnr')}),
        taxable('cdnr'),
      ),
      (
        t('Credit notes — unregistered'),
        t('{v1} notes', {'v1': data.documentCount('cdnur')}),
        taxable('cdnur'),
      ),
      (t('Nil-rated, exempt & non-GST (Table 8)'), '', nil),
      (
        t('HSN summary (Table 12)'),
        t('{v1} B2B rows, {v2} B2C rows', {
          'v1': data.hsn('B2B').length,
          'v2': data.hsn('B2C').length,
        }),
        null,
      ),
      (
        t('Documents issued (Table 13)'),
        t('{v1} bills', {'v1': invoices.round()}),
        null,
      ),
    ];
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(
                rows[i].$1,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: rows[i].$2.isEmpty ? null : Text(rows[i].$2),
              trailing: rows[i].$3 == null
                  ? null
                  : Text(
                      money(rows[i].$3),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

class _CompositionView extends ConsumerWidget {
  const _CompositionView({required this.period, required this.running});

  final GstPeriod period;
  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quarter = ref.watch(compositionReturnProvider(period));
    // The financial year (April–March) the quarter is in.
    final fyStart = period.from.month >= 4
        ? DateTime(period.from.year, 4, 1)
        : DateTime(period.from.year - 1, 4, 1);
    final year = (from: fyStart, to: DateTime(fyStart.year + 1, 3, 31));
    final annual = ref.watch(compositionReturnProvider(year));
    final due = DateTime(period.to.year, period.to.month + 1, 18);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (running)
          _Notice(
            icon: Icons.info_outline,
            color: AppColors.indigo,
            text: t(
              'This period is still running — figures will change until it ends.',
            ),
          ),
        SectionLabel(t('CMP-08 — this quarter')),
        AsyncView(
          value: quarter,
          onRetry: () => ref.invalidate(compositionReturnProvider(period)),
          builder: (q) => _CompositionCard(
            data: q,
            footer: t('File by {v1}.', {'v1': dateStr(due)}),
          ),
        ),
        SectionLabel(
          t('GSTR-4 — year {v1}', {
            'v1': '${fyStart.year}-${(fyStart.year + 1) % 100}',
          }),
        ),
        AsyncView(
          value: annual,
          onRetry: () => ref.invalidate(compositionReturnProvider(year)),
          builder: (a) => _CompositionCard(
            data: a,
            annual: true,
            footer: t('File by 30 April {v1}.', {'v1': fyStart.year + 1}),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'Composition tax is on your turnover at your scheme rate (set in business settings); you collect no GST and claim no credit.',
          ),
          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.settings_outlined),
          label: Text(t('Composition rate')),
          onPressed: () => context.push('/settings/business'),
        ),
      ],
    );
  }
}

class _CompositionCard extends StatelessWidget {
  const _CompositionCard({
    required this.data,
    required this.footer,
    this.annual = false,
  });

  final Map<String, dynamic> data;
  final String footer;
  final bool annual;

  @override
  Widget build(BuildContext context) {
    final inReg = Map<String, dynamic>.from(
      data['inward_registered'] as Map? ?? const {},
    );
    final inUnreg = Map<String, dynamic>.from(
      data['inward_unregistered'] as Map? ?? const {},
    );
    final rc = data['reverse_charge'] as Map? ?? const {};
    final rcTax =
        toDouble(rc['igst_amount']) +
        toDouble(rc['cgst_amount']) +
        toDouble(rc['sgst_amount']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(t('Sales (turnover)'), money(toDouble(data['turnover']))),
            _row(
              t('Of which nil-rated / exempt'),
              money(toDouble(data['exempt_turnover'])),
            ),
            _row(
              t('Taxable turnover'),
              money(toDouble(data['taxable_turnover'])),
            ),
            _row(t('Composition rate'), '${qty(toDouble(data['rate']))}%'),
            const Divider(height: 20),
            _row(t('CGST to pay'), money(toDouble(data['cgst'])), bold: true),
            _row(t('SGST to pay'), money(toDouble(data['sgst'])), bold: true),
            _row(
              t('Total tax'),
              money(toDouble(data['tax'])),
              bold: rcTax <= 0.005,
              color: rcTax <= 0.005 ? AppColors.purple : null,
            ),
            if (rcTax > 0.005) ...[
              _row(
                t('Reverse charge tax on expenses'),
                money(rcTax),
              ),
              _row(
                t('Total to pay'),
                money(toDouble(data['tax']) + rcTax),
                bold: true,
                color: AppColors.purple,
              ),
            ],
            if (annual) ...[
              const Divider(height: 20),
              _row(
                t('Purchases from registered suppliers'),
                money(toDouble(inReg['taxable_value'])),
              ),
              _row(
                t('Purchases from unregistered suppliers'),
                money(toDouble(inUnreg['taxable_value'])),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              footer,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GSTR-2B match
// ---------------------------------------------------------------------------

/// Matches the GSTR-2B downloaded from the portal with the purchases
/// entered: which credit is safe to claim, which bills the supplier hasn't
/// uploaded, which purchases are missing from the books.
class GstItcMatchScreen extends ConsumerStatefulWidget {
  const GstItcMatchScreen({super.key, required this.period});

  final GstPeriod period;

  @override
  ConsumerState<GstItcMatchScreen> createState() => _GstItcMatchScreenState();
}

class _GstItcMatchScreenState extends ConsumerState<GstItcMatchScreen> {
  List<ItcRow>? _rows;
  String _fileName = '';
  bool _loading = false;
  String? _error;

  Future<void> _pick() async {
    final picked = await pickTextFile(const ['json']);
    if (picked == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _fileName = picked.name;
    });
    try {
      final parsed = parseGstr2b(picked.text);
      // The 2B's own month when it names one, else the screen's period.
      var period = widget.period;
      final m = RegExp(r'^(\d{2})(\d{4})$').firstMatch(parsed.period);
      if (m != null) {
        period = monthPeriod(DateTime(int.parse(m[2]!), int.parse(m[1]!), 1));
      }
      final register = List<Map<String, dynamic>>.from(
        await ref
                    .read(supabaseProvider)
                    .rpc(
                      'get_purchase_register',
                      params: {
                        'p_from': ymd(period.from),
                        'p_to': ymd(period.to),
                      },
                    )
                as List? ??
            const [],
      );
      setState(() {
        _rows = matchGstr2b(parsed.docs, register);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e is Gstr2bFormatError ? e.message : friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(t('Match with GSTR-2B'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t(
                  'On gst.gov.in: Returns Dashboard → GSTR-2B → View → Download → Generate JSON. Pick that file here.',
                ),
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.file_open_outlined),
                label: Text(
                  _fileName.isEmpty ? t('Choose GSTR-2B JSON file') : _fileName,
                ),
                onPressed: _loading ? null : _pick,
              ),
              const SizedBox(height: 12),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_error != null)
                _Notice(
                  icon: Icons.error_outline,
                  color: AppColors.red,
                  text: _error!,
                ),
              if (rows != null) ..._results(rows),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _results(List<ItcRow> rows) {
    double sum(ItcMatch s, {bool portal = true}) => rows
        .where((r) => r.status == s)
        .fold(0.0, (a, r) => a + (portal ? r.portalTax : r.booksTax));
    final groups = [
      (
        ItcMatch.matched,
        t('Matched — credit safe to claim'),
        AppColors.green,
        sum(ItcMatch.matched),
      ),
      (
        ItcMatch.differs,
        t('Tax differs — claim what GSTR-2B shows'),
        AppColors.orange,
        sum(ItcMatch.differs),
      ),
      (
        ItcMatch.missingIn2b,
        t('Not uploaded by the supplier — no credit yet'),
        AppColors.red,
        sum(ItcMatch.missingIn2b, portal: false),
      ),
      (
        ItcMatch.missingInBooks,
        t('In GSTR-2B but not entered as a purchase'),
        AppColors.indigo,
        sum(ItcMatch.missingInBooks),
      ),
      (
        ItcMatch.blocked,
        t('Credit not available on the portal'),
        AppColors.inkSoft,
        sum(ItcMatch.blocked),
      ),
    ];
    return [
      for (final g in groups)
        if (rows.any((r) => r.status == g.$1)) ...[
          SectionLabel('${g.$2} · ${money(g.$4)}'),
          Card(
            child: Column(
              children: [
                for (final r in rows.where((r) => r.status == g.$1)) ...[
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.circle, size: 10, color: g.$3),
                    title: Text(
                      '${r.billNo} · ${r.supplierName.isEmpty ? r.supplierGstin : r.supplierName}',
                    ),
                    subtitle: Text(
                      [
                        if (r.date != null) dateStr(r.date),
                        t('Books {v1}', {'v1': money(r.booksTax)}),
                        t('GSTR-2B {v1}', {'v1': money(r.portalTax)}),
                      ].join(' · '),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      if (rows.isEmpty)
        _Notice(
          icon: Icons.info_outline,
          color: AppColors.indigo,
          text: t('No invoices from registered suppliers in this period.'),
        ),
    ];
  }
}
