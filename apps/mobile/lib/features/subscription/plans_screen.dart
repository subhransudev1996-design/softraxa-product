import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

final activePlansProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final rows = await client
      .from('plans')
      .select('*, software:software_products(name)')
      .eq('is_active', true)
      .order('monthly_price');
  return List<Map<String, dynamic>>.from(rows);
});

const kFeatureLabels = <String, String>{
  'gst_billing': 'GST Billing',
  'reports': 'Reports & Analytics',
  'pdf_invoice': 'PDF Invoices',
  'a4_print': 'A4 Printing',
  'thermal_print': 'Thermal Printing',
  'offline_billing': 'Offline Billing',
  'expense_module': 'Expense Tracking',
  'excel_import': 'Excel Product Import',
  'service_module': 'Services & Job Cards',
};

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _isYearly = false;

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(activePlansProvider);
    final appContext = ref.watch(appContextProvider).value;
    final currentPlanId = appContext?.subscription?['plan_id'] as String?;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Subscription Plans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(activePlansProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activePlansProvider),
        child: AsyncView(
          value: plansAsync,
          onRetry: () => ref.invalidate(activePlansProvider),
          builder: (plans) {
            if (plans.isEmpty) {
              return const EmptyState(
                icon: Icons.workspace_premium_outlined,
                message: 'No subscription plans published yet.\nContact support for custom pricing.',
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.verified_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Choose Your Plan',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  appContext?.businessName.isNotEmpty == true
                                      ? 'Selected plan will be configured for ${appContext!.businessName}'
                                      : 'Select a plan to upgrade your store',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Billing cycle toggle
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isYearly = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !_isYearly ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Monthly Billing',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: !_isYearly ? AppColors.primaryDark : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isYearly = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _isYearly ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Yearly Billing 🌟',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: _isYearly ? AppColors.primaryDark : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Plans list
                ...plans.map((p) {
                  final isCurrent = currentPlanId == p['id'];
                  final monthlyPrice = (p['monthly_price'] as num?)?.toDouble() ?? 0;
                  final yearlyPrice = (p['yearly_price'] as num?)?.toDouble() ?? 0;
                  final displayPrice = _isYearly ? yearlyPrice : monthlyPrice;
                  final userLimit = (p['user_limit'] as num?)?.toInt();
                  final incFeatures = List<String>.from(p['included_features'] as List? ?? []);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.primary
                            : (p['is_custom'] == true ? Colors.amber.shade400 : AppColors.line),
                        width: isCurrent ? 2 : 1,
                      ),
                      boxShadow: softShadow(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          p['name'] as String? ?? 'Plan',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.green.shade300),
                                            ),
                                            child: Text(
                                              'CURRENT PLAN',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (p['notes'] != null && (p['notes'] as String).isNotEmpty)
                                      Text(
                                        p['notes'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.inkSoft,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    displayPrice > 0 ? money(displayPrice) : 'Custom',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  Text(
                                    _isYearly ? '/ year' : '/ month',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Specs summary
                          Row(
                            children: [
                              _SpecBadge(
                                icon: Icons.badge_outlined,
                                label: userLimit == null
                                    ? 'Unlimited Staff'
                                    : 'Up to $userLimit Staff',
                              ),
                              const SizedBox(width: 8),
                              _SpecBadge(
                                icon: Icons.inventory_2_outlined,
                                label: p['product_limit'] == null
                                    ? 'Unlimited Products'
                                    : '${p['product_limit']} Products',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Included features checklist
                          Text(
                            'Included Features:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.inkSoft,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (incFeatures.isEmpty)
                            const Text('All features included')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: incFeatures.map((fKey) {
                                final label = kFeatureLabels[fKey] ?? fKey;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 18),

                          // Action button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCurrent ? Colors.grey.shade200 : const Color(0xFF25D366),
                                foregroundColor: isCurrent ? Colors.black87 : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                isCurrent ? Icons.check : Icons.chat,
                                size: 18,
                              ),
                              label: Text(
                                isCurrent
                                    ? 'Active Subscription'
                                    : 'Subscribe to ${p['name']} on WhatsApp',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              onPressed: () {
                                final cycleStr = _isYearly ? 'Yearly (${money(yearlyPrice)}/yr)' : 'Monthly (${money(monthlyPrice)}/mo)';
                                launchWhatsAppContact(
                                  context,
                                  appContext,
                                  customReason: 'I would like to subscribe to the *${p['name']}* plan ($cycleStr) for my store.',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpecBadge extends StatelessWidget {
  const _SpecBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
