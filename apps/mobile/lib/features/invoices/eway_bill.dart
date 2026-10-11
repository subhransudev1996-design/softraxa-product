import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/file_export.dart';
import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

// E-way bill file for the portal's bulk upload (ewaybillgst.gov.in →
// e-Waybill → Generate Bulk). The format is the NIC bulk-generation JSON
// ("version" + "billLists"), the same one ERPNext India Compliance writes:
// outward supply (O / 1), tax invoice INV or bill of supply BIL, regular
// transaction, by road. Part A comes from the bill; the vehicle (Part B)
// can be given here or added on the portal later.

/// E-way bills are needed for goods worth more than this in one movement.
const ewayBillLimit = 50000.0;

/// Most items one e-way bill takes.
const ewayItemLimit = 250;

/// A party's address as the e-way bill wants it.
class EwbParty {
  const EwbParty({
    required this.gstin,
    required this.name,
    required this.address,
    required this.place,
    required this.pincode,
    required this.stateCode,
  });

  final String gstin; // 'URP' for an unregistered buyer
  final String name;
  final String address;
  final String place;
  final String pincode;
  final String stateCode;
}

/// How the goods travel. Only the distance is needed for Part A.
class EwbTransport {
  const EwbTransport({
    required this.distanceKm,
    this.vehicleNo = '',
    this.transporterId = '',
    this.transporterName = '',
  });

  final int distanceKm;
  final String vehicleNo;
  final String transporterId;
  final String transporterName;
}

/// The first 6-digit Indian pincode in a free-text address.
String pincodeIn(String address) =>
    RegExp(r'(?<!\d)[1-9]\d{2}\s?\d{3}(?!\d)')
        .firstMatch(address)
        ?.group(0)
        ?.replaceAll(' ', '') ??
    '';

/// GST unit code (UQC) for a unit name — the app's mirror of the
/// database's gst_uqc() (migration 0040).
String gstUqc(String? unit) {
  const map = {
    'pcs': 'PCS', 'pc': 'PCS', 'piece': 'PCS', 'pieces': 'PCS',
    'nos': 'NOS', 'no': 'NOS', 'number': 'NOS',
    'kg': 'KGS', 'kgs': 'KGS', 'kilogram': 'KGS',
    'g': 'GMS', 'gm': 'GMS', 'gram': 'GMS', 'grams': 'GMS',
    'm': 'MTR', 'mtr': 'MTR', 'metre': 'MTR', 'meter': 'MTR',
    'cm': 'CMS',
    'l': 'LTR', 'ltr': 'LTR', 'litre': 'LTR', 'liter': 'LTR',
    'ml': 'MLT',
    'box': 'BOX', 'dz': 'DOZ', 'doz': 'DOZ', 'dozen': 'DOZ',
    'set': 'SET', 'pair': 'PRS', 'prs': 'PRS',
    'roll': 'ROL', 'bag': 'BAG', 'bundle': 'BDL',
    'pack': 'PAC', 'pkt': 'PAC', 'packet': 'PAC',
    'bottle': 'BTL', 'can': 'CAN', 'carton': 'CTN', 'tube': 'TUB',
    'sqft': 'SQF', 'sq ft': 'SQF', 'sqm': 'SQM', 'sq m': 'SQM',
    'ton': 'TON', 'tonne': 'TON', 'quintal': 'QTL',
  };
  return map[(unit ?? '').trim().toLowerCase()] ?? 'OTH';
}

