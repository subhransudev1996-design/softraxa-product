import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/walkthrough.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';

// ---------------- providers ----------------

class ExpenseRange {
  const ExpenseRange(this.from, this.to);
  final DateTime from;
  final DateTime to;
}

final expenseRangeProvider =
    NotifierProvider<ExpenseRangeNotifier, ExpenseRange>(
      ExpenseRangeNotifier.new,
    );

class ExpenseRangeNotifier extends Notifier<ExpenseRange> {
  @override
  ExpenseRange build() {
    final now = DateTime.now();
    return ExpenseRange(DateTime(now.year, now.month, 1), now);
  }

  void set(DateTime from, DateTime to) => state = ExpenseRange(from, to);
}

/// Selected quick-filter chip ('today' | 'this_week' | 'this_month' |
/// 'last_month' | 'custom'). Kept separate from [ExpenseRangeNotifier] (the
/// actual query bounds) purely so the chip row knows which one to highlight
/// — picking a custom range via the date picker sets this to 'custom' so no
/// chip appears selected.
final expensePresetProvider = NotifierProvider<ExpensePresetNotifier, String>(
  ExpensePresetNotifier.new,
);

class ExpensePresetNotifier extends Notifier<String> {
  @override
  String build() => 'this_month';
  void set(String v) => state = v;
}

const kExpensePresets = [
  ('today', 'Today'),
  ('this_week', 'This week'),
  ('this_month', 'This month'),
  ('last_month', 'Last month'),
];

/// Resolves a quick-filter preset key to a concrete `[from, to]` range as of
/// [now] — a pure function so week/month boundary math (Monday-start weeks,
/// year rollover on "last month" in January) is unit-testable without a
/// date picker.
({DateTime from, DateTime to}) expensePresetRange(String preset, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (preset) {
    case 'today':
      return (from: today, to: now);
    case 'this_week':
      final start = today.subtract(Duration(days: today.weekday - 1));
      return (from: start, to: now);
    case 'this_month':
      return (from: DateTime(now.year, now.month, 1), to: now);
    case 'last_month':
      final start = DateTime(now.year, now.month - 1, 1);
      final end = DateTime(
        now.year,
        now.month,
        1,
      ).subtract(const Duration(days: 1));
      return (from: start, to: end);
    default:
      throw ArgumentError('Unknown expense preset: $preset');
  }
}

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('expense_categories')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    });

final expensesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final range = ref.watch(expenseRangeProvider);
    final rows = await ref
        .watch(supabaseProvider)
        .from('expenses')
        .select('*, expense_categories(name)')
        .gte('expense_date', ymd(range.from))
        .lte('expense_date', ymd(range.to))
        .order('expense_date', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(rows);
  },
);

// ---------------- screen ----------------

