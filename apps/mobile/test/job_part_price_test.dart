import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/jobcards/job_estimates.dart';

void main() {
  test('a part costs its selling price with GST, not GST twice', () {
    // ₹118 with 18% GST → ₹100 before GST; the job card adds the 18% back.
    expect(partPriceExGst({'selling_price': 118, 'gst_rate': 18}, null), 100);
    // A variant's own price.
    expect(
      partPriceExGst(
        {'selling_price': 50, 'gst_rate': 5},
        {'selling_price': 105},
      ),
      100,
    );
    // No GST: unchanged.
    expect(partPriceExGst({'selling_price': 28, 'gst_rate': 0}, null), 28);
    // Rounded to the paisa.
    expect(partPriceExGst({'selling_price': 100, 'gst_rate': 18}, null), 84.75);
  });
}
