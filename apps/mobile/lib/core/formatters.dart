import 'package:intl/intl.dart';

final _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);
final _moneyCompact = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _qty = NumberFormat('#,##0.###', 'en_IN');
final _date = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

String money(num? v) => _money.format(v ?? 0);
String moneyCompact(num? v) => _moneyCompact.format(v ?? 0);
String qty(num? v) => _qty.format(v ?? 0);
String dateStr(dynamic v) {
  final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '' : _date.format(d.toLocal());
}

String dateTimeStr(dynamic v) {
  final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '' : _dateTime.format(d.toLocal());
}

/// Short form for lists: "Today, 10:51 AM", "Yesterday, 6:30 PM", else
/// "25 Jul, 8:12 PM" (with the year only when it isn't this year).
String shortDateTimeStr(dynamic v) {
  final d0 = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
  if (d0 == null) return '';
  final d = d0.toLocal();
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final time = DateFormat('h:mm a').format(d);
  if (day == today) return 'Today, $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
  final date = DateFormat(
    d.year == now.year ? 'd MMM' : 'd MMM yyyy',
  ).format(d);
  return '$date, $time';
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

double toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// "2 pcs", "1.5 kg"
String qtyUnit(num? q, String? unit) =>
    unit == null || unit.isEmpty ? qty(q) : '${qty(q)} $unit';

/// How a saved bill line was sold: a line sold by the pack (migration
/// 0061) is stored in base units — 10 pcs at ₹9.50 — but reads as it was
/// sold: 1 Box at ₹95. [per] is the base units per shown unit, to scale a
/// stored per-unit rate.
({double qty, String unit, double per}) billedQty(Map<String, dynamic> it) {
  final q = toDouble(it['quantity']);
  final factor = toDouble(it['alt_factor']);
  if (it['sold_as_pack'] == true && factor > 0) {
    return (
      qty: q / factor,
      unit: it['alt_unit_name'] as String? ?? '',
      per: factor,
    );
  }
  return (qty: q, unit: it['unit_name'] as String? ?? '', per: 1);
}
