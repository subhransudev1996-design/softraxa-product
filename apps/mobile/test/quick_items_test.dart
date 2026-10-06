import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/quick_items.dart';

void main() {
  test('most often billed first; blanks ignored; capped', () {
    expect(
      mostBilledIds(['milk', 'bread', 'milk', null, '', 'eggs', 'milk', 'bread']),
      ['milk', 'bread', 'eggs'],
    );
    expect(mostBilledIds([for (var i = 0; i < 30; i++) 'p$i']).length, 12);
    expect(mostBilledIds(const []), isEmpty);
  });
}
