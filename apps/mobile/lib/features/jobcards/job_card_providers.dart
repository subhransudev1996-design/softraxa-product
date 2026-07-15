import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../../core/theme.dart';

/// Job status labels + order, matching the `job_status` DB enum (PRD Phase 2 §8).
const jobStatuses = [
  'received',
  'checking',
  'estimate_given',
  'waiting_approval',
  'in_progress',
  'waiting_parts',
  'ready',
  'delivered',
  'cancelled',
  'returned_unrepaired',
];

String jobStatusLabel(String status) => switch (status) {
      'received' => 'Received',
      'checking' => 'Checking',
      'estimate_given' => 'Estimate given',
      'waiting_approval' => 'Waiting approval',
      'in_progress' => 'In progress',
      'waiting_parts' => 'Waiting for parts',
      'ready' => 'Ready for delivery',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      'returned_unrepaired' => 'Returned unrepaired',
      _ => status,
    };

const jobStatusColors = <String, Color>{
  'received': AppColors.indigo,
  'checking': AppColors.indigo,
  'estimate_given': AppColors.orange,
  'waiting_approval': AppColors.orange,
  'in_progress': AppColors.teal,
  'waiting_parts': AppColors.orange,
  'ready': AppColors.green,
  'delivered': AppColors.green,
  'cancelled': AppColors.red,
  'returned_unrepaired': AppColors.red,
};

class JobCardFilter {
  const JobCardFilter({this.search = '', this.status});
  final String search;
  final String? status;

  JobCardFilter copyWith({String? search, Object? status = _s}) => JobCardFilter(
        search: search ?? this.search,
        status: status == _s ? this.status : status as String?,
      );

  static const _s = Object();
}

final jobCardFilterProvider =
    NotifierProvider<JobCardFilterNotifier, JobCardFilter>(JobCardFilterNotifier.new);

class JobCardFilterNotifier extends Notifier<JobCardFilter> {
  @override
  JobCardFilter build() => const JobCardFilter();
  void set(JobCardFilter f) => state = f;
}

final jobCardsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final filter = ref.watch(jobCardFilterProvider);

  var query = client.from('job_cards').select();
  if (filter.search.trim().isNotEmpty) {
    final s = filter.search.trim();
    query = query.or('job_no.ilike.%$s%,customer_name.ilike.%$s%,item_name.ilike.%$s%,'
        'serial_no.ilike.%$s%,brand.ilike.%$s%,model.ilike.%$s%');
  }
  if (filter.status != null) query = query.eq('status', filter.status!);
  final rows =
      await query.order('created_at', ascending: false).limit(200);
  return List<Map<String, dynamic>>.from(rows);
});

/// Job card + its parts/labor line items, status history, and linked invoice.
final jobCardDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
  final client = ref.watch(supabaseProvider);
  final row = await client
      .from('job_cards')
      .select('*, invoices(invoice_no), job_card_items(*), job_status_history(*)')
      .eq('id', id)
      .single();
  return Map<String, dynamic>.from(row);
});
