import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/widgets.dart';
import '../../core/theme.dart';
import '../customers/customer_picker.dart';
import '../services/service_providers.dart';
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
  final _location = TextEditingController();
  final _estimatedCost = TextEditingController();
  final _advanceAmount = TextEditingController();
  final _customerNote = TextEditingController();
  final _internalNote = TextEditingController();
  // PD64: vehicle jobs record registration (required), odometer and fuel.
  // Garages start on vehicle; other shops on device.
  late String _jobType =
      (ref.read(appContextProvider).value?.category.vehicleJobs ?? false)
      ? 'vehicle'
      : 'device';
  final _registration = TextEditingController();
  final _odometer = TextEditingController();
  String _fuel = '';
  String _advanceMode = 'cash';
  // PD59: optional diagnostic fee, only with the customer's agreement.
  Map<String, dynamic>? _diagService;
  bool _diagConsent = false;
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
        'service_location': _location.text.trim(),
        'estimated_cost': double.tryParse(_estimatedCost.text) ?? 0,
        'advance_amount': double.tryParse(_advanceAmount.text) ?? 0,
        'advance_mode': _advanceMode,
        'expected_delivery': _expectedDelivery != null
            ? ymd(_expectedDelivery!)
            : null,
        'customer_note': _customerNote.text.trim(),
        'internal_note': _internalNote.text.trim(),
        'job_type': _jobType,
        if (_diagService != null) ...{
          'diagnostic_service_id': _diagService!['id'],
          'diagnostic_consent': _diagConsent,
        },
        if (_jobType == 'vehicle') ...{
          'registration_no': _registration.text.trim(),
          'odometer_km': int.tryParse(_odometer.text.trim()),
          'fuel_level': _fuel,
        },
      };
      final res =
          await ref
                  .read(supabaseProvider)
                  .rpc('create_job_card', params: {'payload': payload})
              as Map<String, dynamic>;
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

  /// Diagnostic fee (PD59): pick a service that has one, then record the
  /// customer's agreement. Hidden when no service has a fee.
  List<Widget> _diagnosticFee() {
    final services = (ref.watch(servicesProvider).value ?? const [])
        .where((s) => toDouble(s['diagnostic_fee']) > 0)
        .toList();
    if (services.isEmpty) return const [];
    final fee = toDouble(_diagService?['diagnostic_fee']);
    return [
      const SectionLabel('Diagnostic fee'),
      DropdownButtonFormField<String>(
        initialValue: _diagService?['id'] as String?,
        decoration: const InputDecoration(labelText: 'Checking fee (optional)'),
        items: [
          const DropdownMenuItem(value: null, child: Text('No diagnostic fee')),
          for (final s in services)
            DropdownMenuItem(
              value: s['id'] as String,
              child: Text(
                '${s['name']} — ${money(s['diagnostic_fee'] as num?)}',
              ),
            ),
        ],
        onChanged: (id) => setState(() {
          _diagService = id == null
              ? null
              : services.firstWhere((s) => s['id'] == id);
          _diagConsent = false;
        }),
      ),
      if (_diagService != null)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _diagConsent,
          onChanged: (v) => setState(() => _diagConsent = v ?? false),
          title: Text(
            'Customer agrees to pay ${money(fee)} for checking, even if the '
            'repair is not done',
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: appBarBack(context),
        title: const Text('New job card'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionLabel('Customer'),
            Card(
              child: ListTile(
                leading: _customer == null
                    ? const IconChip(
                        Icons.person_outline,
                        color: AppColors.indigo,
                        size: 40,
                      )
                    : InitialsAvatar(_customer!['name'] as String? ?? ''),
                title: Text(
                  _customer?['name'] as String? ?? 'Walk-in customer',
                ),
                subtitle:
                    _customer?['phone'] != null &&
                        (_customer!['phone'] as String).isNotEmpty
                    ? Text(_customer!['phone'] as String)
                    : const Text('Optional, needed for due tracking'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showCustomerPicker(context);
                  if (picked != null) setState(() => _customer = picked);
                },
              ),
            ),
            const SectionLabel('Device / vehicle'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'device',
                  icon: Icon(Icons.smartphone),
                  label: Text('Device / item'),
                ),
                ButtonSegment(
                  value: 'vehicle',
                  icon: Icon(Icons.two_wheeler),
                  label: Text('Vehicle'),
                ),
              ],
              selected: {_jobType},
              onSelectionChanged: (s) => setState(() => _jobType = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _itemName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _jobType == 'vehicle'
                    ? 'Vehicle (e.g. Bike, Car) *'
                    : 'Item name *',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            if (_jobType == 'vehicle') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _registration,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Registration number *',
                  hintText: 'e.g. OD02 AB 1234',
                ),
                validator: (v) =>
                    _jobType == 'vehicle' && (v == null || v.trim().isEmpty)
                    ? 'Required for vehicles'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _odometer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Odometer (km)',
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final n = int.tryParse(t);
                        return n == null || n < 0 ? 'Whole number' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _fuel,
                      decoration: const InputDecoration(
                        labelText: 'Fuel level',
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Not noted')),
                        DropdownMenuItem(value: 'empty', child: Text('Empty')),
                        DropdownMenuItem(value: 'quarter', child: Text('¼')),
                        DropdownMenuItem(value: 'half', child: Text('½')),
                        DropdownMenuItem(
                          value: 'three_quarter',
                          child: Text('¾'),
                        ),
                        DropdownMenuItem(value: 'full', child: Text('Full')),
                      ],
                      onChanged: (v) => setState(() => _fuel = v ?? ''),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _brand,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Brand'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Model'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serialNo,
              decoration: InputDecoration(
                labelText: 'IMEI / serial number (optional)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanSerial,
                ),
              ),
            ),
            const SectionLabel('Issue'),
            TextFormField(
              controller: _issue,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Problem / issue description *',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _condition,
              decoration: const InputDecoration(
                labelText: 'Item condition at receiving (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accessories,
              decoration: const InputDecoration(
                labelText: 'Accessories received (optional)',
              ),
            ),
            ..._diagnosticFee(),
            const SectionLabel('Estimate & advance'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _estimatedCost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Estimated cost ₹',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _advanceAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Advance paid ₹',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _advanceMode,
              decoration: const InputDecoration(
                labelText: 'Advance payment mode',
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
              ],
              onChanged: (v) => setState(() => _advanceMode = v ?? 'cash'),
            ),
            const SectionLabel('Delivery & technician'),
            TextFormField(
              controller: _location,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Service / installation location (optional)',
                hintText:
                    'e.g. Patia, Bhubaneswar — 2nd floor, near water tank',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
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
                decoration: const InputDecoration(
                  labelText: 'Expected delivery date',
                ),
                child: Text(
                  _expectedDelivery == null
                      ? 'Not set'
                      : dateStr(_expectedDelivery),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _technician,
              decoration: const InputDecoration(
                labelText: 'Technician name (optional)',
              ),
            ),
            const SectionLabel('Notes'),
            TextFormField(
              controller: _customerNote,
              decoration: const InputDecoration(
                labelText: 'Customer-visible note (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _internalNote,
              decoration: const InputDecoration(
                labelText: 'Internal note (optional)',
              ),
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
                  : const Text('Create job card'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
