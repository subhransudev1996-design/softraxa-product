import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Outcome of the piece picker. [skipped] means "sell without tying this
/// cut to a specific piece" (e.g. the product's pieces aren't recorded).
/// A null return from [showPiecePicker] means the user cancelled.
class PiecePick {
  const PiecePick.skipped()
    : piece = null,
      skipped = true,
      keepRemnant = null,
      reason = '';
  const PiecePick.piece(
    Map<String, dynamic> this.piece, {
    this.keepRemnant,
    this.reason = '',
  }) : skipped = false;

  final Map<String, dynamic>? piece;
  final bool skipped;

  /// null = follow the suggestion; true/false = keep/scrap the leftover
  /// (stock permission and a reason, checked again by the server).
  final bool? keepRemnant;
  final String reason;
}

/// Pieces that fit the cut plus the product's cutting allowance, smallest
/// leftover first (suggest_pieces, migration 0049).
final pieceSuggestionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, (String, double)>((ref, key) async {
      final rows = await ref
          .watch(supabaseProvider)
          .rpc(
            'suggest_pieces',
            params: {'p_product': key.$1, 'p_variant': null, 'p_cut': key.$2},
          );
      return List<Map<String, dynamic>>.from(rows as List);
    });

String _leftoverText(Map<String, dynamic> s, String unit) {
  final left = toDouble(s['leftover']);
  final allowance = toDouble(s['allowance']);
  final loss = allowance > 0 ? ' (${qty(allowance)} $unit cutting loss)' : '';
  return switch (s['remnant']) {
    'none' => 'Uses the whole piece$loss',
    'scrap' => 'Leaves ${qty(left)} $unit → scrap$loss',
    _ => 'Leaves ${qty(left)} $unit as a piece$loss',
  };
}

/// Lets a wire/rod/pipe shop choose which physical piece a cut of
/// [needQty] comes from (D20). The best fit is first; two short pieces
/// never count as one long one. The cut itself happens with the sale.
Future<PiecePick?> showPiecePicker(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required String productName,
  required double needQty,
  required String unitName,
}) {
  return showModalBottomSheet<PiecePick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Consumer(
        builder: (ctx, ref, _) {
          final canOverride =
              ref.watch(appContextProvider).value?.canManageStock ?? false;
          final pieces = ref.watch(
            pieceSuggestionsProvider((productId, needQty)),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Text(
                  'Cut ${qty(needQty)} $unitName of $productName from…',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: pieces.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(friendlyError(e)),
                  ),
                  data: (rows) => rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No single piece is long enough for '
                            '${qty(needQty)} $unitName. Two short pieces '
                            'can\'t be joined into one cut.',
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (var i = 0; i < rows.length; i++)
                              ListTile(
                                leading: const IconChip(
                                  Icons.straighten,
                                  color: AppColors.indigo,
                                  size: 38,
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${(rows[i]['label'] as String? ?? '').isNotEmpty ? rows[i]['label'] : 'Piece'}'
                                        ' · ${qty(toDouble(rows[i]['length']))} $unitName',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (i == 0) ...[
                                      const SizedBox(width: 6),
                                      const StatusChip(
                                        'Best fit',
                                        color: AppColors.green,
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  _leftoverText(rows[i], unitName),
                                ),
                                trailing:
                                    canOverride && rows[i]['remnant'] != 'none'
                                    ? IconButton(
                                        tooltip: 'Keep or scrap the leftover',
                                        icon: const Icon(Icons.tune),
                                        onPressed: () async {
                                          final pick = await _override(
                                            ctx,
                                            rows[i],
                                            unitName,
                                          );
                                          if (pick != null && ctx.mounted) {
                                            Navigator.pop(ctx, pick);
                                          }
                                        },
                                      )
                                    : null,
                                onTap: () => Navigator.pop(
                                  ctx,
                                  PiecePick.piece(rows[i]),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, const PiecePick.skipped()),
                  child: const Text('Skip — don\'t tie to a piece'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Stock-permission override of the leftover suggestion (D21, PD43).
Future<PiecePick?> _override(
  BuildContext context,
  Map<String, dynamic> suggestion,
  String unitName,
) async {
  final suggestedKeep = suggestion['remnant'] == 'reusable';
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        suggestedKeep ? 'Scrap the leftover?' : 'Keep the leftover as a piece?',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested: ${suggestedKeep ? 'keep' : 'scrap'} the '
            '${qty(toDouble(suggestion['leftover']))} $unitName leftover.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason *'),
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
          onPressed: () {
            if (reason.text.trim().isNotEmpty) Navigator.pop(ctx, true);
          },
          child: Text(suggestedKeep ? 'Scrap it' : 'Keep it'),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  return PiecePick.piece(
    suggestion,
    keepRemnant: !suggestedKeep,
    reason: reason.text.trim(),
  );
}
