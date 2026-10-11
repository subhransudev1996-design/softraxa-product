import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/purchases/bill_reader/bill_match.dart';

void main() {
  test('sizes are written one way', () {
    expect(nameTokens('AMUL GHEE 1LTR TIN'), ['amul', 'ghee', '1l']);
    expect(nameTokens('Amul Pure Ghee 1 L'), ['amul', 'pure', 'ghee', '1l']);
    expect(nameTokens('Tata Salt 1000 GMS'), ['tata', 'salt', '1kg']);
    expect(nameTokens('Surf 500gm pkt'), ['surf', '500g']);
    expect(nameTokens('Oil 1.5 Ltr.'), ['oil', '1.5l']);
    expect(billItemKey('  AMUL GHEE 1LTR TIN '), 'amul ghee 1l');
  });

  test('different sizes never match', () {
    expect(
      nameScore(nameTokens('Amul Ghee 1L'), nameTokens('Amul Ghee 500 ml')),
      0,
    );
    expect(
      nameScore(nameTokens('Amul Ghee 1L'), nameTokens('Amul Ghee 1000ml')),
      1,
    );
  });

  final products = [
    MatchProduct(id: 'ghee1', name: 'Amul Pure Ghee 1 L', hsn: '0405'),
    MatchProduct(id: 'ghee500', name: 'Amul Pure Ghee 500 ml', hsn: '0405'),
    MatchProduct(id: 'butter', name: 'Amul Butter 100 g', hsn: '0405'),
    MatchProduct(id: 'salt', name: 'Tata Salt 1 kg', barcode: '8901234567890'),
    MatchProduct(id: 'parle', name: 'Parle-G Biscuit 250g'),
    MatchProduct(
      id: 'kurta',
      name: 'Cotton Kurta',
      variants: [
        MatchVariant(id: 'red-m', name: 'Red / M'),
        MatchVariant(id: 'blue-m', name: 'Blue / M'),
        MatchVariant(id: 'red-l', name: 'Red / L', sku: 'KUR-RED-L'),
      ],
    ),
  ];

  test("a supplier's name finds the shop's product", () {
    expect(bestMatch('AMUL GHEE 1LTR TIN', products)?.productId, 'ghee1');
    expect(bestMatch('AMUL GHEE 500ML', products)?.productId, 'ghee500');
    expect(bestMatch('TATA SALT 1KG', products)?.productId, 'salt');
    expect(bestMatch('PARLE G BISCUIT 250 GM', products)?.productId, 'parle');
    expect(bestMatch('Colgate Toothpaste 100g', products), isNull);
  });

  test('a size/colour on the bill picks the variant', () {
    final m = bestMatch('COTTON KURTA BLUE M', products)!;
    expect((m.productId, m.variantId), ('kurta', 'blue-m'));
  });

  test('a barcode or stock no. on the bill wins', () {
    final a = bestMatch('SALT', products, code: '8901234567890')!;
    expect((a.productId, a.byCode, a.score), ('salt', true, 1.0));
    final b = bestMatch('KUR-RED-L Kurta', products)!;
    expect((b.productId, b.variantId), ('kurta', 'red-l'));
  });

  test('pack size from the bill unit', () {
    expect(
      defaultPackFactor('Box', secondaryUnit: 'BX', conversionFactor: 12),
      12,
    );
    expect(
      defaultPackFactor('CS', secondaryUnit: 'Case', conversionFactor: 24),
      24,
    );
    expect(
      defaultPackFactor('Pcs', secondaryUnit: 'Box', conversionFactor: 12),
      1,
    );
    expect(defaultPackFactor('Doz', baseUnit: 'Pcs'), 12);
    expect(defaultPackFactor('Doz', baseUnit: 'kg'), 1);
  });

  test('different storage, model, number or colour never match', () {
    final phones = [
      MatchProduct(id: 'black256', name: 'Nothing Phone (4B) 8GB+256GB Black'),
      MatchProduct(id: 'redmi13', name: 'Redmi 13C 4GB+128GB Blue'),
      MatchProduct(id: 'dolo650', name: 'Dolo 650 Tablet'),
    ];
    expect(bestMatch('Nothing Phone (4B)8GB+128Gb White', phones), isNull);
    expect(bestMatch('Nothing Phone (4B)8GB+256Gb White', phones), isNull);
    expect(
      bestMatch('Nothing Phone (4B)8GB+256Gb Black', phones)?.productId,
      'black256',
    );
    expect(bestMatch('Redmi 12C 4GB+128GB Blue', phones), isNull);
    expect(bestMatch('DOLO 500 TAB', phones), isNull);
    expect(bestMatch('DOLO 650 TAB', phones)?.productId, 'dolo650');
    // A pack count the product's name doesn't have is no conflict.
    expect(bestMatch('AMUL GHEE 1LTR TIN 12', products)?.productId, 'ghee1');
  });
}
