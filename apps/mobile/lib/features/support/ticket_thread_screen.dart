import '../../core/i18n.dart' as i18n;
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

/// The request as it is now (status and rating change after it was opened).
final ticketProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, ticketId) async {
      final row = await ref
          .watch(supabaseProvider)
          .from('support_tickets')
          .select()
          .eq('id', ticketId)
          .single();
      return Map<String, dynamic>.from(row);
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
/// Dukania's replies and a box to write back.
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
    // Opening the request marks Dukania's answer as read.
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
      ref.invalidate(ticketProvider(_id));
      ref.invalidate(ticketsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _bubble({
    required bool fromDukania,
    required String body,
    required Object? at,
  }) {
    return Align(
      alignment: fromDukania ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: fromDukania
              ? AppColors.indigo.withValues(alpha: 0.10)
              : AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fromDukania ? 'Dukania' : 'You',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fromDukania ? AppColors.indigo : AppColors.inkSoft,
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
              onRefresh: () async {
                ref.invalidate(ticketMessagesProvider(_id));
                ref.invalidate(ticketProvider(_id));
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _bubble(fromDukania: false, body: first, at: t['created_at']),
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
                              child: Text(i18n.t('Dukania will reply here. You\'ll get a notification.'),
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
                                fromDukania: m['from_softraxa'] == true,
                                body: m['body'] as String,
                                at: m['created_at'],
                              ),
                          ],
                  ),
                  _RateCard(ticketId: _id),
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
                      decoration: InputDecoration(
                        hintText: i18n.t('Write a message…'),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: i18n.t('Send'),
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

/// After Dukania resolves a request, the shop rates the help 1–5 (0099).
class _RateCard extends ConsumerStatefulWidget {
  const _RateCard({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_RateCard> createState() => _RateCardState();
}

class _RateCardState extends ConsumerState<_RateCard> {
  int _stars = 0;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(supabaseProvider).rpc(
        'rate_ticket',
        params: {
          'p_ticket': widget.ticketId,
          'p_rating': _stars,
          'p_note': _note.text.trim(),
        },
      );
      ref.invalidate(ticketProvider(widget.ticketId));
      if (mounted) showSuccess(context, i18n.t('Thank you for rating us!'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = ref.watch(ticketProvider(widget.ticketId)).value;
    if (ticket == null || ticket['status'] != 'resolved') {
      return const SizedBox.shrink();
    }
    final rated = (ticket['rating'] as num?)?.toInt();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: rated != null
            ? Text(
                i18n.t('You rated this {v1} of 5. Thank you!', {'v1': rated}),
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.t('How did we do?'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          onPressed: () => setState(() => _stars = i),
                          icon: Icon(
                            i <= _stars ? Icons.star : Icons.star_border,
                            color: Colors.amber.shade700,
                            size: 30,
                          ),
                        ),
                    ],
                  ),
                  if (_stars > 0) ...[
                    TextField(
                      controller: _note,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: i18n.t('Tell us more (optional)'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(i18n.t('Send rating')),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
