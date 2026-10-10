import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/products/variant_builder.dart';
import 'package:softraxa_inventory/features/products/variant_grid.dart';
import 'package:softraxa_inventory/features/products/variant_matrix.dart';
import 'package:softraxa_inventory/features/products/variant_sheet.dart';

void main() {
  testWidgets('tap sizes and colours: every combination at once', (
    tester,
  ) async {
    List<VariantDraft>? result;
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showVariantBuilder(
                context,
                businessType: 'garment',
                productName: 'Cotton Kurta',
                productCode: 'Cotton Kurta',
                productPrice: 500,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A kurta starts on Size; tap M and L, then add Color: Red, Blue.
    expect(find.text('Size — tap the ones you have'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'M'));
    await tester.tap(find.widgetWithText(FilterChip, 'L'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Color'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Red'));
    await tester.tap(find.widgetWithText(FilterChip, 'Blue'));
    await tester.pump();
    expect(find.text('4 variants'), findsOneWidget);
    expect(find.text('M / Red'), findsOneWidget);

    // One price for all, and stock for one.
    await tester.enterText(
      find.widgetWithText(TextField, 'Same price for all ₹'),
      '550',
    );
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Stock').first, '5');
    await tester.tap(find.text('Make codes automatically'));
    await tester.pump();
    await tester.tap(find.text('Done (4)'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 4);
    expect(
      [for (final d in result!) d.name],
      ['M / Red', 'M / Blue', 'L / Red', 'L / Blue'],
    );
    expect(result!.every((d) => d.sellingPrice == 550), isTrue);
    expect(result!.first.openingStock, 5);
    expect(result!.first.sku, 'COTTON-KURTA-M-RED');
    expect(result!.first.attributes, {'Size': 'M', 'Color': 'Red'});
  });

  testWidgets('later: only the new combinations, the old ones locked', (
    tester,
  ) async {
    List<VariantDraft>? result;
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showVariantBuilder(
                context,
                businessType: 'garment',
                productName: 'Cotton Kurta',
                productPrice: 500,
                existing: const [
                  {
                    'id': 'v1',
                    'name': 'M',
                    'attributes': {'Size': 'M'},
                  },
                ],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Already there'), findsOneWidget);
    // M is in use: it can't be unticked here.
    await tester.tap(find.widgetWithText(FilterChip, 'M'));
    await tester.tap(find.widgetWithText(FilterChip, 'XL'));
    await tester.pump();
    expect(find.text('1 new variants'), findsOneWidget);
    await tester.tap(find.text('Add 1'));
    await tester.pumpAndSettle();
    expect([for (final d in result!) d.name], ['XL']);
  });

  testWidgets('billing grid: sizes across, colours down, tap to pick', (
    tester,
  ) async {
    final variants = [
      for (final (i, c) in ['Red', 'Blue'].indexed)
        for (final (j, s) in ['M', 'L'].indexed)
          {
            'id': '$i$j',
            'name': '$c / $s',
            'attributes': {'Color': c, 'Size': s},
            'current_stock': i + j,
          },
    ];
    Map<String, dynamic>? picked;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showVariantGridPicker(
                context,
                product: const {'name': 'Kurta', 'selling_price': 500},
                grid: variantGridOf(variants)!,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Red'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    // Blue / L has stock 2.
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(picked?['name'], 'Blue / L');
  });

  testWidgets('purchases: quantities for every size at once', (tester) async {
    final variants = [
      for (final s in ['M', 'L', 'XL'])
        {
          'id': s,
          'name': s,
          'attributes': {'Size': s},
          'current_stock': 0,
        },
    ];
    List<(Map<String, dynamic>, double)>? got;
    await tester.binding.setSurfaceSize(const Size(900, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              got = await showVariantQtyGrid(
                context,
                product: const {'name': 'Kurta'},
                grid: variantGridOf(variants)!,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final boxes = find.byType(TextField);
    expect(boxes, findsNWidgets(3));
    await tester.enterText(boxes.at(0), '10');
    await tester.enterText(boxes.at(2), '5');
    await tester.pump();
    await tester.tap(find.text('Add 2 lines (15 pcs)'));
    await tester.pumpAndSettle();
    expect(
      [for (final (v, q) in got!) '${v['name']} $q'],
      ['M 10.0', 'XL 5.0'],
    );
  });
}