/// Letters, digits and simple punctuation only, cut to [max] — the portal
/// rejects other characters in names and addresses.
String _clean(String s, int max) {
  final v = s
      .replaceAll(RegExp(r'[\r\n\t]+'), ', ')
      .replaceAll(RegExp(r'''[^A-Za-z0-9 ,.\-/&()#:']'''), '')
      .replaceAll(RegExp(r'\s*,[\s,]*'), ', ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '');
  return v.length <= max ? v : v.substring(0, max).trim();
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// What is missing before the file can be made, as messages; empty = ready.
List<String> ewayBillProblems({
  required Map<String, dynamic> invoice,
  required EwbParty from,
  required EwbParty to,
  required EwbTransport transport,
}) {
  final items = List<Map<String, dynamic>>.from(
    invoice['invoice_items'] as List? ?? const [],
  );
  return [
    if (!isValidGstin(from.gstin))
      t('Add your shop\'s GSTIN in business settings first.'),
    if (from.pincode.length != 6) t('Enter your shop\'s 6-digit pincode.'),
    if (from.place.trim().isEmpty) t('Enter your shop\'s town or city.'),
    if (to.pincode.length != 6) t('Enter the buyer\'s 6-digit pincode.'),
    if (to.place.trim().isEmpty) t('Enter the buyer\'s town or city.'),
    if (to.stateCode.isEmpty) t('Set the place of supply on the bill.'),
    if (transport.distanceKm < 1 || transport.distanceKm > 4000)
      t('Enter the distance in km (1 to 4000).'),
    if (items.any((i) => (i['hsn_code'] as String? ?? '').trim().length < 4))
      t('Every item needs an HSN code of at least 4 digits.'),
    if (items.length > ewayItemLimit)
      t('An e-way bill takes at most {v1} items.', {'v1': ewayItemLimit}),
  ];
}

/// One e-way bill in the portal's bulk-upload format.
Map<String, dynamic> buildEwayBill({
  required Map<String, dynamic> invoice,
  required EwbParty from,
  required EwbParty to,
  required EwbTransport transport,
}) {
  final items = List<Map<String, dynamic>>.from(
    invoice['invoice_items'] as List? ?? const [],
  );
  final taxInvoice = invoice['invoice_type'] == 'gst';
  double sum(String key) =>
      _r2(items.fold(0.0, (s, i) => s + toDouble(i[key])));
  final taxable = sum('taxable_value');
  final igst = sum('igst_amount');
  final cgst = sum('cgst_amount');
  final sgst = sum('sgst_amount');
  // IGST or CGST + SGST as the bill charged it; a bill with no tax goes
  // by the states.
  final inter = igst > 0 || (cgst + sgst == 0 && from.stateCode != to.stateCode);
  // Round-off on top of the goods and tax (never negative on the portal).
  final other = _r2(toDouble(invoice['round_off'])).clamp(0.0, 10.0);
  // The HSN carrying the most value is the bill's main HSN.
  final byHsn = <String, double>{};
  for (final i in items) {
    final h = (i['hsn_code'] as String? ?? '').trim();
    byHsn[h] = (byHsn[h] ?? 0) + toDouble(i['taxable_value']);
  }
  final mainHsn = byHsn.entries.isEmpty
      ? ''
      : (byHsn.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
  final date = DateTime.parse(invoice['invoice_date'] as String).toLocal();
  final vehicle = transport.vehicleNo.toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]'),
    '',
  );

  return {
    'userGstin': from.gstin,
    'supplyType': 'O',
    'subSupplyType': 1,
    'subSupplyDesc': '',
    'docType': taxInvoice ? 'INV' : 'BIL',
    'docNo': _clean(invoice['invoice_no'] as String? ?? '', 16),
    'docDate': _ddmmyyyy(date),
    'transType': 1,
    'fromGstin': from.gstin,
    'fromTrdName': _clean(from.name, 100),
    'fromAddr1': _clean(from.address, 120),
    'fromAddr2': '',
    'fromPlace': _clean(from.place, 50),
    'fromPincode': int.parse(from.pincode),
    'fromStateCode': int.parse(from.stateCode),
    'actualFromStateCode': int.parse(from.stateCode),
    'toGstin': isValidGstin(to.gstin) ? to.gstin : 'URP',
    'toTrdName': _clean(to.name, 100),
    'toAddr1': _clean(to.address, 120),
    'toAddr2': '',
    'toPlace': _clean(to.place, 50),
    'toPincode': int.parse(to.pincode),
    'toStateCode': int.parse(to.stateCode),
    'actualToStateCode': int.parse(to.stateCode),
    'totalValue': taxable,
    'cgstValue': cgst,
    'sgstValue': sgst,
    'igstValue': igst,
    'cessValue': 0,
    'TotNonAdvolVal': 0,
    'OthValue': other,
    'totInvValue': _r2(taxable + igst + cgst + sgst + other),
    'transMode': 1,
    'transDistance': transport.distanceKm,
    'transporterName': _clean(transport.transporterName, 100),
    'transporterId': transport.transporterId.trim().toUpperCase(),
    'transDocNo': '',
    'transDocDate': '',
    'vehicleNo': vehicle,
    'vehicleType': 'R',
    'mainHsnCode': int.tryParse(mainHsn) ?? 0,
    'itemList': [
      for (var n = 0; n < items.length; n++)
        () {
          final i = items[n];
          final rate = toDouble(i['gst_rate']);
          final name = [
            i['product_name'] as String? ?? '',
            i['variant_name'] as String? ?? '',
          ].where((s) => s.trim().isNotEmpty).join(' ');
          return {
            'itemNo': n + 1,
            'productName': _clean(name, 100),
            'productDesc': _clean(name, 100),
            'hsnCode': int.tryParse((i['hsn_code'] as String? ?? '').trim()) ?? 0,
            'quantity': toDouble(i['quantity']),
            'qtyUnit': gstUqc(i['unit_name'] as String?),
            'taxableAmount': _r2(toDouble(i['taxable_value'])),
            'cgstRate': inter ? 0 : rate / 2,
            'sgstRate': inter ? 0 : rate / 2,
            'igstRate': inter ? rate : 0,
            'cessRate': 0,
            'cessNonAdvol': 0,
          };
        }(),
    ],
  };
}

/// The upload file: one or more e-way bills.
String ewayBillJsonText(List<Map<String, dynamic>> bills) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'version': '1.0.0621', 'billLists': bills});

