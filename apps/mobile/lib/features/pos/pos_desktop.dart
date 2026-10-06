import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'cart.dart';

// Desktop billing (window ≥ kDesktopBreakpoint): the bill as a table on the
// left, the customer, totals and Checkout in a fixed panel on the right —
// the layout counter software uses. The phone layout in pos_screen.dart is
// unchanged; both drive the same cart and the same add/edit/checkout code.

const _cellStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);

/// Table header row shared by the bill and the search results.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow(this.cells);

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppColors.inkSoft,
        ),
        child: Row(children: cells),
      ),
    );
  }
}

Widget _cell(Widget child, {int flex = 0, double? width, bool end = false}) {
  final aligned = Align(
    alignment: end ? Alignment.centerRight : Alignment.centerLeft,
    child: child,
  );
  if (width != null) return SizedBox(width: width, child: aligned);
  return Expanded(flex: flex == 0 ? 1 : flex, child: aligned);
}

/// A bordered white panel with a table inside.
class _TablePanel extends StatelessWidget {
  const _TablePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

/// The bill's items: # · Item · Qty · Rate · Discount · GST · Amount.
/// Clicking a row opens the line editor (price, discount, serial).
class PosCartTable extends StatelessWidget {
  const PosCartTable({
    super.key,
    required this.lines,
    required this.onEdit,
    required this.onChangeQty,
    required this.onRemove,
  });

  final List<CartLine> lines;
  final ValueChanged<CartLine> onEdit;
  final void Function(CartLine line, double qty) onChangeQty;
  final ValueChanged<CartLine> onRemove;

  @override
  Widget build(BuildContext context) {
    return _TablePanel(
      child: Column(
        children: [
          _HeaderRow([
            _cell(const Text('#'), width: 36),
            _cell(const Text('ITEM'), flex: 5),
            _cell(const Text('QTY'), width: 128),
            _cell(const Text('RATE'), width: 110, end: true),
            _cell(const Text('DISCOUNT'), width: 100, end: true),
            _cell(const Text('GST'), width: 64, end: true),
            _cell(const Text('AMOUNT'), width: 120, end: true),
            const SizedBox(width: 44),
          ]),
          Expanded(
            child: lines.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    message:
                        'No items yet.\nSearch above or scan a barcode to add products.',
                  )
                : ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: AppColors.line),
                    itemBuilder: (context, i) => _CartRow(
                      index: i + 1,
                      line: lines[i],
                      onEdit: onEdit,
                      onChangeQty: onChangeQty,
                      onRemove: onRemove,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.index,
    required this.line,
    required this.onEdit,
    required this.onChangeQty,
    required this.onRemove,
  });

  final int index;
  final CartLine line;
  final ValueChanged<CartLine> onEdit;
  final void Function(CartLine line, double qty) onChangeQty;
  final ValueChanged<CartLine> onRemove;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (line.variantName.isNotEmpty) line.variantName,
      if (line.isPack)
        '${line.unitName} of ${qtyUnit(line.packSize, line.baseUnitName)}',
      if (line.trackSerial)
        line.serialNo.isEmpty ? 'IMEI/serial missing' : 'S/N ${line.serialNo}',
      if (line.priceSource != 'retail' && line.priceSource != 'manual')
        priceSourceLabel(line.priceSource),
    ];
    return InkWell(
      onTap: () => onEdit(line),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _cell(
              Text(
                '$index',
                style: _cellStyle.copyWith(color: AppColors.inkSoft),
              ),
              width: 36,
            ),
            _cell(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: line.trackSerial && line.serialNo.isEmpty
                            ? AppColors.orange
                            : AppColors.inkSoft,
                      ),
                    ),
                ],
              ),
              flex: 5,
            ),
            _cell(
              _QtyBox(
                qty: line.qty,
                unit: line.unitName,
                onDecrement: () => onChangeQty(line, line.qty - 1),
                onIncrement: () => onChangeQty(line, line.qty + 1),
              ),
              width: 128,
            ),
            _cell(
              Text(money(line.price), style: _cellStyle),
              width: 110,
              end: true,
            ),
            _cell(
              Text(
                line.discountAmount > 0
                    ? (line.discountIsPercent
                          ? '${qty(line.discount)}%'
                          : money(line.discountAmount))
                    : '—',
                style: _cellStyle.copyWith(
                  color: line.discountAmount > 0
                      ? AppColors.green
                      : AppColors.hint,
                ),
              ),
              width: 100,
              end: true,
            ),
            _cell(
              Text(
                line.gstRate > 0 ? '${qty(line.gstRate)}%' : '—',
                style: _cellStyle.copyWith(color: AppColors.inkSoft),
              ),
              width: 64,
              end: true,
            ),
            _cell(
              Text(
                money(line.gross),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              width: 120,
              end: true,
            ),
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: 'Remove',
                iconSize: 18,
                icon: Icon(Icons.close, color: AppColors.inkSoft),
                onPressed: () => onRemove(line),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyBox extends StatelessWidget {
  const _QtyBox({
    required this.qty,
    required this.unit,
    required this.onDecrement,
    required this.onIncrement,
  });

  final double qty;
  final String unit;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _step(Icons.remove, onDecrement),
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            alignment: Alignment.center,
            child: Text(
              cartQtyLabel(qty, unit),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          _step(Icons.add, onIncrement),
        ],
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: 30,
      height: 30,
      child: Icon(icon, size: 16, color: AppColors.primary),
    ),
  );
}

