import '../../core/i18n.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/business_category.dart';
import '../../core/data_export.dart';
import '../../core/gst.dart';
import '../../core/imagekit.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';

/// Business profile form (PRD 7.2). Used for first-time setup and,
/// with [existing] set, for editing the profile from Settings.
class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key, this.existing});

  final Map<String, dynamic>? existing;

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.existing?['name'] ?? '',
  );
  late final _owner = TextEditingController(
    text: widget.existing?['owner_name'] ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.existing?['phone'] ?? '',
  );
  late final _email = TextEditingController(
    text: widget.existing?['email'] ?? '',
  );
  late final _address = TextEditingController(
    text: widget.existing?['address'] ?? '',
  );
  late final _gst = TextEditingController(
    text: widget.existing?['gst_number'] ?? '',
  );
  late final _prefix = TextEditingController(
    text: widget.existing?['invoice_prefix'] ?? 'INV',
  );
  late String _state = widget.existing?['state_code'] ?? '';
  late final _defaultCredit = TextEditingController(
    text:
        (widget.existing?['default_credit_limit'] as num?)?.toStringAsFixed(
          0,
        ) ??
        '0',
  );
  late final _returnWindow = TextEditingController(
    text: '${(widget.existing?['return_window_days'] as num?)?.toInt() ?? 30}',
  );
  // PD19/PD20: due date = bill date + terms; overdue after the grace days.
  late final _terms = TextEditingController(
    text: '${(widget.existing?['payment_terms_days'] as num?)?.toInt() ?? 30}',
  );
  late final _grace = TextEditingController(
    text: '${(widget.existing?['overdue_grace_days'] as num?)?.toInt() ?? 0}',
  );
  // D37: repair work waits for the customer's approval of an estimate.
  late bool _requireEstimate =
      widget.existing?['require_repair_estimate'] as bool? ?? true;
  late String _type = widget.existing?['business_type'] ?? 'mobile';
  late String _taxPref = widget.existing?['tax_preference'] ?? 'gst';
  late final _upi = TextEditingController(
    text: widget.existing?['upi_id'] as String? ?? '',
  );
  late String? _band = widget.existing?['turnover_band'] as String?;
  XFile? _logo;
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 85,
    );
    if (img != null) setState(() => _logo = img);
  }

  Future<String?> _uploadLogo(SupabaseClient client, String businessId) async {
    if (_logo == null) return null;
    final ext = _logo!.path.split('.').last.toLowerCase();
    return uploadToImageKit(
      client,
      File(_logo!.path),
      fileName: 'logo_$businessId.$ext',
      folder: '/logos',
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final client = ref.read(supabaseProvider);
    try {
      final payload = {
        'name': _name.text.trim(),
        'owner_name': _owner.text.trim(),
        'business_type': _type,
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'address': _address.text.trim(),
        'gst_number': _gst.text.trim().toUpperCase(),
        'invoice_prefix': _prefix.text.trim().toUpperCase(),
        'tax_preference': _taxPref,
      };
      // Not accepted by create_business, so saved with a follow-up update.
      final extra = <String, dynamic>{
        'state_code': _state,
        'default_credit_limit': double.tryParse(_defaultCredit.text) ?? 0,
        'return_window_days': int.tryParse(_returnWindow.text.trim()) ?? 30,
        'payment_terms_days': int.tryParse(_terms.text.trim()) ?? 30,
        'overdue_grace_days': int.tryParse(_grace.text.trim()) ?? 0,
        'require_repair_estimate': _requireEstimate,
        'upi_id': _upi.text.trim(),
        if (_taxPref != 'non_gst') 'turnover_band': _band,
      };
      if (isEdit) {
        final id = widget.existing!['id'] as String;
        final logoUrl = await _uploadLogo(client, id);
        if (logoUrl != null) payload['logo_url'] = logoUrl;
        await client
            .from('businesses')
            .update({...payload, ...extra})
            .eq('id', id);
      } else {
        final businessId =
            await client.rpc('create_business', params: {'payload': payload})
                as String;
        final logoUrl = await _uploadLogo(client, businessId);
        await client
            .from('businesses')
            .update({...extra, 'logo_url': ?logoUrl})
            .eq('id', businessId);
      }
      await ref.read(appContextProvider.notifier).refresh();
      if (mounted) {
        showSuccess(context, isEdit ? 'Business updated' : 'Business created!');
        if (isEdit) Navigator.of(context).pop();
        // For setup, the router redirects to the dashboard automatically.
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ask SOFTRAXA to delete the shop's account and data (migration 0058).
  Future<void> _requestDeletion() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Delete your account?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('SOFTRAXA will delete your shop, its logins and its data, and confirm on WhatsApp or by email. Bills may be kept for as long as GST law requires. Export your data first if you want a copy.'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: t('Reason (optional)')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Ask to delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(supabaseProvider)
          .rpc(
            'request_account_deletion',
            params: {'p_reason': reason.text.trim()},
          );
      if (mounted) {
        showSuccess(
          context,
          t('Request sent — SOFTRAXA will confirm when your account is deleted'),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: Text(isEdit ? 'Business profile' : 'Set up your business'),
        actions: [
          if (!isEdit)
            TextButton(
              onPressed: () => ref.read(supabaseProvider).auth.signOut(),
              child: Text(t('Logout')),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: InkWell(
                  onTap: _pickLogo,
                  borderRadius: BorderRadius.circular(50),
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.line,
                    backgroundImage: _logo != null
                        ? FileImage(File(_logo!.path))
                        : (widget.existing?['logo_url'] != null
                                  ? NetworkImage(
                                      widget.existing!['logo_url'] as String,
                                    )
                                  : null)
                              as ImageProvider?,
                    child: _logo == null && widget.existing?['logo_url'] == null
                        ? const Icon(Icons.add_a_photo_outlined, size: 28)
                        : null,
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(t('Business logo')),
                ),
              ),
              SectionLabel(t('Business details')),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t('Business name *')),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _owner,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t('Owner name')),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(labelText: t('Business type')),
                items: [
                  for (final c in businessCategories)
                    DropdownMenuItem(value: c.key, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t('Phone number')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t('Business email')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: t('Business address'),
                ),
              ),
              SectionLabel(t('Tax & billing')),
              DropdownButtonFormField<String>(
                initialValue: _taxPref,
                decoration: InputDecoration(labelText: t('Tax preference')),
                items: [
                  DropdownMenuItem(value: 'gst', child: Text(t('GST billing'))),
                  DropdownMenuItem(
                    value: 'composition',
                    child: Text(t('Composition (bill of supply)')),
                  ),
                  DropdownMenuItem(
                    value: 'non_gst',
                    child: Text(t('Non-GST billing')),
                  ),
                ],
                onChanged: (v) => setState(() => _taxPref = v ?? 'gst'),
              ),
              const SizedBox(height: 12),
              if (_taxPref != 'non_gst')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _gst,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: t('GST number (GSTIN)'),
                    ),
                    validator: (v) => gstinError(v ?? ''),
                    onChanged: (v) {
                      final s = stateFromGstin(v);
                      if (s != null && s != _state) setState(() => _state = s);
                    },
                  ),
                ),
              if (_taxPref != 'non_gst')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GstStateField(
                    value: _state,
                    label: t('State *'),
                    helperText: t('Decides CGST + SGST vs IGST on invoices'),
                    onChanged: (v) => setState(() => _state = v),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Required for GST billing' : null,
                  ),
                ),
              if (_taxPref != 'non_gst')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _band,
                    decoration: InputDecoration(
                      labelText: t('Annual turnover'),
                      helperText: t('Above ₹5 crore needs e-invoicing — contact SOFTRAXA'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'up_to_5cr',
                        child: Text(t('Up to ₹5 crore')),
                      ),
                      DropdownMenuItem(
                        value: 'above_5cr',
                        child: Text(t('Above ₹5 crore')),
                      ),
                    ],
                    onChanged: (v) => setState(() => _band = v),
                  ),
                ),
              TextFormField(
                controller: _upi,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: t('UPI ID (optional)'),
                  hintText: t('shopname@okaxis'),
                  helperText: t('Printed on bills as a "scan to pay" QR code'),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty ||
                          RegExp(
                            r'^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$',
                          ).hasMatch(t)
                      ? null
                      : 'Enter a UPI ID like name@bank';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _defaultCredit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t('Default credit limit for new customers ₹'),
                  helperText: t('0 = new customers get no credit until you set a limit'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _returnWindow,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('Return window (days)'),
                  helperText: t('Returns after this need the owner and a reason. 0 = no limit'),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 0 || n > 3650
                      ? 'Enter 0–3650 days'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _terms,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('Payment terms (days)'),
                        helperText: t('Credit bills are due after this'),
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 0 || n > 365 ? '0–365' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _grace,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('Grace days'),
                        helperText: t('Before a bill counts as overdue'),
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 0 || n > 365 ? '0–365' : null;
                      },
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _requireEstimate,
                onChanged: (v) => setState(() => _requireEstimate = v),
                title: Text(t('Repairs need an approved estimate')),
                subtitle: Text(t('Job card work starts only after the customer approves the estimate. Turn off if you don\'t do repairs.'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prefix,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('Invoice prefix'),
                  helperText: t('Up to 4 characters — bills become INV/26-27/0001'),
                ),
                // Bill numbers must fit in 16 characters (migration 0048).
                validator: (v) =>
                    RegExp(r'^[A-Za-z0-9]{1,4}$').hasMatch((v ?? '').trim())
                    ? null
                    : '1–4 letters or digits',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEdit ? 'Save changes' : 'Start using the app'),
              ),
              // Full data export for the owner (migration 0050).
              if (isEdit &&
                  (ref.watch(appContextProvider).value?.isOwner ?? false)) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => exportAllData(context, ref),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(t('Export all data (Excel)')),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: _requestDeletion,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(t('Delete my account')),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
