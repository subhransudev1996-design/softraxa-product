import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/file_export.dart';

void main() {
  test('safeFileName removes characters Windows rejects', () {
    expect(safeFileName('INV/26-27/0001.pdf'), 'INV-26-27-0001.pdf');
    expect(safeFileName(r'a\b:c*d?e"f<g>h|i.pdf'), 'a-b-c-d-e-f-g-h-i.pdf');
    expect(safeFileName('  Sales   report .pdf '), 'Sales report .pdf');
    expect(safeFileName('///'), '---');
    expect(safeFileName(''), 'document');
  });
}
