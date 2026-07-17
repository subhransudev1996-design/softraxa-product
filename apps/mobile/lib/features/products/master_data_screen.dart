import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data_refresh.dart';

import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import 'product_providers.dart';
import '../../core/theme.dart';

/// Manage categories, brands and units (PRD 7.4).
class MasterDataScreen extends ConsumerWidget {
  const MasterDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(
          leading: appBarBack(context),
          title: const Text('Categories, brands & units'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Categories'),
              Tab(text: 'Brands'),
              Tab(text: 'Units'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _MasterList(table: 'categories'),
            _MasterList(table: 'brands'),
            _MasterList(table: 'units'),
          ],
        ),
      ),
    );
  }
}

class _MasterList extends ConsumerWidget {
  const _MasterList({required this.table});

  final String table;

  AsyncValue<List<Map<String, dynamic>>> _watch(WidgetRef ref) =>
      switch (table) {
        'categories' => ref.watch(categoriesProvider),
        'brands' => ref.watch(brandsProvider),
        _ => ref.watch(unitsProvider),
      };

  void _invalidate(WidgetRef ref) {
    switch (table) {
      case 'categories':
        ref.invalidate(categoriesProvider);
    // category/brand names are embedded in product rows; units drive
    // decimal rules in POS — refresh those screens too
    invalidateStockData(ref);
      case 'brands':
        ref.invalidate(brandsProvider);
      default:
        ref.invalidate(unitsProvider);
    }
  }

  Future<void> _addOrEdit(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? existing,
  }) async {
    final name = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );
    final shortName = TextEditingController(
      text: existing?['short_name'] as String? ?? '',
    );
    bool allowDecimal = existing?['allow_decimal'] as bool? ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add' : 'Edit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (table == 'units') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: shortName,
                  decoration: const InputDecoration(
                    labelText: 'Short name (pcs, kg…)',
                  ),
                ),
                SwitchListTile(
                  value: allowDecimal,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow decimal qty'),
                  onChanged: (v) => setState(() => allowDecimal = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;

    final client = ref.read(supabaseProvider);
    final businessId = ref.read(appContextProvider).value?.businessId;
    final row = {
      'name': name.text.trim(),
      if (table == 'units') 'short_name': shortName.text.trim(),
      if (table == 'units') 'allow_decimal': allowDecimal,
    };
    try {
      if (existing == null) {
        await client.from(table).insert({...row, 'business_id': businessId});
      } else {
        await client.from(table).update(row).eq('id', existing['id'] as String);
      }
      _invalidate(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${row['name']}"?',
      message: 'Products using it will keep working but lose this label.',
      confirmText: 'Delete',
    );
    if (!ok) return;
    try {
      await ref
          .read(supabaseProvider)
          .from(table)
          .delete()
          .eq('id', row['id'] as String);
      _invalidate(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = _watch(ref);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_$table',
        onPressed: () => _addOrEdit(context, ref),
        child: const Icon(Icons.add),
      ),
      body: AsyncView(
        value: value,
        onRetry: () => _invalidate(ref),
        builder: (rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.category_outlined,
                message: 'Nothing here yet.\nTap + to add.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  return ListTile(
                    title: Text(row['name'] as String),
                    subtitle: table == 'units'
                        ? Text(row['short_name'] as String? ?? '')
                        : null,
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.red,
                      ),
                      onPressed: () => _delete(context, ref, row),
                    ),
                    onTap: () => _addOrEdit(context, ref, existing: row),
                  );
                },
              ),
      ),
    );
  }
}
