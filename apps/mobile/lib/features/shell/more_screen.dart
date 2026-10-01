import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/crash_reporting.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';
import '../approvals/approvals_screen.dart';
import '../support/ticket_thread_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appContext = ref.watch(appContextProvider).value;
    final features = appContext;

    Widget tile(
      IconData icon,
      String title,
      String route, {
      bool enabled = true,
      String? subtitle,
      Color color = AppColors.indigo,
    }) {
      return ListTile(
        enabled: enabled,
        leading: IconChip(
          icon,
          color: enabled ? color : AppColors.inkSoft,
          size: 38,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 13)),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: appContext?.business?['logo_url'] != null
                  ? CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(
                        appContext!.business!['logo_url'] as String,
                      ),
                    )
                  : const IconChip(
                      Icons.storefront,
                      color: AppColors.primary,
                      size: 48,
                    ),
              title: Text(
                appContext?.businessName ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                appContext?.business?['phone'] as String? ?? '',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => context.push('/settings/business'),
            ),
          ),
          const SectionLabel('Sales'),
          Card(
            child: Column(
              children: [
                tile(
                  Icons.receipt_long_outlined,
                  'All invoices',
                  '/invoices',
                  color: AppColors.primary,
                ),
                const Divider(),
                tile(
                  Icons.assignment_return_outlined,
                  'Sale returns',
                  '/sale-returns',
                  color: AppColors.orange,
                  enabled: appContext?.canManageReturns ?? false,
                ),
                const Divider(),
                // D18: the owner's approval inbox; staff see their requests.
                Builder(
                  builder: (context) {
                    final isOwner = appContext?.isOwner ?? false;
                    final pending =
                        ref.watch(pendingApprovalCountProvider).value ?? 0;
                    return tile(
                      Icons.verified_user_outlined,
                      isOwner ? 'Approvals' : 'My approval requests',
                      '/approvals',
                      color: pending > 0 ? AppColors.red : AppColors.teal,
                      subtitle: isOwner
                          ? (pending > 0
                                ? '$pending waiting for you'
                                : 'Sales that need your OK')
                          : 'Sales waiting for the owner',
                    );
                  },
                ),
                const Divider(),
                tile(
                  Icons.people_outline,
                  'Customers',
                  '/customers',
                  color: AppColors.green,
                ),
              ],
            ),
          ),
          const SectionLabel('Inventory'),
          Card(
            child: Column(
              children: [
                tile(
                  Icons.warehouse_outlined,
                  'Stock',
                  '/stock',
                  color: AppColors.indigo,
                ),
                const Divider(),
                tile(
                  Icons.shopping_cart_outlined,
                  'Purchases',
                  '/purchases',
                  color: AppColors.teal,
                  enabled: appContext?.canManagePurchases ?? false,
                ),
                const Divider(),
                tile(
                  Icons.assignment_return_outlined,
                  'Purchase returns',
                  '/purchase-returns',
                  color: AppColors.orange,
                  enabled: appContext?.canManagePurchases ?? false,
                ),
                const Divider(),
                tile(
                  Icons.local_shipping_outlined,
                  'Suppliers',
                  '/suppliers',
                  color: AppColors.purple,
                  enabled: appContext?.canManagePurchases ?? false,
                ),
                const Divider(),
                tile(
                  Icons.upload_file_outlined,
                  'Import products (Excel)',
                  '/import',
                  color: AppColors.pink,
                  enabled:
                      (features?.featureOn('excel_import') ?? true) &&
                      (appContext?.canManageProducts ?? false),
                ),
              ],
            ),
          ),
          // Hidden for categories that don't do jobs (garment, hardware).
          if (appContext?.category.jobCards ?? true) ...[
            const SectionLabel('Services'),
            Card(
              child: Column(
                children: [
                  tile(
                    Icons.build_outlined,
                    'Service catalog',
                    '/services',
                    color: AppColors.indigo,
                    enabled:
                        (features?.featureOn('service_module') ?? true) &&
                        (appContext?.canManageServices ?? false),
                  ),
                  const Divider(),
                  tile(
                    Icons.assignment_outlined,
                    'Job cards',
                    '/job-cards',
                    color: AppColors.teal,
                    enabled:
                        (features?.featureOn('service_module') ?? true) &&
                        (appContext?.canManageServices ?? false),
                  ),
                ],
              ),
            ),
          ],
          const SectionLabel('Money'),
          Card(
            child: Column(
              children: [
                tile(
                  Icons.point_of_sale_outlined,
                  'Cashbook & day closing',
                  '/cashbook',
                  color: AppColors.green,
                  enabled: appContext?.canManageCash ?? false,
                  subtitle: 'Cash in the drawer, count and close the day',
                ),
                const Divider(),
                tile(
                  Icons.payments_outlined,
                  'Expenses',
                  '/expenses',
                  color: AppColors.red,
                  enabled:
                      (features?.featureOn('expense_module') ?? true) &&
                      (appContext?.canManageExpenses ?? false),
                ),
              ],
            ),
          ),
          if (appContext?.isOwner == true) ...[
            const SectionLabel('Store Management'),
            Card(
              child: Column(
                children: [
                  tile(
                    Icons.workspace_premium_outlined,
                    'Your Plan',
                    '/subscription/plans',
                    color: AppColors.primary,
                    enabled: true,
                    subtitle: 'What your plan includes, usage and other plans',
                  ),
                  const Divider(),
                  tile(
                    Icons.badge_outlined,
                    'Staff & Permissions',
                    '/staff',
                    color: AppColors.teal,
                    enabled: true,
                    subtitle: 'Manage store user accounts and permissions',
                  ),
                ],
              ),
            ),
          ],
          const SectionLabel('Other'),
          Card(
            child: Column(
              children: [
                tile(
                  Icons.sync_outlined,
                  'Pending offline bills',
                  '/offline-bills',
                  color: AppColors.orange,
                ),
                const Divider(),
                ListTile(
                  leading: const IconChip(
                    Icons.help_outline,
                    color: AppColors.purple,
                    size: 38,
                  ),
                  title: const Text(
                    'App walkthrough',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Replay the guided tour anytime',
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () async {
                    // Welcome tour anchors live on the dashboard tab.
                    context.go('/home');
                    await Future<void>.delayed(
                      const Duration(milliseconds: 250),
                    );
                    if (context.mounted) showWalkthrough(context, 'home');
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const IconChip(
                    Icons.chat,
                    color: Color(0xFF25D366),
                    size: 38,
                  ),
                  title: const Text(
                    'Contact Support on WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Get instant help or upgrade plan on WhatsApp',
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => launchWhatsAppContact(context, appContext),
                ),
                const Divider(),
                // Shows when SOFTRAXA has answered (migration 0054).
                Builder(
                  builder: (context) {
                    final unread = ref.watch(supportUnreadProvider).value ?? 0;
                    return tile(
                      Icons.support_agent_outlined,
                      'Support tickets',
                      '/support',
                      color: unread > 0 ? AppColors.red : AppColors.indigo,
                      subtitle: unread > 0
                          ? '$unread new repl${unread == 1 ? 'y' : 'ies'} from SOFTRAXA'
                          : null,
                    );
                  },
                ),
                const Divider(),
                if (kDebugMode && crashReportingEnabled) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.bug_report_outlined,
                      color: AppColors.orange,
                    ),
                    title: const Text('Verify Sentry setup'),
                    subtitle: const Text(
                      'Debug builds only: throws a test error',
                      style: TextStyle(fontSize: 13),
                    ),
                    onTap: () => throw StateError('This is test exception'),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: AppColors.red),
                  ),
                  onTap: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Logout',
                      message: 'Are you sure you want to logout?',
                      confirmText: 'Logout',
                    );
                    if (ok) await ref.read(supabaseProvider).auth.signOut();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