// ---------------------------------------------------------------------------
// Sheet
// ---------------------------------------------------------------------------

const _shopPinKey = 'ewb_shop_pincode';
const _shopPlaceKey = 'ewb_shop_place';

/// Asks for what the bill doesn't hold (pincodes, town, distance, vehicle)
/// and saves / shares the e-way bill file for this invoice.
Future<void> showEwayBillSheet(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> invoice,
) async {
  final business = ref.read(appContextProvider).value?.business ?? const {};
  Map<String, dynamic>? customer;
  final customerId = invoice['customer_id'] as String?;
  String? shopPin, shopPlace;
  try {
    if (customerId != null) {
      customer = await ref
          .read(supabaseProvider)
          .from('customers')
          .select('name, address')
          .eq('id', customerId)
          .maybeSingle();
    }
    final prefs = await SharedPreferences.getInstance();
    shopPin = prefs.getString(_shopPinKey);
    shopPlace = prefs.getString(_shopPlaceKey);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EwayBillForm(
      invoice: invoice,
      business: business,
      customerAddress: customer?['address'] as String? ?? '',
      shopPin: shopPin,
      shopPlace: shopPlace,
    ),
  );
}

class _EwayBillForm extends StatefulWidget {
  const _EwayBillForm({
    required this.invoice,
    required this.business,
    required this.customerAddress,
    this.shopPin,
    this.shopPlace,
  });

  final Map<String, dynamic> invoice;
  final Map<String, dynamic> business;
  final String customerAddress;
  final String? shopPin;
  final String? shopPlace;

  @override
  State<_EwayBillForm> createState() => _EwayBillFormState();
}

class _EwayBillFormState extends State<_EwayBillForm> {
  late final _shopPin = TextEditingController(
    text:
        widget.shopPin ??
        pincodeIn(widget.business['address'] as String? ?? ''),
  );
  late final _shopPlace = TextEditingController(text: widget.shopPlace ?? '');
  late final _buyerAddress = TextEditingController(
    text: widget.customerAddress,
  );
  late final _buyerPin = TextEditingController(
    text: pincodeIn(widget.customerAddress),
  );
  final _buyerPlace = TextEditingController();
  final _distance = TextEditingController();
  final _vehicle = TextEditingController();
  final _transporterId = TextEditingController();
  final _transporterName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _shopPin,
      _shopPlace,
      _buyerAddress,
      _buyerPin,
      _buyerPlace,
      _distance,
      _vehicle,
      _transporterId,
      _transporterName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  EwbParty get _from => EwbParty(
    gstin: (widget.business['gst_number'] as String? ?? '').trim().toUpperCase(),
    name: widget.business['name'] as String? ?? '',
    address: widget.business['address'] as String? ?? '',
    place: _shopPlace.text.trim(),
    pincode: _shopPin.text.trim(),
    stateCode: widget.business['state_code'] as String? ?? '',
  );

