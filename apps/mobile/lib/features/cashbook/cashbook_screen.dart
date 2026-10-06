import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../offline/offline_service.dart';

/// Daily cashbook and closing (D34–D36, migration 0045): one shared drawer.
final cashbookProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, DateTime>((ref, day) async {
      final res = await ref
          .watch(supabaseProvider)
          .rpc('get_cashbook', params: {'p_date': ymd(day)});
      return Map<String, dynamic>.from(res as Map);
    });

/// Manual cash kinds and their labels (cash_entries.kind).
const cashEntryKinds = <String, String>{
  'owner_in': 'Owner added cash',
  'owner_out': 'Owner took cash',
  'bank_deposit': 'Deposited in bank',
  'bank_withdrawal': 'Withdrawn from bank',
  'other_in': 'Other cash in',
  'other_out': 'Other cash out',
};

/// Counted minus expected: negative = short, positive = excess.
String varianceLabel(num variance) {
  if (variance.abs() < 0.005) return 'Matches';
  return variance < 0 ? 'Short by ${money(-variance)}' : 'Excess ${money(variance)}';
}

class CashbookScreen extends ConsumerStatefulWidget {
  const CashbookScreen({super.key});

  @override
  ConsumerState<CashbookScreen> createState() => _CashbookScreenState();
}

class _CashbookScreenState extends ConsumerState<CashbookScreen> {
  DateTime _day = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  void _refresh() => ref.invalidate(cashbookProvider(_day));

