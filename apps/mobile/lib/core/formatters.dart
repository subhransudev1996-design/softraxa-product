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

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

double toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// "2 pcs", "1.5 kg"
String qtyUnit(num? q, String? unit) =>
    unit == null || unit.isEmpty ? qty(q) : '${qty(q)} $unit';
