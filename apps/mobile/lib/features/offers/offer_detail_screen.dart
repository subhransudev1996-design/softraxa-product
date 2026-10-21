import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'offer_entry.dart' show offerSummary;
import 'offers_screen.dart';

/// One offer: its use, its codes (add, print, remove unused) and the bills
/// it was used on — with the customer's phone, for following up.
class OfferDetailScreen extends ConsumerWidget {
  const OfferDetailScreen({super.key, required this.offerId});

  final String offerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(offersProvider(offerId));
    void reload() => ref.invalidate(offersProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(leading: appBarBack(context), title: Text(t('Offer'))),
      body: AsyncView<Map<String, dynamic>>(
        value: data,
        onRetry: reload,
        builder: (d) {
          final offer = [
            for (final o in (d['offers'] as List? ?? const []))
              if ((o as Map)['id'] == offerId) Map<String, dynamic>.from(o),
          ].firstOrNull;
          if (offer == null) {
            return EmptyState(
              icon: Icons.local_offer_outlined,
              message: t('This offer is no longer there.'),
            );
          }
          final codes = [
            for (final c in (d['codes'] as List? ?? const []))
              Map<String, dynamic>.from(c as Map),
          ];
          final uses = [
            for (final u in (d['uses'] as List? ?? const []))
              Map<String, dynamic>.from(u as Map),
          ];
          final unique = offer['code_mode'] == 'unique';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              offer['name'] as String? ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await showOfferEditor(
                                context,
                                ref,
                                existing: offer,
                              );
                              reload();
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(t('Change')),
                          ),
                        ],
                      ),
                      Text(offerSummary(offer)),
                      Text(
                        offerClaimLabel(offer),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                      if (offer['valid_from'] != null ||
                          offer['valid_until'] != null)
                        Text(
                          [
                            if (offer['valid_from'] != null)
                              t('from {v1}', {
                                'v1': dateStr(offer['valid_from']),
                              }),
                            if (offer['valid_until'] != null)
                              t('till {v1}', {
                                'v1': dateStr(offer['valid_until']),
                              }),
                          ].join(' '),
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                      if (offer['is_active'] != true)
                        Text(
                          t('Switched off'),
                          style: const TextStyle(color: AppColors.red),
                        ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          _stat(t('Used'), '${offer['uses'] ?? 0}'),
                          _stat(t('Given'), money(offer['given'] as num?)),
                          if (unique)
                            _stat(
                              t('Codes left'),
                              '${(offer['codes'] as num? ?? 0) - (offer['codes_used'] as num? ?? 0)}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (unique) ...[
                SectionLabel(t('Codes')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: dialogActionStyle,
                      onPressed: () async {
                        if (await _addCodes(context, ref, offer)) reload();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(t('Add codes')),
                    ),
                    if (codes.any((c) => c['invoice_no'] == null))
                      OutlinedButton.icon(
                        onPressed: () => _printCodes(context, ref, offer, [
                          for (final c in codes)
                            if (c['invoice_no'] == null) c,
                        ]),
                        icon: const Icon(Icons.print_outlined),
                        label: Text(t('Print unused codes')),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (codes.isEmpty)
                  Text(
                    t(
                      'No codes yet. Make new ones to print, or type the numbers printed on your cards.',
                    ),
                    style: TextStyle(color: AppColors.inkSoft),
                  ),
                if (codes.isNotEmpty)
                  Card(
                    child: Column(
                      children: [
                        for (final c in codes.take(300))
                          ListTile(
                            dense: true,
                            title: Text(
                              c['code'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (c['amount'] != null)
                                  money(c['amount'] as num?),
                                c['invoice_no'] == null
                                    ? t('Not used')
                                    : t('Used on {v1}', {
                                        'v1': c['invoice_no'] as String,
                                      }),
                              ].join(' · '),
                            ),
                            trailing: c['invoice_no'] == null
                                ? IconButton(
                                    tooltip: t('Remove'),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                    onPressed: () async {
                                      if (!await confirmDialog(
                                        context,
                                        title: t('Remove this code?'),
                                        message: t(
                                          'It won\'t work at the counter any more.',
                                        ),
                                        confirmText: t('Remove'),
                                      )) {
                                        return;
                                      }
                                      try {
                                        await ref
                                            .read(supabaseProvider)
                                            .rpc(
                                              'delete_offer_codes',
                                              params: {
                                                'p_ids': [c['id']],
                                              },
                                            );
                                        reload();
                                      } catch (e) {
                                        if (context.mounted) {
                                          showError(context, e);
                                        }
                                      }
                                    },
                                  )
                                : null,
                          ),
                        if (codes.length > 300)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              t('and {v1} more', {
                                'v1': '${codes.length - 300}',
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              SectionLabel(t('Used on bills')),
              if (uses.isEmpty)
                Text(
                  t('Not used yet.'),
                  style: TextStyle(color: AppColors.inkSoft),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final u in uses)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${u['customer']}'
                            '${(u['phone'] as String? ?? '').isEmpty ? '' : ' · ${u['phone']}'}',
                          ),
                          subtitle: Text(
                            [
                              u['invoice_no'] as String? ?? '',
                              dateStr(u['date']),
                              if ((u['code'] as String? ?? '').isNotEmpty)
                                u['code'] as String,
                            ].join(' · '),
                          ),
                          trailing: Text(
                            '− ${money(u['amount'] as num?)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () =>
                              context.push('/invoices/${u['invoice_id']}'),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
      ],
    ),
  );
}

/// New codes: made by the app, or typed / pasted (the numbers printed on
/// cards). True when codes were added.
Future<bool> _addCodes(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> offer,
) async {
  final count = TextEditingController(text: '50');
  final prefix = TextEditingController();
  final typed = TextEditingController();
  final amount = TextEditingController();
  final prizes = (offer['amounts'] as List? ?? const []).length > 1;
  var generate = true;
  var busy = false;

  final added = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(t('Add codes')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(t('Make new codes')),
                    ),
                    ButtonSegment(value: false, label: Text(t('Type codes'))),
                  ],
                  selected: {generate},
                  onSelectionChanged: (s) => setLocal(() => generate = s.first),
                ),
                const SizedBox(height: 12),
                if (generate) ...[
                  TextField(
                    controller: count,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t('How many'),
                      helperText: t('Up to 2000 at a time'),
                    ),
                  ),
                  TextField(
                    controller: prefix,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: t('Start of each code (optional)'),
                      helperText: t('e.g. your shop\'s initials: TBW-7K3QX9'),
                    ),
                  ),
                ] else
                  TextField(
                    controller: typed,
                    minLines: 4,
                    maxLines: 10,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: t('Codes, one per line'),
                      helperText: t(
                        'The numbers printed on your cards or vouchers',
                      ),
                    ),
                  ),
                if (offer['kind'] == 'amount' && prizes)
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t('Each code\'s value ₹ (optional)'),
                      helperText: t(
                        'Empty: the cashier picks the prize the customer scratched.',
                      ),
                      helperMaxLines: 2,
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
                    setLocal(() => busy = true);
                    try {
                      final n = await ref
                          .read(supabaseProvider)
                          .rpc(
                            'add_offer_codes',
                            params: {
                              'p_offer': offer['id'],
                              'p_count': generate
                                  ? int.tryParse(count.text.trim()) ?? 0
                                  : 0,
                              'p_prefix': generate ? prefix.text.trim() : '',
                              'p_codes': generate
                                  ? <String>[]
                                  : [
                                      for (final l in typed.text.split('\n'))
                                        if (l.trim().isNotEmpty) l.trim(),
                                    ],
                              'p_amount': double.tryParse(amount.text.trim()),
                            },
                          );
                      if (ctx.mounted) Navigator.pop(ctx, n as int);
                    } catch (e) {
                      setLocal(() => busy = false);
                      if (ctx.mounted) showError(ctx, e);
                    }
                  },
            child: Text(t('Add')),
          ),
        ],
      ),
    ),
  );
  if (added != null && context.mounted) {
    showSuccess(context, t('{v1} codes added', {'v1': '$added'}));
  }
  return added != null;
}

