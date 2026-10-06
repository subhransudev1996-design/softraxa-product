import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/whatsapp_helper.dart';
import 'package:softraxa_inventory/features/customers/payment_reminder.dart';

void main() {
  test('reminder names the customer, the amount, UPI and the shop', () {
    final m = paymentReminderMessage(
      customerName: 'Ramesh',
      due: 1250,
      shopName: 'Sharma General Store',
      shopPhone: '8260966559',
      upiId: 'sharma@upi',
    );
    expect(m, contains('Namaste Ramesh ji'));
    expect(m, contains('1,250.00'));
    expect(m, contains('UPI: sharma@upi'));
    expect(m, contains('Sharma General Store'));
    expect(m, contains('8260966559'));
  });

  test('no UPI line when the shop has no UPI ID', () {
    final m = paymentReminderMessage(
      customerName: '',
      due: 40,
      shopName: 'Shop',
    );
    expect(m, isNot(contains('UPI')));
    expect(m, startsWith('Namaste 🙏'));
  });

  test('WhatsApp numbers get the country code', () {
    expect(whatsAppNumber('98765 00011'), '919876500011');
    expect(whatsAppNumber(''), '');
  });
}
