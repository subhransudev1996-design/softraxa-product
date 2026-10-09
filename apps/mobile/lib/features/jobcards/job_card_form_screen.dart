import '../../core/i18n.dart';
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
import 'job_estimates.dart';

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

  /// Parts (from the product list) and labour (from the service catalog)
  /// for the estimate. With lines, the estimated cost is their total and
  /// the job is saved with this estimate for the customer to approve.
  final List<EstimateDraftLine> _estimateLines = [];

  double get _estimateTotal =>
      _estimateLines.fold<double>(0, (s, l) => s + l.total);

  @override
  void dispose() {
    for (final l in _estimateLines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _addEstimatePart() async {
    final line = await pickEstimatePart(context);
    if (line != null && mounted) setState(() => _estimateLines.add(line));
  }

  Future<void> _addEstimateLabour() async {
    final line = await pickEstimateLabour(context, ref);
    if (line != null && mounted) setState(() => _estimateLines.add(line));
  }

  Future<void> _scanSerial() async {
    final code = isDesktopPlatform
        ? await promptBarcode(context, title: t('Enter serial number'))
        : await context.push<String>('/scan?mode=return');
    if (!mounted) return;
    if (code != null && code.isNotEmpty) setState(() => _serialNo.text = code);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    for (final l in _estimateLines) {
      if (l.quantity <= 0 || l.unitPrice < 0) {
        showError(
          context,
          t('Check the quantity and price of {v1}', {'v1': l.name}),
        );
        return;
      }
    }
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
        'estimated_cost': _estimateLines.isNotEmpty
            ? double.parse(_estimateTotal.toStringAsFixed(2))
            : double.tryParse(_estimatedCost.text) ?? 0,
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
      // The parts and labour become the job's first estimate.
      if (_estimateLines.isNotEmpty) {
        try {
          await ref
              .read(supabaseProvider)
              .rpc(
                'create_job_estimate',
                params: {
                  'p_job_id': res['id'],
                  'p_lines': [for (final l in _estimateLines) l.toJson()],
                  'p_note': '',
                },
              );
        } catch (e) {
          if (mounted) {
            showError(
              context,
              t(
                'Job card {v1} saved, but the estimate was not — add it from the job card. ({v2})',
                {'v1': res['job_no'], 'v2': friendlyError(e)},
              ),
            );
            context.pushReplacement('/job-cards/${res['id']}');
          }
          return;
        }
      }
      if (mounted) {
        showSuccess(context, t('Job card {v1} created', {'v1': res['job_no']}));
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
      SectionLabel(t('Diagnostic fee')),
      DropdownButtonFormField<String>(
        initialValue: _diagService?['id'] as String?,
        decoration: InputDecoration(labelText: t('Checking fee (optional)')),
        items: [
          DropdownMenuItem(value: null, child: Text(t('No diagnostic fee'))),
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
        title: Text(t('New job card')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionLabel(t('Customer')),
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
                  _customer?['name'] as String? ?? t('Walk-in customer'),
                ),
                subtitle:
                    _customer?['phone'] != null &&
                        (_customer!['phone'] as String).isNotEmpty
                    ? Text(_customer!['phone'] as String)
                    : Text(t('Optional, needed for due tracking')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showCustomerPicker(context);
                  if (picked != null) setState(() => _customer = picked);
                },
              ),
            ),
            SectionLabel(t('Device / vehicle')),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'device',
                  icon: Icon(Icons.smartphone),
                  label: Text(t('Device / item')),
                ),
                ButtonSegment(
                  value: 'vehicle',
                  icon: Icon(Icons.two_wheeler),
                  label: Text(t('Vehicle')),
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
                    ? t('Vehicle (e.g. Bike, Car) *')
                    : 'Item name *',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('Required') : null,
            ),
            if (_jobType == 'vehicle') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _registration,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('Registration number *'),
                  hintText: t('e.g. OD02 AB 1234'),
                ),
                validator: (v) =>
                    _jobType == 'vehicle' && (v == null || v.trim().isEmpty)
                    ? t('Required for vehicles')
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _odometer,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t('Odometer (km)'),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return null;
                        final n = int.tryParse(s);
                        return n == null || n < 0 ? t('Whole number') : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _fuel,
                      decoration: InputDecoration(labelText: t('Fuel level')),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(t('Not noted')),
                        ),
                        DropdownMenuItem(
                          value: 'empty',
                          child: Text(t('Empty')),
                        ),
                        DropdownMenuItem(value: 'quarter', child: Text('¼')),
                        DropdownMenuItem(value: 'half', child: Text('½')),
                        DropdownMenuItem(
                          value: 'three_quarter',
                          child: Text('¾'),
                        ),
                        DropdownMenuItem(value: 'full', child: Text(t('Full'))),
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
                    decoration: InputDecoration(labelText: t('Brand')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: t('Model')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serialNo,
              decoration: InputDecoration(
                labelText: t('IMEI / serial number (optional)'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanSerial,
                ),
              ),
            ),
            SectionLabel(t('Issue')),
            TextFormField(
              controller: _issue,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t('Problem / issue description *'),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('Required') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _condition,
              decoration: InputDecoration(
                labelText: t('Item condition at receiving (optional)'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accessories,
              decoration: InputDecoration(
                labelText: t('Accessories received (optional)'),
              ),
            ),
            ..._diagnosticFee(),
            SectionLabel(t('Estimate & advance')),
            Text(
              t(
                'Add the parts from your product list and the labour, so the estimate uses your real prices.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _estimateLines.length; i++)
              EstimateLineCard(
                line: _estimateLines[i],
                onChanged: () => setState(() {}),
                onRemove: () =>
                    setState(() => _estimateLines.removeAt(i).dispose()),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addEstimatePart,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(t('Add part')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addEstimateLabour,
                    icon: const Icon(Icons.build_outlined),
                    label: Text(t('Add labour')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _estimateLines.isEmpty
                      ? TextFormField(
                          controller: _estimatedCost,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: t('Estimated cost ₹'),
                            helperText: t('Or add parts and labour above'),
                          ),
                        )
                      : InputDecorator(
                          decoration: InputDecoration(
                            labelText: t(
                              'Estimated cost (from the lines above)',
                            ),
                            helperText: t(
                              'Saved as the estimate for the customer to approve',
                            ),
                            helperMaxLines: 2,
                          ),
                          child: Text(
                            money(_estimateTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
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
                    decoration: InputDecoration(labelText: t('Advance paid ₹')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _advanceMode,
              decoration: InputDecoration(labelText: t('Advance payment mode')),
              items: [
                DropdownMenuItem(value: 'cash', child: Text(t('Cash'))),
                DropdownMenuItem(value: 'upi', child: Text(t('UPI'))),
                DropdownMenuItem(value: 'card', child: Text(t('Card'))),
              ],
              onChanged: (v) => setState(() => _advanceMode = v ?? 'cash'),
            ),
            SectionLabel(t('Delivery & technician')),
            TextFormField(
              controller: _location,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t('Service / installation location (optional)'),
                hintText: t(
                  'e.g. Patia, Bhubaneswar — 2nd floor, near water tank',
                ),
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
                decoration: InputDecoration(
                  labelText: t('Expected delivery date'),
                ),
                child: Text(
                  _expectedDelivery == null
                      ? t('Not set')
                      : dateStr(_expectedDelivery),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _technician,
              decoration: InputDecoration(
                labelText: t('Technician name (optional)'),
              ),
            ),
            SectionLabel(t('Notes')),
            TextFormField(
              controller: _customerNote,
              decoration: InputDecoration(
                labelText: t('Customer-visible note (optional)'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _internalNote,
              decoration: InputDecoration(
                labelText: t('Internal note (optional)'),
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
                  : Text(t('Create job card')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
