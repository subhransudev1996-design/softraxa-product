import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'cart.dart';

/// Result of the loose-quantity sheet: the quantity in BASE units, plus the
/// unit label it was entered in (for the snackbar/label only).
class LooseQtyResult {
  const LooseQtyResult(this.qty);
  final double qty;
}

/// Quantity entry for loose/weighed goods (kirana sugar by the kg, rods by
/// the metre — PRD Phase 3 "partial quantities"). Shown instead of the
/// silent qty-1 add when the product's unit has `allow_decimal`. Supports
/// the two ways loose goods are actually asked for in Indian stores:
///   • by quantity  — "500 grams" → type 0.5 or tap the ½ chip
///   • by amount    — "₹50 ka sugar" → type 50 in the ₹ field, qty computes
/// If [secondaryUnitName] and [conversionFactor] are set (e.g. Bag = 50 kg),
/// a unit toggle lets the qty be typed in the secondary unit and converts to
/// base units on return.
Future<LooseQtyResult?> showLooseQtySheet(
  BuildContext context, {
  required String name,
  required double rate,
  required String unitName,
  String? secondaryUnitName,
  double? conversionFactor,
}) {
  // Desktop: a small dialog; the quantity is pre-selected so typing
  // replaces it, and Enter adds.
  if (isWideLayout(context)) {
    return showDialog<LooseQtyResult>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _LooseQtySheet(
            name: name,
            rate: rate,
            unitName: unitName,
            secondaryUnitName: secondaryUnitName,
            conversionFactor: conversionFactor,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<LooseQtyResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _LooseQtySheet(
        name: name,
        rate: rate,
        unitName: unitName,
        secondaryUnitName: secondaryUnitName,
        conversionFactor: conversionFactor,
      ),
    ),
  );
}

class _LooseQtySheet extends StatefulWidget {
  const _LooseQtySheet({
    required this.name,
    required this.rate,
    required this.unitName,
    this.secondaryUnitName,
    this.conversionFactor,
    this.dialog = false,
  });

  final bool dialog;
  final String name;
  final double rate; // per base unit, GST-inclusive
  final String unitName;
  final String? secondaryUnitName;
  final double? conversionFactor; // 1 secondary = X base units

  @override
  State<_LooseQtySheet> createState() => _LooseQtySheetState();
}

class _LooseQtySheetState extends State<_LooseQtySheet> {
  final _qtyC = TextEditingController(text: '1');
  final _amountC = TextEditingController();
  bool _inSecondaryUnit = false;
  bool _syncing = false; // guards against qty<->amount update loops

  bool get _hasSecondary =>
      widget.secondaryUnitName != null && (widget.conversionFactor ?? 0) > 0;

  /// Rate for the unit currently being typed in.
  double get _activeRate => _inSecondaryUnit
      ? widget.rate * (widget.conversionFactor ?? 1)
      : widget.rate;

  String get _activeUnit =>
      _inSecondaryUnit ? widget.secondaryUnitName! : widget.unitName;

  @override
  void initState() {
    super.initState();
    _amountC.text = widget.rate > 0 ? _activeRate.toStringAsFixed(2) : '';
    _qtyC.addListener(_onQtyChanged);
    _amountC.addListener(_onAmountChanged);
    if (widget.dialog) {
      _qtyC.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyC.text.length,
      );
    }
  }

  @override
  void dispose() {
    _qtyC.dispose();
    _amountC.dispose();
    super.dispose();
  }

  void _onQtyChanged() {
    if (_syncing || widget.rate <= 0) return;
    _syncing = true;
    final q = double.tryParse(_qtyC.text);
    _amountC.text = q == null ? '' : (q * _activeRate).toStringAsFixed(2);
    _syncing = false;
    setState(() {});
  }

  void _onAmountChanged() {
    if (_syncing || widget.rate <= 0) return;
    _syncing = true;
    final a = double.tryParse(_amountC.text);
    final q = a == null ? 0.0 : qtyForAmount(a, _activeRate);
    _qtyC.text = q <= 0 ? '' : qty(q).replaceAll(',', '');
    _syncing = false;
    setState(() {});
  }

  void _setQty(double v) {
    _qtyC.text = qty(v).replaceAll(',', '');
    // listener recomputes amount
  }

  void _submit() {
    final q = double.tryParse(_qtyC.text);
    if (q == null || q <= 0) return;
    Navigator.pop(
      context,
      LooseQtyResult(
        toBaseQty(q, _inSecondaryUnit ? widget.conversionFactor : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsedQty = double.tryParse(_qtyC.text);
    final valid = parsedQty != null && parsedQty > 0;

    return Padding(
      padding: EdgeInsets.all(widget.dialog ? 24 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '${money(widget.rate)} / ${widget.unitName.isEmpty ? 'unit' : widget.unitName}',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (_hasSecondary) ...[
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(widget.unitName)),
                ButtonSegment(
                  value: true,
                  label: Text(
                    '${widget.secondaryUnitName} (${qty(widget.conversionFactor)} ${widget.unitName})',
                  ),
                ),
              ],
              selected: {_inSecondaryUnit},
              onSelectionChanged: (s) {
                setState(() => _inSecondaryUnit = s.first);
                _onQtyChanged(); // recompute amount at the new unit's rate
              },
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyC,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: 'Qty ($_activeUnit)'),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _amountC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount ₹'),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final f in const [
                (0.25, '¼'),
                (0.5, '½'),
                (1.0, '1'),
                (2.0, '2'),
                (5.0, '5'),
              ])
                ActionChip(
                  label: Text('${f.$2} $_activeUnit'),
                  onPressed: () => _setQty(f.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: valid ? _submit : null,
            child: Text(
              valid
                  ? 'Add ${qty(_inSecondaryUnit ? parsedQty * (widget.conversionFactor ?? 1) : parsedQty)} '
                        '${widget.unitName.isEmpty ? '' : widget.unitName} • '
                        '${money((parsedQty) * _activeRate)}'
                  : 'Add',
            ),
          ),
          SizedBox(height: widget.dialog ? 4 : 24),
        ],
      ),
    );
  }
}
