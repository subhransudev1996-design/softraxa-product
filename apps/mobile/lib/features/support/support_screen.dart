import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';

final ticketsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  final rows = await ref
      .watch(supabaseProvider)
      .from('support_tickets')
      .select()
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});

/// Raise and track support issues (PRD 8.6, client side).
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  Future<void> _newTicket(BuildContext context, WidgetRef ref) async {
    final subject = TextEditingController();
    final message = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New support request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subject,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Subject *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe the issue',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (saved != true || subject.text.trim().isEmpty) return;
    try {
      final businessId = ref.read(appContextProvider).value?.businessId;
      await ref.read(supabaseProvider).from('support_tickets').insert({
        'business_id': businessId,
        'subject': subject.text.trim(),
        'message': message.text.trim(),
      });
      ref.invalidate(ticketsProvider);
      if (context.mounted) {
        showSuccess(context, 'Request sent. We will contact you soon.');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(ticketsProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('Support'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newTicket(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ticketsProvider),
        child: AsyncView(
          value: tickets,
          onRetry: () => ref.invalidate(ticketsProvider),
          builder: (rows) => rows.isEmpty
              ? const EmptyState(
                  icon: Icons.support_agent_outlined,
                  message:
                      'No support requests yet.\nFacing a problem? Tap "New request".',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = rows[i];
                    return Card(
                      child: ListTile(
                        leading: const IconChip(
                          Icons.support_agent_outlined,
                          color: AppColors.indigo,
                          size: 40,
                        ),
                        title: Text(
                          t['subject'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${t['message'] ?? ''}\n${dateTimeStr(t['created_at'])}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 12,
                          ),
                        ),
                        trailing: StatusChip(
                          (t['status'] as String).replaceAll('_', ' '),
                          color: switch (t['status']) {
                            'resolved' => AppColors.green,
                            'in_progress' => AppColors.orange,
                            _ => AppColors.inkSoft,
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
