import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'cart.dart';

/// A bill put aside at the counter — the customer went back for one more
/// thing — so the next customer can be billed meanwhile.
class HeldBill {
  const HeldBill({required this.id, required this.cart, required this.at});
  final int id;
  final CartState cart;
  final DateTime at;

  /// The customer's name, else the first item ("Sugar + 2 more").
  String get label {
    final name = (cart.customer?['name'] as String? ?? '').trim();
    if (name.isNotEmpty) return name;
    if (cart.lines.isEmpty) return 'Bill';
    final more = cart.lines.length - 1;
    return '${cart.lines.first.name}${more > 0 ? ' + $more more' : ''}';
  }
}

/// Held bills on this device, oldest first. Kept while the app is open.
class HeldBillsNotifier extends Notifier<List<HeldBill>> {
  int _next = 1;

  @override
  List<HeldBill> build() => const [];

  void hold(CartState cart) {
    if (cart.lines.isEmpty) return;
    state = [...state, HeldBill(id: _next++, cart: cart, at: DateTime.now())];
  }

  /// Removes the held bill and gives it back (null if it's gone).
  HeldBill? take(int id) {
    final i = state.indexWhere((h) => h.id == id);
    if (i < 0) return null;
    final h = state[i];
    state = [...state]..removeAt(i);
    return h;
  }
}

final heldBillsProvider = NotifierProvider<HeldBillsNotifier, List<HeldBill>>(
  HeldBillsNotifier.new,
);

/// Puts the bill on the counter aside and clears it for the next customer.
void holdCurrentBill(BuildContext context, WidgetRef ref) {
  final cart = ref.read(cartProvider);
  if (cart.lines.isEmpty) return;
  ref.read(heldBillsProvider.notifier).hold(cart);
  ref.read(cartProvider.notifier).clear();
  showSuccess(context, t('Bill held — open "Held bills" to finish it'));
}

/// Lists held bills; tapping one brings it back to the counter. If the
/// counter has items, those are held first so nothing is lost.
Future<void> showHeldBills(BuildContext context, WidgetRef ref) async {
  final id = await showDialog<int>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final held = ref.watch(heldBillsProvider);
        return AlertDialog(
          title: Text(t('Held bills')),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 460,
            child: held.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(t('No bills on hold.')),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final h in held)
                        ListTile(
                          leading: const IconChip(
                            Icons.pause_circle_outline,
                            color: AppColors.orange,
                            size: 38,
                          ),
                          title: Text(
                            h.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${h.cart.itemCount} item${h.cart.itemCount == 1 ? '' : 's'}'
                            ' · held at ${TimeOfDay.fromDateTime(h.at).format(ctx)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                money(h.cart.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: t('Discard'),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.red,
                                ),
                                onPressed: () async {
                                  final ok = await confirmDialog(
                                    ctx,
                                    title: t('Discard this held bill?'),
                                    message:
                                        '${h.label} — ${money(h.cart.total)}',
                                    confirmText: t('Discard'),
                                  );
                                  if (ok) {
                                    ref
                                        .read(heldBillsProvider.notifier)
                                        .take(h.id);
                                  }
                                },
                              ),
                            ],
                          ),
                          onTap: () => Navigator.pop(ctx, h.id),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Close')),
            ),
          ],
        );
      },
    ),
  );
  if (id == null || !context.mounted) return;
  final current = ref.read(cartProvider);
  final held = ref.read(heldBillsProvider.notifier);
  final picked = held.take(id);
  if (picked == null) return;
  if (current.lines.isNotEmpty) held.hold(current);
  ref.read(cartProvider.notifier).restore(picked.cart);
  if (current.lines.isNotEmpty && context.mounted) {
    showSuccess(context, t('The bill you were on is now held'));
  }
}
