import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customer_picker.dart';
import '../products/product_providers.dart';

/// Card types and cards, with each card's use (migration 0083).
final discountCardsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, search) async {
      final res = await ref
          .watch(supabaseProvider)
          .rpc('get_discount_cards', params: {'p_search': search});
      return Map<String, dynamic>.from(res as Map);
    });

/// Discount (privilege / membership) cards: the owner sets up card types
/// (Gold 10% on Books…); the owner and staff who may change prices issue
/// cards. Cashiers apply them at checkout.
class DiscountCardsScreen extends ConsumerStatefulWidget {
  const DiscountCardsScreen({super.key});

  @override
  ConsumerState<DiscountCardsScreen> createState() =>
      _DiscountCardsScreenState();
}

class _DiscountCardsScreenState extends ConsumerState<DiscountCardsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(discountCardsProvider);

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(appContextProvider).value;
    final isOwner = ctx?.isOwner ?? false;
    final canIssue = isOwner || (ctx?.canEditPrices ?? false);
    final data = ref.watch(discountCardsProvider(_query));
    final types = [
      for (final t in (data.value?['types'] as List? ?? const []))
        Map<String, dynamic>.from(t as Map),
    ];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          leading: appBarBack(context),
          title: Text(t('Discount cards')),
          bottom: TabBar(
            tabs: [
              Tab(text: t('Cards')),
              Tab(text: t('Card types')),
            ],
          ),
        ),
        body: AsyncView<Map<String, dynamic>>(
          value: data,
          onRetry: _reload,
          builder: (d) {
            final cards = [
              for (final c in (d['cards'] as List? ?? const []))
                Map<String, dynamic>.from(c as Map),
            ];
            return TabBarView(
              children: [
                _cardsTab(cards, types, canIssue),
                _typesTab(types, isOwner),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cardsTab(
    List<Map<String, dynamic>> cards,
    List<Map<String, dynamic>> types,
    bool canIssue,
  ) {
    final active = types.where((t) => t['is_active'] == true).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t('Card number or holder'),
                    isDense: true,
                  ),
                  onSubmitted: (v) => setState(() => _query = v.trim()),
                ),
              ),
              if (canIssue) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: dialogActionStyle,
                  onPressed: active.isEmpty
                      ? () => showError(
                          context,
                          t('First add a card type (Card types tab).'),
                        )
                      : () async {
                          final saved = await showDiscountCardEditor(
                            context,
                            ref,
                            types: active,
                          );
                          if (saved != null) _reload();
                        },
                  icon: const Icon(Icons.add),
                  label: Text(t('Add card')),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: cards.isEmpty
              ? EmptyState(
                  icon: Icons.card_membership_outlined,
                  message: _query.isEmpty
                      ? t(
                          'No cards yet. Add the cards you give customers, or add one at checkout when a customer shows it.',
                        )
                      : t('No card matches.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = cards[i];
                    final holder = [
                      c['holder_name'] as String? ?? '',
                      c['customer_name'] as String? ?? '',
                    ].where((s) => s.isNotEmpty).join(' · ');
                    final until = c['valid_until'] as String?;
                    final uses = (c['uses'] as num?)?.toInt() ?? 0;
                    return Card(
                      child: ListTile(
                        enabled: canIssue,
                        leading: IconChip(
                          Icons.card_membership,
                          color: c['is_active'] == true
                              ? AppColors.primary
                              : AppColors.inkSoft,
                          size: 38,
                        ),
                        title: Text(
                          c['card_no'] as String? ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        subtitle: Text(
                          [
                            '${c['type_name']} ${qty(c['discount_pct'] as num?)}%',
                            if (holder.isNotEmpty) holder,
                            if (until != null)
                              t('Valid till {v1}', {'v1': dateStr(until)}),
                            if (c['is_active'] != true) t('Switched off'),
                            if (uses > 0)
                              t('Used {v1} times · {v2} off', {
                                'v1': '$uses',
                                'v2': money(c['discount_given'] as num?),
                              }),
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        onTap: canIssue
                            ? () async {
                                final saved = await showDiscountCardEditor(
                                  context,
                                  ref,
                                  types: types,
                                  existing: c,
                                );
                                if (saved != null) _reload();
                              }
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _typesTab(List<Map<String, dynamic>> types, bool isOwner) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          t(
            'Each type has its own discount and decides which items it covers. Only the owner can change them.',
          ),
          style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        if (isOwner)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: dialogActionStyle,
              onPressed: () async {
                if (await showCardTypeEditor(context, ref)) _reload();
              },
              icon: const Icon(Icons.add),
              label: Text(t('Add card type')),
            ),
          ),
        const SizedBox(height: 8),
        if (types.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              t('No card types yet — for example Gold 10% or Student 5%.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ),
        for (final ty in types)
          Card(
            child: ListTile(
              leading: IconChip(
                Icons.loyalty_outlined,
                color: ty['is_active'] == true
                    ? AppColors.teal
                    : AppColors.inkSoft,
                size: 38,
              ),
              title: Text(
                '${ty['name']} — ${qty(ty['discount_pct'] as num?)}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  _coverage(ref, ty),
                  t('{v1} cards', {'v1': '${ty['cards'] ?? 0}'}),
                  if (ty['is_active'] != true) t('Switched off'),
                ].join(' · '),
              ),
              trailing: isOwner ? const Icon(Icons.edit_outlined) : null,
              onTap: isOwner
                  ? () async {
                      if (await showCardTypeEditor(
                        context,
                        ref,
                        existing: ty,
                      )) {
                        _reload();
                      }
                    }
                  : null,
            ),
          ),
      ],
    );
  }
}

/// "All items", "Only: Books, Guides", "All except: Stationery".
String _coverage(WidgetRef ref, Map<String, dynamic> type) {
  final names = {
    for (final c in ref.watch(categoriesProvider).value ?? const [])
      c['id'] as String: c['name'] as String,
  };
  final picked = [
    for (final id in (type['category_ids'] as List? ?? const []))
      names[id] ?? '?',
  ].join(', ');
  return switch (type['applies_to']) {
    'only' => t('Only: {v1}', {'v1': picked}),
    'except' => t('All except: {v1}', {'v1': picked}),
    _ => t('All items'),
  };
}

/// Add or change a card type (owner). True when saved.
Future<bool> showCardTypeEditor(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? existing,
}) async {
  final name = TextEditingController(text: existing?['name'] as String? ?? '');
  final pct = TextEditingController(
    text: existing == null ? '' : qty(existing['discount_pct'] as num?),
  );
  var applies = existing?['applies_to'] as String? ?? 'all';
  final picked = <String>{
    for (final c in (existing?['category_ids'] as List? ?? const []))
      c as String,
  };
  var active = existing?['is_active'] as bool? ?? true;
  var busy = false;
  // Loaded first: the dialog doesn't rebuild when the list arrives later
  // (it said "Add categories first" to shops that have them).
  List<Map<String, dynamic>> categories = const [];
  try {
    categories = await ref.read(categoriesProvider.future);
  } catch (_) {}
  if (!context.mounted) return false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text(
            existing == null ? t('Add card type') : t('Change card type'),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: t('Name (e.g. Gold, Student)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pct,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: t('Discount %'),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('The discount is for'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  RadioGroup<String>(
                    groupValue: applies,
                    onChanged: (v) => setLocal(() => applies = v ?? 'all'),
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: 'all',
                          dense: true,
                          title: Text(t('All items')),
                        ),
                        RadioListTile<String>(
                          value: 'only',
                          dense: true,
                          title: Text(t('Only these categories')),
                        ),
                        RadioListTile<String>(
                          value: 'except',
                          dense: true,
                          title: Text(t('All items except these categories')),
                        ),
                      ],
                    ),
                  ),
                  if (applies != 'all') ...[
                    if (categories.isEmpty)
                      Text(
                        t('Add categories to your products first.'),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in categories)
                          FilterChip(
                            label: Text(c['name'] as String),
                            selected: picked.contains(c['id']),
                            onSelected: (on) => setLocal(() {
                              on
                                  ? picked.add(c['id'] as String)
                                  : picked.remove(c['id']);
                            }),
                          ),
                      ],
                    ),
                  ],
                  if (existing != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      onChanged: (v) => setLocal(() => active = v),
                      title: Text(t('In use')),
                      subtitle: Text(
                        t('Switched off: its cards stop giving a discount.'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() => busy = true);
                      try {
                        await ref
                            .read(supabaseProvider)
                            .rpc(
                              'save_discount_card_type',
                              params: {
                                'p_id': existing?['id'],
                                'p': {
                                  'name': name.text.trim(),
                                  'discount_pct': double.tryParse(
                                    pct.text.trim(),
                                  ),
                                  'applies_to': applies,
                                  'category_ids': picked.toList(),
                                  'is_active': active,
                                },
                              },
                            );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() => busy = false);
                        if (ctx.mounted) showError(ctx, e);
                      }
                    },
              child: Text(t('Save')),
            ),
          ],
        );
      },
    ),
  );
  return saved ?? false;
}

