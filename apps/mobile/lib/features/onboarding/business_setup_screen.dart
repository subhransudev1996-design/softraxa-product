import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  late String _type = widget.existing?['business_type'] ?? 'mobile';
  late String _taxPref = widget.existing?['tax_preference'] ?? 'gst';
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
              child: const Text('Logout'),
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
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Business logo'),
                ),
              ),
              const SectionLabel('Business details'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Business name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _owner,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Owner name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Business type'),
                items: const [
                  DropdownMenuItem(value: 'mobile', child: Text('Mobile shop')),
                  DropdownMenuItem(
                    value: 'garment',
                    child: Text('Garment shop'),
                  ),
                  DropdownMenuItem(
                    value: 'hardware',
                    child: Text('Hardware shop'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Business email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Business address',
                ),
              ),
              const SectionLabel('Tax & billing'),
              DropdownButtonFormField<String>(
                initialValue: _taxPref,
                decoration: const InputDecoration(labelText: 'Tax preference'),
                items: const [
                  DropdownMenuItem(value: 'gst', child: Text('GST billing')),
                  DropdownMenuItem(
                    value: 'non_gst',
                    child: Text('Non-GST billing'),
                  ),
                ],
                onChanged: (v) => setState(() => _taxPref = v ?? 'gst'),
              ),
              const SizedBox(height: 12),
              if (_taxPref == 'gst')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _gst,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'GST number (GSTIN)',
                    ),
                    validator: (v) => gstinError(v ?? ''),
                    onChanged: (v) {
                      final s = stateFromGstin(v);
                      if (s != null && s != _state) setState(() => _state = s);
                    },
                  ),
                ),
              if (_taxPref == 'gst')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GstStateField(
                    value: _state,
                    label: 'State *',
                    helperText: 'Decides CGST + SGST vs IGST on invoices',
                    onChanged: (v) => setState(() => _state = v),
                    validator: (v) => (v ?? '').isEmpty
                        ? 'Required for GST billing'
                        : null,
                  ),
                ),
              TextFormField(
                controller: _defaultCredit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Default credit limit for new customers ₹',
                  helperText:
                      '0 = new customers get no credit until you set a limit',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prefix,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Invoice prefix',
                  helperText: 'e.g. INV — invoices become INV-00001',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
