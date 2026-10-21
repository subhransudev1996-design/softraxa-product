import '../../core/formatters.dart';

/// A discount (privilege / membership) card found at billing (migration
/// 0083): its type's % comes off the lines it covers.
class DiscountCard {
  const DiscountCard({
    required this.id,
    required this.cardNo,
    required this.typeName,
    required this.pct,
    this.appliesTo = 'all',
    this.categoryIds = const {},
    this.holderName = '',
    this.customerName = '',
  });

  factory DiscountCard.fromJson(Map<String, dynamic> j) => DiscountCard(
    id: j['id'] as String,
    cardNo: j['card_no'] as String? ?? '',
    typeName: j['type_name'] as String? ?? '',
    pct: toDouble(j['discount_pct']),
    appliesTo: j['applies_to'] as String? ?? 'all',
    categoryIds: {
      for (final c in (j['category_ids'] as List? ?? const [])) c as String,
    },
    holderName: j['holder_name'] as String? ?? '',
    customerName: j['customer_name'] as String? ?? '',
  );

  final String id;
  final String cardNo;
  final String typeName;
  final double pct;

  /// 'all' items, 'only' the [categoryIds], or all 'except' them.
  final String appliesTo;
  final Set<String> categoryIds;
  final String holderName;
  final String customerName;

  /// Who the card was given to, if recorded.
  String get holder => holderName.isNotEmpty ? holderName : customerName;

  /// The card's % for a bill line — 0 when it doesn't cover it. Charges
  /// and services (no product) are never covered, as on the server.
  double pctFor({required String productId, String? categoryId}) {
    if (productId.isEmpty) return 0;
    return switch (appliesTo) {
      'only' => categoryIds.contains(categoryId) ? pct : 0,
      'except' => categoryIds.contains(categoryId) ? 0 : pct,
      _ => pct,
    };
  }

  /// "Gold 10%" — how the card shows on the counter and on bills.
  String get label => '$typeName ${qty(pct)}%';
}
