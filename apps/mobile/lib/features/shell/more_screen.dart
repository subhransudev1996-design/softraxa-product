import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appContext = ref.watch(appContextProvider).value;
    final features = appContext;

    Widget tile(IconData icon, String title, String route,
        {bool enabled = true, String? subtitle, Color color = AppColors.indigo}) {
      return ListTile(
        enabled: enabled,
        leading: IconChip(icon, color: enabled ? color : AppColors.inkSoft, size: 38),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: enabled
            ? const Icon(Icons.chevron_right, size: 20)
            : const Icon(Icons.lock_outline, size: 18),
        onTap: enabled ? () => context.push(route) : null,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: appContext?.business?['logo_url'] != null
                  ? CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(appContext!.business!['logo_url'] as String),
                    )
                  : const IconChip(Icons.storefront, color: AppColors.primary, size: 48),
              title: Text(appContext?.businessName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              subtitle: Text(appContext?.business?['phone'] as String? ?? '',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => context.push('/settings/business'),
            ),
          ),
          const SectionLabel('Sales'),
          Card(
            child: Column(children: [
              tile(Icons.receipt_long_outlined, 'All invoices', '/invoices',
                  color: AppColors.primary),
              const Divider(),
              tile(Icons.assignment_return_outlined, 'Sale returns', '/sale-returns',
                  color: AppColors.orange),
              const Divider(),
              tile(Icons.people_outline, 'Customers', '/customers',
                  color: AppColors.green),
            ]),
          ),
          const SectionLabel('Inventory'),
          Card(
            child: Column(children: [
              tile(Icons.warehouse_outlined, 'Stock', '/stock',
                  color: AppColors.indigo),
              const Divider(),
              tile(Icons.shopping_cart_outlined, 'Purchases', '/purchases',
                  color: AppColors.teal),
              const Divider(),
              tile(Icons.assignment_return_outlined, 'Purchase returns', '/purchase-returns',
                  color: AppColors.orange),
              const Divider(),
              tile(Icons.local_shipping_outlined, 'Suppliers', '/suppliers',
                  color: AppColors.purple),
              const Divider(),
              tile(Icons.upload_file_outlined, 'Import products (Excel)', '/import',
                  color: AppColors.pink,
                  enabled: features?.featureOn('excel_import') ?? true),
            ]),
          ),
          const SectionLabel('Services'),
          Card(
            child: Column(children: [
              tile(Icons.build_outlined, 'Service catalog', '/services',
                  color: AppColors.indigo,
                  enabled: features?.featureOn('service_module') ?? true),
              const Divider(),
              tile(Icons.assignment_outlined, 'Job cards', '/job-cards',
                  color: AppColors.teal,
                  enabled: features?.featureOn('service_module') ?? true),
            ]),
          ),
          const SectionLabel('Money'),
          Card(
            child: Column(children: [
              tile(Icons.payments_outlined, 'Expenses', '/expenses',
                  color: AppColors.red,
                  enabled: features?.featureOn('expense_module') ?? true),
            ]),
          ),
          const SectionLabel('Other'),
          Card(
            child: Column(children: [
              tile(Icons.sync_outlined, 'Pending offline bills', '/offline-bills',
                  color: AppColors.orange),
              const Divider(),
              tile(Icons.support_agent_outlined, 'Support', '/support',
                  color: AppColors.indigo),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.red),
                title: const Text('Logout', style: TextStyle(color: AppColors.red)),
                onTap: () async {
                  final ok = await confirmDialog(context,
                      title: 'Logout', message: 'Are you sure you want to logout?', confirmText: 'Logout');
                  if (ok) await ref.read(supabaseProvider).auth.signOut();
                },
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
