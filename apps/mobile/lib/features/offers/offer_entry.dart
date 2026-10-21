import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/network.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customer_picker.dart';
import '../pos/cart.dart';
import '../pos/pos_providers.dart';
import 'offer.dart';

/// The bill's offer at checkout: a button to add one, or the applied offer
/// with what it takes off — or why it doesn't apply yet.
class OfferRow extends ConsumerWidget {
  const OfferRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final offer = cart.offer;
    if (offer == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => askOffer(context, ref),
          icon: const Icon(Icons.local_offer_outlined, size: 18),
          label: Text(t('Offer / coupon')),
        ),
      );
    }
    final off = cart.offerAmount;
    final before = cart.itemsGross - cart.manualBillDiscountAmount;
    final phone = (cart.customer?['phone'] as String? ?? '').trim();
    final problem = before + 0.005 < offer.minBill
        ? t('Needs a bill of at least {v1}', {'v1': money(offer.minBill)})
        : offer.needsCustomer && cart.customer == null
        ? t('Choose the customer — this offer needs their name and phone')
        : offer.needsCustomer && phone.isEmpty
        ? t('The customer needs a phone number for this offer')
        : null;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: (problem == null ? AppColors.green : AppColors.red).withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_offer,
            color: problem == null ? AppColors.green : AppColors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.code.isEmpty
                      ? offer.label
                      : '${offer.label} · ${offer.code}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  problem ?? t('{v1} off', {'v1': money(off)}),
                  style: TextStyle(
                    fontSize: 12,
                    color: problem == null ? AppColors.inkSoft : AppColors.red,
                  ),
                ),
              ],
            ),
          ),
          if (offer.needsCustomer && cart.customer == null)
            TextButton(
              onPressed: () => _pickCustomer(context, ref),
              child: Text(t('Choose')),
            ),
          IconButton(
            tooltip: t('Remove offer'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => ref.read(cartProvider.notifier).setOffer(null),
          ),
        ],
      ),
    );
  }
}

Future<void> _pickCustomer(BuildContext context, WidgetRef ref) async {
  final c = await showCustomerPicker(context);
  if (c != null) await setCartCustomer(ref, c);
}

/// Type or scan a code, or pick one of the shop's counter offers.
Future<void> askOffer(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseProvider);
  List<Map<String, dynamic>> counter = const [];
  try {
    counter = [
      for (final o in (await client.rpc('counter_offers') as List? ?? const []))
        Map<String, dynamic>.from(o as Map),
    ];
  } catch (_) {
    // Offline or not set up: codes can still be tried (and say why not).
  }
  if (!context.mounted) return;

  final code = TextEditingController();
  final picked = await showDialog<Object>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Offer / coupon')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: code,
                autofocus: counter.isEmpty,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('Coupon or voucher code'),
                  suffixIcon: isDesktopPlatform
                      ? null
                      : IconButton(
                          tooltip: t('Scan'),
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () async {
                            final c = await ctx.push<String>(
                              '/scan?mode=return',
                            );
                            if (c != null && ctx.mounted) {
                              Navigator.pop(ctx, c);
                            }
                          },
                        ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: dialogActionStyle,
                  onPressed: () => Navigator.pop(ctx, code.text),
                  child: Text(t('Apply code')),
                ),
              ),
              if (counter.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  t('Or pick an offer'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final o in counter)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.local_offer_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(o['name'] as String? ?? ''),
                    subtitle: Text(offerSummary(o)),
                    onTap: () => Navigator.pop(ctx, o),
                  ),
              ],
            ],
          ),
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
  if (picked == null || !context.mounted) return;

  Map<String, dynamic> json;
  if (picked is Map<String, dynamic>) {
    json = picked;
  } else {
    final text = (picked as String).trim();
    if (text.isEmpty) return;
    try {
      json = Map<String, dynamic>.from(
        await client.rpc('find_offer_code', params: {'p_code': text}) as Map,
      );
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          isNetworkError(e) ? t('Checking a code needs the internet.') : e,
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (json['found'] != true) {
      showError(context, t('No offer with the code {v1}', {'v1': text}));
      return;
    }
    if (json['usable'] != true) {
      showError(
        context,
        json['problem'] as String? ?? t('This code can\'t be used'),
      );
      return;
    }
  }

  // A scratch card's prize: the cashier picks the amount revealed.
  double? amount;
  final amounts = [
    for (final a in (json['amounts'] as List? ?? const [])) toDouble(a),
  ];
  if (json['kind'] == 'amount' &&
      json['code_amount'] == null &&
      amounts.length > 1) {
    amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Which amount did the customer win?')),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in amounts)
              ActionChip(
                label: Text(money(a)),
                onPressed: () => Navigator.pop(ctx, a),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
        ],
      ),
    );
    if (amount == null || !context.mounted) return;
  }

  final offer = AppliedOffer.fromJson(
    json,
    amount: amount,
    code: json['code'] as String? ?? '',
  );
  ref.read(cartProvider.notifier).setOffer(offer);
  if (offer.needsCustomer && ref.read(cartProvider).customer == null) {
    showSuccess(
      context,
      t('Now choose the customer — this offer needs their name and phone'),
    );
    await _pickCustomer(context, ref);
  } else {
    showSuccess(context, t('{v1} applied', {'v1': offer.label}));
  }
}

/// "₹20 / ₹50 / ₹100 · bill ≥ ₹200 · needs customer" — an offer's rules
/// in one line.
String offerSummary(Map<String, dynamic> o) {
  final amounts = [
    for (final a in (o['amounts'] as List? ?? const [])) money(toDouble(a)),
  ];
  final max = (o['max_discount'] as num?)?.toDouble();
  final minBill = toDouble(o['min_bill']);
  return [
    if (o['kind'] == 'percent')
      '${qty(o['percent'] as num?)}%${max != null ? ' (${t('up to {v1}', {'v1': money(max)})})' : ''}'
    else
      amounts.join(' / '),
    if (minBill > 0) t('bill {v1} or more', {'v1': money(minBill)}),
    if (o['needs_customer'] == true) t('needs customer'),
  ].join(' · ');
}