  EwbParty get _to => EwbParty(
    gstin: (widget.invoice['customer_gstin'] as String? ?? '')
        .trim()
        .toUpperCase(),
    name: (widget.invoice['customer_name'] as String? ?? '').trim().isEmpty
        ? 'Customer'
        : widget.invoice['customer_name'] as String,
    address: _buyerAddress.text.trim(),
    place: _buyerPlace.text.trim(),
    pincode: _buyerPin.text.trim(),
    // A bill without a place of supply (made before the shop had a state)
    // was a sale within the shop's own state.
    stateCode:
        (widget.invoice['place_of_supply'] as String? ?? '').trim().isNotEmpty
        ? widget.invoice['place_of_supply'] as String
        : widget.business['state_code'] as String? ?? '',
  );

  EwbTransport get _transport => EwbTransport(
    distanceKm: int.tryParse(_distance.text.trim()) ?? 0,
    vehicleNo: _vehicle.text,
    transporterId: _transporterId.text,
    transporterName: _transporterName.text,
  );

  Future<void> _make() async {
    final problems = ewayBillProblems(
      invoice: widget.invoice,
      from: _from,
      to: _to,
      transport: _transport,
    );
    if (problems.isNotEmpty) {
      showError(context, problems.join('\n'));
      return;
    }
    setState(() => _busy = true);
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_shopPinKey, _shopPin.text.trim());
        await prefs.setString(_shopPlaceKey, _shopPlace.text.trim());
      } catch (_) {}
      final bill = buildEwayBill(
        invoice: widget.invoice,
        from: _from,
        to: _to,
        transport: _transport,
      );
      final no = widget.invoice['invoice_no'] as String? ?? 'bill';
      final message = await saveOrShareFile(
        Uint8List.fromList(utf8.encode(ewayBillJsonText([bill]))),
        'EWB_$no.json',
        subject: t('E-way bill file for {v1}', {'v1': no}),
      );
      if (!mounted) return;
      if (message != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    String? hint,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      minLines: 1,
      decoration: InputDecoration(labelText: label, helperText: hint),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final value = toDouble(widget.invoice['total']);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('E-way bill file'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'Upload it on ewaybillgst.gov.in: e-Waybill → Generate Bulk. The portal gives the e-way bill number.',
              ),
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
            if (value <= ewayBillLimit) ...[
              const SizedBox(height: 8),
              Text(
                t(
                  'This bill is {v1} — an e-way bill is needed only above ₹50,000, unless your state asks for one.',
                  {'v1': money(value)},
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SectionLabel(t('From — your shop')),
            _field(
              _shopPin,
              t('Shop pincode'),
              keyboard: TextInputType.number,
            ),
            _field(_shopPlace, t('Shop town / city')),
            SectionLabel(t('To — the buyer')),
            _field(_buyerAddress, t('Delivery address'), maxLines: 3),
            _field(
              _buyerPin,
              t('Buyer pincode'),
              keyboard: TextInputType.number,
            ),
            _field(_buyerPlace, t('Buyer town / city')),
            SectionLabel(t('Transport')),
            _field(
              _distance,
              t('Distance in km *'),
              keyboard: TextInputType.number,
            ),
            _field(
              _vehicle,
              t('Vehicle number (optional)'),
              hint: t('Leave empty to add it on the portal later (Part B).'),
            ),
            _field(_transporterId, t('Transporter ID (optional)')),
            _field(_transporterName, t('Transporter name (optional)')),
            const SizedBox(height: 6),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.local_shipping_outlined),
              label: Text(t('Make e-way bill file')),
              onPressed: _busy ? null : _make,
            ),
          ],
        ),
      ),
    );
  }
}
