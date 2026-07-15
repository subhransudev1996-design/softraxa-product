import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';

/// Service catalog (PRD Phase 2 §5) — the sellable "service SKU" list used
/// by job cards for labor/service charges.
final servicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final rows = await client
      .from('services')
      .select()
      .eq('is_active', true)
      .order('name');
  return List<Map<String, dynamic>>.from(rows);
});
