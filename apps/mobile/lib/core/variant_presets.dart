/// Variant fields that fit the product being added, so a washing machine
/// asks for capacity and load type, not the shop's phone fields (RAM,
/// storage). Matched on the product's name and category; the shop type's
/// own fields (business_category.dart) are the fallback.
library;

class VariantField {
  const VariantField(this.name, [this.options = const []]);

  final String name;

  /// Common values, offered as one-tap chips.
  final List<String> options;
}

class VariantPreset {
  const VariantPreset(this.label, this.keywords, this.fields);

  /// Shown as "Fields for: <label>".
  final String label;

  /// Whole words (or phrases) looked for in the product name and category.
  final List<String> keywords;
  final List<VariantField> fields;
}

const _colors = ['Black', 'White', 'Blue', 'Red', 'Grey', 'Silver'];
const _stars = ['3 Star', '4 Star', '5 Star'];

/// Most specific first: the first preset with a matching keyword wins.
const variantPresets = <VariantPreset>[
  VariantPreset(
    'Washing machine',
    ['washing machine', 'washing', 'washer'],
    [
      VariantField('Capacity', ['6 kg', '7 kg', '8 kg', '9 kg', '10 kg']),
      VariantField('Type', ['Front load', 'Top load', 'Semi-automatic']),
      VariantField('Color', _colors),
    ],
  ),
  VariantPreset(
    'Air conditioner',
    [
      'air conditioner',
      'ac',
      'split ac',
      'window ac',
      'voltas',
      'daikin',
      'lloyd',
      'carrier',
      'hitachi',
    ],
    [
      VariantField('Capacity', ['1 Ton', '1.5 Ton', '2 Ton']),
      VariantField('Type', ['Split', 'Window', 'Portable']),
      VariantField('Star rating', _stars),
      VariantField('Inverter', ['Inverter', 'Non-inverter']),
    ],
  ),
  VariantPreset(
    'Refrigerator',
    ['refrigerator', 'fridge'],
    [
      VariantField('Capacity', ['190 L', '250 L', '300 L', '340 L', '450 L']),
      VariantField('Doors', ['Single door', 'Double door', 'Side-by-side']),
      VariantField('Star rating', _stars),
      VariantField('Color', _colors),
    ],
  ),
  VariantPreset(
    'Television',
    ['tv', 'television', 'smart tv', 'led tv'],
    [
      VariantField('Screen size', [
        '32 inch',
        '43 inch',
        '50 inch',
        '55 inch',
        '65 inch',
      ]),
      VariantField('Resolution', ['HD Ready', 'Full HD', '4K']),
    ],
  ),
  VariantPreset(
    'Laptop',
    ['laptop', 'notebook', 'macbook'],
    [
      VariantField('Processor', ['i3', 'i5', 'i7', 'Ryzen 5', 'Ryzen 7']),
      VariantField('RAM', ['8 GB', '16 GB', '32 GB']),
      VariantField('Storage', ['256 GB SSD', '512 GB SSD', '1 TB SSD']),
      VariantField('Color', _colors),
    ],
  ),
  VariantPreset(
    'Mobile phone',
    [
      'phone',
      'mobile',
      'smartphone',
      'iphone',
      'galaxy',
      'redmi',
      'vivo',
      'oppo',
      'realme',
      'iqoo',
      'oneplus',
      'poco',
      'nokia',
      'motorola',
      'neo',
      'note',
    ],
    [
      VariantField('RAM', ['4 GB', '6 GB', '8 GB', '12 GB']),
      VariantField('Storage', ['64 GB', '128 GB', '256 GB', '512 GB']),
      VariantField('Color', _colors),
    ],
  ),
  VariantPreset(
    'Mobile accessory',
    [
      'charger',
      'cable',
      'earphone',
      'earphones',
      'earbuds',
      'headphone',
      'headphones',
      'cover',
      'case',
      'tempered',
      'screen guard',
      'power bank',
    ],
    [
      VariantField('Fits model'),
      VariantField('Type', ['Type-C', 'Lightning', 'Micro USB']),
      VariantField('Color', _colors),
    ],
  ),
  VariantPreset(
    'Fan',
    ['fan', 'ceiling fan', 'table fan'],
    [
      VariantField('Sweep', ['900 mm', '1200 mm', '1400 mm']),
      VariantField('Type', ['Ceiling', 'Table', 'Wall', 'Pedestal']),
      VariantField('Color', ['White', 'Brown', 'Black', 'Ivory']),
    ],
  ),
  VariantPreset(
    'Light / bulb',
    ['bulb', 'led light', 'tube', 'tubelight', 'batten', 'lamp', 'panel light'],
    [
      VariantField('Wattage', ['9 W', '12 W', '15 W', '18 W', '20 W']),
      VariantField('Light color', [
        'Cool white',
        'Warm white',
        'Natural white',
      ]),
    ],
  ),
  VariantPreset(
    'Wire',
    ['wire', 'wires', 'cable roll'],
    [
      VariantField('Size', [
        '0.75 sq mm',
        '1 sq mm',
        '1.5 sq mm',
        '2.5 sq mm',
        '4 sq mm',
      ]),
      VariantField('Color', ['Red', 'Black', 'Blue', 'Yellow', 'Green']),
      VariantField('Length', ['90 m', '180 m']),
    ],
  ),
  VariantPreset(
    'Switch / socket',
    ['switch', 'socket', 'mcb', 'plug'],
    [
      VariantField('Rating', ['6 A', '16 A', '32 A']),
      VariantField('Color', ['White', 'Black', 'Grey']),
    ],
  ),
  VariantPreset(
    'Pipe',
    ['pipe', 'pipes', 'fitting', 'elbow'],
    [
      VariantField('Size', [
        '1/2 inch',
        '3/4 inch',
        '1 inch',
        '1.5 inch',
        '2 inch',
      ]),
      VariantField('Material', ['PVC', 'CPVC', 'UPVC', 'GI']),
      VariantField('Length', ['3 m', '6 m']),
    ],
  ),
  VariantPreset(
    'Paint',
    ['paint', 'emulsion', 'primer', 'distemper', 'enamel'],
    [
      VariantField('Shade'),
      VariantField('Pack size', ['1 L', '4 L', '10 L', '20 L']),
      VariantField('Finish', ['Matt', 'Satin', 'Gloss']),
    ],
  ),
  VariantPreset(
    'Tiles / marble',
    ['tile', 'tiles', 'marble', 'granite'],
    [
      VariantField('Size', ['60x60 cm', '60x120 cm', '30x60 cm', '80x80 cm']),
      VariantField('Finish', ['Glossy', 'Matt', 'Rustic']),
      VariantField('Color'),
      VariantField('Thickness', ['8 mm', '10 mm', '16 mm']),
    ],
  ),
  VariantPreset(
    'Engine oil',
    ['engine oil', '5w', '10w', '15w', '20w', 'lubricant', 'castrol', 'servo'],
    [
      VariantField('Grade', ['5W-30', '10W-30', '15W-40', '20W-40', '20W-50']),
      VariantField('Pack size', ['500 ml', '900 ml', '1 L', '3.5 L', '5 L']),
    ],
  ),
  VariantPreset(
    'Tyre',
    ['tyre', 'tyres', 'tire'],
    [
      VariantField('Size'),
      VariantField('Type', ['Tubeless', 'Tube type']),
    ],
  ),
  VariantPreset(
    'Battery',
    ['battery', 'inverter battery'],
    [
      VariantField('Capacity', ['35 Ah', '65 Ah', '100 Ah', '150 Ah']),
      VariantField('Warranty', ['1 year', '2 years', '3 years', '5 years']),
    ],
  ),
  VariantPreset(
    'Clothing',
    [
      'shirt',
      't-shirt',
      'tshirt',
      'kurta',
      'kurti',
      'jeans',
      'pant',
      'pants',
      'trouser',
      'saree',
      'dress',
      'top',
      'jacket',
      'hoodie',
      'leggings',
      'shorts',
    ],
    [
      VariantField('Size', [
        'XS',
        'S',
        'M',
        'L',
        'XL',
        'XXL',
        '3XL',
        'Free size',
      ]),
      VariantField('Color', _colors),
      VariantField('Fabric', ['Cotton', 'Polyester', 'Denim', 'Linen']),
    ],
  ),
  VariantPreset(
    'Footwear',
    [
      'shoe',
      'shoes',
      'sandal',
      'sandals',
      'slipper',
      'slippers',
      'chappal',
      'sneaker',
      'sneakers',
    ],
    [
      VariantField('Size', ['6', '7', '8', '9', '10']),
      VariantField('Color', _colors),
    ],
  ),
  VariantPreset(
    'Packed goods',
    [
      'rice',
      'atta',
      'flour',
      'dal',
      'sugar',
      'salt',
      'oil',
      'ghee',
      'tea',
      'coffee',
      'biscuit',
      'soap',
      'shampoo',
      'detergent',
      'masala',
    ],
    [
      VariantField('Pack size', ['100 g', '250 g', '500 g', '1 kg', '5 kg']),
      VariantField('Flavour / type'),
    ],
  ),
];

/// The preset for a product, from its name and category; null when
/// nothing matches (the caller falls back to the shop type's fields).
VariantPreset? suggestVariantPreset({String name = '', String category = ''}) {
  final text =
      ' ${'$name $category'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.\- ]'), ' ')} ';
  if (text.trim().isEmpty) return null;
  for (final p in variantPresets) {
    for (final k in p.keywords) {
      if (text.contains(' $k ')) return p;
    }
  }
  return null;
}

/// Common values for a field name across all presets (used for fields
/// the user typed or that came from another variant).
List<String> optionsForField(String fieldName) {
  final f = fieldName.trim().toLowerCase();
  if (f.isEmpty) return const [];
  final out = <String>[];
  for (final p in variantPresets) {
    for (final vf in p.fields) {
      if (vf.name.toLowerCase() == f) {
        for (final o in vf.options) {
          if (!out.contains(o)) out.add(o);
        }
      }
    }
  }
  return out;
}
