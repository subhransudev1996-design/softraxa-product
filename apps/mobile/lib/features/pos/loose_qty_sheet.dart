import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'cart.dart';

/// Result of the quantity sheet: the quantity in BASE units — or, when
/// [asPack], in whole packs to bill at the product's pack price (0061).
class LooseQtyResult {
  const LooseQtyResult(this.qty, {this.asPack = false});
  final double qty;
  final bool asPack;
}

/// Quantity entry for loose/weighed goods (kirana sugar by the kg, rods by
/// the metre — PRD Phase 3 "partial quantities"). Shown instead of the
/// silent qty-1 add when the product's unit has `allow_decimal`. Supports
/// the two ways loose goods are actually asked for in Indian stores:
///   • by quantity  — "500 grams" → type 0.5 or tap the ½ chip
///   • by amount    — "₹50 ka sugar" → type 50 in the ₹ field, qty computes
/// If [secondaryUnitName] and [conversionFactor] are set (e.g. Bag = 50 kg),
/// a unit toggle lets the qty be typed in the secondary unit and converts to
/// base units on return. With a [packPrice] (cigarettes: Box of 10 at ₹95,
/// not 10 × ₹10) the pack is billed as whole packs at that price instead.
/// Whole-number units ([allowDecimal] false) only take whole quantities.
Future<LooseQtyResult?> showLooseQtySheet(
  BuildContext context, {
  required String name,
  required double rate,
  required String unitName,
  String? secondaryUnitName,
  double? conversionFactor,
  double? packPrice,
  bool allowDecimal = true,
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
            packPrice: packPrice,
            allowDecimal: allowDecimal,
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
        packPrice: packPrice,
        allowDecimal: allowDecimal,
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
    this.packPrice,
    this.allowDecimal = true,
    this.dialog = false,
  });

  final bool dialog;
  final String name;
  final double rate; // per base unit, GST-inclusive
  final String unitName;
  final String? secondaryUnitName;
  final double? conversionFactor; // 1 secondary = X base units
  final double? packPrice; // own price of one whole pack, if set
  final bool allowDecimal;

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

  /// Packs billed at their own price — whole packs only.
  bool get _packPriced => _inSecondaryUnit && (widget.packPrice ?? 0) > 0;

  /// Rate for the unit currently being typed in.
  double get _activeRate => _inSecondaryUnit
      ? (_packPriced
            ? widget.packPrice!
            : widget.rate * (widget.conversionFactor ?? 1))
      : widget.rate;

  /// Whole numbers only: whole-number units, and packs at a pack price.
  bool get _wholeOnly => !widget.allowDecimal || _packPriced;

  bool _isValid(double? q) =>
      q != null && q > 0 && (!_wholeOnly || q == q.roundToDouble());

  String get _activeUnit =>
      _inSecondaryUnit ? widget.secondaryUnitName! : widget.unitName;

  @override
  void initState() {
    super.initState();
    _amountC.text = _activeRate > 0 ? _activeRate.toStringAsFixed(2) : '';
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
    if (_syncing || _activeRate <= 0) return;
    _syncing = true;
    final q = double.tryParse(_qtyC.text);
    _amountC.text = q == null ? '' : (q * _activeRate).toStringAsFixed(2);
    _syncing = false;
    setState(() {});
  }

  void _onAmountChanged() {
    if (_syncing || _activeRate <= 0) return;
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
    if (!_isValid(q)) return;
    Navigator.pop(
      context,
      _packPriced
          ? LooseQtyResult(q!, asPack: true)
          : LooseQtyResult(
              toBaseQty(q!, _inSecondaryUnit ? widget.conversionFactor : null),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsedQty = double.tryParse(_qtyC.text);
    final valid = _isValid(parsedQty);
    final whole = parsedQty != null && parsedQty == parsedQty.roundToDouble();

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
            '${money(widget.rate)} / ${widget.unitName.isEmpty ? 'unit' : widget.unitName}'
            '${(widget.packPrice ?? 0) > 0 && _hasSecondary ? '  ·  ${money(widget.packPrice)} / ${widget.secondaryUnitName}' : ''}',
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
                  decoration: InputDecoration(
                    labelText: 'Qty ($_activeUnit)',
                    errorText: parsedQty != null && _wholeOnly && !whole
                        ? 'Whole $_activeUnit only'
                        : null,
                  ),
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
              for (final f
                  in _wholeOnly
                      ? const [(1.0, '1'), (2.0, '2'), (5.0, '5'), (10.0, '10')]
                      : const [
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
              !valid
                  ? 'Add'
                  : _packPriced
                  ? 'Add ${qty(parsedQty)} ${widget.secondaryUnitName} • '
                        '${money(parsedQty! * _activeRate)}'
                  : 'Add ${qty(_inSecondaryUnit ? parsedQty! * (widget.conversionFactor ?? 1) : parsedQty)} '
                        '${widget.unitName.isEmpty ? '' : widget.unitName} • '
                        '${money(parsedQty! * _activeRate)}',
            ),
          ),
          SizedBox(height: widget.dialog ? 4 : 24),
        ],
      ),
    );
  }
}