/// Expense tracking (PRD 7.15).
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  Future<void> _addCategory(
    BuildContext context,
    WidgetRef ref,
    void Function(String id, List<Map<String, dynamic>> categories) onAdded,
  ) async {
    final name = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Add expense category')),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: t('Name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Save')),
          ),
        ],
      ),
    );
    final trimmedName = name.text.trim();
    if (saved != true || trimmedName.isEmpty) return;
    try {
      final client = ref.read(supabaseProvider);
      final businessId = ref.read(appContextProvider).value?.businessId;

      // Check existing loaded categories (case-insensitive)
      final existingCategories =
          ref.read(expenseCategoriesProvider).value ?? [];
      final existingMatch = existingCategories.firstWhere(
        (c) =>
            (c['name'] as String?)?.trim().toLowerCase() ==
            trimmedName.toLowerCase(),
        orElse: () => {},
      );

      if (existingMatch.isNotEmpty) {
        final existingId = existingMatch['id'] as String;
        onAdded(existingId, existingCategories);
        if (context.mounted) {
          showSuccess(
            context,
            t('Expense category "{trimmedName}" already exists', {'trimmedName': trimmedName}),
          );
        }
        return;
      }

      final inserted = await client
          .from('expense_categories')
          .insert({'business_id': businessId, 'name': trimmedName})
          .select('id')
          .single();
      ref.invalidate(expenseCategoriesProvider);
      final fresh = await ref.read(expenseCategoriesProvider.future);
      onAdded(inserted['id'] as String, fresh);
      if (context.mounted) {
        showSuccess(context, t('Expense category "{trimmedName}" added', {'trimmedName': trimmedName}));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _addOrEdit(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? existing,
  }) async {
    List<Map<String, dynamic>> categories;
    try {
      categories = await ref.read(expenseCategoriesProvider.future);
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    if (!context.mounted) return;
    final amount = TextEditingController(
      text: existing == null
          ? ''
          : toDouble(existing['amount']).toStringAsFixed(2),
    );
    final note = TextEditingController(
      text: existing?['note'] as String? ?? '',
    );
    String? categoryId = existing?['category_id'] as String?;
    DateTime date = existing == null
        ? DateTime.now()
        : DateTime.parse(existing['expense_date'] as String);
    String mode = existing?['payment_mode'] as String? ?? 'cash';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? t('Add expense') : 'Edit expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amount,
                  autofocus: existing == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: t('Amount ₹ *')),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'expense_cat_${categories.any((c) => c['id'] == categoryId) ? categoryId : null}',
                        ),
                        isExpanded: true,
                        initialValue:
                            categories.any((c) => c['id'] == categoryId)
                            ? categoryId
                            : null,
                        decoration: InputDecoration(
                          labelText: t('Category'),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('—')),
                          for (final c in categories)
                            DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text(
                                c['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => categoryId = v),
                      ),
                    ),
                    IconButton(
                      tooltip: t('Add category'),
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _addCategory(
                        context,
                        ref,
                        (id, fresh) => setState(() {
                          categories = fresh;
                          categoryId = id;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: InputDecoration(labelText: t('Paid via')),
                  items: [
                    DropdownMenuItem(value: 'cash', child: Text(t('Cash'))),
                    DropdownMenuItem(value: 'upi', child: Text(t('UPI'))),
                    DropdownMenuItem(value: 'card', child: Text(t('Card'))),
                    DropdownMenuItem(value: 'other', child: Text(t('Bank/Other'))),
                  ],
                  onChanged: (v) => setState(() => mode = v ?? 'cash'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: t('Date')),
                    child: Text(dateStr(date)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: InputDecoration(
                    labelText: t('Note (optional)'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final amt = double.tryParse(amount.text) ?? 0;
    if (amt <= 0) {
      if (context.mounted) showError(context, t('Enter a valid amount'));
      return;
    }
    try {
      final client = ref.read(supabaseProvider);
      final row = {
        'amount': amt,
        'category_id': categoryId,
        'payment_mode': mode,
        'expense_date': ymd(date),
        'note': note.text.trim(),
      };
      if (existing == null) {
        final businessId = ref.read(appContextProvider).value?.businessId;
        await client.from('expenses').insert({
          ...row,
          'business_id': businessId,
        });
      } else {
        await client
            .from('expenses')
            .update(row)
            .eq('id', existing['id'] as String);
      }
      ref.invalidate(expensesProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> e,
  ) async {
    final ok = await confirmDialog(
      context,
      title: t('Delete expense?'),
      message:
          '${money(e['amount'] as num?)} — ${(e['expense_categories'] as Map?)?['name'] ?? 'expense'}',
      confirmText: t('Delete'),
    );
    if (!ok) return;
    try {
      await ref
          .read(supabaseProvider)
          .from('expenses')
          .delete()
          .eq('id', e['id'] as String);
      ref.invalidate(expensesProvider);
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final range = ref.read(expenseRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked != null) {
      ref.read(expenseRangeProvider.notifier).set(picked.start, picked.end);
      ref.read(expensePresetProvider.notifier).set('custom');
    }
  }

  void _applyPreset(WidgetRef ref, String preset) {
    final r = expensePresetRange(preset, DateTime.now());
    ref.read(expenseRangeProvider.notifier).set(r.from, r.to);
    ref.read(expensePresetProvider.notifier).set(preset);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    final range = ref.watch(expenseRangeProvider);
    final preset = ref.watch(expensePresetProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

    final mainAction = ScreenAction(
      label: t('Add expense'),
      icon: Icons.add,
      onPressed: () => _addOrEdit(context, ref),
      coachPage: 'expenses',
      coachId: 'add',
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(t('Expenses')),
        actions: [
          const GuideButton('expenses'),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: t('Custom date range'),
            onPressed: () => _pickRange(context, ref),
          ),
          mainAction.inAppBar(context),
        ],
      ),
      floatingActionButton: mainAction.fab(context),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: CoachTarget(
              page: 'expenses',
              id: 'presets',
              child: Row(
                children: [
                  for (final p in kExpensePresets)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.$2),
                        selected: preset == p.$1,
                        onSelected: (_) => _applyPreset(ref, p.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: expenses,
              onRetry: () => ref.invalidate(expensesProvider),
              builder: (rows) {
                final total = rows.fold<double>(
                  0,
                  (s, e) => s + toDouble(e['amount']),
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: CoachTarget(
                        page: 'expenses',
                        id: 'total',
                        child: Card(
                          child: ListTile(
                            title: Text(
                              '${dateStr(range.from)} → ${dateStr(range.to)}',
                            ),
                            subtitle: Text(t('{v1} entries', {'v1': rows.length})),
                            trailing: Text(
                              money(total),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? EmptyState(
                              icon: Icons.payments_outlined,
                              message: t('No expenses in this period'),
                            )
                          : isDesktop
                          ? Align(
                              alignment: Alignment.topLeft,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: responsiveCardWrap([
                                  for (final e in rows)
                                    _ExpenseCard(
                                      expense: e,
                                      onEdit: () =>
                                          _addOrEdit(context, ref, existing: e),
                                      onDelete: () => _delete(context, ref, e),
                                    ),
                                ]),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                              itemCount: rows.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final e = rows[i];
                                return Card(
                                  child: ListTile(
                                    onTap: () =>
                                        _addOrEdit(context, ref, existing: e),
                                    leading: const IconChip(
                                      Icons.payments_outlined,
                                      color: AppColors.red,
                                      size: 40,
                                    ),
                                    title: Text(
                                      (e['expense_categories'] as Map?)?['name']
                                              as String? ??
                                          'Uncategorised',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${dateStr(e['expense_date'])}'
                                      '${(e['note'] as String? ?? '').isNotEmpty ? ' • ${e['note']}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.inkSoft,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          money(e['amount'] as num?),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.red,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                          ),
                                          color: AppColors.inkSoft,
                                          tooltip: t('Delete expense'),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _delete(context, ref, e),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop card for an expense entry — mirrors [PartyCard]'s look for visual
/// consistency, with explicit edit/delete actions instead of relying on
/// touch-only gestures (tap/long-press) that don't suit mouse users.
class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final note = e['note'] as String? ?? '';
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const IconChip(
                    Icons.payments_outlined,
                    color: AppColors.red,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (e['expense_categories'] as Map?)?['name']
                                  as String? ??
                              'Uncategorised',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          dateStr(e['expense_date']),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    color: AppColors.inkSoft,
                    tooltip: t('Edit expense'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 19),
                    color: AppColors.red,
                    tooltip: t('Delete expense'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t('Paid via {v1}', {'v1': (e['payment_mode'] as String? ?? 'cash').toUpperCase()}),
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                  Text(
                    money(e['amount'] as num?),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
