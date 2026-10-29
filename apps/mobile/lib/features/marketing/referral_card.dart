import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

/// The shop's referral code and what it has earned (migration 0101). Null
/// before 0101 — the card doesn't show.
final referralProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  try {
    final r = await ref.watch(supabaseProvider).rpc('my_referral');
    return r == null ? null : Map<String, dynamic>.from(r as Map);
  } catch (_) {
    return null;
  }
});

/// "Refer a shop": the owner shares the code; a friend who joins with it
/// and pays earns free months. A new shop can also enter a friend's code
/// or an influencer partner's code (migration 0104).
/// No prices are shown.
class ReferralCard extends ConsumerStatefulWidget {
  const ReferralCard({super.key});

  @override
  ConsumerState<ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends ConsumerState<ReferralCard> {
  final _code = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _saving = true);
    try {
      final name = await ref
          .read(supabaseProvider)
          .rpc('apply_referral_code', params: {'p_code': code});
      ref.invalidate(referralProvider);
      if (mounted) {
        showSuccess(context, t('Saved — referred by {v1}', {'v1': name}));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(referralProvider).value;
    if (r == null || (r['code'] as String? ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    final code = r['code'] as String;
    final months = (r['reward_months'] as num?)?.toInt() ?? 0;
    final joined = (r['joined'] as num?)?.toInt() ?? 0;
    final earned = (r['months_earned'] as num?)?.toInt() ?? 0;
    final referredBy = r['referred_by'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.card_giftcard_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  t('Refer a shop'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              months > 0
                  ? t(
                      'When a shop joins with your code and takes a plan, you get {v1} month(s) free.',
                      {'v1': months},
                    )
                  : t('Share your code with other shop owners.'),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      code,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => sendWhatsAppText(
                    '',
                    t(
                      'I use Dukania for billing and stock in my shop. Try it free — enter my code {v1} in the app (Plan screen) when you join.',
                      {'v1': code},
                    ),
                  ),
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(t('Share')),
                ),
              ],
            ),
            if (joined > 0 || earned > 0) ...[
              const SizedBox(height: 10),
              Text(
                t(
                  '{v1} shop(s) joined with your code · {v2} free month(s) so far',
                  {'v1': joined, 'v2': earned},
                ),
                style: TextStyle(fontSize: 13, color: AppColors.ink),
              ),
            ],
            if (referredBy != null) ...[
              const SizedBox(height: 10),
              Text(
                t('You joined with the code of {v1}.', {'v1': referredBy}),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ] else if (r['can_enter'] == true) ...[
              const Divider(height: 28),
              Text(
                t(
                  'Got a code from a shop or someone you follow? Enter it here.',
                ),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'DKAB2CD / RAHUL10',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _saving ? null : _apply,
                    child: Text(t('Save')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