/// Add or change a card. [initialNo] pre-fills the number (a card shown at
/// checkout that isn't in the list yet). Returns the card's id when saved.
Future<String?> showDiscountCardEditor(
  BuildContext context,
  WidgetRef ref, {
  required List<Map<String, dynamic>> types,
  Map<String, dynamic>? existing,
  String initialNo = '',
}) async {
  final no = TextEditingController(
    text: existing?['card_no'] as String? ?? initialNo,
  );
  final holder = TextEditingController(
    text: existing?['holder_name'] as String? ?? '',
  );
  final notes = TextEditingController(
    text: existing?['notes'] as String? ?? '',
  );
  String? typeId =
      existing?['card_type_id'] as String? ??
      (types.length == 1 ? types.first['id'] as String : null);
  String? customerId = existing?['customer_id'] as String?;
  String customerName = existing?['customer_name'] as String? ?? '';
  DateTime? until = existing?['valid_until'] == null
      ? null
      : DateTime.tryParse(existing!['valid_until'] as String);
  var active = existing?['is_active'] as bool? ?? true;
  var busy = false;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(existing == null ? t('Add card') : t('Change card')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: no,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t('Card number, as printed'),
                    helperText: t('Spaces and dashes don\'t matter.'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: typeId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('Card type')),
                  items: [
                    for (final ty in types)
                      DropdownMenuItem(
                        value: ty['id'] as String,
                        child: Text(
                          '${ty['name']} — ${qty(ty['discount_pct'] as num?)}%',
                        ),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => typeId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: holder,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: t('Given to (optional)'),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customerName.isEmpty
                            ? t('Not linked to a customer')
                            : t('Customer: {v1}', {'v1': customerName}),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final c = await showCustomerPicker(ctx);
                        if (c != null) {
                          setLocal(() {
                            customerId = c['id'] as String?;
                            customerName = c['name'] as String? ?? '';
                          });
                        }
                      },
                      child: Text(
                        customerName.isEmpty ? t('Link') : t('Change'),
                      ),
                    ),
                    if (customerName.isNotEmpty)
                      IconButton(
                        tooltip: t('Remove'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setLocal(() {
                          customerId = null;
                          customerName = '';
                        }),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        until == null
                            ? t('Valid for life')
                            : t('Valid till {v1}', {
                                'v1': dateStr(until!.toIso8601String()),
                              }),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate:
                              until ??
                              DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) setLocal(() => until = d);
                      },
                      child: Text(t('Set date')),
                    ),
                    if (until != null)
                      IconButton(
                        tooltip: t('Remove'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setLocal(() => until = null),
                      ),
                  ],
                ),
                TextField(
                  controller: notes,
                  decoration: InputDecoration(labelText: t('Note (optional)')),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                    title: Text(t('In use')),
                    subtitle: Text(t('Switched off: it gives no discount.')),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: busy
                ? null
                : () async {
                    setLocal(() => busy = true);
                    try {
                      final id = await ref
                          .read(supabaseProvider)
                          .rpc(
                            'save_discount_card',
                            params: {
                              'p_id': existing?['id'],
                              'p': {
                                'card_no': no.text.trim(),
                                'card_type_id': typeId,
                                'holder_name': holder.text.trim(),
                                'customer_id': customerId,
                                'valid_until': until == null
                                    ? null
                                    : ymd(until!),
                                'is_active': active,
                                'notes': notes.text.trim(),
                              },
                            },
                          );
                      if (ctx.mounted) Navigator.pop(ctx, id as String);
                    } catch (e) {
                      setLocal(() => busy = false);
                      if (ctx.mounted) showError(ctx, e);
                    }
                  },
            child: Text(t('Save')),
          ),
        ],
      ),
    ),
  );
}
