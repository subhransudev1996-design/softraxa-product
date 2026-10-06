import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'gst_export.dart';

/// GSTR-1, GSTR-3B and purchase register for one month (D40), with an
/// Excel download for the shop's accountant.
final gstReturnDataProvider = FutureProvider.autoDispose
    .family<GstReturnData, DateTime>((ref, month) async {
      final client = ref.watch(supabaseProvider);
      final params = {
        'p_from': ymd(month),
        'p_to': ymd(DateTime(month.year, month.month + 1, 0)),
      };
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

class GstReturnsScreen extends ConsumerStatefulWidget {
  const GstReturnsScreen({super.key});

  @override
  ConsumerState<GstReturnsScreen> createState() => _GstReturnsScreenState();
}

class _GstReturnsScreenState extends ConsumerState<GstReturnsScreen> {
  // Returns are filed for the month just ended.
  late DateTime _month = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1, 1);
  }();
  bool _exporting = false;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shiftMonth(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by, 1));

  Future<void> _download(GstReturnData data) async {
    final business = ref.read(appContextProvider).value?.business ?? {};
    final gstin = business['gst_number'] as String? ?? '';
    final period = DateFormat('MMyyyy').format(_month);
    setState(() => _exporting = true);
    try {
      final bytes = buildGstWorkbook(
        data: data,
        businessName: business['name'] as String? ?? '',
        gstin: gstin,
        from: _month,
        to: DateTime(_month.year, _month.month + 1, 0),
      );
      final message = await saveOrShareFile(
        bytes,
        'GST_${gstin.isEmpty ? 'returns' : gstin}_$period.xlsx',
        subject: 'GST returns ${DateFormat('MMMM yyyy').format(_month)}',
      );
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(gstReturnDataProvider(_month));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('GST returns')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: t('Previous month'),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: t('Next month'),
                  onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: data,
              onRetry: () => ref.invalidate(gstReturnDataProvider(_month)),
              builder: (d) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_isCurrentMonth)
                        _Notice(
                          icon: Icons.info_outline,
                          color: AppColors.indigo,
                          text: t('This month is still running — figures will change until it ends.'),
                        ),
                      if (d.warningCount > 0) _WarningsCard(data: d),
                      SectionLabel(t('GSTR-3B summary')),
                      _Gstr3bCard(data: d),
                      SectionLabel(t('GSTR-1 sections')),
                      _Gstr1Card(data: d),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(t('Download Excel for your accountant')),
                        onPressed: _exporting ? null : () => _download(d),
                      ),
                      const SizedBox(height: 8),
                      Text(t('One workbook with GSTR-1 (B2B, B2CL, B2CS, credit notes, HSN summary, documents), GSTR-3B and the purchase register. Your accountant should review it before filing. E-invoice (IRN) and e-way bills are not supported yet.'),
                        style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
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

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.data});

  final GstReturnData data;

  @override
  Widget build(BuildContext context) {
    final w = data.warnings;
    int count(String key) => (w[key] as num?)?.toInt() ?? 0;
    return _Notice(
      icon: Icons.warning_amber_rounded,
      color: AppColors.orange,
      text: [
        if (count('lines_without_hsn') > 0)
          '${count('lines_without_hsn')} taxed bill lines have no HSN code — '
              'add HSN codes to those products.',
        if (count('invalid_customer_gstins') > 0)
          '${count('invalid_customer_gstins')} bills have a customer GSTIN that '
              'is not valid, so they are reported as B2C. Correct the customer\'s GSTIN.',
        if (count('invoices_without_state') > 0)
          '${count('invoices_without_state')} bills have no place of supply — '
              'set your shop\'s state in business settings.',
      ].join('\n'),
    );
  }
}

class _Gstr3bCard extends StatelessWidget {
  const _Gstr3bCard({required this.data});

  final GstReturnData data;

  @override
  Widget build(BuildContext context) {
    final out = data.outward;
    final itc = data.itc;
    final net = data.netPayable;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row('Outward taxable value (3.1a)', money(toDouble(out['taxable_value']))),
            _taxRow('Output tax', out['igst_amount'], out['cgst_amount'], out['sgst_amount']),
            const Divider(height: 20),
            _taxRow(
              'Input tax credit (4A)',
              itc['igst_amount'],
              itc['cgst_amount'],
              itc['sgst_amount'],
            ),
            const Divider(height: 20),
            _taxRow('Net (before set-off)', net.igst, net.cgst, net.sgst, bold: true),
            const SizedBox(height: 6),
            Text(t('A negative figure is credit to carry forward. Your accountant applies credits across IGST, CGST and SGST in the order the GST portal requires.'),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ],
    ),
  );

  Widget _taxRow(String label, Object? igst, Object? cgst, Object? sgst, {bool bold = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          _row('  IGST', money(toDouble(igst)), bold: bold),
          _row('  CGST', money(toDouble(cgst)), bold: bold),
          _row('  SGST', money(toDouble(sgst)), bold: bold),
        ],
      );
}

class _Gstr1Card extends StatelessWidget {
  const _Gstr1Card({required this.data});

  final GstReturnData data;

  @override
  Widget build(BuildContext context) {
    double taxable(String key) =>
        data.section(key).fold(0.0, (s, r) => s + toDouble(r['taxable_value']));
    final rows = [
      ('B2B — registered customers', '${data.documentCount('b2b')} invoices', taxable('b2b')),
      ('B2C large — inter-state above ₹1 lakh', '${data.documentCount('b2cl')} invoices', taxable('b2cl')),
      ('B2C small — net of their credit notes', '${data.section('b2cs').length} rows', taxable('b2cs')),
      ('Credit notes — registered', '${data.documentCount('cdnr')} notes', taxable('cdnr')),
      ('Credit notes — unregistered', '${data.documentCount('cdnur')} notes', taxable('cdnur')),
      ('HSN summary', '${data.section('hsn').length} rows', null),
    ];
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(rows[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(rows[i].$2),
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
