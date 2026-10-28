import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';

/// Announcements from Dukania for this shop (migration 0101): running,
/// not dismissed. Empty before 0101 or offline — the banners just don't show.
final announcementsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      try {
        final rows = await ref.watch(supabaseProvider).rpc('my_announcements');
        return [
          for (final r in (rows as List? ?? const []))
            Map<String, dynamic>.from(r as Map),
        ];
      } catch (_) {
        return const [];
      }
    });

/// Dukania's announcements on the home screen, each with an optional
/// button (a link) and a close button.
class AnnouncementBanners extends ConsumerWidget {
  const AnnouncementBanners({super.key, required this.padding});

  final EdgeInsets padding;

  Future<void> _dismiss(WidgetRef ref, String id) async {
    try {
      await ref
          .read(supabaseProvider)
          .rpc('dismiss_announcement', params: {'p_id': id});
    } catch (_) {
      // Shows again next time; nothing lost.
    }
    ref.invalidate(announcementsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(announcementsProvider).value ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (final a in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.campaign_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a['title'] as String? ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppColors.ink,
                          ),
                        ),
                        if ((a['body'] as String? ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              a['body'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        if ((a['button_url'] as String? ?? '').startsWith(
                          'https://',
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: FilledButton.tonal(
                              onPressed: () => launchUrl(
                                Uri.parse(a['button_url'] as String),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: Text(
                                (a['button_label'] as String? ?? '').isEmpty
                                    ? t('Open')
                                    : a['button_label'] as String,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t('Close'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _dismiss(ref, a['id'] as String),
                    icon: Icon(Icons.close, size: 18, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
