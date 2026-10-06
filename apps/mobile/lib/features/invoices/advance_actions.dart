import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../customers/customer_providers.dart';
import '../dashboard/dashboard_screen.dart';
import 'invoice_providers.dart';

/// Uses the customer's advance on a bill (apply_customer_advance, migration
/// 0041) after the user confirms — advances are never used automatically
/// (PD22). Returns true when something was applied.
Future<bool> applyAdvanceToInvoice(
  BuildContext context,
  WidgetRef ref, {
  required String invoiceId,
  required double amount,
  bool confirm = true,
  String? customerName,
}) async {
  if (confirm) {
    final ok = await confirmDialog(
      context,
      title: t('Use advance?'),
      message:
          '${customerName ?? t('This customer')} has an advance. Use ${money(amount)} '
          'of it to pay this bill? This is not a new cash receipt.',
      confirmText: t('Use {v1}', {'v1': money(amount)}),
    );
    if (!ok || !context.mounted) return false;
  }
  try {
    final res = await ref
        .read(supabaseProvider)
        .rpc(
          'apply_customer_advance',
          params: {'p_invoice_id': invoiceId, 'p_amount': amount},
        );
    ref.invalidate(invoiceDetailProvider(invoiceId));
    ref.invalidate(invoicesProvider);
    ref.invalidate(customersProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(recentInvoicesProvider);
    if (context.mounted) {
      showSuccess(
        context,
        t('Advance of {v1} used on this bill', {'v1': money(toDouble((res as Map)['applied']))}),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
