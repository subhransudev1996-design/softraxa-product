import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/features/invoices/eway_bill.dart';

/// A made-up tax invoice shaped like invoiceDetailProvider's row.
Map<String, dynamic> invoice({
  String type = 'gst',
  bool inter = false,
  String hsn = '8507',
}) => {
  'invoice_no': 'INV/26-27/0042',
  'invoice_type': type,
  'invoice_date': '2026-10-11T06:30:00Z',
  'customer_name': 'Test Motors',
  'customer_gstin': inter ? '29AAPFU0939F1ZR' : '',
  'place_of_supply': inter ? '29' : '27',
  'round_off': 0.4,
  'total': 59000.4,
  'invoice_items': [
    {
      'product_name': 'Exide XLTZ4A',
      'variant_name': '',
      'hsn_code': hsn,
      'quantity': 20,
      'unit_name': 'Piece',
      'gst_rate': 18,
      'taxable_value': 40000,
      'igst_amount': inter ? 7200 : 0,
      'cgst_amount': inter ? 0 : 3600,
      'sgst_amount': inter ? 0 : 3600,
    },
    {
      'product_name': 'Distilled Water',
      'variant_name': '5 L',
      'hsn_code': '2853',
      'quantity': 2,
      'unit_name': 'Can',
      'gst_rate': 18,
      'taxable_value': 10000,
      'igst_amount': inter ? 1800 : 0,
      'cgst_amount': inter ? 0 : 900,
      'sgst_amount': inter ? 0 : 900,
    },
  ],
};

const shop = EwbParty(
  gstin: '27AAPFU0939F1ZV',
  name: 'Sharma Battery House',
  address: 'Shop 4, Main Road,\nPune 411001',
  place: 'Pune',
  pincode: '411001',
  stateCode: '27',
);

EwbParty buyer({bool inter = false}) => EwbParty(
  gstin: inter ? '29AAPFU0939F1ZR' : '',
  name: 'Test Motors',
  address: 'Near bus stand',
  place: inter ? 'Belagavi' : 'Satara',
  pincode: inter ? '590001' : '415001',
  stateCode: inter ? '29' : '27',
);

void main() {
  test('pincode from a free-text address', () {
    expect(pincodeIn('Shop 4, Main Road, Pune 411001'), '411001');
    expect(pincodeIn('Pune - 411 001, MH'), '411001');
    expect(pincodeIn('Phone 9876543210'), '');
    expect(pincodeIn(''), '');
  });

  test('unit names map to GST unit codes', () {
    expect(gstUqc('Piece'), 'PCS');
    expect(gstUqc('kg'), 'KGS');
    expect(gstUqc('Can'), 'CAN');
    expect(gstUqc('bunch'), 'OTH');
  });

  test('local sale to an unregistered buyer', () {
    final b = buildEwayBill(
      invoice: invoice(),
      from: shop,
      to: buyer(),
      transport: const EwbTransport(distanceKm: 110, vehicleNo: 'mh 12 ab-1234'),
    );
    expect(b['supplyType'], 'O');
    expect(b['subSupplyType'], 1);
    expect(b['docType'], 'INV');
    expect(b['docDate'], '11/10/2026');
    expect(b['toGstin'], 'URP');
    expect(b['fromPincode'], 411001);
    expect(b['toStateCode'], 27);
    expect(b['fromAddr1'], 'Shop 4, Main Road, Pune 411001');
    expect(b['totalValue'], 50000);
    expect((b['cgstValue'], b['sgstValue'], b['igstValue']), (4500, 4500, 0));
    expect(b['OthValue'], 0.4);
    expect(b['totInvValue'], 59000.4);
    expect(b['vehicleNo'], 'MH12AB1234');
    expect(b['transMode'], 1);
    expect(b['transDistance'], 110);
    expect(b['mainHsnCode'], 8507);
    final items = b['itemList'] as List;
    expect(items.length, 2);
    expect(items[0]['qtyUnit'], 'PCS');
    expect((items[0]['cgstRate'], items[0]['sgstRate'], items[0]['igstRate']),
        (9.0, 9.0, 0));
    expect(items[1]['productDesc'], 'Distilled Water 5 L');
  });

  test('inter-state sale to a registered buyer uses IGST', () {
    final b = buildEwayBill(
      invoice: invoice(inter: true),
      from: shop,
      to: buyer(inter: true),
      transport: const EwbTransport(distanceKm: 380),
    );
    expect(b['toGstin'], '29AAPFU0939F1ZR');
    expect((b['cgstValue'], b['sgstValue'], b['igstValue']), (0, 0, 9000));
    final item = (b['itemList'] as List).first;
    expect((item['cgstRate'], item['sgstRate'], item['igstRate']), (0, 0, 18.0));
    expect(b['vehicleNo'], '');
  });

  test('a bill of supply is BIL', () {
    final b = buildEwayBill(
      invoice: invoice(type: 'non_gst'),
      from: shop,
      to: buyer(),
      transport: const EwbTransport(distanceKm: 5),
    );
    expect(b['docType'], 'BIL');
  });

  test('the upload file wraps the bills', () {
    final text = ewayBillJsonText([
      buildEwayBill(
        invoice: invoice(),
        from: shop,
        to: buyer(),
        transport: const EwbTransport(distanceKm: 10),
      ),
    ]);
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json['version'], '1.0.0621');
    expect((json['billLists'] as List).length, 1);
  });

  test('missing details are listed before the file is made', () {
    final problems = ewayBillProblems(
      invoice: invoice(hsn: '85'),
      from: shop,
      to: const EwbParty(
        gstin: '',
        name: 'x',
        address: '',
        place: '',
        pincode: '41',
        stateCode: '27',
      ),
      transport: const EwbTransport(distanceKm: 0),
    );
    expect(problems.length, 4); // pincode, town, distance, HSN
    expect(
      ewayBillProblems(
        invoice: invoice(),
        from: shop,
        to: buyer(),
        transport: const EwbTransport(distanceKm: 10),
      ),
      isEmpty,
    );
  });
}
