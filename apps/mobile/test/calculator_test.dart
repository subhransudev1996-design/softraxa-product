import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/calculator/calc_engine.dart';

CalcState type(String keys, [CalcState s = const CalcState()]) {
  for (final c in keys.split('')) {
    s = switch (c) {
      '+' => s.op(calcPlus),
      '-' => s.op(calcMinus),
      '*' => s.op(calcTimes),
      '/' => s.op(calcDivide),
      '%' => s.percent(),
      '=' => s.equals(),
      _ => s.digit(c),
    };
  }
  return s;
}

const salt = CalcItem(
  kind: 'product',
  name: 'Salt',
  price: 28,
  gstRate: 5,
  product: {'id': 'p1'},
);
const sugar = CalcItem(kind: 'product', name: 'Sugar', price: 45);
const fitting = CalcItem(
  kind: 'service',
  name: 'Fitting',
  price: 118,
  gstRate: 18,
);

void main() {
  test('plain sums, × and ÷ before + and −', () {
    expect(type('2+3*4').evaluate().total, 14);
    expect(type('100-20/4').evaluate().total, 95);
    expect(type('-5+2').evaluate().total, -3);
    expect(type('7+').evaluate().total, 7); // trailing operator ignored
    expect(type('5/0').evaluate().total, isNull);
    expect(const CalcState().evaluate().total, isNull);
  });

  test('percent works like a shop calculator', () {
    expect(type('200+10%').evaluate().total, 220);
    expect(type('200-10%').evaluate().total, 180);
    expect(type('50*10%').evaluate().total, 5);
  });

  test('typing numbers', () {
    expect(type('1.2.5').tokens.single.text, '1.25');
    expect(type('007').tokens.single.text, '7');
    expect(type('12').backspace().tokens.single.text, '1');
    expect(type('9+').backspace().tokens.length, 1);
  });

  test('= turns a plain sum into its answer', () {
    final s = type('12*3=');
    expect(s.tokens.single.text, '36');
    expect(type('+4', s).evaluate().total, 40);
    expect(type('2-5=').evaluate().total, -3);
  });

  test('items: a number before or after is the quantity', () {
    // Salt then 3 → Salt × 3; then Fitting → + Fitting.
    var s = const CalcState().addItem(salt);
    s = type('3', s).addItem(fitting);
    final r = s.evaluate();
    expect(r.total, 28 * 3 + 118);
    expect(r.lines.length, 2);
    expect(r.lines[0].item, salt);
    expect(r.lines[0].qty, 3);
    expect(r.lines[0].amount, 84);
    expect(r.lines[1].item, fitting);
    expect(r.lines[1].qty, 1);
    expect(r.problem, isNull);

    // 2 then Sugar → 2 × Sugar; Sugar then Salt → +.
    s = type('2').addItem(sugar).addItem(salt);
    expect(s.evaluate().total, 90 + 28);
    expect(s.evaluate().lines.first.qty, 2);
  });

  test('typed amounts and discounts beside items', () {
    final s = type('-10', type('+20', const CalcState().addItem(salt)));
    final r = s.evaluate();
    expect(r.total, 38);
    expect(r.lines[1].item, isNull);
    expect(r.lines[1].amount, 20);
    expect(r.lines[2].amount, -10);
    expect(r.hasItems, isTrue);
    // = keeps the items linked.
    expect(s.equals().tokens.length, s.tokens.length);
  });

  test('sums that cannot become a bill say why', () {
    var s = const CalcState().addItem(salt);
    s = type('*', s).addItem(sugar);
    expect(s.evaluate().problem, 'Two items are multiplied together');
    s = type('10/').addItem(salt);
    expect(s.evaluate().problem, 'An item is divided');
    s = type('-').addItem(salt);
    expect(s.evaluate().problem, 'An item has a minus or zero quantity');
  });

  test('a box keeps its box price', () {
    const box = CalcItem(
      kind: 'product',
      name: 'Pen',
      price: 95,
      packSize: 10,
      unit: 'Box',
    );
    final r = type('2', const CalcState().addItem(box)).evaluate();
    expect(r.total, 190);
    expect(r.lines.single.qty, 2);
  });

  test('WhatsApp quote lists the parts and the total', () {
    final s = type(
      '-10',
      type('+20', type('3', const CalcState().addItem(salt))),
    );
    final text = calcQuoteMessage(
      s.evaluate(),
      shopName: 'Sharma Store',
      shopPhone: '98765 43210',
      customerName: 'Ravi',
    );
    expect(text, contains('Hello Ravi,'));
    expect(text, contains('Price quote from Sharma Store:'));
    expect(text, contains('Salt × 3'));
    expect(text, contains('Other charges'));
    expect(text, contains('Discount'));
    expect(text, contains('Total: '));
    expect(text, contains('Prices include GST.'));
    expect(text, endsWith('— Sharma Store, 98765 43210'));
  });
}
