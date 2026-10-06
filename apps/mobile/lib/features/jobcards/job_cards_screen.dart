import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import 'job_card_providers.dart';

/// Job card list (repair/service orders) — PRD Phase 2 §6-8.
class JobCardsScreen extends ConsumerWidget {
  const JobCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobCardsProvider);
    final filter = ref.watch(jobCardFilterProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final mainAction = ScreenAction(
      label: t('New job card'),
      icon: Icons.add,
      onPressed: () => context.push('/job-cards/new'),
      coachPage: 'job_cards',
      coachId: 'add',
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Job cards')),
        actions: [const GuideButton('job_cards'), mainAction.inAppBar(context)],
      ),
      floatingActionButton: mainAction.fab(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SearchField(
              hint: t('Search job no, customer, device, IMEI'),
              onChanged: (v) => ref
                  .read(jobCardFilterProvider.notifier)
                  .set(filter.copyWith(search: v)),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CoachTarget(
              page: 'job_cards',
              id: 'filters',
              child: Row(
                children: [
                  for (final s in [null, ...jobStatuses])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s == null ? 'All' : jobStatusLabel(s)),
                        selected: filter.status == s,
                        onSelected: (_) => ref
                            .read(jobCardFilterProvider.notifier)
                            .set(filter.copyWith(status: s)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(jobCardsProvider),
              child: AsyncView(
                value: jobs,
                onRetry: () => ref.invalidate(jobCardsProvider),
                builder: (rows) => rows.isEmpty
                    ? EmptyState(
                        icon: Icons.build_outlined,
                        message: t('No job cards found.\nCreate one when a customer drops off an item.'),
                      )
                    : isDesktop
                    ? DesktopTable<Map<String, dynamic>>(
                        // Newest first, like the phone list.
                        initialSortIndex: 2,
                        initialAscending: false,
                        rows: rows,
                        trailingWidth: 130,
                        columns: [
                          DesktopTableColumn(
                            label: t('Job #'),
                            flex: 3,
                            comparable: (j) => j['job_no'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: t('Customer'),
                            flex: 2,
                            comparable: (j) =>
                                (j['customer_name'] as String? ?? '')
                                    .toLowerCase(),
                          ),
                          DesktopTableColumn(
                            label: t('Date'),
                            flex: 2,
                            comparable: (j) => j['created_at'] as String? ?? '',
                          ),
                          DesktopTableColumn(
                            label: t('Est. cost'),
                            flex: 2,
                            alignEnd: true,
                            comparable: (j) => toDouble(j['estimated_cost']),
                          ),
                        ],
                        rowBuilder: (context, j) => _JobCardRow(job: j),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _JobCardTile(job: rows[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== desktop: sortable data table ====================

class _JobCardRow extends StatelessWidget {
  const _JobCardRow({required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final status = j['status'] as String? ?? 'received';

    return InkWell(
      onTap: () => context.push('/job-cards/${j['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                '${j['job_no']} • ${(j['item_name'] as String? ?? '').isNotEmpty ? j['item_name'] : 'Item'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                (j['customer_name'] as String?)?.isNotEmpty == true
                    ? j['customer_name'] as String
                    : 'Walk-in',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateStr(j['created_at']),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                money(j['estimated_cost'] as num?),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: Align(
                alignment: Alignment.centerRight,
                child: StatusChip(
                  jobStatusLabel(status),
                  color: jobStatusColors[status] ?? AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _JobCardTile extends StatelessWidget {
  const _JobCardTile({required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final status = j['status'] as String? ?? 'received';
    // Built manually instead of ListTile (its trailing
    // slot enforces a fixed max height independent of
    // contentPadding, which this 2-line trailing column
    // can overflow under some font metrics).
    return Card(
      child: InkWell(
        onTap: () => context.push('/job-cards/${j['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              IconChip(
                Icons.build_outlined,
                color: jobStatusColors[status] ?? AppColors.inkSoft,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${j['job_no']} • ${(j['item_name'] as String? ?? '').isNotEmpty ? j['item_name'] : 'Item'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(j['customer_name'] as String?)?.isNotEmpty == true ? j['customer_name'] : 'Walk-in'}'
                      ' • ${dateStr(j['created_at'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(
                    jobStatusLabel(status),
                    color: jobStatusColors[status] ?? AppColors.inkSoft,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money(j['estimated_cost'] as num?),
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
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
