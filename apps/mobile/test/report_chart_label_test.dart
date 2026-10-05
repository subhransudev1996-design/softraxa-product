import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/reports/report_charts.dart';

void main() {
  test('a full date shrinks to day and month so labels never collide', () {
    expect(ReportBarChart.axisLabel('01 Oct 2026'), '1 Oct');
    expect(ReportBarChart.axisLabel('15 Dec 2026'), '15 Dec');
    expect(ReportBarChart.axisLabel('5 Jan 2027'), '5 Jan');
  });

  test('other labels are only cut when they are long', () {
    expect(ReportBarChart.axisLabel('Grocery'), 'Grocery');
    expect(ReportBarChart.axisLabel('Amul Pure Ghee 1 L'), 'Amul Pure…');
  });
}
