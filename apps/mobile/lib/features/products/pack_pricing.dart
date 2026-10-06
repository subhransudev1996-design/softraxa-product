/// Bulk-unit price maths for the product form: a shop owner knows what a
/// 50 kg bag of sugar costs, not what one kg costs, so they type the bag
/// price and the per-kg price follows.
library;

/// Price of one base unit when [packPrice] buys [size] of them
/// (₹1600 a 50 kg bag → ₹32 a kg), rounded to paise.
/// Null when either number is missing.
double? perUnitPrice(double? packPrice, double? size) {
  if (packPrice == null || packPrice <= 0 || size == null || size <= 0) {
    return null;
  }
  return (packPrice / size * 100).round() / 100;
}

/// Price of one pack when one base unit costs [unitPrice].
double? packPriceFor(double? unitPrice, double? size) {
  if (unitPrice == null || unitPrice <= 0 || size == null || size <= 0) {
    return null;
  }
  return (unitPrice * size * 100).round() / 100;
}

/// A price for a text field: "32", "36.67", "" for null.
String priceText(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// "Profit ₹200 a Bag (13%)", or a loss, or null without both prices.
/// Selling prices include GST, so with a [gstRate] the tax comes off the
/// selling price first (₹1800 at 18% GST is ₹1525.42 to the shop).
String? packMarginText(
  double? cost,
  double? sell,
  String unit, {
  double gstRate = 0,
}) {
  if (cost == null || cost <= 0 || sell == null || sell <= 0) return null;
  final net = gstRate > 0 ? sell / (1 + gstRate / 100) : sell;
  final m = ((net - cost) * 100).round() / 100;
  final pct = (m / cost * 100).round();
  final amt = priceText(m.abs());
  final gst = gstRate > 0 ? ' after ${priceText(gstRate)}% GST' : '';
  return m >= 0
      ? 'Profit ₹$amt a $unit ($pct%)$gst'
      : 'Loss ₹$amt a $unit$gst — selling below cost';
}
