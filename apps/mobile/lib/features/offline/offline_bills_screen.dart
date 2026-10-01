import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/widgets.dart';
import 'local_db.dart';
import 'offline_service.dart';
import '../../core/theme.dart';

final _pendingBillsProvider = FutureProvider.autoDispose<List<PendingBill>>((
  ref,
) async {
  return ref.watch(offlineServiceProvider).pendingBills();
});

/// Bills waiting to sync (PRD 7.10).
class OfflineBillsScreen extends ConsumerWidget {
  const OfflineBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(_pendingBillsProvider);
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Pending offline bills'),
        actions: [
          const GuideButton('offline_bills'),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: () async {
              await ref.read(offlineServiceProvider).syncPendingBills();
              ref.invalidate(_pendingBillsProvider);
              ref.invalidate(pendingBillCountProvider);
              if (context.mounted) showSuccess(context, 'Sync attempted');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.orangeSoft,
              child: const Text(
                'You are offline. Bills will sync automatically when internet returns.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          Expanded(
            child: AsyncView(
              value: bills,
              onRetry: () => ref.invalidate(_pendingBillsProvider),
              builder: (rows) => rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.cloud_done_outlined,
                      message: 'All bills are synced!',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final b = rows[i];
                        final failed = b.status == 'failed';
                        return Card(
                          child: ListTile(
                            leading: IconChip(
                              failed
                                  ? Icons.error_outline
                                  : Icons.cloud_upload_outlined,
                              color: failed ? AppColors.red : AppColors.orange,
                              size: 40,
                            ),
                            title: Text(
                              '${b.displayNo} • ${money(b.total)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${b.customerName.isNotEmpty ? '${b.customerName} • ' : ''}'
                              '${dateTimeStr(b.createdAt)}'
                              '${failed ? '\nFailed: ${b.error}' : ''}',
                              maxLines: 3,
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 13,
                              ),
                            ),
                            trailing: failed
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.refresh),
                                        tooltip: 'Try again',
                                        onPressed: () async {
                                          await ref
                                              .read(offlineServiceProvider)
                                              .syncPendingBills();
                                          ref.invalidate(_pendingBillsProvider);
                                          ref.invalidate(
                                            pendingBillCountProvider,
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: AppColors.red,
                                        ),
                                        tooltip: 'Discard bill',
                                        onPressed: () async {
                                          final ok = await confirmDialog(
                                            context,
                                            title: 'Discard bill?',
                                            message:
                                                'This offline bill will be permanently deleted. Stock was never deducted for it.',
                                            confirmText: 'Discard',
                                          );
                                          if (!ok) return;
                                          await ref
                                              .read(offlineServiceProvider)
                                              .deletePendingBill(b.localId);
                                          ref.invalidate(_pendingBillsProvider);
                                          ref.invalidate(
                                            pendingBillCountProvider,
                                          );
                                        },
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