  Future<void> _addEntry() async {
    String kind = 'bank_deposit';
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t('Cash moved by hand')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: InputDecoration(labelText: t('What')),
                items: [
                  for (final e in cashEntryKinds.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => kind = v ?? kind),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: t('Amount ₹')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: InputDecoration(
                  labelText: kind.startsWith('other') ? t('What for? *') : 'Note (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Save'))),
          ],
        ),
      ),
    );
    final amt = double.tryParse(amount.text.trim()) ?? 0;
    if (ok != true || amt <= 0) return;
    try {
      await ref.read(supabaseProvider).rpc('add_cash_entry', params: {
        'p_kind': kind,
        'p_amount': amt,
        'p_note': note.text.trim(),
      });
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _close(Map<String, dynamic> book) async {
    // PD58: not while this device still has bills waiting to sync.
    final pending = await ref.read(pendingBillCountProvider.future);
    if (pending > 0) {
      if (mounted) {
        showError(context, t('{pending} offline bill(s) haven\'t synced yet — sync them before closing.', {'pending': pending}));
      }
      return;
    }
    if (!mounted) return;
    final expected = toDouble(book['expected']);
    final counted = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final c = double.tryParse(counted.text.trim());
          final diff = c == null ? null : c - expected;
          final needsReason = diff != null && diff.abs() >= 0.005;
          return AlertDialog(
            title: Text(t('Close {v1}', {'v1': dateStr(_day)})),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Expected in the drawer: {v1}', {'v1': money(expected)})),
                const SizedBox(height: 12),
                TextField(
                  controller: counted,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: t('Cash you counted ₹')),
                  onChanged: (_) => setState(() {}),
                ),
                if (diff != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    varianceLabel(diff),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: needsReason ? AppColors.red : AppColors.green,
                    ),
                  ),
                ],
                if (needsReason)
                  TextField(
                    controller: reason,
                    decoration: InputDecoration(labelText: t('Why is it different? *')),
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 8),
                Text(t('After closing, the day is locked. Cash taken later counts in the next day. Only the owner can reopen it.'),
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
              FilledButton(
                style: dialogActionStyle,
                onPressed: c != null && (!needsReason || reason.text.trim().length >= 3)
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: Text(t('Close the day')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(supabaseProvider).rpc('submit_cash_closing', params: {
        'p_date': ymd(_day),
        'p_counted': double.parse(counted.text.trim()),
        'p_reason': reason.text.trim(),
      });
      _refresh();
      if (mounted) showSuccess(context, t('Day closed'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _review(Map<String, dynamic> closing) async {
    try {
      await ref.read(supabaseProvider).rpc('review_cash_closing', params: {'p_id': closing['id']});
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reopen(Map<String, dynamic> closing) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Reopen this day?')),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: InputDecoration(labelText: t('Reason *')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Reopen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(supabaseProvider).rpc('reopen_cash_closing', params: {
        'p_id': closing['id'],
        'p_reason': reason.text.trim(),
      });
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(cashbookProvider(_day));
    final isOwner = ref.watch(appContextProvider).value?.isOwner ?? false;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(leading: appBarBack(context), title: Text(t('Cashbook'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: t('Previous day'),
                  onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
                ),
                Expanded(
                  child: Text(
                    _isToday ? 'Today — ${dateStr(_day)}' : dateStr(_day),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: t('Next day'),
                  onPressed: _isToday ? null : () => setState(() => _day = _day.add(const Duration(days: 1))),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: data,
              onRetry: _refresh,
              builder: (book) {
                final closing = book['closing'] as Map?;
                final lines = List<Map<String, dynamic>>.from(book['lines'] as List? ?? const []);
                final nonCash = List<Map<String, dynamic>>.from(book['non_cash'] as List? ?? const []);
                final history = List<Map<String, dynamic>>.from(book['history'] as List? ?? const []);
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _row('Opening cash', money(toDouble(book['opening']))),
                              _row('Cash in', '+ ${money(toDouble(book['cash_in']))}', color: AppColors.green),
                              _row('Cash out', '− ${money(toDouble(book['cash_out']))}', color: AppColors.red),
                              const Divider(height: 20),
                              _row('Expected in drawer', money(toDouble(book['expected'])), bold: true),
                            ],
                          ),
                        ),
                      ),
                      if (nonCash.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            t('Not in the drawer: {v1}', {'v1': [
                              for (final n in nonCash)
                                '${'${n['mode']}'.toUpperCase()} ${money(toDouble(n['in']) - toDouble(n['out']))}',
                            ].join(' • ')}),
                            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                          ),
                        ),
                      if (closing != null)
                        _ClosingCard(
                          closing: Map<String, dynamic>.from(closing),
                          isOwner: isOwner,
                          onReview: () => _review(Map<String, dynamic>.from(closing)),
                          onReopen: () => _reopen(Map<String, dynamic>.from(closing)),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _addEntry,
                                icon: const Icon(Icons.add),
                                label: Text(t('Cash in / out')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _close(book),
                                icon: const Icon(Icons.lock_outline),
                                label: Text(t('Close the day')),
                              ),
                            ),
                          ],
                        ),
                      ],
                      for (final h in history)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Earlier closing (v${h['version']}): counted ${money(toDouble(h['counted_cash']))}, '
                            '${varianceLabel(toDouble(h['variance']))} — reopened: ${h['reopen_reason']}',
                            style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                          ),
                        ),
                      SectionLabel(t('Cash movements')),
                      if (lines.isEmpty)
                        EmptyState(icon: Icons.payments_outlined, message: t('No cash moved this day'))
                      else
                        Card(
                          child: Column(
                            children: [
                              for (final l in lines)
                                ListTile(
                                  dense: true,
                                  title: Text('${l['label']}'),
                                  subtitle: Text(_time(l['ts'])),
                                  trailing: Text(
                                    '${(l['direction'] as num) > 0 ? '+' : '−'} ${money(toDouble(l['amount']))}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: (l['direction'] as num) > 0 ? AppColors.green : AppColors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _time(Object? ts) {
    final d = DateTime.tryParse('$ts')?.toLocal();
    return d == null ? '' : DateFormat('hh:mm a').format(d);
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null))),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontSize: bold ? 17 : 14,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({
    required this.closing,
    required this.isOwner,
    required this.onReview,
    required this.onReopen,
  });

  final Map<String, dynamic> closing;
  final bool isOwner;
  final VoidCallback onReview;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final variance = toDouble(closing['variance']);
    final reviewed = closing['status'] == 'reviewed';
    return Card(
      color: (variance.abs() < 0.005 ? AppColors.green : AppColors.orange).withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reviewed ? t('Closed and reviewed by the owner') : 'Closed — waiting for owner review',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(t('Counted {v1} • {v2}', {'v1': money(toDouble(closing['counted_cash'])), 'v2': varianceLabel(variance)})),
            if ((closing['reason'] as String? ?? '').isNotEmpty)
              Text(t('Reason: {v1}', {'v1': closing['reason']}), style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            Text(
              t('Closed at {v1}', {'v1': dateTimeStr(closing['submitted_at'])}),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            if (isOwner) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (!reviewed) FilledButton(onPressed: onReview, child: Text(t('Mark reviewed'))),
                  OutlinedButton(onPressed: onReopen, child: Text(t('Reopen'))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
