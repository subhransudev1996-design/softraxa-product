import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/products/variant_matrix.dart';

Map<String, dynamic> v(String id, Map<String, String> attrs) => {
  'id': id,
  'name': variantNameOf(attrs),
  'attributes': attrs,
};

void main() {
  test('every size in every colour, first axis slowest', () {
    final combos = variantCombinations([
      VariantAxis('Color', ['Red', 'Blue']),
      VariantAxis('Size', ['S', 'M', 'L']),
      VariantAxis('Fabric'), // no values: skipped
    ]);
    expect(combos.length, 6);
    expect(combos.first, {'Color': 'Red', 'Size': 'S'});
    expect(combos.last, {'Color': 'Blue', 'Size': 'L'});
    expect(variantNameOf(combos.first), 'Red / S');
    expect(variantCombinations([VariantAxis('Size')]), isEmpty);
  });

  test('sizes in the order they are worn; numbers by value', () {
    expect(sortAxisValues(['XL', 'S', 'XXL', 'M', 'L']), [
      'S',
      'M',
      'L',
      'XL',
      'XXL',
    ]);
    expect(sortAxisValues(['32', '28', '30', '34']), ['28', '30', '32', '34']);
    expect(sortAxisValues(['8 kg', '6 kg', '10 kg']), [
      '6 kg',
      '8 kg',
      '10 kg',
    ]);
    // Colours keep the order they were given in.
    expect(sortAxisValues(['Red', 'Black', 'Blue']), ['Red', 'Black', 'Blue']);
  });

  test('the same combination whatever the order or case', () {
    expect(
      variantKey({'Size': 'M', 'Color': 'Red'}),
      variantKey({'color': 'red', 'size': 'm'}),
    );
    expect(variantKey({'Size': 'M'}), isNot(variantKey({'Size': 'L'})));
  });

  test('a size × colour grid: sizes across, colours down', () {
    final variants = [
      v('1', {'Color': 'Red', 'Size': 'L'}),
      v('2', {'Color': 'Red', 'Size': 'S'}),
      v('3', {'Color': 'Blue', 'Size': 'S'}),
    ];
    final g = variantGridOf(variants)!;
    expect(g.columns.name, 'Size');
    expect(g.columns.values, ['S', 'L']);
    expect(g.rows!.values, ['Red', 'Blue']);
    expect(g.cell('Red', 'S')!['id'], '2');
    expect(g.cell('Blue', 'L'), isNull); // not made
  });

  test('one axis is a single row; three axes or no attributes: no grid', () {
    final g = variantGridOf([
      v('1', {'Storage': '128 GB'}),
      v('2', {'Storage': '64 GB'}),
    ])!;
    expect(g.rows, isNull);
    expect(g.rowValues, [null]);
    expect(g.columns.values, ['64 GB', '128 GB']);
    expect(g.cell(null, '128 GB')!['id'], '1');

    expect(
      variantGridOf([
        v('1', {'A': '1', 'B': '2', 'C': '3'}),
      ]),
      isNull,
    );
    expect(
      variantGridOf([
        {'id': '1', 'name': 'Old one', 'attributes': {}},
      ]),
      isNull,
    );
    // Two variants claiming the same box: a list is safer.
    expect(
      variantGridOf([
        v('1', {'Size': 'M'}),
        v('2', {'Size': 'M'}),
      ]),
      isNull,
    );
  });

  test('automatic codes', () {
    expect(
      autoVariantSku('Cotton Kurta', {'Color': 'Red', 'Size': 'XL'}),
      'COTTON-KURTA-RED-XL',
    );
    expect(autoVariantSku('', {'Storage': '128 GB'}), '128-GB');
    expect(
      autoVariantSku('Very Long Product Name Here', {'Size': 'M'}),
      'VERY-LONG-PR-M',
    );
  });
}
