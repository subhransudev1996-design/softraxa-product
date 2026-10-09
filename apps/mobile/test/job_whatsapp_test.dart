import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/jobcards/job_whatsapp.dart';

Map<String, dynamic> job(String status) => {
  'status': status,
  'job_no': 'JC-0042',
  'customer_name': 'Ravi Kumar',
  'customer_phone': '9876543210',
  'item_name': 'Phone',
  'brand': 'Samsung',
  'model': 'A15',
  'registration_no': '',
  'advance_amount': 500,
  'job_card_items': [
    {'name': 'Screen replacement', 'quantity': 1, 'line_total': 1800},
    {'name': 'Tempered glass', 'quantity': 2, 'line_total': 200},
  ],
};

void main() {
  test('ready: item, work done with prices, total, advance and balance', () {
    final m = jobWhatsAppMessage(job('ready'), shopName: 'Sharma Mobiles', shopPhone: '9000000000');
    expect(m, startsWith('Hello Ravi Kumar,'));
    expect(m, contains('Your Phone Samsung A15 is repaired and ready to collect from Sharma Mobiles.'));
    expect(m, contains('Job card: JC-0042'));
    expect(m, contains('Screen replacement — ₹1,800.00'));
    expect(m, contains('Tempered glass × 2 — ₹200.00'));
    expect(m, contains('Total: ₹2,000.00'));
    expect(m, contains('Advance paid: ₹500.00'));
    expect(m, contains('Balance to pay: ₹1,500.00'));
    expect(m, endsWith('— Sharma Mobiles, 9000000000'));
  });

  test('delivered: thanks, no balance line; unrepaired says so', () {
    final d = jobWhatsAppMessage(job('delivered'), shopName: 'Shop');
    expect(d, contains('has been delivered'));
    expect(d, isNot(contains('Balance to pay')));
    final u = jobWhatsAppMessage(job('returned_unrepaired'), shopName: 'Shop');
    expect(u, contains('could not repair it'));
  });

  test('vehicle shows its registration number', () {
    final j = job('ready')
      ..['item_name'] = 'Car'
      ..['brand'] = 'Maruti'
      ..['model'] = 'Swift'
      ..['registration_no'] = 'MH12AB1234';
    expect(jobWhatsAppMessage(j, shopName: 'Garage'), contains('Your Car Maruti Swift (MH12AB1234)'));
  });
}
