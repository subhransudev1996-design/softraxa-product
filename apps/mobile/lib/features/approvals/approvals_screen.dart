import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/approvals.dart';
import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../pos/cart.dart';
import '../pos/pos_providers.dart';
import 'approval_dialogs.dart';

/// Owner approval inbox and staff requests (D17–D19, migration 0044).

/// Owner: requests waiting for a decision, offline bills to review, and
/// the last week's decisions.
final ownerApprovalsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('sale_approvals')
          .select(
            '*, customers(name), '
            'requester:profiles!sale_approvals_requested_by_fkey(full_name)',
          )
          .gte('created_at', DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(rows);
    });

/// Staff: their own requests (no cost details unless allowed).
final myApprovalsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final res = await ref.watch(supabaseProvider).rpc('my_sale_approvals');
      return List<Map<String, dynamic>>.from(res as List? ?? const []);
    });

/// Pending decisions for the owner's badge (in-app is authoritative, PD13).
final pendingApprovalCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final ctx = ref.watch(appContextProvider).value;
  if (!(ctx?.isOwner ?? false)) return 0;
  final rows = await ref
      .watch(supabaseProvider)
      .from('sale_approvals')
      .select('id, status, expires_at')
      .inFilter('status', ['pending', 'flagged']);
  final now = DateTime.now();
  return [
    for (final r in List<Map<String, dynamic>>.from(rows))
      if (r['status'] == 'flagged' ||
          (DateTime.tryParse('${r['expires_at']}')?.isAfter(now) ?? true))
        r,
  ].length;
});

/// A request's effective status: pending/approved past expiry = expired.
String effectiveApprovalStatus(Map<String, dynamic> r) {
  final s = r['status'] as String? ?? '';
  final exp = DateTime.tryParse('${r['expires_at']}');
  if ((s == 'pending' || s == 'approved') && exp != null && exp.isBefore(DateTime.now())) {
    return 'expired';
  }
  return s;
}

/// Rebuilds a cart from a stored sale payload, to revise a rejected sale.
CartState cartFromSalePayload(Map<String, dynamic> payload) {
  final items = [
    for (final (i, it) in List<Map<String, dynamic>>.from(payload['items'] as List? ?? const []).indexed)
      {...it, 'id': 'req$i'},
  ];
  return CartState(
    lines: invoiceItemsToCartLines(items),
    billDiscount: toDouble(payload['discount_amount']),
  );
}

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(appContextProvider).value?.isOwner ?? false;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(isOwner ? 'Approvals' : 'My approval requests'),
      ),
      body: isOwner ? const _OwnerInbox() : const _MyRequests(),
    );
  }
}

// ---------------------------------------------------------------- owner

class _OwnerInbox extends ConsumerWidget {
  const _OwnerInbox();

