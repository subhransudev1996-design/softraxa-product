import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Reports hub (PRD 7.16).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  static const _reports = [
    (
      'sales',
      'Sales report',
      'Today, monthly or custom range',
      Icons.trending_up,
      AppColors.green,
    ),
    (
      'products',
      'Product-wise sales',
      'Best sellers, revenue & profit per product',
      Icons.inventory_2_outlined,
      AppColors.indigo,
    ),
    (
      'profit',
      'Profit report',
      'Sales, cost, expenses and net profit',
      Icons.account_balance_wallet_outlined,
      AppColors.teal,
    ),
    (
      'stock',
      'Stock report',
      'Current stock and value',
      Icons.warehouse_outlined,
      AppColors.primary,
    ),
    (
      'low_stock',
      'Low stock report',
      'Products that need reordering',
      Icons.warning_amber,
      AppColors.orange,
    ),
    (
      'customer_due',
      'Customer due report',
      'Who owes you money',
      Icons.people_outline,
      AppColors.red,
    ),
    (
      'supplier_due',
      'Supplier due report',
      'Who you owe money to',
      Icons.local_shipping_outlined,
      AppColors.purple,
    ),
    (
      'purchases',
      'Purchase report',
      'Purchases in a period',
      Icons.shopping_cart_outlined,
      AppColors.teal,
    ),
    (
      'expenses',
      'Expense report',
      'Spending by category',
      Icons.payments_outlined,
      AppColors.pink,
    ),
    (
      'gst',
      'GST report',
      'Output & input tax by rate',
      Icons.receipt_long_outlined,
      AppColors.indigo,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(appContextProvider).value;
    final enabled = features?.featureOn('reports') ?? true;
    final allowed = features?.canViewReports ?? false;
    // Reports whose data needs an extra permission (the server refuses
    // them otherwise — migration 0037 report wrappers and table policies).
    final reports = [
      for (final r in _reports)
        if (switch (r.$1) {
          'profit' => features?.canViewProfit ?? false,
          'purchases' || 'supplier_due' => features?.canManagePurchases ?? false,
          'expenses' => features?.canManageExpenses ?? false,
          _ => true,
        })
          r,
    ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Reports'),
        actions: const [GuideButton('reports')],
      ),
      body: !enabled
          ? const Center(child: Text('Reports are not enabled on your plan.'))
          : !allowed
          ? const EmptyState(
              icon: Icons.lock_outline,
              message: 'Ask the shop owner for permission to view reports.',
            )
          : CoachTarget(
              page: 'reports',
              id: 'list',
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = reports[i];
                  return Card(
                    child: ListTile(
                      leading: IconChip(r.$4, color: r.$5, size: 40),
                      title: Text(
                        r.$2,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        r.$3,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push('/reports/${r.$1}'),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
