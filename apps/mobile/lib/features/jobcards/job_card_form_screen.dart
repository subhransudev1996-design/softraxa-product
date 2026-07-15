import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import '../customers/customer_picker.dart';
import 'job_card_providers.dart';

/// Repair/service intake flow (PRD Phase 2 §7).
class JobCardFormScreen extends ConsumerStatefulWidget {
  const JobCardFormScreen({super.key});

  @override
  ConsumerState<JobCardFormScreen> createState() => _JobCardFormScreenState();
}

class _JobCardFormScreenState extends ConsumerState<JobCardFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _customer;
  final _itemName = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serialNo = TextEditingController();
  final _issue = TextEditingController();
  final _condition = TextEditingController();
  final _accessories = TextEditingController();
  final _technician = TextEditingController();
  final _estimatedCost = TextEditingController();
  final _advanceAmount = TextEditingController();
  final _customerNote = TextEditingController();
  final _internalNote = TextEditingController();
  String _advanceMode = 'cash';
  DateTime? _expectedDelivery;
  bool _busy = false;

  Future<void> _scanSerial() async {
    final code = isDesktopPlatform
        ? await promptBarcode(context, title: 'Enter serial number')
        : await context.push<String>('/scan?mode=return');
    if (!mounted) return;
    if (code != null && code.isNotEmpty) setState(() => _serialNo.text = code);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final payload = {
        'customer_id': _customer?['id'],
        'customer_name': _customer?['name'] ?? '',
        'customer_phone': _customer?['phone'] ?? '',
        'item_name': _itemName.text.trim(),
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        'serial_no': _serialNo.text.trim(),
        'issue_description': _issue.text.trim(),
        'item_condition': _condition.text.trim(),
        'accessories_received': _accessories.text.trim(),
        'technician_name': _technician.text.trim(),
        'estimated_cost': double.tryParse(_estimatedCost.text) ?? 0,
        'advance_amount': double.tryParse(_advanceAmount.text) ?? 0,
        'advance_mode': _advanceMode,
        'expected_delivery': _expectedDelivery != null ? ymd(_expectedDelivery!) : null,
        'customer_note': _customerNote.text.trim(),
        'internal_note': _internalNote.text.trim(),
      };
      final res = await ref
          .read(supabaseProvider)
          .rpc('create_job_card', params: {'payload': payload}) as Map<String, dynamic>;
      ref.invalidate(jobCardsProvider);
      if (mounted) {
        showSuccess(context, 'Job card ${res['job_no']} created');
        context.pushReplacement('/job-cards/${res['id']}');
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
      appBar: AppBar(title: const Text('New job card')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionLabel('Customer'),
            Card(
              child: ListTile(
                leading: _customer == null
                    ? const IconChip(Icons.person_outline, color: AppColors.indigo, size: 40)
                    : InitialsAvatar(_customer!['name'] as String? ?? ''),
                title: Text(_customer?['name'] as String? ?? 'Walk-in customer'),
                subtitle: _customer?['phone'] != null && (_customer!['phone'] as String).isNotEmpty
                    ? Text(_customer!['phone'] as String)
                    : const Text('Optional, needed for due tracking'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showCustomerPicker(context);
                  if (picked != null) setState(() => _customer = picked);
                },
              ),
            ),
            const SectionLabel('Device / item'),
            TextFormField(
              controller: _itemName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Item name *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextFormField(
                      controller: _brand,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Brand'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextFormField(
                      controller: _model,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Model'))),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serialNo,
              decoration: InputDecoration(
                labelText: 'IMEI / serial number (optional)',
                suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner), onPressed: _scanSerial),
              ),
            ),
            const SectionLabel('Issue'),
            TextFormField(
              controller: _issue,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Problem / issue description *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _condition,
                decoration: const InputDecoration(labelText: 'Item condition at receiving (optional)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _accessories,
                decoration: const InputDecoration(labelText: 'Accessories received (optional)')),
            const SectionLabel('Estimate & advance'),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _estimatedCost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Estimated cost ₹'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _advanceAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Advance paid ₹'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _advanceMode,
              decoration: const InputDecoration(labelText: 'Advance payment mode'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
              ],
              onChanged: (v) => setState(() => _advanceMode = v ?? 'cash'),
            ),
            const SectionLabel('Delivery & technician'),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expectedDelivery ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _expectedDelivery = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expected delivery date'),
                child: Text(_expectedDelivery == null ? 'Not set' : dateStr(_expectedDelivery)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _technician,
                decoration: const InputDecoration(labelText: 'Technician name (optional)')),
            const SectionLabel('Notes'),
            TextFormField(
                controller: _customerNote,
                decoration: const InputDecoration(labelText: 'Customer-visible note (optional)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _internalNote,
                decoration: const InputDecoration(labelText: 'Internal note (optional)')),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create job card'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
