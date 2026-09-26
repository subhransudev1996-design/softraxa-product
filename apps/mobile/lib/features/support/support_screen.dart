import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';

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
    final appContext = ref.watch(appContextProvider).value;
    final isTrial = appContext?.subscriptionState == 'trial';

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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            // Instant WhatsApp Contact Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: isTrial ? const Color(0xFFFFE1A8) : AppColors.line,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              color: isTrial ? const Color(0xFFFFF7E6) : Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.chat,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTrial
                                    ? 'Trial Account — WhatsApp Upgrade & Support'
                                    : 'Instant WhatsApp Support',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isTrial ? const Color(0xFF8C5400) : Colors.green.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isTrial
                                    ? 'Chat with our team to upgrade your store plan or get help.'
                                    : 'Get instant assistance on WhatsApp for your store.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isTrial ? const Color(0xFF996300) : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text(
                          'Chat on WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () => launchWhatsAppContact(context, appContext),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Support Requests'),
            AsyncView(
              value: tickets,
              onRetry: () => ref.invalidate(ticketsProvider),
              builder: (rows) => rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.support_agent_outlined,
                      message:
                          'No support requests yet.\nFacing a problem? Tap "New request".',
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
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
          ],
        ),
      ),
    );
  }
}
