import '../../core/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/data_refresh.dart';
import '../../core/formatters.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../services/service_providers.dart';
import 'job_card_detail_screen.dart';
import 'job_card_providers.dart';

/// Repair estimates with versioned customer approval (D37, D38).
///
/// Every change to an estimate makes a new version. Staff record the
/// customer's answer (who, how, when, optional photo); it is shown as
/// "staff-recorded", never as a digital signature. Work is added to the
/// job only from the approved lines, so the bill can't include extras the
/// customer didn't agree to.

const _bucket = 'job-attachments';
const _maxUploadBytes = 5 * 1024 * 1024;

void _refreshJob(WidgetRef ref, String jobId) {
  ref.invalidate(jobEstimatesProvider(jobId));
  ref.invalidate(jobAttachmentsProvider(jobId));
  ref.invalidate(jobCardDetailProvider(jobId));
  ref.invalidate(jobCardsProvider);
}

/// The version work may be done against: newest approved (fully or partly).
Map<String, dynamic>? currentApprovedEstimate(
  List<Map<String, dynamic>> estimates,
) {
  for (final e in estimates) {
    if (e['status'] == 'approved' || e['status'] == 'partially_approved') {
      return e;
    }
  }
  return null;
}

List<Map<String, dynamic>> estimateLines(Map<String, dynamic> estimate) =>
    List<Map<String, dynamic>>.from(
      estimate['job_estimate_lines'] as List? ?? [],
    )..sort((a, b) => (a['line_no'] as int).compareTo(b['line_no'] as int));

Map<String, dynamic>? _answer(Map<String, dynamic> estimate) {
  final list = estimate['job_estimate_approvals'];
  if (list is List && list.isNotEmpty) {
    return Map<String, dynamic>.from(list.first as Map);
  }
  if (list is Map) return Map<String, dynamic>.from(list);
  return null;
}

