import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/variant_presets.dart';

String? label(String name, [String category = '']) =>
    suggestVariantPreset(name: name, category: category)?.label;

void main() {
  group('suggestVariantPreset', () {
    test('appliances by name', () {
      expect(label('LG Washing Machine 7kg'), 'Washing machine');
      expect(label('Voltas 1.5 Ton AC'), 'Air conditioner');
      expect(label('Samsung Double Door Fridge'), 'Refrigerator');
      expect(label('Mi Smart TV'), 'Television');
    });
    test('phones, clothes, hardware', () {
      expect(label('Redmi Note 13'), 'Mobile phone');
      expect(label('Cotton Shirt'), 'Clothing');
      expect(label('Bata Shoes'), 'Footwear');
      expect(label('Havells Wire'), 'Wire');
      expect(label('Italian White Marble'), 'Tiles / marble');
      expect(label('Castrol Magnetic 5W-30'), 'Engine oil');
    });
    test('category is used when the name says nothing', () {
      expect(label('Model X200', 'Washing Machines'), 'Washing machine');
      expect(label('Model X200', 'Washing machine'), 'Washing machine');
    });
    test('no match falls back', () {
      expect(label('Something'), isNull);
      expect(label(''), isNull);
      // "ac" only as a whole word
      expect(label('Lacquer'), isNull);
    });
  });

  test('optionsForField gathers values across presets', () {
    expect(optionsForField('Capacity'), contains('7 kg'));
    expect(optionsForField('color'), contains('Black'));
    expect(optionsForField('Unknown'), isEmpty);
  });
}
