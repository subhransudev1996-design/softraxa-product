import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'support_screen.dart';

/// Messages on one support request, oldest first (migration 0054).
final ticketMessagesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, ticketId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('support_messages')
          .select()
          .eq('ticket_id', ticketId)
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows);
    });

/// Support requests with an answer the shop hasn't opened yet.
final supportUnreadProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final n = await ref.watch(supabaseProvider).rpc('support_unread_count');
    return (n as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0; // before migration 0054, or offline
  }
});

/// A support request as a conversation: the shop's first message,
/// SOFTRAXA's replies and a box to write back.
class TicketThreadScreen extends ConsumerStatefulWidget {
  const TicketThreadScreen({super.key, required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  ConsumerState<TicketThreadScreen> createState() => _TicketThreadScreenState();
}

class _TicketThreadScreenState extends ConsumerState<TicketThreadScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  String get _id => widget.ticket['id'] as String;

  @override
  void initState() {
    super.initState();
    // Opening the request marks SOFTRAXA's answer as read.
    Future.microtask(() async {
      try {
        await ref
            .read(supabaseProvider)
            .rpc('mark_ticket_seen', params: {'p_ticket': _id});
        ref.invalidate(supportUnreadProvider);
        ref.invalidate(ticketsProvider);
      } catch (_) {
        // Not critical: the badge clears next time.
      }
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(supabaseProvider)
          .rpc('reply_to_ticket', params: {'p_ticket': _id, 'p_body': text});
      _reply.clear();
      ref.invalidate(ticketMessagesProvider(_id));
      ref.invalidate(ticketsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _bubble({
    required bool softraxa,
    required String body,
    required Object? at,
  }) {
    return Align(
      alignment: softraxa ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: softraxa
              ? AppColors.indigo.withValues(alpha: 0.10)
              : AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              softraxa ? 'SOFTRAXA' : 'You',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: softraxa ? AppColors.indigo : AppColors.inkSoft,
              ),
            ),
            Text(body, style: const TextStyle(fontSize: 14)),
            Text(
              dateTimeStr(at),
              style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final messages = ref.watch(ticketMessagesProvider(_id));
    final first = (t['message'] as String? ?? '').isEmpty
        ? t['subject'] as String
        : t['message'] as String;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(t['subject'] as String)),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(ticketMessagesProvider(_id)),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _bubble(softraxa: false, body: first, at: t['created_at']),
                  ...messages.when(
                    loading: () => const [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                    error: (e, _) => [Text(friendlyError(e))],
                    data: (rows) => rows.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                'SOFTRAXA will reply here. You\'ll get a notification.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.inkSoft,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ]
                        : [
                            for (final m in rows)
                              _bubble(
                                softraxa: m['from_softraxa'] == true,
                                body: m['body'] as String,
                                at: m['created_at'],
                              ),
                          ],
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write a message…',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
