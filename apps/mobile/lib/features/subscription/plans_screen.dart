import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// This shop's plan with its usage, and the plans it can ask for
/// (get_plans_for_app, migration 0055). Prices never reach the app:
/// SOFTRAXA agrees them with each shop.
final plansForAppProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final res = await ref.watch(supabaseProvider).rpc('get_plans_for_app');
  return Map<String, dynamic>.from((res ?? const {}) as Map);
});

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  String? _busyPlan;

  /// Sends the request to SOFTRAXA as a support request (request_plan_change).
  Future<void> _ask(Map<String, dynamic> plan) async {
    final id = plan['id'] as String;
    setState(() => _busyPlan = id);
    try {
      await ref
          .read(supabaseProvider)
          .rpc('request_plan_change', params: {'p_plan': id});
      ref.invalidate(plansForAppProvider);
      if (mounted) {
        showSuccess(
          context,
          'Request sent — SOFTRAXA will contact you about the ${plan['name']} plan',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansForAppProvider);
    final appContext = ref.watch(appContextProvider).value;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Your plan')),
        actions: [
          IconButton(
            tooltip: t('Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(plansForAppProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(plansForAppProvider),
        child: AsyncView(
          value: plans,
          onRetry: () => ref.invalidate(plansForAppProvider),
          builder: (d) {
            final current = Map<String, dynamic>.from(
              (d['current'] as Map?) ?? const {},
            );
            final others = [
              for (final p in (d['plans'] as List? ?? const []))
                Map<String, dynamic>.from(p as Map),
            ];
            final requested = d['requested_plan_id'] as String?;
            final support = d['support_whatsapp'] as String? ?? '';

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CurrentPlanCard(
                          current: current,
                          state: appContext?.subscriptionState ?? 'active',
                        ),
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(t('Other plans'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final p in others)
                            _PlanCard(
                              plan: p,
                              requested: requested == p['id'],
                              busy: _busyPlan == p['id'],
                              onAsk: () => _ask(p),
                            ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => launchWhatsAppContact(
                            context,
                            appContext,
                            number: support,
                            customReason:
                                'I would like to know more about the Dukania plans for my shop.',
                          ),
                          icon: const Icon(Icons.chat_outlined),
                          label: Text(t('Talk to SOFTRAXA on WhatsApp')),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The shop's own plan: name, validity, how much of each limit is used and
/// what is included.
class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.current, required this.state});
  final Map<String, dynamic> current;

  /// active | trial | expired | suspended, with grace days applied.
  final String state;

  @override
  Widget build(BuildContext context) {
    final plan = current['plan'] == null
        ? null
        : Map<String, dynamic>.from(current['plan'] as Map);
    final usage = Map<String, dynamic>.from(
      (current['usage'] as Map?) ?? const {},
    );
    final expiry = current['expiry_date'];
    final name =
        plan?['name'] as String? ??
        (state == 'trial' ? 'Free trial' : 'No plan');
    final description = plan?['description'] as String? ?? '';
    final (label, color) = switch (state) {
      'trial' => ('TRIAL', AppColors.orange),
      'expired' => ('EXPIRED', AppColors.red),
      'suspended' => ('SUSPENDED', AppColors.red),
      _ => ('ACTIVE', AppColors.green),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: softShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                if (expiry != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state == 'expired'
                        ? 'Expired on ${dateStr(expiry)}'
                        : 'Valid until ${dateStr(expiry)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UsageRow(
                  icon: Icons.badge_outlined,
                  label: t('Users (owner + staff)'),
                  used: (usage['users'] as num?)?.toInt() ?? 0,
                  limit: (usage['user_limit'] as num?)?.toInt(),
                ),
                _UsageRow(
                  icon: Icons.inventory_2_outlined,
                  label: t('Products'),
                  used: (usage['products'] as num?)?.toInt() ?? 0,
                  limit: (usage['product_limit'] as num?)?.toInt(),
                ),
                _UsageRow(
                  icon: Icons.receipt_long_outlined,
                  label: t('Bills this month'),
                  used: (usage['bills_this_month'] as num?)?.toInt() ?? 0,
                  limit: (usage['invoice_limit'] as num?)?.toInt(),
                ),
                if (plan != null) ...[
                  const Divider(height: 24),
                  _PlanDetails(plan: plan),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Products — 120 of 500" with a bar; no bar when the limit is unlimited.
class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.icon,
    required this.label,
    required this.used,
    required this.limit,
  });
  final IconData icon;
  final String label;
  final int used;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final max = limit;
    final full = max != null && used >= max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                max == null ? '$used · unlimited' : '$used of $max',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: full ? AppColors.red : AppColors.inkSoft,
                ),
              ),
            ],
          ),
          if (max != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max == 0 ? 1 : (used / max).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: AppColors.line,
                color: full ? AppColors.red : AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A plan the shop can ask for.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.requested,
    required this.busy,
    required this.onAsk,
  });
  final Map<String, dynamic> plan;
  final bool requested;
  final bool busy;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final recommended = plan['is_recommended'] == true;
    final description = plan['description'] as String? ?? '';
    final users = (plan['user_limit'] as num?)?.toInt();
    final products = (plan['product_limit'] as num?)?.toInt();
    final bills = (plan['invoice_limit'] as num?)?.toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: recommended ? AppColors.primary : AppColors.line,
          width: recommended ? 1.5 : 1,
        ),
        boxShadow: softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan['name'] as String? ?? 'Plan',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (recommended)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(t('RECOMMENDED'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LimitChip(
                icon: Icons.badge_outlined,
                label: users == null
                    ? 'Unlimited users'
                    : users == 1
                    ? '1 user (owner only)'
                    : '$users users (owner + ${users - 1} staff)',
              ),
              _LimitChip(
                icon: Icons.inventory_2_outlined,
                label: products == null
                    ? 'Unlimited products'
                    : '$products products',
              ),
              _LimitChip(
                icon: Icons.receipt_long_outlined,
                label: bills == null
                    ? 'Unlimited bills'
                    : '$bills bills a month',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PlanDetails(plan: plan),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: requested
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.hourglass_top, size: 18),
                    label: Text(t('Requested — SOFTRAXA will contact you')),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : onAsk,
                    icon: const Icon(Icons.north_east, size: 18),
                    label: Text(busy ? 'Sending…' : 'Ask for this plan'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The highlight lines SOFTRAXA wrote for the plan, then every feature of
/// the app marked included or not.
class _PlanDetails extends StatelessWidget {
  const _PlanDetails({required this.plan});
  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final highlights = [
      for (final h in (plan['highlights'] as List? ?? const [])) h.toString(),
    ];
    final features = [
      for (final f in (plan['features'] as List? ?? const []))
        Map<String, dynamic>.from(f as Map),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in highlights)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.star, size: 14, color: AppColors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    h,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (highlights.isNotEmpty && features.isNotEmpty)
          const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final f in features)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    f['included'] == true
                        ? Icons.check_circle
                        : Icons.remove_circle_outline,
                    size: 15,
                    color: f['included'] == true
                        ? AppColors.green
                        : AppColors.hint,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    f['label'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: f['included'] == true
                          ? AppColors.ink
                          : AppColors.hint,
                      decoration: f['included'] == true
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _LimitChip extends StatelessWidget {
  const _LimitChip({required this.icon, required this.label});
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
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