/// Search results while typing: Item · Price · Stock. The highlighted row
/// (↑/↓) is what Enter adds.
class PosResultsTable extends StatelessWidget {
  const PosResultsTable({
    super.key,
    required this.rows,
    required this.highlight,
    required this.onPick,
  });

  final List<Map<String, dynamic>> rows;
  final int highlight;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context) {
    return _TablePanel(
      child: Column(
        children: [
          _HeaderRow([
            _cell(const Text('PRODUCT'), flex: 5),
            _cell(const Text('BARCODE / SKU'), flex: 2),
            _cell(const Text('PRICE'), width: 120, end: true),
            _cell(const Text('STOCK'), width: 120, end: true),
          ]),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.line),
              itemBuilder: (context, i) {
                final p = rows[i];
                final stock = toDouble(p['current_stock']);
                final selected = i == highlight;
                final code = [
                  p['barcode'],
                  p['sku'],
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
                return Material(
                  color: selected ? AppColors.primarySoft : Colors.transparent,
                  child: InkWell(
                    onTap: () => onPick(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _cell(
                            Text(
                              p['name'] as String? ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            flex: 5,
                          ),
                          _cell(
                            Text(
                              code.isEmpty ? '—' : code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _cellStyle.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                            flex: 2,
                          ),
                          _cell(
                            Text(
                              money(p['selling_price'] as num?),
                              style: _cellStyle,
                            ),
                            width: 120,
                            end: true,
                          ),
                          _cell(
                            Text(
                              qty(stock),
                              style: _cellStyle.copyWith(
                                color: stock <= 0
                                    ? AppColors.red
                                    : AppColors.green,
                              ),
                            ),
                            width: 120,
                            end: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The right-hand panel: customer, totals, Checkout.
class PosBillPanel extends StatelessWidget {
  const PosBillPanel({
    super.key,
    required this.cart,
    required this.customerTile,
    required this.checkoutLabel,
    required this.onCheckout,
  });

  final CartState cart;
  final Widget customerTile;
  final String checkoutLabel;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {Color? color, bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? AppColors.ink,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'CUSTOMER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: customerTile,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.line),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                Text(
                  'BILL SUMMARY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                row('Items', '${cart.itemCount}  ·  Qty ${qty(cart.totalQty)}'),
                row('Subtotal', money(cart.itemsGross)),
                if (cart.billDiscountAmount > 0)
                  row(
                    'Bill discount',
                    '− ${money(cart.billDiscountAmount)}',
                    color: AppColors.green,
                  ),
                if (cart.billTaxTotal > 0)
                  row('GST (included)', money(cart.billTaxTotal)),
                if (cart.roundOff.abs() >= 0.005)
                  row(
                    'Round off',
                    '${cart.roundOff > 0 ? '+' : '−'} ${money(cart.roundOff.abs())}',
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                    Text(
                      money(cart.total),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onCheckout,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(checkoutLabel),
                      const SizedBox(width: 8),
                      const _KeyHint('F12', onDark: true),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _Shortcut('F2', 'Search'),
                    _Shortcut('↑↓ Enter', 'Add item'),
                    _Shortcut('F4', 'Customer'),
                    _Shortcut('Esc', 'Clear search'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.keys, this.label);

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _KeyHint(keys),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
      ],
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint(this.keys, {this.onDark = false});

  final String keys;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.18) : AppColors.canvas,
        borderRadius: BorderRadius.circular(4),
        border: onDark ? null : Border.all(color: AppColors.line),
      ),
      child: Text(
        keys,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: onDark ? Colors.white : AppColors.inkSoft,
        ),
      ),
    );
  }
}
