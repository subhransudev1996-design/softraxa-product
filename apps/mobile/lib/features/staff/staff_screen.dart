import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Every staff permission the database enforces (migration 0037 —
/// has_permission / staff_permission_defaults). Staff management itself is
/// owner-only, so it isn't offered here.
typedef StaffPermission = ({
  String key,
  String label,
  String chip,
  bool byDefault,
});

// A getter, not a const: labels are translated (t()) when read.
List<StaffPermission> get staffPermissions => [
  (
    key: 'can_create_invoice',
    label: t('Create bills (POS)'),
    chip: 'Billing',
    byDefault: true,
  ),
  (
    key: 'can_edit_prices',
    label: t('Change prices & give discounts'),
    chip: 'Prices',
    byDefault: false,
  ),
  (
    key: 'can_record_payments',
    label: t('Receive customer payments'),
    chip: 'Payments',
    byDefault: true,
  ),
  (
    key: 'can_edit_invoices',
    label: t('Edit or cancel bills'),
    chip: 'Edit bills',
    byDefault: false,
  ),
  (
    key: 'can_manage_returns',
    label: t('Sale returns & refunds'),
    chip: 'Returns',
    byDefault: false,
  ),
  (
    key: 'can_manage_products',
    label: t('Add & edit products'),
    chip: 'Products',
    byDefault: true,
  ),
  (
    key: 'can_manage_stock',
    label: t('Stock adjustments & cut pieces'),
    chip: 'Stock',
    byDefault: false,
  ),
  (
    key: 'can_manage_purchases',
    label: t('Purchases, suppliers & supplier payments'),
    chip: 'Purchases',
    byDefault: false,
  ),
  (
    key: 'can_manage_expenses',
    label: t('Expenses'),
    chip: 'Expenses',
    byDefault: false,
  ),
  (
    key: 'can_manage_cash',
    label: t('Cash drawer & day closing'),
    chip: 'Cash',
    byDefault: false,
  ),
  (
    key: 'can_manage_services',
    label: t('Services & job cards'),
    chip: 'Services',
    byDefault: true,
  ),
  (
    key: 'can_view_reports',
    label: t('View reports'),
    chip: 'Reports',
    byDefault: false,
  ),
  (
    key: 'can_view_profit',
    label: t('See cost prices & profit'),
    chip: 'Profit',
    byDefault: false,
  ),
];

/// Checkbox list shared by the add and edit dialogs.
class _PermissionChecklist extends StatelessWidget {
  const _PermissionChecklist({required this.values, required this.onChanged});

  final Map<String, bool> values;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in staffPermissions)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(p.label),
            value: values[p.key] ?? p.byDefault,
            onChanged: (v) => onChanged(p.key, v ?? false),
          ),
      ],
    );
  }
}

final staffListProvider =
    AsyncNotifierProvider<StaffListNotifier, List<Map<String, dynamic>>>(
      StaffListNotifier.new,
    );

class StaffListNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final client = ref.watch(supabaseProvider);
    final ctx = await ref.watch(appContextProvider.future);
    if (!ctx.hasBusiness) return [];

    final profiles = await client
        .from('profiles')
        .select('id, full_name, email, role, created_at')
        .eq('business_id', ctx.businessId!)
        .order('created_at');

    final permissions = await client
        .from('staff_permissions')
        .select('*')
        .eq('business_id', ctx.businessId!);

    final permMap = <String, Map<String, dynamic>>{};
    for (final p in (permissions as List<dynamic>)) {
      final map = p as Map<String, dynamic>;
      permMap[map['profile_id'] as String] = map;
    }

    final list = <Map<String, dynamic>>[];
    for (final p in (profiles as List<dynamic>)) {
      final map = Map<String, dynamic>.from(p as Map<String, dynamic>);
      map['permissions'] = permMap[map['id'] as String] ?? {};
      list.add(map);
    }
    return list;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(appContextProvider).value;
    final staffAsync = ref.watch(staffListProvider);

    final mainAction = ScreenAction(
      label: t('Add staff'),
      icon: Icons.person_add,
      onPressed: () {
        if (ctx?.isStaffLimitReached ?? false) {
          showError(
            context,
            'Staff limit reached for your plan (${ctx?.userLimit} allowed).',
          );
        } else {
          _showAddStaffDialog();
        }
      },
    );
    final isOwner = ctx?.isOwner ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Staff & Permissions')),
        leading: appBarBack(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(staffListProvider.notifier).refresh(),
          ),
          if (isOwner) mainAction.inAppBar(context),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (staffList) {
          final limit = ctx?.userLimit ?? 999;
          final isLimitReached = limit != 999 && staffList.length >= limit;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: isLimitReached
                    ? Colors.orange.shade50
                    : AppColors.primary.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(
                      isLimitReached
                          ? Icons.warning_amber_rounded
                          : Icons.people_outline,
                      color: isLimitReached
                          ? Colors.orange.shade900
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Staff Accounts: ${staffList.length} / ${limit == 999 ? "Unlimited" : limit}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isLimitReached
                                ? 'Plan limit reached. Upgrade plan to add more staff.'
                                : 'Store owners can create accounts and assign permissions.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isLimitReached
                                  ? Colors.orange.shade900
                                  : AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: staffList.isEmpty
                    ? EmptyState(
                        icon: Icons.person_off_outlined,
                        message: t('No staff members registered.\nTap + to add a staff account.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: staffList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final staff = staffList[index];
                          final isOwner =
                              staff['role'] == 'owner' ||
                              staff['role'] == 'admin';
                          final perms =
                              staff['permissions'] as Map<String, dynamic>;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: AppColors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: isOwner
                                            ? AppColors.primary
                                            : Colors.teal,
                                        child: Text(
                                          (staff['full_name'] as String? ?? 'S')
                                              .characters
                                              .first
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  staff['full_name']
                                                          as String? ??
                                                      'Staff User',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isOwner
                                                        ? Colors.blue.shade50
                                                        : Colors.teal.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    (staff['role'] as String? ??
                                                            'staff')
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isOwner
                                                          ? Colors.blue.shade900
                                                          : Colors
                                                                .teal
                                                                .shade900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              staff['email'] as String? ?? '',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.inkSoft,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!isOwner && (ctx?.isOwner ?? false))
                                        PopupMenuButton<String>(
                                          onSelected: (val) {
                                            if (val == 'edit') {
                                              _showEditPermissionsDialog(staff);
                                            } else if (val == 'delete') {
                                              _confirmDeleteStaff(staff);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.lock_person_outlined,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(t('Edit Permissions')),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(t('Remove User'),
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (!isOwner) ...[
                                    const Divider(height: 24),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final p in staffPermissions)
                                          _PermissionChip(
                                            p.chip,
                                            (perms[p.key] as bool?) ??
                                                p.byDefault,
                                          ),
                                      ],
                                    ),
                                  ],
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
      floatingActionButton: isOwner ? mainAction.fab(context) : null,
    );
  }

  void _showAddStaffDialog() {
    showDialog(context: context, builder: (ctx) => const _AddStaffDialog());
  }

  void _showEditPermissionsDialog(Map<String, dynamic> staff) {
    showDialog(
      context: context,
      builder: (ctx) => _EditPermissionsDialog(staff: staff),
    );
  }

  void _confirmDeleteStaff(Map<String, dynamic> staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Remove Staff Member')),
        content: Text(
          'Are you sure you want to remove ${staff['full_name']} (${staff['email']})? They will immediately lose access to this store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final client = ref.read(supabaseProvider);
                await client.rpc(
                  'delete_staff_user',
                  params: {'p_profile_id': staff['id']},
                );
                if (mounted) {
                  showSuccess(context, t('Staff member removed successfully.'));
                  ref.read(staffListProvider.notifier).refresh();
                  ref.read(appContextProvider.notifier).refresh();
                }
              } catch (e) {
                if (mounted) {
                  showError(context, e);
                }
              }
            },
            child: Text(t('Remove'), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip(this.label, this.enabled);
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: enabled ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: enabled ? Colors.green.shade300 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 12,
            color: enabled ? Colors.green.shade700 : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.green.shade900 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddStaffDialog extends ConsumerStatefulWidget {
  const _AddStaffDialog();

  @override
  ConsumerState<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends ConsumerState<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final Map<String, bool> _perms = {
    for (final p in staffPermissions) p.key: p.byDefault,
  };
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      final client = ref.read(supabaseProvider);
      final created = await client.rpc(
        'create_staff_user',
        params: {
          'p_email': _emailCtrl.text.trim(),
          'p_password': _passwordCtrl.text,
          'p_full_name': _nameCtrl.text.trim(),
          'p_permissions': _perms,
        },
      );
      // The cash permission (0045) is set by its own owner-only call.
      final userId = (created as Map?)?['user_id'] as String?;
      if (userId != null && _perms['can_manage_cash'] == true) {
        await client.rpc(
          'set_staff_cash_permission',
          params: {'p_profile': userId, 'p_value': true},
        );
      }

      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, t('Staff account created successfully!'));
        ref.read(staffListProvider.notifier).refresh();
        ref.read(appContextProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('Add New Staff User')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: t('Full Name *')),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t('Email Address *')),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Valid email required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(labelText: t('Password *')),
                validator: (v) => (v == null || v.length < 8)
                    ? 'At least 8 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              Text(t('Staff Access Permissions'),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _PermissionChecklist(
                values: _perms,
                onChanged: (k, v) => setState(() => _perms[k] = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('Cancel')),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Create Account')),
        ),
      ],
    );
  }
}

