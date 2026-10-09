import '../../core/formatters.dart';

/// Sale-return rules per bill line, matching create_sale_return (0075):
/// each returned quantity is worth its own bill line's price — a box at the
/// box price, a loose piece at the loose price, after the line's discount,
/// GST included — then the bill discount's share.

/// One unit (base unit, e.g. a piece) of this bill line, as billed.
double returnUnitValue(Map<String, dynamic> it) {
  final q = toDouble(it['quantity']);
  return q > 0 ? toDouble(it['line_total']) / q : 0;
}

/// Pieces in one pack for a line sold by the pack (0061); null otherwise.
double? linePackSize(Map<String, dynamic> it) {
  final f = toDouble(it['alt_factor']);
  return it['sold_as_pack'] == true && f > 0 ? f : null;
}

String lineUnitShort(Map<String, dynamic> it) {
  final u = (it['unit_name'] as String? ?? '').trim();
  return u.isEmpty ? 'pcs' : u;
}

/// A return quantity (base units) as it reads for this line:
/// "2 Box", "1 Box + 3 pcs", "7 pcs", or just "7" for a plain line.
String returnQtyLabel(double q, Map<String, dynamic> it) {
  final size = linePackSize(it);
  if (size == null) return qty(q);
  final packs = (q / size + 1e-9).floorToDouble();
  final loose = double.parse((q - packs * size).toStringAsFixed(3));
  final pack = it['alt_unit_name'] as String? ?? '';
  final unit = lineUnitShort(it);
  if (packs <= 0) return '${qty(loose)} $unit';
  if (loose <= 0) return '${qty(packs)} $pack';
  return '${qty(packs)} $pack + ${qty(loose)} $unit';
}

/// Already returned from this bill: per bill line (returns that name their
/// line) and per product (all returns, older ones included).
class ReturnedSoFar {
  const ReturnedSoFar({this.byLine = const {}, this.byProduct = const {}});

  final Map<String, double> byLine;
  final Map<String, double> byProduct;

  static String productKey(Map<String, dynamic> row) =>
      '${row['product_id']}:${row['variant_id'] ?? ''}';

  factory ReturnedSoFar.fromRows(List<Map<String, dynamic>> rows) {
    final line = <String, double>{};
    final product = <String, double>{};
    for (final r in rows) {
      final q = toDouble(r['quantity']);
      final k = productKey(r);
      product[k] = (product[k] ?? 0) + q;
      final id = r['invoice_item_id'] as String?;
      if (id != null) line[id] = (line[id] ?? 0) + q;
    }
    return ReturnedSoFar(byLine: line, byProduct: product);
  }
}

/// What is still returnable from a line: its own quantity less what was
/// returned from it, and never more than the product has left on the bill
/// (older returns didn't record their line).
double maxReturnableFrom(
  Map<String, dynamic> it,
  List<Map<String, dynamic>> allLines,
  ReturnedSoFar returned,
) {
  final lineLeft = toDouble(it['quantity']) - (returned.byLine[it['id']] ?? 0);
  final key = ReturnedSoFar.productKey(it);
  final sold = allLines
      .where((l) => ReturnedSoFar.productKey(l) == key)
      .fold<double>(0, (s, l) => s + toDouble(l['quantity']));
  final productLeft = sold - (returned.byProduct[key] ?? 0);
  final left = lineLeft < productLeft ? lineLeft : productLeft;
  return left < 0 ? 0 : double.parse(left.toStringAsFixed(3));
}

/// The value the server gives one returned row: quantity × the line's unit
/// value × the bill-discount share, to the paisa.
double returnRowValue(
  double quantity,
  Map<String, dynamic> it,
  double billDiscountFactor,
) => (quantity * returnUnitValue(it) * billDiscountFactor * 100).round() / 100;
