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
import '../pos/cart.dart';
import 'discount_card.dart';
import 'discount_cards_screen.dart';

/// The bill's discount card at checkout: a button to add one, or the
/// applied card with what it takes off and a way to remove it.
class DiscountCardRow extends ConsumerWidget {
  const DiscountCardRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final card = cart.card;
    if (card == null) {
      final ctx = ref.watch(appContextProvider).value;
      final canIssue = (ctx?.isOwner ?? false) || (ctx?.canEditPrices ?? false);
      final customer = cart.customer;
      return Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: () => askDiscountCard(context, ref),
            icon: const Icon(Icons.card_membership_outlined, size: 18),
            label: Text(t('Discount card')),
          ),
          // A new card for the bill's customer, numbered by the shop's
          // pattern (0094), and used on this bill straight away.
          if (canIssue && customer != null)
            TextButton.icon(
              onPressed: () => _giveCard(context, ref, customer),
              icon: const Icon(Icons.add_card_outlined, size: 18),
              label: Text(t('Give card')),
            ),
        ],
      );
    }
    final off = cart.cardDiscountTotal;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_membership, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('{v1} card {v2}', {'v1': card.label, 'v2': card.cardNo}),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  off > 0
                      ? t('{v1} off', {'v1': money(off)}) +
                            (card.holder.isEmpty ? '' : ' · ${card.holder}')
                      : t('No item on this bill is covered by this card'),
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t('Remove card'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => ref.read(cartProvider.notifier).setCard(null),
          ),
        ],
      ),
    );
  }
}

/// Asks for the card number (typed, or scanned on phones), finds the card
/// and applies it. A card that isn't in the list yet can be added on the
/// spot by someone allowed to issue cards.
Future<void> askDiscountCard(BuildContext context, WidgetRef ref) async {
  final number = TextEditingController();
  final query = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('Discount card')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: number,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: t('Card number'),
              helperText: t('The whole number, or just its last digits'),
              suffixIcon: isDesktopPlatform
                  ? null
                  : IconButton(
                      tooltip: t('Scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () async {
                        final code = await ctx.push<String>(
                          '/scan?mode=return',
                        );
                        if (code != null && ctx.mounted) {
                          Navigator.pop(ctx, code);
                        }
                      },
                    ),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('Cancel')),
        ),
        FilledButton(
          style: dialogActionStyle,
          onPressed: () => Navigator.pop(ctx, number.text),
          child: Text(t('Apply')),
        ),
      ],
    ),
  );
  if (query == null || query.trim().isEmpty || !context.mounted) return;
  await _findAndApply(context, ref, query.trim());
}

Future<void> _giveCard(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> customer,
) async {
  Map<String, dynamic> data;
  try {
    data = await ref.read(discountCardsProvider('').future);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final types = [
    for (final ty in (data['types'] as List? ?? const []))
      if ((ty as Map)['is_active'] == true) Map<String, dynamic>.from(ty),
  ];
  if (types.isEmpty) {
    showError(
      context,
      t('There are no card types yet. The owner adds them in Discount cards.'),
    );
    return;
  }
  final id = await showDiscountCardEditor(
    context,
    ref,
    types: types,
    customer: customer,
  );
  ref.invalidate(discountCardsProvider);
  if (id == null || !context.mounted) return;
  final row = await ref
      .read(supabaseProvider)
      .from('discount_cards')
      .select('card_no')
      .eq('id', id)
      .single();
  if (!context.mounted) return;
  await _findAndApply(context, ref, row['card_no'] as String);
}

Future<void> _findAndApply(
  BuildContext context,
  WidgetRef ref,
  String query,
) async {
  final client = ref.read(supabaseProvider);
  Map<String, dynamic> res;
  try {
    res = Map<String, dynamic>.from(
      await client.rpc('find_discount_card', params: {'p_query': query}) as Map,
    );
  } catch (e) {
    if (!context.mounted) return;
    showError(
      context,
      isNetworkError(e) ? t('Checking a discount card needs the internet.') : e,
    );
    return;
  }
  if (!context.mounted) return;

  if (res['found'] != true) {
    final ctx = ref.read(appContextProvider).value;
    final canIssue = (ctx?.isOwner ?? false) || (ctx?.canEditPrices ?? false);
    final add = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(t('Card not in your list')),
        content: Text(
          canIssue
              ? t(
                  'No card {v1} yet. Add it now? The customer can use it from this bill on.',
                  {'v1': query},
                )
              : t(
                  'No card {v1} yet. Ask the owner to add it in Discount cards.',
                  {'v1': query},
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(canIssue ? t('Cancel') : t('OK')),
          ),
          if (canIssue)
            FilledButton(
              style: dialogActionStyle,
              onPressed: () => Navigator.pop(d, true),
              child: Text(t('Add card')),
            ),
        ],
      ),
    );
    if (add != true || !context.mounted) return;
    final data = await ref.read(discountCardsProvider('').future);
    if (!context.mounted) return;
    final types = [
      for (final ty in (data['types'] as List? ?? const []))
        if ((ty as Map)['is_active'] == true) Map<String, dynamic>.from(ty),
    ];
    if (types.isEmpty) {
      showError(
        context,
        t(
          'There are no card types yet. The owner adds them in Discount cards.',
        ),
      );
      return;
    }
    final id = await showDiscountCardEditor(
      context,
      ref,
      types: types,
      initialNo: query,
    );
    ref.invalidate(discountCardsProvider);
    if (id == null || !context.mounted) return;
    // Found by its full number now.
    final added = await client.rpc(
      'find_discount_card',
      params: {'p_query': query},
    );
    res = Map<String, dynamic>.from(added as Map);
    if (!context.mounted) return;
  }

  if (res['usable'] != true) {
    showError(
      context,
      res['problem'] as String? ?? t('This card can\'t be used'),
    );
    return;
  }
  final card = DiscountCard.fromJson(res);
  ref.read(cartProvider.notifier).setCard(card);
  showSuccess(
    context,
    t('{v1} card applied', {'v1': card.label}) +
        (card.holder.isEmpty ? '' : ' · ${card.holder}'),
  );
}