// ============================================================
// Section on the job card
// ============================================================
class EstimateSection extends ConsumerWidget {
  const EstimateSection({super.key, required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobId = job['id'] as String;
    final closed =
        job['invoice_id'] != null ||
        const [
          'delivered',
          'cancelled',
          'returned_unrepaired',
        ].contains(job['status']);
    final estimates = ref.watch(jobEstimatesProvider(jobId));

    return AsyncView(
      value: estimates,
      onRetry: () => ref.invalidate(jobEstimatesProvider(jobId)),
      builder: (list) {
        if (list.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('No estimate yet. Work can start only after the customer approves an estimate.'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                  if (!closed) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => openEstimateEditor(context, ref, jobId),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: Text(t('Create estimate')),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        final latest = list.first;
        final older = list.skip(1).toList();
        final awaiting = latest['status'] == 'awaiting_approval';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EstimateCard(estimate: latest, highlight: true),
            if (!closed) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          openEstimateEditor(context, ref, jobId, base: latest),
                      icon: const Icon(Icons.edit_note),
                      label: Text(
                        awaiting ? t('Edit estimate') : 'Revise estimate',
                      ),
                    ),
                  ),
                  if (awaiting) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            showRecordAnswerDialog(context, ref, job, latest),
                        icon: const Icon(Icons.how_to_reg_outlined),
                        label: Text(t('Customer\'s answer')),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (older.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: ExpansionTile(
                  title: Text(
                    'Earlier versions (${older.length})',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [for (final e in older) _EstimateCard(estimate: e)],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EstimateCard extends ConsumerWidget {
  const _EstimateCard({required this.estimate, this.highlight = false});

  final Map<String, dynamic> estimate;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = estimate['status'] as String;
    final decided = status == 'approved' || status == 'partially_approved';
    final lines = estimateLines(estimate);
    final answer = _answer(estimate);
    final attachments =
        ref
            .watch(jobAttachmentsProvider(estimate['job_card_id'] as String))
            .value ??
        const [];
    final evidence = answer == null
        ? const <Map<String, dynamic>>[]
        : attachments.where((a) => a['approval_id'] == answer['id']).toList();

    return Card(
      elevation: highlight ? null : 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimate v${estimate['version']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                StatusChip(
                  estimateStatusLabel(status),
                  color: estimateStatusColor(status),
                ),
              ],
            ),
            Text(
              dateTimeStr(estimate['created_at']),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 6),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    if (decided)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          l['approved'] == true
                              ? Icons.check_circle
                              : Icons.cancel_outlined,
                          size: 16,
                          color: l['approved'] == true
                              ? AppColors.green
                              : AppColors.red,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${l['name']}  ·  ${qty(l['quantity'] as num?)} × ${money(l['unit_price'] as num?)}'
                        '${toDouble(l['gst_rate']) > 0 ? ' + ${toDouble(l['gst_rate']).toStringAsFixed(0)}% GST' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          decoration: decided && l['approved'] != true
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      money(l['line_total'] as num?),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(t('Total'),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  money(estimate['total'] as num?),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (answer != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: estimateStatusColor(status).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${answer['decision'] == 'rejected' ? t('Rejected') : 'Approved'} by '
                      '${answer['customer_name']} · ${approvalChannelLabel(answer['channel'] as String)}'
                      '${answer['decision'] == 'partially_approved' ? ' · ${money(answer['approved_total'] as num?)} approved' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${dateTimeStr(answer['customer_decided_at'])} · staff-recorded',
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                    ),
                    if ((answer['notes'] as String? ?? '').isNotEmpty)
                      Text(
                        answer['notes'] as String,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    for (final a in evidence)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => viewJobAttachment(context, ref, a),
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(
                          (a['file_name'] as String? ?? '').isEmpty
                              ? t('Evidence')
                              : a['file_name'] as String,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if ((estimate['note'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                estimate['note'] as String,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Estimate editor (new version)
// ============================================================
Future<void> openEstimateEditor(
  BuildContext context,
  WidgetRef ref,
  String jobId, {
  Map<String, dynamic>? base,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => EstimateEditorScreen(jobId: jobId, base: base),
    ),
  );
  if (saved == true) _refreshJob(ref, jobId);
}

class _DraftLine {
  _DraftLine({
    required this.itemType,
    required this.name,
    this.fromLineId,
    this.productId,
    this.variantId,
    this.serviceId,
    this.hsn = '',
    num quantity = 1,
    num price = 0,
    num gst = 0,
  }) : qty = TextEditingController(text: _num(quantity)),
       price = TextEditingController(text: _num(price)),
       gst = TextEditingController(text: _num(gst));

  final String itemType;
  final String name;
  final String? fromLineId;
  final String? productId;
  final String? variantId;
  final String? serviceId;
  final String hsn;
  final TextEditingController qty;
  final TextEditingController price;
  final TextEditingController gst;

  static String _num(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double get quantity => double.tryParse(qty.text.trim()) ?? 0;
  double get unitPrice => double.tryParse(price.text.trim()) ?? 0;
  double get gstRate => double.tryParse(gst.text.trim()) ?? 0;
  double get total => quantity * unitPrice * (1 + gstRate / 100);

  Map<String, dynamic> toJson() => {
    'item_type': itemType,
    'name': name,
    'quantity': quantity,
    'unit_price': unitPrice,
    'gst_rate': gstRate,
    'hsn_code': hsn,
    'from_line_id': ?fromLineId,
    'product_id': ?productId,
    'variant_id': ?variantId,
    'service_id': ?serviceId,
  };

  void dispose() {
    qty.dispose();
    price.dispose();
    gst.dispose();
  }
}

class EstimateEditorScreen extends ConsumerStatefulWidget {
  const EstimateEditorScreen({super.key, required this.jobId, this.base});

  final String jobId;

  /// The version being revised; its lines are carried into the new one.
  final Map<String, dynamic>? base;

  @override
  ConsumerState<EstimateEditorScreen> createState() =>
      _EstimateEditorScreenState();
}

class _EstimateEditorScreenState extends ConsumerState<EstimateEditorScreen> {
  final List<_DraftLine> _lines = [];
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final base = widget.base;
    if (base != null) {
      for (final l in estimateLines(base)) {
        _lines.add(
          _DraftLine(
            itemType: l['item_type'] as String,
            name: l['name'] as String,
            fromLineId: l['id'] as String,
            productId: l['product_id'] as String?,
            variantId: l['variant_id'] as String?,
            serviceId: l['service_id'] as String?,
            hsn: l['hsn_code'] as String? ?? '',
            quantity: toDouble(l['quantity']),
            price: toDouble(l['unit_price']),
            gst: toDouble(l['gst_rate']),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _addPart() async {
    final search = TextEditingController();
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: PartPicker(searchController: search),
      ),
    );
    if (picked == null || !mounted) return;
    final product = picked['product'] as Map<String, dynamic>;
    final variant = picked['variant'] as Map<String, dynamic>?;
    setState(
      () => _lines.add(
        _DraftLine(
          itemType: 'part',
          name:
              '${product['name']}${variant != null ? ' (${variant['name']})' : ''}',
          productId: product['id'] as String,
          variantId: variant?['id'] as String?,
          hsn: product['hsn_code'] as String? ?? '',
          price: toDouble(
            variant?['selling_price'] ?? product['selling_price'],
          ),
          gst: toDouble(product['gst_rate']),
        ),
      ),
    );
  }

  Future<void> _addLabour() async {
    List<Map<String, dynamic>> services = const [];
    try {
      services = await ref.read(servicesProvider.future);
    } catch (_) {
      // The catalogue is optional; a labour line can be typed.
    }
    if (!mounted) return;
    Map<String, dynamic>? service;
    final name = TextEditingController();
    final price = TextEditingController();
    final gst = TextEditingController(text: '18');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(t('Add labour')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (services.isNotEmpty)
                  DropdownButtonFormField<Map<String, dynamic>>(
                    isExpanded: true,
                    initialValue: service,
                    decoration: InputDecoration(
                      labelText: t('From service catalog (optional)'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(t('Type manually')),
                      ),
                      for (final s in services)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            s['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setDialog(() {
                      service = v;
                      if (v != null) {
                        name.text = v['name'] as String;
                        price.text = toDouble(v['price']).toStringAsFixed(2);
                        gst.text = toDouble(v['gst_rate']).toStringAsFixed(0);
                      }
                    }),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: t('Work *')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: t('Price ₹ (excl. GST)'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gst,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: t('GST %')),
                ),
              ],
            ),
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
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    setState(
      () => _lines.add(
        _DraftLine(
          itemType: 'labor',
          name: name.text.trim(),
          serviceId: service?['id'] as String?,
          hsn: service?['sac_code'] as String? ?? '',
          price: double.tryParse(price.text) ?? 0,
          gst: double.tryParse(gst.text) ?? 0,
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      showError(context, t('Add at least one part or labour line'));
      return;
    }
    for (final l in _lines) {
      if (l.quantity <= 0 || l.unitPrice < 0) {
        showError(context, 'Check the quantity and price of ${l.name}');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final res =
          await ref
                  .read(supabaseProvider)
                  .rpc(
                    'create_job_estimate',
                    params: {
                      'p_job_id': widget.jobId,
                      'p_lines': [for (final l in _lines) l.toJson()],
                      'p_note': _note.text.trim(),
                    },
                  )
              as Map<String, dynamic>;
      if (mounted) {
        showSuccess(
          context,
          'Estimate v${res['version']} saved — ${money(res['total'] as num?)}',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold<double>(0, (s, l) => s + l.total);
    final version = widget.base == null
        ? 1
        : (widget.base!['version'] as int) + 1;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text('Estimate v$version')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.base != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t('Saving makes a new version for the customer to approve. Earlier answers stay on record. Work already done must stay in the estimate at the same price.'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ),
          for (var i = 0; i < _lines.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _lines[i].itemType == 'part'
                              ? Icons.inventory_2_outlined
                              : Icons.build_outlined,
                          size: 18,
                          color: _lines[i].itemType == 'part'
                              ? AppColors.teal
                              : AppColors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lines[i].name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.red,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _lines.removeAt(i).dispose()),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _lines[i].qty,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: t('Qty'),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _lines[i].price,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: t('Price ₹'),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _lines[i].gst,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: t('GST %'),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addPart,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(t('Add part')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addLabour,
                  icon: const Icon(Icons.build_outlined),
                  label: Text(t('Add labour')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(
              labelText: t('Note for this version (optional)'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t('Estimate total'),
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    money(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t('Save estimate')),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Customer's answer (D38)
// ============================================================
Future<void> showRecordAnswerDialog(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> job,
  Map<String, dynamic> estimate,
) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecordAnswerDialog(job: job, estimate: estimate),
  );
  if (saved == true) _refreshJob(ref, job['id'] as String);
}

class _RecordAnswerDialog extends ConsumerStatefulWidget {
  const _RecordAnswerDialog({required this.job, required this.estimate});

  final Map<String, dynamic> job;
  final Map<String, dynamic> estimate;

  @override
  ConsumerState<_RecordAnswerDialog> createState() =>
      _RecordAnswerDialogState();
}

class _RecordAnswerDialogState extends ConsumerState<_RecordAnswerDialog> {
  String _decision = 'all'; // all | some | rejected
  late final _name = TextEditingController(
    text: widget.job['customer_name'] as String? ?? '',
  );
  final _notes = TextEditingController();
  String _channel = 'in_person';
  DateTime? _when; // null = now
  late final List<Map<String, dynamic>> _estLines = estimateLines(
    widget.estimate,
  );
  late final Set<String> _chosen = {
    for (final l in _estLines) l['id'] as String,
  };
  final List<XFile> _photos = [];
  bool _busy = false;

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _when ?? now,
      firstDate: DateTime.parse(
        widget.estimate['created_at'] as String,
      ).toLocal(),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when ?? now),
    );
    if (time == null) return;
    setState(
      () => _when = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _addPhoto() async {
    final file = await pickJobPhoto(context);
    if (file != null) setState(() => _photos.add(file));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showError(context, t('Enter the name of the person who gave the answer'));
      return;
    }
    if (_decision == 'some' && _chosen.isEmpty) {
      showError(context, t('Tick the lines the customer approved'));
      return;
    }
    setState(() => _busy = true);
    final client = ref.read(supabaseProvider);
    Map<String, dynamic> res;
    try {
      res =
          await client.rpc(
                'record_estimate_decision',
                params: {
                  'p_estimate_id': widget.estimate['id'],
                  'p_decision': _decision == 'rejected'
                      ? 'rejected'
                      : 'approved',
                  'p_customer_name': _name.text.trim(),
                  'p_channel': _channel,
                  'p_line_ids': _decision == 'some' ? _chosen.toList() : null,
                  'p_decided_at': _when?.toUtc().toIso8601String(),
                  'p_notes': _notes.text.trim(),
                },
              )
              as Map<String, dynamic>;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
      return;
    }
    // The answer is saved; now the evidence. A failed upload doesn't undo
    // the answer — the photo can be added again from the job's photos.
    var failed = 0;
    for (final p in _photos) {
      try {
        await uploadJobAttachment(
          ref,
          jobId: widget.job['id'] as String,
          file: p,
          kind: 'approval_evidence',
          approvalId: res['id'] as String,
        );
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    Navigator.pop(context, true);
    if (failed > 0) {
      showError(
        context,
        'Answer saved, but $failed photo(s) failed to upload. Add them again under Photos.',
      );
    } else {
      showSuccess(context, t('Customer\'s answer recorded'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Customer\'s answer — v${widget.estimate['version']}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'all', label: Text(t('Approved'))),
                  ButtonSegment(value: 'some', label: Text(t('Some lines'))),
                  ButtonSegment(value: 'rejected', label: Text(t('Rejected'))),
                ],
                selected: {_decision},
                onSelectionChanged: (s) => setState(() => _decision = s.first),
              ),
              if (_decision == 'some')
                for (final l in _estLines)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _chosen.contains(l['id']),
                    title: Text(
                      '${l['name']}  ·  ${money(l['line_total'] as num?)}',
                    ),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _chosen.add(l['id'] as String)
                          : _chosen.remove(l['id']),
                    ),
                  ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t('Answered by (customer name) *'),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in approvalChannels)
                    ChoiceChip(
                      label: Text(approvalChannelLabel(c)),
                      selected: _channel == c,
                      onSelected: (_) => setState(() => _channel = c),
                    ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(
                  _when == null
                      ? t('Answered just now')
                      : 'Answered ${dateTimeStr(_when!.toIso8601String())}',
                ),
                trailing: Text(t('Change')),
                onTap: _pickWhen,
              ),
              TextField(
                controller: _notes,
                decoration: InputDecoration(
                  labelText: t('Notes (optional)'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    InputChip(
                      avatar: const Icon(Icons.image_outlined, size: 16),
                      label: Text(
                        _photos[i].name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: () => setState(() => _photos.removeAt(i)),
                    ),
                  TextButton.icon(
                    onPressed: _addPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(t('Photo / screenshot')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(t('Saved as a staff-recorded answer with your name — not a digital signature by the customer.'),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(t('Cancel')),
        ),
        FilledButton(
          style: dialogActionStyle,
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t('Save')),
        ),
      ],
    );
  }
}

// ============================================================
// Work done from the approved estimate
// ============================================================
Future<void> markEstimateWorkDone(
  BuildContext context,
  WidgetRef ref,
  String jobId,
  List<Map<String, dynamic>> items,
) async {
  final List<Map<String, dynamic>> estimates;
  try {
    estimates = await ref.read(jobEstimatesProvider(jobId).future);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final current = currentApprovedEstimate(estimates);
  if (current == null) {
    showError(context, t('Record the customer\'s approval of an estimate first'));
    return;
  }
  final used = <String, double>{};
  for (final it in items) {
    final lineId = it['estimate_line_id'] as String?;
    if (lineId != null) {
      used[lineId] = (used[lineId] ?? 0) + toDouble(it['quantity']);
    }
  }
  final open = [
    for (final l in estimateLines(current))
      if (l['approved'] == true &&
          toDouble(l['quantity']) - (used[l['id']] ?? 0) > 0)
        l,
  ];
  if (open.isEmpty) {
    showError(
      context,
      t('All approved work is already added. Revise the estimate for more work.'),
    );
    return;
  }
  final line = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(
              'Approved work — estimate v${current['version']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final l in open)
            ListTile(
              leading: Icon(
                l['item_type'] == 'part'
                    ? Icons.inventory_2_outlined
                    : Icons.build_outlined,
              ),
              title: Text(l['name'] as String),
              subtitle: Text(
                '${qty(toDouble(l['quantity']) - (used[l['id']] ?? 0))} left of ${qty(l['quantity'] as num?)} · '
                '${money(l['unit_price'] as num?)} each',
              ),
              onTap: () => Navigator.pop(ctx, l),
            ),
        ],
      ),
    ),
  );
  if (line == null || !context.mounted) return;
  final left = toDouble(line['quantity']) - (used[line['id']] ?? 0);
  var quantity = left;
  if (left > 1) {
    final c = TextEditingController(text: _DraftLine._num(left));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line['name'] as String),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity used (up to ${qty(left)})',
          ),
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
    if (ok != true || !context.mounted) return;
    quantity = double.tryParse(c.text.trim()) ?? 0;
  }
  try {
    await ref
        .read(supabaseProvider)
        .rpc(
          'add_job_card_item',
          params: {
            'payload': {
              'job_card_id': jobId,
              'estimate_line_id': line['id'],
              'quantity': quantity,
            },
          },
        );
    ref.invalidate(jobCardDetailProvider(jobId));
    if (line['item_type'] == 'part') invalidateStockData(ref);
    if (context.mounted) {
      showSuccess(
        context,
        line['item_type'] == 'part'
            ? t('Part added — stock deducted')
            : 'Work added',
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

// ============================================================
// Photos (Supabase Storage, private bucket)
// ============================================================
class JobPhotosSection extends ConsumerWidget {
  const JobPhotosSection({super.key, required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobId = job['id'] as String;
    final list = ref.watch(jobAttachmentsProvider(jobId)).value ?? const [];
    return Card(
      child: Column(
        children: [
          for (final a in list)
            ListTile(
              dense: true,
              leading: const Icon(Icons.image_outlined),
              title: Text(
                (a['file_name'] as String? ?? '').isEmpty
                    ? t('Photo')
                    : a['file_name'] as String,
              ),
              subtitle: Text(
                '${switch (a['kind']) {
                  'approval_evidence' => 'Customer\'s answer',
                  'intake_photo' => 'At receiving',
                  _ => 'Other',
                }} · ${dateTimeStr(a['created_at'])}',
              ),
              onTap: () => viewJobAttachment(context, ref, a),
            ),
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.indigo,
            ),
            title: Text(t('Add photo'),
              style: TextStyle(color: AppColors.indigo),
            ),
            onTap: () => _add(context, ref, jobId),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String jobId) async {
    final file = await pickJobPhoto(context);
    if (file == null || !context.mounted) return;
    final atIntake = const ['received', 'checking'].contains(job['status']);
    try {
      await uploadJobAttachment(
        ref,
        jobId: jobId,
        file: file,
        kind: atIntake ? 'intake_photo' : 'other',
      );
      ref.invalidate(jobAttachmentsProvider(jobId));
      if (context.mounted) showSuccess(context, t('Photo saved'));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Camera or gallery on phones; a file dialog on desktop. Photos are
/// downsized so they stay well under the 5 MB limit.
Future<XFile?> pickJobPhoto(BuildContext context) async {
  var source = ImageSource.gallery;
  if (!isDesktopPlatform) {
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t('Take a photo')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('Choose from gallery (e.g. WhatsApp screenshot)'),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return null;
    source = picked;
  }
  return ImagePicker().pickImage(
    source: source,
    maxWidth: 1800,
    imageQuality: 80,
  );
}

String _contentType(String ext) => switch (ext) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  'heic' => 'image/heic',
  'pdf' => 'application/pdf',
  _ => 'image/jpeg',
};

/// Uploads to `<business>/<job>/<random>.<ext>` and records it on the job.
Future<void> uploadJobAttachment(
  WidgetRef ref, {
  required String jobId,
  required XFile file,
  required String kind,
  String? approvalId,
}) async {
  final businessId = ref.read(appContextProvider).value?.businessId;
  if (businessId == null) throw 'No shop selected';
  final bytes = await file.readAsBytes();
  if (bytes.length > _maxUploadBytes) throw 'That file is larger than 5 MB';
  final dot = file.name.lastIndexOf('.');
  var ext = dot >= 0 ? file.name.substring(dot + 1).toLowerCase() : 'jpg';
  if (ext == 'jpeg') ext = 'jpg';
  final path = '$businessId/$jobId/${const Uuid().v4()}.$ext';
  final client = ref.read(supabaseProvider);
  await client.storage
      .from(_bucket)
      .uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: _contentType(ext)),
      );
  await client.rpc(
    'add_job_attachment',
    params: {
      'p_job_id': jobId,
      'p_path': path,
      'p_kind': kind,
      'p_file_name': file.name,
      'p_content_type': _contentType(ext),
      'p_size': bytes.length,
      'p_approval_id': approvalId,
    },
  );
}

/// Opens a stored photo through a short-lived signed link.
Future<void> viewJobAttachment(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> attachment,
) async {
  try {
    final url = await ref
        .read(supabaseProvider)
        .storage
        .from(_bucket)
        .createSignedUrl(attachment['storage_path'] as String, 300);
    if (!context.mounted) return;
    if ((attachment['content_type'] as String? ?? '').startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    errorBuilder: (_, _, _) => Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(t('Couldn\'t load the photo')),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('Close')),
              ),
            ],
          ),
        ),
      );
    } else {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
