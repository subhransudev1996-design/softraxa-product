import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';

/// Available (uncut/remnant) pieces of one product — rods, sheets, rolls.
/// See stock_pieces (migration 0021): an auxiliary layer over
/// current_stock, which remains the source of truth for totals.
final stockPiecesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, productId) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('stock_pieces')
      .select()
      .eq('product_id', productId)
      .eq('status', 'available')
      .order('length', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});

/// Best-effort piece shortening after a successful bill: cut [cutQty] off
/// each piece. A piece shrinking to ~0 is marked consumed. Failures are
/// swallowed by the caller — piece bookkeeping must never block billing.
Future<void> applyPieceCuts(
    dynamic client, List<(String pieceId, double cutQty)> cuts) async {
  for (final (pieceId, cutQty) in cuts) {
    final row = await client
        .from('stock_pieces')
        .select('length')
        .eq('id', pieceId)
        .maybeSingle();
    if (row == null) continue;
    final remaining =
        ((row['length'] as num).toDouble() - cutQty).clamp(0.0, double.infinity);
    await client.from('stock_pieces').update({
      'length': remaining,
      if (remaining <= 0.0005) 'status': 'consumed',
    }).eq('id', pieceId);
  }
}
