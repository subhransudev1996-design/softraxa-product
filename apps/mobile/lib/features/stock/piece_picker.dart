import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'piece_providers.dart';

/// Outcome of the piece picker. [skipped] means "sell without tying this
/// cut to a specific piece" — always allowed, since pieces are an aid, not
/// a gate. A null return from [showPiecePicker] means the user cancelled.
class PiecePick {
  const PiecePick.skipped() : piece = null, skipped = true;
  const PiecePick.piece(Map<String, dynamic> this.piece) : skipped = false;

  final Map<String, dynamic>? piece;
  final bool skipped;
}

/// Lets a rod/sheet store choose which physical piece a cut of [needQty]
/// comes from (PRD Phase 3 cut-piece tracking). Pieces shorter than the cut
/// are shown but flagged — selecting one is allowed (shops sometimes join
/// offcuts), it just warns.
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
          final pieces = ref.watch(stockPiecesProvider(productId));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Cut ${qty(needQty)} $unitName of $productName from…',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                  ],
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
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No pieces recorded for this product yet — '
                            'add them from the product page.',
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final piece in rows)
                              ListTile(
                                leading: const IconChip(
                                  Icons.straighten,
                                  color: AppColors.indigo,
                                  size: 38,
                                ),
                                title: Text(
                                  (piece['label'] as String? ?? '').isNotEmpty
                                      ? piece['label'] as String
                                      : 'Piece',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${qty(toDouble(piece['length']))} $unitName',
                                ),
                                trailing: toDouble(piece['length']) < needQty
                                    ? const StatusChip(
                                        'too short',
                                        color: AppColors.orange,
                                      )
                                    : null,
                                onTap: () =>
                                    Navigator.pop(ctx, PiecePick.piece(piece)),
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
