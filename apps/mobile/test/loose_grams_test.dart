import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/loose_qty_sheet.dart';

void main() {
  test('kg and litre goods have a smaller unit', () {
    expect(looseSubUnit('kg'), (name: 'g', factor: 1000.0));
    expect(looseSubUnit('L'), (name: 'ml', factor: 1000.0));
    expect(looseSubUnit('pcs'), isNull);
  });

  testWidgets('100 g of a ₹40/kg product adds 0.1 kg for ₹4', (tester) async {
    LooseQtyResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showLooseQtySheet(
              context,
              name: 'Sugar',
              rate: 40,
              unitName: 'kg',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Switch to grams and type 100.
    await tester.tap(find.text('g'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pumpAndSettle();
    expect(find.textContaining('Add 100 g'), findsOneWidget);
    expect(find.textContaining('4.00'), findsWidgets);

    await tester.tap(find.textContaining('Add 100 g'));
    await tester.pumpAndSettle();
    expect(result!.qty, closeTo(0.1, 1e-9));
  });

  testWidgets('the 250 g chip works while typing in kg', (tester) async {
    LooseQtyResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showLooseQtySheet(
              context,
              name: 'Dal',
              rate: 120,
              unitName: 'kg',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('250 g'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add 250 g'));
    await tester.pumpAndSettle();
    expect(result!.qty, closeTo(0.25, 1e-9));
  });
}
