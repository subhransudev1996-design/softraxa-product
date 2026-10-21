import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'offer_entry.dart' show offerSummary;

/// Offers with their use; with an id, that offer's codes and the bills it
/// was used on (migration 0084).
final offersProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String?>((ref, offerId) async {
      final res = await ref
          .watch(supabaseProvider)
          .rpc('get_offers', params: {'p_offer': offerId});
      return Map<String, dynamic>.from(res as Map);
    });

/// Offers & coupons (owner): scratch cards, coupon codes and vouchers.
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(offersProvider(null));
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Offers & coupons')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final id = await showOfferEditor(context, ref);
          ref.invalidate(offersProvider);
          if (id != null && context.mounted) context.push('/offers/$id');
        },
        icon: const Icon(Icons.add),
        label: Text(t('New offer')),
      ),
      body: AsyncView<Map<String, dynamic>>(
        value: data,
        onRetry: () => ref.invalidate(offersProvider),
        builder: (d) {
          final offers = [
            for (final o in (d['offers'] as List? ?? const []))
              Map<String, dynamic>.from(o as Map),
          ];
          if (offers.isEmpty) {
            return EmptyState(
              icon: Icons.local_offer_outlined,
              message: t(
                'No offers yet. Make a scratch card prize, a coupon code like DIWALI100, or vouchers with their own codes.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: offers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = offers[i];
              final uses = (o['uses'] as num?)?.toInt() ?? 0;
              return Card(
                child: ListTile(
                  leading: IconChip(
                    _modeIcon(o['code_mode'] as String?),
                    color: o['is_active'] == true
                        ? AppColors.primary
                        : AppColors.inkSoft,
                    size: 40,
                  ),
                  title: Text(
                    o['name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      offerSummary(o),
                      offerClaimLabel(o),
                      if (o['is_active'] != true) t('Switched off'),
                      t('Used {v1} times · {v2} off', {
                        'v1': '$uses',
                        'v2': money(o['given'] as num?),
                      }),
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/offers/${o['id']}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

IconData _modeIcon(String? mode) => switch (mode) {
  'shared' => Icons.confirmation_number_outlined,
  'unique' => Icons.qr_code_2,
  _ => Icons.local_offer_outlined,
};

/// How customers claim an offer, in a few words.
String offerClaimLabel(Map<String, dynamic> o) => switch (o['code_mode']) {
  'shared' => t('Code {v1}', {'v1': o['shared_code'] as String? ?? ''}),
  'unique' => t('{v1} codes, {v2} used', {
    'v1': '${o['codes'] ?? 0}',
    'v2': '${o['codes_used'] ?? 0}',
  }),
  _ => t('Picked at the counter'),
};

/// Add or change an offer. Returns its id when saved.
Future<String?> showOfferEditor(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) async {
  String n(Object? v) => v == null ? '' : qty(v as num);
  final name = TextEditingController(text: existing?['name'] as String? ?? '');
  var kind = existing?['kind'] as String? ?? 'amount';
  final amounts = TextEditingController(
    text: [
      for (final a in (existing?['amounts'] as List? ?? const [])) n(a as num),
    ].join(', '),
  );
  final percent = TextEditingController(text: n(existing?['percent']));
  final maxOff = TextEditingController(text: n(existing?['max_discount']));
  final minBill = TextEditingController(
    text: toDouble(existing?['min_bill']) > 0 ? n(existing?['min_bill']) : '',
  );
  var mode = existing?['code_mode'] as String? ?? 'none';
  final sharedCode = TextEditingController(
    text: existing?['shared_code'] as String? ?? '',
  );
  final perCustomer = TextEditingController(
    text: existing?['uses_per_customer']?.toString() ?? '',
  );
  var needsCustomer = existing?['needs_customer'] as bool? ?? false;
  DateTime? from = DateTime.tryParse(existing?['valid_from'] as String? ?? '');
  DateTime? until = DateTime.tryParse(
    existing?['valid_until'] as String? ?? '',
  );
  var active = existing?['is_active'] as bool? ?? true;
  var busy = false;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> pickDate(bool start) async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: (start ? from : until) ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) setLocal(() => start ? from = d : until = d);
        }

        Widget dateRow(String label, DateTime? value, bool start) => Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? label
                    : '$label: ${dateStr(value.toIso8601String())}',
                style: TextStyle(color: AppColors.inkSoft),
              ),
            ),
            TextButton(
              onPressed: () => pickDate(start),
              child: Text(t('Set date')),
            ),
            if (value != null)
              IconButton(
                tooltip: t('Remove'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    setLocal(() => start ? from = null : until = null),
              ),
          ],
        );

        final hasCodes = toDouble(existing?['codes']) > 0;
        return AlertDialog(
          title: Text(existing == null ? t('New offer') : t('Change offer')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: t('Name (e.g. Scratch & Win, Diwali Sale)'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'amount', label: Text(t('₹ off'))),
                      ButtonSegment(value: 'percent', label: Text(t('% off'))),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setLocal(() => kind = s.first),
                  ),
                  const SizedBox(height: 10),
                  if (kind == 'amount')
                    TextField(
                      controller: amounts,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: t('Amount ₹'),
                        helperText: t(
                          'One amount, or a scratch card\'s prizes: 20, 50, 100',
                        ),
                        helperMaxLines: 2,
                      ),
                    )
                  else ...[
                    TextField(
                      controller: percent,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t('Discount %'),
                        suffixText: '%',
                      ),
                    ),
                    TextField(
                      controller: maxOff,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t('At most ₹ (optional)'),
                      ),
                    ),
                  ],
                  TextField(
                    controller: minBill,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t('Minimum bill ₹ (optional)'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t('How customers claim it'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  RadioGroup<String>(
                    groupValue: mode,
                    onChanged: (v) {
                      if (hasCodes && v != 'unique') return;
                      setLocal(() => mode = v ?? 'none');
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'none',
                          dense: true,
                          title: Text(t('The cashier picks it')),
                          subtitle: Text(
                            t('Scratch cards without numbers, counter offers'),
                          ),
                        ),
                        RadioListTile<String>(
                          value: 'shared',
                          dense: true,
                          title: Text(t('One code for everyone')),
                          subtitle: Text(t('Like DIWALI100')),
                        ),
                        RadioListTile<String>(
                          value: 'unique',
                          dense: true,
                          title: Text(t('Each card has its own code')),
                          subtitle: Text(
                            t(
                              'Numbered scratch cards, vouchers — each used once',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (mode == 'shared') ...[
                    TextField(
                      controller: sharedCode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(labelText: t('The code')),
                    ),
                    TextField(
                      controller: perCustomer,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('Times each customer may use it'),
                        helperText: t(
                          'Empty = no limit. A limit needs the customer on the bill.',
                        ),
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: needsCustomer,
                    onChanged: (v) => setLocal(() => needsCustomer = v),
                    title: Text(t('Customer\'s name and phone needed')),
                    subtitle: Text(
                      t(
                        'Instead of a paper slip: the bill must name a customer with a phone number.',
                      ),
                    ),
                  ),
                  dateRow(t('Starts'), from, true),
                  dateRow(t('Ends'), until, false),
                  if (existing != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      onChanged: (v) => setLocal(() => active = v),
                      title: Text(t('In use')),
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
                      final list = [
                        for (final p in amounts.text.split(RegExp(r'[,\s/]+')))
                          if (double.tryParse(p.replaceAll('₹', '')) != null)
                            double.parse(p.replaceAll('₹', '')),
                      ];
                      setLocal(() => busy = true);
                      try {
                        final id = await ref
                            .read(supabaseProvider)
                            .rpc(
                              'save_offer',
                              params: {
                                'p_id': existing?['id'],
                                'p': {
                                  'name': name.text.trim(),
                                  'kind': kind,
                                  'amounts': list,
                                  'percent': double.tryParse(percent.text),
                                  'max_discount': double.tryParse(maxOff.text),
                                  'min_bill': double.tryParse(minBill.text),
                                  'code_mode': mode,
                                  'shared_code': sharedCode.text.trim(),
                                  'uses_per_customer': int.tryParse(
                                    perCustomer.text.trim(),
                                  ),
                                  'needs_customer': needsCustomer,
                                  'valid_from': from == null
                                      ? null
                                      : ymd(from!),
                                  'valid_until': until == null
                                      ? null
                                      : ymd(until!),
                                  'is_active': active,
                                },
                              },
                            );
                        if (ctx.mounted) Navigator.pop(ctx, id as String);
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
