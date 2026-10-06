import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/pos/cart.dart';
import 'package:softraxa_inventory/features/stock/pieces_card.dart';

Map<String, dynamic> rod({double charge = 0}) => {
  'id': 'r1',
  'name': 'TMT Rod',
  'selling_price': 50,
  'purchase_price': 40,
  'gst_rate': 0,
  'current_stock': 120,
  'track_pieces': true,
  'cutting_charge': charge,
  'units': {'short_name': 'ft', 'allow_decimal': true},
};

void main() {
  test('pieces of the same length are one row, longest first', () {
    final groups = groupPieces([
      {'id': 'a', 'length': 5},
      {'id': 'b', 'length': 12},
      {'id': 'c', 'length': 12.0},
      {'id': 'd', 'length': 12.0004},
    ]);
    expect(groups.map((g) => g.length), [12, 5]);
    expect(groups.first.pieces.length, 3);
  });

  group('cart', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('each cut is its own line, so the server cuts each one', () {
      final cart = c.read(cartProvider.notifier);
      cart.addProduct(rod(), addQty: 7);
      cart.addProduct(rod(), addQty: 5);
      final lines = c.read(cartProvider).lines;
      expect(lines.map((l) => l.qty), [7, 5]);
      expect(lines.every((l) => l.pieceId == null), isTrue);
    });

    test('the cutting charge comes once per cut', () {
      final cart = c.read(cartProvider.notifier);
      cart.addProduct(rod(charge: 10), addQty: 7);
      cart.addProduct(rod(charge: 10), addQty: 5);
      final charges = c
          .read(cartProvider)
          .lines
          .where((l) => l.linkedTo != null);
      expect(charges.length, 2);
    });
  });
}
