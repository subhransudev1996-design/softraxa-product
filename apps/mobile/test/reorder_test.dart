import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/reports/reorder.dart';

void main() {
  final rows = [
    {
      'id': 'p1',
      'name': 'Amul Butter 100 g',
      'current_stock': 4,
      'low_stock_qty': 10,
      'has_variants': false,
      'units': {'short_name': 'pcs', 'allow_decimal': false},
    },
    {
      'id': 'p2',
      'name': 'Sugar (loose)',
      'current_stock': 3.25,
      'low_stock_qty': 5,
      'has_variants': false,
      'units': {'short_name': 'kg', 'allow_decimal': true},
    },
    {
      'id': 'p3',
      'name': 'Bisleri 1 L',
      'current_stock': 60,
      'low_stock_qty': 10,
      'has_variants': false,
      'units': {'short_name': 'pcs'},
    },
    {
      'id': 'p4',
      'name': 'T-shirt',
      'has_variants': true,
      'low_stock_qty': 2,
      'units': {'short_name': 'pcs'},
      'product_variants': [
        {'id': 'v1', 'name': 'M', 'current_stock': 1, 'low_stock_qty': null, 'is_active': true},
        {'id': 'v2', 'name': 'L', 'current_stock': 9, 'low_stock_qty': null, 'is_active': true},
        {'id': 'v3', 'name': 'XL', 'current_stock': 0, 'low_stock_qty': 3, 'is_active': false},
      ],
    },
  ];

  test('suggested quantity refills to twice the alert level', () {
    expect(suggestedReorderQty(4, 10), 16);
    expect(suggestedReorderQty(3.25, 5, allowDecimal: true), 6.8);
    expect(suggestedReorderQty(25, 10), 1); // never below one unit
  });

  test('picks low items, variant-aware, skipping inactive variants', () {
    final items = lowStockItems(rows);
    expect(items.map((i) => i.name), ['Amul Butter 100 g', 'Sugar (loose)', 'T-shirt — M']);
    expect(items.first.qty, 16);
    expect(items[2].qty, 3);
  });

  test('last supplier: latest purchase wins; variant lines match exactly', () {
    final items = lowStockItems(rows);
    applyLastSuppliers(items, [
      {'product_id': 'p1', 'variant_id': null, 'purchases': {'supplier_id': 's1', 'supplier_name': 'Rakesh', 'purchase_date': '2026-09-01'}},
      {'product_id': 'p1', 'variant_id': null, 'purchases': {'supplier_id': 's2', 'supplier_name': 'Sharma Wholesale', 'purchase_date': '2026-10-05'}},
      {'product_id': 'p2', 'variant_id': null, 'purchases': {'supplier_id': 's2', 'supplier_name': 'Sharma Wholesale', 'purchase_date': '2026-10-01'}},
      {'product_id': 'p4', 'variant_id': 'v2', 'purchases': {'supplier_id': 's1', 'supplier_name': 'Rakesh', 'purchase_date': '2026-10-02'}},
      {'product_id': 'p4', 'variant_id': null, 'purchases': {'supplier_id': null, 'supplier_name': '', 'purchase_date': '2026-10-03'}},
    ]);
    expect(items[0].lastSupplierName, 'Sharma Wholesale');
    expect(items[1].lastSupplierId, 's2');
    expect(items[2].lastSupplierId, isNull); // only variant L was bought
    expect(likelySupplier(items), 's2');
  });

  test('WhatsApp message lists items with quantities and the shop', () {
    final items = lowStockItems(rows).take(2).toList();
    final text = reorderMessage(
      supplierName: 'Sharma Wholesale',
      shopName: 'Sharma General Store',
      shopPhone: '82609 66559',
      items: items,
    );
    expect(text, contains('Namaste Sharma Wholesale ji,'));
    expect(text, contains('1. Amul Butter 100 g — 16 pcs'));
    expect(text, contains('2. Sugar (loose) — 6.8 kg'));
    expect(text, endsWith('— Sharma General Store, 82609 66559'));
  });

  test('WhatsApp numbers get the country code', () {
    expect(whatsAppNumber('98765 00011'), '919876500011');
    expect(whatsAppNumber('09876500011'), '919876500011');
    expect(whatsAppNumber('+91 98765-00011'), '919876500011');
    expect(whatsAppNumber('12345'), '');
  });
}
