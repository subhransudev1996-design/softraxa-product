import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Ask the owner now? (migration 0102: after 14 days, then every 90 days;
/// "Not now" waits 30.) False before 0102 or offline.
final recommendDueProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(supabaseProvider).rpc('nps_due') == true;
  } catch (_) {
    return false;
  }
});

/// "How likely are you to recommend Dukania?" 0–10 on the home screen,
/// with an optional comment. Dukania's team reads the answers.
class RecommendCard extends ConsumerStatefulWidget {
  const RecommendCard({super.key, required this.padding});

  final EdgeInsets padding;

  @override
  ConsumerState<RecommendCard> createState() => _RecommendCardState();
}

class _RecommendCardState extends ConsumerState<RecommendCard> {
  int? _score;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send(int? score) async {
    setState(() => _sending = true);
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'submit_nps',
            params: {'p_score': score, 'p_comment': _comment.text.trim()},
          );
      if (mounted && score != null) {
        showSuccess(context, t('Thank you! It helps us make Dukania better.'));
      }
    } catch (_) {
      // Asked again another day.
    }
    ref.invalidate(recommendDueProvider);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(recommendDueProvider).value != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.padding,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  'How likely are you to recommend Dukania to another shop owner?',
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t('0 = not at all, 10 = surely'),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i <= 10; i++)
                    ChoiceChip(
                      label: Text('$i'),
                      selected: _score == i,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _score = i),
                    ),
                ],
              ),
              if (_score != null) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _comment,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: _score! <= 6
                        ? t('What should we fix? (optional)')
                        : t('What do you like most? (optional)'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _sending ? null : () => _send(null),
                    child: Text(t('Not now')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending || _score == null
                        ? null
                        : () => _send(_score),
                    child: Text(t('Send')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
