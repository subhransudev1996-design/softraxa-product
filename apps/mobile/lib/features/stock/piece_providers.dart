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
