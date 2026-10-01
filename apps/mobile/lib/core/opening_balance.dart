import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'formatters.dart';
import 'supabase_providers.dart';
import 'widgets.dart';

/// Owner enters what a customer owed (or had paid in advance), or what the
/// shop owed a supplier, before starting on Dukania (migration 0051).
/// Returns true when saved.
Future<bool> showOpeningBalanceDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool supplier,
  required String partyId,
  required String name,
}) async {
  final amount = TextEditingController();
  var asOf = DateTime.now().subtract(const Duration(days: 1));
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Opening balance — $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: supplier ? 'You owed them ₹' : 'They owed you ₹',
                helperText: supplier
                    ? 'Settled first by your next payments to them'
                    : 'Minus amount = advance they had paid you',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text('As of ${dateStr(asOf)}'),
              trailing: const Text('Change'),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: asOf,
                  firstDate: DateTime(now.year - 5),
                  lastDate: now.subtract(const Duration(days: 1)),
                );
                if (d != null) setState(() => asOf = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return false;
  final value = double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
  if (value == 0) return false;
  try {
    await ref
        .read(supabaseProvider)
        .rpc(
          'set_opening_balance',
          params: {
            'p_party': supplier ? 'supplier' : 'customer',
            'p_party_id': partyId,
            'p_amount': value,
            'p_as_of': ymd(asOf),
          },
        );
    if (context.mounted) showSuccess(context, 'Opening balance saved');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
