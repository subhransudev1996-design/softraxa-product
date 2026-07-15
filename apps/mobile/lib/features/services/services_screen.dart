import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import 'service_providers.dart';

/// Service catalog management (PRD Phase 2 §5).
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  Future<void> _addOrEdit(BuildContext context, WidgetRef ref,
      {Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name'] as String? ?? '');
    final category = TextEditingController(text: existing?['category'] as String? ?? '');
    final price = TextEditingController(
        text: existing == null ? '' : toDouble(existing['price']).toStringAsFixed(2));
    final sacCode = TextEditingController(text: existing?['sac_code'] as String? ?? '');
    final minutes = TextEditingController(
        text: existing?['estimated_minutes']?.toString() ?? '');
    final warrantyDays = TextEditingController(
        text: existing?['warranty_days']?.toString() ?? '');
    final description = TextEditingController(text: existing?['description'] as String? ?? '');
    double gstRate = (existing?['gst_rate'] as num?)?.toDouble() ?? 18;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add service' : 'Edit service'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Service name *')),
              const SizedBox(height: 12),
              TextField(
                  controller: category,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Category (optional)')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price ₹ *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<double>(
                    initialValue: gstRate,
                    decoration: const InputDecoration(labelText: 'GST %'),
                    items: const [
                      DropdownMenuItem(value: 0.0, child: Text('0%')),
                      DropdownMenuItem(value: 5.0, child: Text('5%')),
                      DropdownMenuItem(value: 12.0, child: Text('12%')),
                      DropdownMenuItem(value: 18.0, child: Text('18%')),
                      DropdownMenuItem(value: 28.0, child: Text('28%')),
                    ],
                    onChanged: (v) => setState(() => gstRate = v ?? 0),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: sacCode,
                  decoration: const InputDecoration(labelText: 'SAC code (optional)')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Est. time (minutes)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: warrantyDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Warranty (days)'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;

    final row = {
      'name': name.text.trim(),
      'category': category.text.trim(),
      'price': double.tryParse(price.text) ?? 0,
      'gst_rate': gstRate,
      'sac_code': sacCode.text.trim(),
      'estimated_minutes': int.tryParse(minutes.text),
      'warranty_days': int.tryParse(warrantyDays.text),
      'description': description.text.trim(),
    };
    try {
      final client = ref.read(supabaseProvider);
      if (existing == null) {
        final businessId = ref.read(appContextProvider).value?.businessId;
        await client.from('services').insert({...row, 'business_id': businessId});
      } else {
        await client.from('services').update(row).eq('id', existing['id'] as String);
      }
      ref.invalidate(servicesProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Map<String, dynamic> service) async {
    final ok = await confirmDialog(context,
        title: 'Remove "${service['name']}"?',
        message: 'This only hides it from the service catalog; past job cards are unaffected.',
        confirmText: 'Remove');
    if (!ok) return;
    try {
      await ref
          .read(supabaseProvider)
          .from('services')
          .update({'is_active': false}).eq('id', service['id'] as String);
      ref.invalidate(servicesProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Service catalog')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: AsyncView(
        value: services,
        onRetry: () => ref.invalidate(servicesProvider),
        builder: (rows) => rows.isEmpty
            ? const EmptyState(
                icon: Icons.build_outlined,
                message: 'No services yet.\nAdd repair/labor charges you offer.')
            : isDesktop
                ? DesktopTable<Map<String, dynamic>>(
                    rows: rows,
                    trailingWidth: 90,
                    columns: [
                      DesktopTableColumn(
                          label: 'Service',
                          flex: 3,
                          comparable: (s) => (s['name'] as String? ?? '').toLowerCase()),
                      DesktopTableColumn(
                          label: 'Category',
                          flex: 2,
                          comparable: (s) => (s['category'] as String? ?? '').toLowerCase()),
                      DesktopTableColumn(
                          label: 'Price',
                          flex: 2,
                          alignEnd: true,
                          comparable: (s) => toDouble(s['price'])),
                    ],
                    rowBuilder: (context, s) => _ServiceRow(
                        service: s,
                        onTap: () => _addOrEdit(context, ref, existing: s),
                        onDelete: () => _delete(context, ref, s)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ServiceTile(
                        service: rows[i],
                        onTap: () => _addOrEdit(context, ref, existing: rows[i]),
                        onDelete: () => _delete(context, ref, rows[i])),
                  ),
      ),
    );
  }
}

// ==================== desktop: sortable data table ====================

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.onTap, required this.onDelete});

  final Map<String, dynamic> service;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = service;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Text(s['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
          Expanded(
            flex: 2,
            child: Text(
                (s['category'] as String? ?? '').isNotEmpty ? s['category'] as String : 'Service',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          ),
          Expanded(
            flex: 2,
            child: Text(money(s['price'] as num?),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
          SizedBox(
            width: 90,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 18),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ==================== mobile: card list (unchanged) ====================

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap, required this.onDelete});

  final Map<String, dynamic> service;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = service;
    // Built manually instead of ListTile (its trailing slot
    // enforces a fixed max height independent of contentPadding,
    // which this 2-line trailing column can overflow under some
    // font metrics).
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            const IconChip(Icons.build_outlined, color: AppColors.indigo, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      (s['category'] as String? ?? '').isNotEmpty
                          ? s['category'] as String
                          : 'Service',
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(s['price'] as num?),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 18),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
