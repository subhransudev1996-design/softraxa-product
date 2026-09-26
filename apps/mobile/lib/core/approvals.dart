import 'dart:convert';

import 'formatters.dart';

/// Owner approvals (migration 0044): a sale that breaks a rule is refused
/// with "APPROVAL_REQUIRED [ ...exceptions... ]". These helpers read that
/// list and describe each exception in plain words.

/// The exceptions in an APPROVAL_REQUIRED error, or null for other errors.
List<Map<String, dynamic>>? approvalExceptions(Object error) {
  final s = error.toString();
  final at = s.indexOf('APPROVAL_REQUIRED');
  if (at < 0) return null;
  final start = s.indexOf('[', at);
  final end = s.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  try {
    final list = jsonDecode(s.substring(start, end + 1)) as List;
    return [for (final e in list) Map<String, dynamic>.from(e as Map)];
  } catch (_) {
    return const [];
  }
}

/// Short title for an exception kind.
String exceptionTitle(String? kind) => switch (kind) {
  'below_cost' => 'Below cost',
  'credit_limit' => 'Over credit limit',
  'overdue' => 'Customer has overdue bills',
  'discount' => 'Discount over the staff limit',
  _ => 'Needs approval',
};

/// One-line explanation. Cost figures appear only when the server sent them
/// (staff without the profit permission don't get them).
String describeException(Map<String, dynamic> e) {
  switch (e['kind']) {
    case 'below_cost':
      final lines = [
        for (final l in (e['lines'] as List? ?? const []))
          (l as Map).containsKey('cost')
              ? '${l['product_name']} × ${qty(l['quantity'] as num?)} at '
                    '${money(l['price'] as num?)} (cost ${money(l['cost'] as num?)})'
              : '${l['product_name']} × ${qty(l['quantity'] as num?)}',
      ];
      final loss = e['loss'] == null ? '' : ' — loss ${money(e['loss'] as num?)}';
      return 'Sold below cost: ${lines.join(', ')}$loss';
    case 'credit_limit':
      return 'Customer would owe ${money(e['exposure_after'] as num?)} '
          '(after advances) — limit ${money(e['limit'] as num?)}';
    case 'overdue':
      return 'Customer has ${money(e['overdue_amount'] as num?)} overdue on '
          '${e['bills']} bill(s) since ${dateStr(e['oldest_due'])}; this adds '
          '${money(e['new_due'] as num?)} more credit';
    case 'discount':
      return 'Bill is ${money(e['reduction'] as num?)} (${qty(e['pct'] as num?)}%) '
          'below default prices — staff limit ${qty(e['limit_pct'] as num?)}%';
    default:
      return exceptionTitle(e['kind'] as String?);
  }
}

String approvalSummary(List<Map<String, dynamic>> exceptions) =>
    exceptions.map(describeException).join('; ');

/// Status label for a request.
String approvalStatusLabel(String? status) => switch (status) {
  'pending' => 'Waiting for owner',
  'approved' => 'Approved — complete the sale',
  'rejected' => 'Rejected',
  'withdrawn' => 'Withdrawn',
  'consumed' => 'Completed',
  'expired' => 'Expired',
  'flagged' => 'Offline bill — owner to review',
  'reviewed' => 'Reviewed',
  _ => status ?? '',
};
