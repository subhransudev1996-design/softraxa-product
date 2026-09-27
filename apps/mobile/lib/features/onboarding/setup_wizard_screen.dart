import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/business_category.dart';
import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../invoices/thermal_printer.dart';

/// First-time setup (LAUNCH_SPECIFICATION, onboarding "Setup wizard"):
/// category → shop details → GST and turnover → UPI and invoice prefix →
/// printer test. Creates the shop if needed, then complete_onboarding()
/// saves everything and applies the category's defaults (migration 0047).
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

final _upiPattern = RegExp(
  r'^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$',
);
final _prefixPattern = RegExp(r'^[A-Za-z0-9]{1,6}$');

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  static const _titles = [
    'What kind of shop is it?',
    'Shop details',
    'GST',
    'Payments and bills',
    'Printer check',
  ];

  // An existing shop (created by SOFTRAXA) pre-fills the wizard.
  late final Map<String, dynamic>? _existing = ref
      .read(appContextProvider)
      .value
      ?.business;

  int _step = 0;
  final _detailsKey = GlobalKey<FormState>();
  final _gstKey = GlobalKey<FormState>();
  final _billsKey = GlobalKey<FormState>();

  late String? _category =
      _existing == null || _existing['business_type'] == 'other'
      ? null
      : _existing['business_type'] as String?;
  late final _name = TextEditingController(
    text: _existing?['name'] as String? ?? '',
  );
  late final _owner = TextEditingController(
    text: _existing?['owner_name'] as String? ?? '',
  );
  late final _phone = TextEditingController(
    text: _existing?['phone'] as String? ?? '',
  );
  late final _address = TextEditingController(
    text: _existing?['address'] as String? ?? '',
  );
  late String _tax = _existing?['tax_preference'] as String? ?? 'gst';
  late final _gstin = TextEditingController(
    text: _existing?['gst_number'] as String? ?? '',
  );
  late String _state = _existing?['state_code'] as String? ?? '';
  late String? _band = _existing?['turnover_band'] as String?;
  late final _upi = TextEditingController(
    text: _existing?['upi_id'] as String? ?? '',
  );
  late final _prefix = TextEditingController(
    text: _existing?['invoice_prefix'] as String? ?? 'INV',
  );
  bool _busy = false;
  bool _created = false; // create_business ran; a retry only re-saves

  bool get _tooLarge => _tax == 'gst' && _band == 'above_5cr';

  void _next() {
    final ok = switch (_step) {
      0 => _category != null,
      1 => _detailsKey.currentState?.validate() ?? false,
      2 => (_gstKey.currentState?.validate() ?? false) && !_tooLarge,
      3 => _billsKey.currentState?.validate() ?? false,
      _ => true,
    };
    if (_step == 0 && _category == null) {
      showError(context, 'Choose your type of shop');
      return;
    }
    if (_step == 2 && _tax == 'gst' && _band == null) {
      showError(context, 'Choose your annual turnover');
      return;
    }
    if (!ok) return;
    if (_step < _titles.length - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  Map<String, dynamic> get _payload => {
    'business_type': _category,
    'name': _name.text.trim(),
    'owner_name': _owner.text.trim(),
    'phone': _phone.text.trim(),
    'address': _address.text.trim(),
    'tax_preference': _tax,
    'gst_number': _tax == 'gst' ? _gstin.text.trim().toUpperCase() : '',
    'state_code': _state,
    'turnover_band': _tax == 'gst' ? _band : null,
    'upi_id': _upi.text.trim(),
    'invoice_prefix': _prefix.text.trim().toUpperCase(),
  };

  Future<void> _finish() async {
    setState(() => _busy = true);
    final client = ref.read(supabaseProvider);
    try {
      if (_existing == null && !_created) {
        await client.rpc(
          'create_business',
          params: {
            'payload': {
              'name': _name.text.trim(),
              'owner_name': _owner.text.trim(),
              'business_type': _category,
              'phone': _phone.text.trim(),
              'address': _address.text.trim(),
              'tax_preference': _tax,
              'gst_number': _tax == 'gst'
                  ? _gstin.text.trim().toUpperCase()
                  : '',
              'invoice_prefix': _prefix.text.trim().toUpperCase(),
            },
          },
        );
        _created = true;
      }
      await client.rpc('complete_onboarding', params: {'payload': _payload});
      await ref.read(appContextProvider.notifier).refresh();
      if (mounted) showSuccess(context, 'Your shop is ready');
      // The router moves on to the dashboard once setup is done.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printA4Test() async {
    final doc = pw.Document()
      ..addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _name.text.trim().isEmpty ? 'Your shop' : _name.text.trim(),
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Printer test - Dukania'),
              pw.Text(dateTimeStr(DateTime.now().toIso8601String())),
              pw.SizedBox(height: 16),
              pw.Text('If you can read this, your bills will print.'),
            ],
          ),
        ),
      );
    try {
      await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: 'Printer test',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _step == _titles.length - 1;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Set up your shop'),
        actions: [
          TextButton(
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
            child: const Text('Logout'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: (_step + 1) / _titles.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Step ${_step + 1} of ${_titles.length}',
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _titles[_step],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      switch (_step) {
                        0 => _categoryStep(),
                        1 => _detailsStep(),
                        2 => _gstStep(),
                        3 => _billsStep(),
                        _ => _printerStep(),
                      },
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_step > 0)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _step--),
                          child: const Text('Back'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy ? null : _next,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(last ? 'Finish setup' : 'Next'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This decides which screens and product fields you see. You can '
          'change it later in business settings.',
          style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 12),
        for (final c in businessCategories)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _category == c.key
                    ? AppColors.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: ListTile(
              leading: Icon(c.icon, color: AppColors.primary),
              title: Text(
                c.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(c.description),
              trailing: _category == c.key
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () => setState(() => _category = c.key),
            ),
          ),
      ],
    );
  }

  Widget _detailsStep() {
    return Form(
      key: _detailsKey,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Shop name *'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _owner,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Owner name'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Shop address (printed on bills)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _gstStep() {
    return Form(
      key: _gstKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'gst', label: Text('GST registered')),
              ButtonSegment(value: 'non_gst', label: Text('Not registered')),
            ],
            selected: {_tax},
            onSelectionChanged: (s) => setState(() => _tax = s.first),
          ),
          const SizedBox(height: 16),
          if (_tax == 'gst') ...[
            TextFormField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'GSTIN *'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Required' : gstinError(v ?? ''),
              onChanged: (v) {
                final s = stateFromGstin(v);
                if (s != null && s != _state) setState(() => _state = s);
              },
            ),
            if (_state.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'State: ${gstStateLabel(_state)}',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Annual turnover (all your GST registrations together)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            RadioGroup<String>(
              groupValue: _band,
              onChanged: (v) => setState(() => _band = v),
              child: const Column(
                children: [
                  RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: 'up_to_5cr',
                    title: Text('Up to ₹5 crore'),
                  ),
                  RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: 'above_5cr',
                    title: Text('Above ₹5 crore'),
                  ),
                ],
              ),
            ),
            if (_tooLarge)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Above ₹5 crore, GST needs e-invoicing (IRN), which Dukania '
                  'doesn\'t support yet. Please contact SOFTRAXA support before '
                  'billing with Dukania.',
                  style: TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ),
          ] else ...[
            Text(
              'Bills will be issued without GST. You can switch to GST later '
              'in business settings once you register.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            GstStateField(
              value: _state,
              label: 'State',
              onChanged: (v) => setState(() => _state = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _billsStep() {
    return Form(
      key: _billsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _upi,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'UPI ID (optional)',
              hintText: 'shopname@okaxis',
              helperText: 'Printed on bills as a "scan to pay" QR code',
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || _upiPattern.hasMatch(t)
                  ? null
                  : 'Enter a UPI ID like name@bank';
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _prefix,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invoice prefix',
              helperText: 'e.g. INV — bills become INV-00001',
            ),
            validator: (v) => _prefixPattern.hasMatch((v ?? '').trim())
                ? null
                : '1–6 letters or digits',
          ),
        ],
      ),
    );
  }

  Widget _printerStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Print a test page to check your printer now. You can skip this '
          'and print from any bill later.',
          style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 16),
        if (!isDesktopPlatform) ...[
          OutlinedButton.icon(
            onPressed: () => ThermalPrinterService.printTestPage(
              context,
              _name.text.trim().isEmpty ? 'Your shop' : _name.text.trim(),
            ),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Bluetooth receipt printer'),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _printA4Test,
          icon: const Icon(Icons.print_outlined),
          label: Text(
            isDesktopPlatform ? 'Print a test page' : 'A4 / other printer',
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ready to finish',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${categoryOf(_category).label} · '
                  '${_tax == 'gst' ? 'GST ${_gstin.text.trim().toUpperCase()}' : 'Not GST registered'}'
                  '${_upi.text.trim().isEmpty ? '' : ' · UPI ${_upi.text.trim()}'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