/// A sheet of the unused codes to cut out: offer, value, code and its QR
/// (scanned at the counter), 3 x 8 on A4.
Future<void> _printCodes(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> offer,
  List<Map<String, dynamic>> codes,
) async {
  final shop =
      ref.read(appContextProvider).value?.business?['name'] as String? ?? '';
  final name = offer['name'] as String? ?? '';
  String value(Map<String, dynamic> c) => c['amount'] != null
      ? 'Rs. ${qty(c['amount'] as num)}'
      : offer['kind'] == 'percent'
      ? '${qty(offer['percent'] as num?)}% off'
      : (offer['amounts'] as List? ?? const []).length == 1
      ? 'Rs. ${qty((offer['amounts'] as List).single as num)}'
      : '';

  final doc = pw.Document();
  const perPage = 24;
  for (var start = 0; start < codes.length; start += perPage) {
    final page = codes.skip(start).take(perPage).toList();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in page)
              pw.Container(
                width: (PdfPageFormat.a4.width - 36 - 12) / 3,
                height: (PdfPageFormat.a4.height - 36 - 42) / 8,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    width: 0.5,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: c['code'] as String,
                      width: 54,
                      height: 54,
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            shop,
                            maxLines: 1,
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                          pw.Text(
                            name,
                            maxLines: 2,
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (value(c).isNotEmpty)
                            pw.Text(
                              value(c),
                              style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            c['code'] as String,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
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
  await Printing.layoutPdf(
    name: safeFileName('$name codes'),
    format: PdfPageFormat.a4,
    onLayout: (_) => doc.save(),
  );
}
