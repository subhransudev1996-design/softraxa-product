import '../../core/formatters.dart';

/// An offer applied to the bill (migration 0084): a scratch-card prize, a
/// coupon code or a voucher — a ₹ amount or a % off the whole bill.
class AppliedOffer {
  const AppliedOffer({
    required this.offerId,
    required this.name,
    this.code = '',
    this.kind = 'amount',
    this.amount = 0,
    this.percent = 0,
    this.maxDiscount,
    this.minBill = 0,
    this.needsCustomer = false,
  });

  /// [json] from find_offer_code / counter_offers; [amount] is the ₹ value
  /// chosen (a scratch card's prize) for 'amount' offers.
  factory AppliedOffer.fromJson(
    Map<String, dynamic> json, {
    double? amount,
    String code = '',
  }) => AppliedOffer(
    offerId: json['offer_id'] as String,
    name: json['name'] as String? ?? '',
    code: code,
    kind: json['kind'] as String? ?? 'amount',
    amount:
        amount ??
        (json['code_amount'] as num?)?.toDouble() ??
        _single(json['amounts']),
    percent: toDouble(json['percent']),
    maxDiscount: (json['max_discount'] as num?)?.toDouble(),
    minBill: toDouble(json['min_bill']),
    needsCustomer: json['needs_customer'] == true,
  );

  static double _single(Object? amounts) {
    final list = (amounts as List? ?? const []);
    return list.length == 1 ? toDouble(list.single) : 0;
  }

  final String offerId;
  final String name;

  /// The code typed or scanned ('' for a counter offer).
  final String code;

  /// 'amount' (₹ off) or 'percent'.
  final String kind;
  final double amount;
  final double percent;
  final double? maxDiscount;
  final double minBill;
  final bool needsCustomer;

  /// What it takes off a bill of [gross] (after every other discount):
  /// never more than the bill, a % at most [maxDiscount], nothing under
  /// [minBill].
  double discountOn(double gross) {
    if (gross <= 0 || gross + 0.005 < minBill) return 0;
    var d = kind == 'percent'
        ? ((gross * percent / 100) * 100).roundToDouble() / 100
        : amount;
    if (kind == 'percent' && maxDiscount != null && d > maxDiscount!) {
      d = maxDiscount!;
    }
    return d > gross ? gross : d;
  }

  /// "Scratch & Win ₹50", "Diwali 10%".
  String get label =>
      kind == 'percent' ? '$name ${qty(percent)}%' : '$name ${money(amount)}';
}

/// The offer on a saved bill (or a stored sale payload), as what it gave —
/// so an edit keeps it as an offer, not as a typed discount. Null when
/// the bill has none.
AppliedOffer? offerOnSavedBill(Map<String, dynamic> bill) {
  final id = bill['offer_id'] as String?;
  if (id == null || id.isEmpty) return null;
  return AppliedOffer(
    offerId: id,
    name: bill['offer_name'] as String? ?? 'Offer',
    code: bill['offer_code'] as String? ?? '',
    amount: toDouble(bill['offer_amount']),
  );
}
