import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/reports/report_detail_screen.dart';

void main() {
  final rows = [
    ['Ravi Kumar', '98765 43210', '₹1,200.00'],
    ['Sita Devi', '91234 56789', '₹300.00'],
    ['Amul Butter 100 g', '28', '₹52.00'],
  ];

  test('matches any cell, ignoring case', () {
    expect(filterReportRows(rows, ''), rows);
    expect(filterReportRows(rows, 'ravi'), [rows[0]]);
    expect(filterReportRows(rows, 'BUTTER'), [rows[2]]);
    expect(filterReportRows(rows, '1,200'), [rows[0]]);
    expect(filterReportRows(rows, 'xyz'), isEmpty);
  });

  test('phone numbers match with or without spaces', () {
    expect(filterReportRows(rows, '9876543210'), [rows[0]]);
    expect(filterReportRows(rows, '56789'), [rows[1]]);
  });
}