  Future<void> _decide(BuildContext context, WidgetRef ref, Map<String, dynamic> r, bool approve) async {
    final exceptions = List<Map<String, dynamic>>.from(r['exceptions'] as List? ?? const []);
    final note = TextEditingController();
    final ticked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final all = exceptions.every((e) => ticked.contains(e['kind']));
          return AlertDialog(
            title: Text(approve ? 'Approve this sale?' : 'Reject this sale?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (approve)
                    ExceptionCheckList(
                      exceptions: exceptions,
                      ticked: ticked,
                      onChanged: (k, v) => setState(() => v ? ticked.add(k) : ticked.remove(k)),
                    ),
                  TextField(
                    controller: note,
                    decoration: InputDecoration(
                      labelText: approve ? 'Note (optional)' : 'Tell staff why',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: approve ? null : FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: !approve || all ? () => Navigator.pop(ctx, true) : null,
                child: Text(approve ? 'Approve' : 'Reject'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(supabaseProvider).rpc('decide_sale_approval', params: {
        'p_id': r['id'],
        'p_approve': approve,
        'p_note': note.text.trim(),
        'p_ticked': ticked.toList(),
      });
      ref.invalidate(ownerApprovalsProvider);
      ref.invalidate(pendingApprovalCountProvider);
      if (context.mounted) showSuccess(context, approve ? 'Approved' : 'Rejected');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _markReviewed(BuildContext context, WidgetRef ref, Map<String, dynamic> r) async {
    try {
      await ref.read(supabaseProvider).rpc('decide_sale_approval', params: {
        'p_id': r['id'],
        'p_approve': true,
        'p_note': 'Reviewed',
      });
      ref.invalidate(ownerApprovalsProvider);
      ref.invalidate(pendingApprovalCountProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(ownerApprovalsProvider);
    return AsyncView(
      value: data,
      onRetry: () => ref.invalidate(ownerApprovalsProvider),
      builder: (rows) {
        final open = [
          for (final r in rows)
            if (effectiveApprovalStatus(r) == 'pending' || r['status'] == 'flagged') r,
        ];
        final done = [for (final r in rows) if (!open.contains(r)) r];
        if (rows.isEmpty) {
          return const EmptyState(icon: Icons.verified_outlined, message: 'Nothing to approve');
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(ownerApprovalsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (open.isNotEmpty) const SectionLabel('Waiting for you'),
              for (final r in open)
                _ApprovalCard(
                  r: r,
                  customerName: (r['customers'] as Map?)?['name'] as String?,
                  requester: (r['requester'] as Map?)?['full_name'] as String?,
                  actions: r['status'] == 'flagged'
                      ? [
                          FilledButton(
                            onPressed: () => _markReviewed(context, ref, r),
                            child: const Text('Mark reviewed'),
                          ),
                        ]
                      : [
                          OutlinedButton(
                            onPressed: () => _decide(context, ref, r, false),
                            child: const Text('Reject'),
                          ),
                          FilledButton(
                            onPressed: () => _decide(context, ref, r, true),
                            child: const Text('Approve'),
                          ),
                        ],
                ),
              if (done.isNotEmpty) const SectionLabel('Last 7 days'),
              for (final r in done)
                _ApprovalCard(
                  r: r,
                  customerName: (r['customers'] as Map?)?['name'] as String?,
                  requester: (r['requester'] as Map?)?['full_name'] as String?,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- staff

class _MyRequests extends ConsumerWidget {
  const _MyRequests();

  Future<void> _complete(BuildContext context, WidgetRef ref, Map<String, dynamic> r) async {
    try {
      final res = Map<String, dynamic>.from(
        await ref.read(supabaseProvider).rpc('complete_approved_sale', params: {'p_id': r['id']}) as Map,
      );
      ref.invalidate(myApprovalsProvider);
      if (context.mounted) {
        showSuccess(context, 'Bill ${res['invoice_no'] ?? ''} created');
        context.push('/invoices/${res['id']}?new=1');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref, Map<String, dynamic> r) async {
    try {
      await ref.read(supabaseProvider).rpc('withdraw_sale_approval', params: {'p_id': r['id']});
      ref.invalidate(myApprovalsProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Load the sale back into the POS to change it (D18: a rejected sale
  /// can be revised; it is checked again at checkout).
  Future<void> _revise(BuildContext context, WidgetRef ref, Map<String, dynamic> r) async {
    final payload = Map<String, dynamic>.from(r['payload'] as Map? ?? const {});
    ref.read(editingInvoiceProvider.notifier).set(null);
    ref.read(cartProvider.notifier).replaceAll(cartFromSalePayload(payload));
    final customerId = payload['customer_id'] as String?;
    if (customerId != null) {
      try {
        final customer = await ref
            .read(supabaseProvider)
            .from('customers')
            .select('id, name, phone, address, due_amount, advance_amount, credit_limit, is_wholesale')
            .eq('id', customerId)
            .single();
        await setCartCustomer(ref, Map<String, dynamic>.from(customer));
      } catch (_) {}
    }
    if ((r['status'] as String?) == 'pending' || r['status'] == 'approved') {
      try {
        await ref.read(supabaseProvider).rpc('withdraw_sale_approval', params: {'p_id': r['id']});
      } catch (_) {}
    }
    ref.invalidate(myApprovalsProvider);
    if (context.mounted) context.go('/pos');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myApprovalsProvider);
    return AsyncView(
      value: data,
      onRetry: () => ref.invalidate(myApprovalsProvider),
      builder: (rows) {
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.hourglass_empty,
            message: 'No approval requests in the last 7 days',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myApprovalsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final r in rows)
                _ApprovalCard(
                  r: r,
                  customerName: r['customer_name'] as String?,
                  actions: switch (effectiveApprovalStatus(r)) {
                    'approved' => [
                      OutlinedButton(
                        onPressed: () => _withdraw(context, ref, r),
                        child: const Text('Withdraw'),
                      ),
                      FilledButton(
                        onPressed: () => _complete(context, ref, r),
                        child: const Text('Complete sale'),
                      ),
                    ],
                    'pending' => [
                      OutlinedButton(
                        onPressed: () => _withdraw(context, ref, r),
                        child: const Text('Withdraw'),
                      ),
                      OutlinedButton(
                        onPressed: () => _revise(context, ref, r),
                        child: const Text('Change the sale'),
                      ),
                    ],
                    'rejected' || 'expired' || 'withdrawn' => [
                      OutlinedButton(
                        onPressed: () => _revise(context, ref, r),
                        child: const Text('Change the sale'),
                      ),
                    ],
                    'consumed' => [
                      TextButton(
                        onPressed: () => context.push('/invoices/${r['invoice_id']}'),
                        child: const Text('Open bill'),
                      ),
                    ],
                    _ => const [],
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- card

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.r,
    this.customerName,
    this.requester,
    this.actions = const [],
  });

  final Map<String, dynamic> r;
  final String? customerName;
  final String? requester;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final status = effectiveApprovalStatus(r);
    final exceptions = List<Map<String, dynamic>>.from(r['exceptions'] as List? ?? const []);
    final color = switch (status) {
      'approved' || 'consumed' || 'reviewed' => AppColors.green,
      'rejected' || 'expired' => AppColors.red,
      'pending' || 'flagged' => AppColors.orange,
      _ => AppColors.inkSoft,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (customerName?.isNotEmpty ?? false) ? customerName! : 'Walk-in customer',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Text(money(r['total'] as num?), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                approvalStatusLabel(status),
                if (requester != null) 'by $requester',
                dateTimeStr(r['created_at']),
              ].join(' • '),
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final e in exceptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.orange),
                    const SizedBox(width: 6),
                    Expanded(child: Text(describeException(e), style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            if ((r['reason'] as String? ?? '').isNotEmpty)
              Text('Reason: ${r['reason']}', style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            if ((r['decision_note'] as String? ?? '').isNotEmpty)
              Text('Owner: ${r['decision_note']}', style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.end, spacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
