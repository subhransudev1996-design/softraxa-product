import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'customer_providers.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../offline/offline_service.dart';
import '../../core/theme.dart';

/// Bottom sheet to pick (or quickly add) a customer. Works offline
/// from the cached customer list.
Future<Map<String, dynamic>?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const _CustomerPicker(),
    ),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _search = '';
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final offline = ref.read(offlineServiceProvider);
    try {
      final client = ref.read(supabaseProvider);
      var query = client
          .from('customers')
          .select(
            'id, name, phone, address, due_amount, advance_amount, credit_limit, is_wholesale',
          )
          .eq('is_active', true);
      if (_search.isNotEmpty) {
        query = query.or('name.ilike.%$_search%,phone.ilike.%$_search%');
      }
      final rows = List<Map<String, dynamic>>.from(
        await query.order('name', ascending: true).limit(50),
      );
      if (_search.isEmpty) offline.cacheCustomers(rows);
      if (mounted) {
        setState(() {
          _customers = rows;
          _loading = false;
        });
      }
    } catch (_) {
      final rows = await offline.searchCachedCustomers(_search);
      if (mounted) {
        setState(() {
          _customers = rows;
          _loading = false;
        });
      }
    }
  }

  Future<void> _quickAdd() async {
    final name = TextEditingController(text: _search);
    final phone = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('New customer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t('Name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t('Phone')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Add')),
          ),
        ],
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    try {
      final client = ref.read(supabaseProvider);
      final businessId = ref.read(appContextProvider).value?.businessId;
      final row = await client
          .from('customers')
          .insert({
            'business_id': businessId,
            'name': name.text.trim(),
            'phone': phone.text.trim(),
          })
          .select(
            'id, name, phone, address, due_amount, advance_amount, credit_limit, is_wholesale',
          )
          .single();
      ref.invalidate(customersProvider);
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(row));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: SearchField(
                    hint: t('Search name or phone'),
                    autofocus: true,
                    onChanged: (v) {
                      _search = v;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _quickAdd,
                  icon: const Icon(Icons.person_add),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                ? EmptyState(
                    icon: Icons.person_search,
                    message: t('No customers found'),
                    action: FilledButton.icon(
                      onPressed: _quickAdd,
                      icon: const Icon(Icons.add),
                      label: Text(t('Add new customer')),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    itemCount: _customers.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final c = _customers[i];
                      final due = toDouble(c['due_amount']);
                      return ListTile(
                        leading: InitialsAvatar(
                          c['name'] as String? ?? '',
                          radius: 19,
                        ),
                        title: Text(c['name'] as String),
                        subtitle: Text(c['phone'] as String? ?? ''),
                        trailing: due > 0
                            ? Text(
                                t('Due {v1}', {'v1': money(due)}),
                                style: const TextStyle(
                                  color: AppColors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