class _EditPermissionsDialog extends ConsumerStatefulWidget {
  const _EditPermissionsDialog({required this.staff});
  final Map<String, dynamic> staff;

  @override
  ConsumerState<_EditPermissionsDialog> createState() =>
      _EditPermissionsDialogState();
}

class _EditPermissionsDialogState
    extends ConsumerState<_EditPermissionsDialog> {
  late final Map<String, bool> _perms;
  late final TextEditingController _limit;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.staff['permissions'] as Map<String, dynamic>;
    _perms = {
      for (final perm in staffPermissions)
        perm.key: (p[perm.key] as bool?) ?? perm.byDefault,
    };
    // PD07/PD08: percent of the bill's default total; new staff start at 0.
    _limit = TextEditingController(
      text: '${(p['discount_limit_pct'] as num?)?.toDouble() ?? 0}'.replaceAll(
        RegExp(r'\.0$'),
        '',
      ),
    );
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limit = double.tryParse(_limit.text.trim()) ?? 0;
    if (limit < 0 || limit > 100) {
      showError(context, t('The discount limit must be between 0 and 100%'));
      return;
    }
    setState(() => _busy = true);
    try {
      final client = ref.read(supabaseProvider);
      await client.rpc(
        'update_staff_permissions',
        params: {'p_profile_id': widget.staff['id'], 'p_permissions': _perms},
      );
      await client.rpc(
        'set_staff_discount_limit',
        params: {
          'p_profile': widget.staff['id'],
          'p_pct': _perms['can_edit_prices'] == true ? limit : 0,
        },
      );
      await client.rpc(
        'set_staff_cash_permission',
        params: {
          'p_profile': widget.staff['id'],
          'p_value': _perms['can_manage_cash'] == true,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, t('Permissions updated successfully!'));
        ref.read(staffListProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Permissions (${widget.staff['full_name']})'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PermissionChecklist(
              values: _perms,
              onChanged: (k, v) => setState(() => _perms[k] = v),
            ),
            if (_perms['can_edit_prices'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _limit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: t('Discount limit %'),
                    helperText: t('Most a bill may go below the default prices — price changes, line and bill discounts together'),
                    helperMaxLines: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t('Cancel')),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Save Permissions')),
        ),
      ],
    );
  }
}
