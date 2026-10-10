import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';

/// Rounds [amount] to the nearest whole rupee, returning the (possibly
/// negative) adjustment needed to get there — shared by POS bills and
/// purchase totals so both round the same way.
double roundOffFor(double amount) => amount.roundToDouble() - amount;

/// One line in the bill. Prices entered/displayed are GST-INCLUSIVE
/// (standard for Indian retail). Tax is back-calculated per line.
class CartLine {
  CartLine({
    required this.key,
    required this.productId,
    this.variantId,
    required this.name,
    this.variantName = '',
    this.hsnCode = '',
    this.unitName = '',
    required this.price,
    this.qty = 1,
    this.discount = 0,
    this.discountIsPercent = false,
    this.gstRate = 0,
    this.costPrice = 0,
    this.mrp = 0,
    this.serialNo = '',
    this.trackSerial = false,
    this.allowDecimal = false,
    this.availableStock,
    this.wholesalePrice,
    this.wholesaleMinQty,
    this.retailPrice,
    this.pieceId,
    this.keepRemnant,
    this.remnantReason = '',
    this.linkedTo,
    this.customerPrice,
    this.wholesaleCustomer = false,
    this.priceIsDefault = true,
    this.packSize,
    this.baseUnitName = '',
  });

  final String key; // productId:variantId (":pack" for a pack line)
  final String productId;
  final String? variantId;
  final String name;
  final String variantName;
  final String hsnCode;
  final String unitName;
  double price; // per-unit, GST inclusive
  double qty;
  double
  discount; // line discount — a ₹ amount, or a 0-100 percent if discountIsPercent
  bool discountIsPercent;
  final double gstRate;
  final double costPrice;
  final double mrp;
  String serialNo;
  final bool trackSerial;
  final bool allowDecimal;
  double? availableStock;
  final double? wholesalePrice;
  final double? wholesaleMinQty;
  final double? retailPrice;

  /// Which physical piece (wire coil, rod, pipe) this line is cut from.
  /// Sent with the bill: the server cuts it in the same transaction
  /// (migration 0049).
  final String? pieceId;

  /// Leftover override for the cut: null follows the suggestion (D21).
  final bool? keepRemnant;
  final String remnantReason;

  /// A cutting-charge line points at the cut line it belongs to (PD44),
  /// so removing the cut removes its charge.
  final String? linkedTo;

  /// The selected customer's agreed price for this item (migration 0043).
  double? customerPrice;

  /// The selected customer buys at wholesale prices (PD05).
  bool wholesaleCustomer;

  /// False once someone changed the price by hand — then quantity or
  /// customer changes no longer reprice the line.
  bool priceIsDefault;

  /// A line sold by the pack (migration 0061): [qty], [price], [costPrice]
  /// and [mrp] are per pack ([unitName], e.g. Box) and [packSize] base
  /// units ([baseUnitName], e.g. pcs) make one pack. Null for loose lines.
  final double? packSize;
  final String baseUnitName;

  bool get isPack => packSize != null;

  /// Quantity in the base unit stock is kept in.
  double get baseQty => qty * (packSize ?? 1);

  bool get _wholesaleApplies =>
      (wholesalePrice ?? 0) > 0 &&
      (wholesaleCustomer ||
          (wholesaleMinQty != null && qty >= wholesaleMinQty!));

  /// Default price (D15): customer's agreed price → wholesale (customer or
  /// quantity tier) → retail. Null for items without a catalogue price.
  double? get defaultPrice {
    if (customerPrice != null) return customerPrice;
    if (_wholesaleApplies) return wholesalePrice;
    return (retailPrice ?? 0) > 0 ? retailPrice : null;
  }

  /// Which price the line is charged at, as recorded on the bill.
  String get priceSource {
    bool at(double? p) => p != null && (price - p).abs() < 0.005;
    final def = defaultPrice;
    if (def == null) return 'manual';
    if (at(def)) {
      return customerPrice != null
          ? 'customer'
          : _wholesaleApplies
          ? 'wholesale'
          : 'retail';
    }
    if (at(customerPrice)) return 'customer';
    if (at(wholesalePrice)) return 'wholesale';
    if (at(retailPrice)) return 'retail';
    return 'negotiated';
  }

  /// The prices this line may be charged at, for picking one by hand.
  List<(String source, double price)> get priceOptions => [
    if (customerPrice != null) ('customer', customerPrice!),
    if ((wholesalePrice ?? 0) > 0) ('wholesale', wholesalePrice!),
    if ((retailPrice ?? 0) > 0) ('retail', retailPrice!),
  ];

  /// Amount this line is charged below its default price (0 if none).
  double get reductionFromDefault {
    final def = defaultPrice;
    if (def == null) return 0;
    final r = qty * def - gross;
    return r > 0 ? r : 0;
  }

  /// Resolved ₹ discount, whichever unit [discount] was entered in.
  double get discountAmount =>
      discountIsPercent ? (qty * price) * discount / 100 : discount;
  double get gross => (qty * price) - discountAmount;
  double get net => gstRate > 0 ? gross / (1 + gstRate / 100) : gross;
  double get tax => gross - net;

  CartLine copy() => CartLine(
    key: key,
    productId: productId,
    variantId: variantId,
    name: name,
    variantName: variantName,
    hsnCode: hsnCode,
    unitName: unitName,
    price: price,
    qty: qty,
    discount: discount,
    discountIsPercent: discountIsPercent,
    gstRate: gstRate,
    costPrice: costPrice,
    mrp: mrp,
    serialNo: serialNo,
    trackSerial: trackSerial,
    allowDecimal: allowDecimal,
    availableStock: availableStock,
    wholesalePrice: wholesalePrice,
    wholesaleMinQty: wholesaleMinQty,
    retailPrice: retailPrice,
    pieceId: pieceId,
    keepRemnant: keepRemnant,
    remnantReason: remnantReason,
    linkedTo: linkedTo,
    customerPrice: customerPrice,
    wholesaleCustomer: wholesaleCustomer,
    priceIsDefault: priceIsDefault,
    packSize: packSize,
    baseUnitName: baseUnitName,
  );
}

/// The product's pack with its own price (Box of 10 at ₹95), or null when
/// it has none — then a pack is just [size] base units at the unit price.
/// Products without variants only.
({String unit, double size, double price})? packOf(
  Map<String, dynamic> product,
  Map<String, dynamic>? variant,
) {
  final unit = (product['secondary_unit_name'] as String? ?? '').trim();
  final size = toDouble(product['conversion_factor']);
  final price = toDouble(product['pack_price']);
  if (variant != null || unit.isEmpty || size <= 0 || price <= 0) return null;
  return (unit: unit, size: size, price: price);
}

/// A customer's agreed per-unit price as a pack price — only when it beats
/// the pack price, as on the server (migration 0061).
double? packCustomerPrice(double? perUnit, double size, double packPrice) {
  if (perUnit == null) return null;
  final p = perUnit * size;
  return p < packPrice ? p : null;
}

/// Human label for a price source.
String priceSourceLabel(String source) => switch (source) {
  'customer' => 'Customer price',
  'wholesale' => 'Wholesale',
  'retail' => 'Retail',
  'negotiated' => 'Negotiated',
  _ => 'Manual',
};

class CartState {
  const CartState({
    this.lines = const [],
    this.customer,
    this.billDiscount = 0,
    this.billDiscountIsPercent = false,
    this.applyGst = true,
    this.customerPrices = const {},
    this.wholesaleCustomer = false,
  });

  final List<CartLine> lines;
  final Map<String, dynamic>? customer;

  /// The selected customer's agreed prices, keyed "productId:variantId".
  final Map<String, double> customerPrices;
  final bool wholesaleCustomer;

  /// What the bill would come to at default prices, and how far below that
  /// it is — price changes, line and bill discounts together (PD07).
  double get defaultTotal =>
      lines.fold(0.0, (s, l) => s + l.qty * (l.defaultPrice ?? l.price));
  double get priceReduction {
    final r = defaultTotal - grandBeforeRound;
    return r > 0.005 ? r : 0;
  }

  double get priceReductionPct =>
      defaultTotal > 0 ? priceReduction / defaultTotal * 100 : 0;
  final double
  billDiscount; // a ₹ amount, or a 0-100 percent if billDiscountIsPercent
  final bool billDiscountIsPercent;
  final bool applyGst;

  double get itemsGross => lines.fold(0, (s, l) => s + l.gross);
  double get taxTotal => applyGst ? lines.fold(0.0, (s, l) => s + l.tax) : 0;
  double get netTotal =>
      applyGst ? lines.fold(0.0, (s, l) => s + l.net) : itemsGross;

  /// Resolved ₹ bill discount, whichever unit [billDiscount] was entered in.
  double get billDiscountAmount =>
      billDiscountIsPercent ? itemsGross * billDiscount / 100 : billDiscount;
  double get grandBeforeRound => itemsGross - billDiscountAmount;

  /// GST inside the amount actually charged: the bill discount comes off the
  /// tax-inclusive total, so it reduces tax in proportion — the same figure
  /// the saved invoice shows (migration 0040). [taxTotal] stays the pre-bill-
  /// discount line tax that is sent to the server.
  double get billTaxTotal => itemsGross > 0
      ? taxTotal * (grandBeforeRound.clamp(0, itemsGross) / itemsGross)
      : 0;
  double get roundOff => roundOffFor(grandBeforeRound);
  double get total => grandBeforeRound + roundOff;
  int get itemCount => lines.length;
  double get totalQty => lines.fold(0, (s, l) => s + l.qty);

  /// Total cost of goods in the cart (purchase price × qty per line).
  double get totalCost => lines.fold(0.0, (s, l) => s + l.costPrice * l.qty);

  /// Owner-facing estimated profit: what's actually kept after GST (a
  /// pass-through, not revenue) and every discount, minus cost of goods.
  /// `netTotal` already nets out each line's own discount and GST; the bill
  /// discount and round-off come straight out of margin since they aren't
  /// split back across lines, so they're subtracted/added here directly —
  /// algebraically this equals `(total - taxTotal) - totalCost`, i.e. what
  /// was actually collected excluding tax, minus what the goods cost.
  double get estimatedProfit => profitFor(gst: applyGst);

  /// [estimatedProfit] for a bill type: only a GST bill collects GST, so a
  /// Non-GST bill / cash memo keeps the whole amount.
  double profitFor({required bool gst}) =>
      (gst ? lines.fold(0.0, (s, l) => s + l.net) : itemsGross) -
      billDiscountAmount +
      roundOff -
      totalCost;

  CartState copyWith({
    List<CartLine>? lines,
    Object? customer = _sentinel,
    double? billDiscount,
    bool? billDiscountIsPercent,
    bool? applyGst,
    Map<String, double>? customerPrices,
    bool? wholesaleCustomer,
  }) => CartState(
    lines: lines ?? this.lines,
    customer: customer == _sentinel
        ? this.customer
        : customer as Map<String, dynamic>?,
    billDiscount: billDiscount ?? this.billDiscount,
    billDiscountIsPercent: billDiscountIsPercent ?? this.billDiscountIsPercent,
    applyGst: applyGst ?? this.applyGst,
    customerPrices: customerPrices ?? this.customerPrices,
    wholesaleCustomer: wholesaleCustomer ?? this.wholesaleCustomer,
  );

  static const _sentinel = Object();
}

/// Marks the cart as editing an existing invoice rather than building a new
/// one — set right before [CartNotifier.replaceAll] loads that invoice's
/// items, read by the checkout sheet to save via `update_invoice` instead of
/// `create_invoice`. `paidAmount` is carried along so the checkout sheet can
/// show "due after changes" without a second fetch — editing never changes
/// what's already been paid, only the items/total.
class EditingInvoice {
  const EditingInvoice({
    required this.id,
    required this.invoiceNo,
    required this.invoiceType,
    required this.paidAmount,
  });

  final String id;
  final String invoiceNo;
  final String invoiceType;
  final double paidAmount;
}

final editingInvoiceProvider =
    NotifierProvider<EditingInvoiceNotifier, EditingInvoice?>(
      EditingInvoiceNotifier.new,
    );

class EditingInvoiceNotifier extends Notifier<EditingInvoice?> {
  @override
  EditingInvoice? build() => null;
  void set(EditingInvoice? v) => state = v;
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Total quantity already in the cart for this product/variant — sums
  /// across lines, since serial-tracked items get one line per unit rather
  /// than merging into a single line. In base units: a pack line counts its
  /// pieces.
  double qtyInCart(String productId, String? variantId) => state.lines
      .where((l) => l.productId == productId && l.variantId == variantId)
      .fold(0.0, (s, l) => s + l.baseQty);

  /// Add a product (or variant) to the cart; merges quantity if already there.
  /// Serial-tracked items always get their own line. [addQty] supports loose
  /// quantities (e.g. 0.5 kg) for units with allow_decimal. Lines cut from a
  /// specific piece ([pieceId]) or of a cut-length product never merge —
  /// each cut is its own line, so the server cuts each one from the best
  /// piece at checkout (0064).
  ///
  /// [asPack] adds whole packs at the product's pack price (migration
  /// 0061) — [addQty] is then in packs, on a line of its own.
  void addProduct(
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
    String serialNo = '',
    double addQty = 1,
    String? pieceId,
    bool? keepRemnant,
    String remnantReason = '',
    bool asPack = false,
  }) {
    final variantId = variant?['id'] as String?;
    final priceKey = '${product['id']}:${variantId ?? ''}';
    final pack = asPack ? packOf(product, variant) : null;
    final key = pack != null ? '$priceKey:pack' : priceKey;
    final trackSerial = product['track_serial'] == true;
    final cutLength = product['track_pieces'] == true && variantId == null;
    final ownLine = trackSerial || pieceId != null || cutLength;

    if (!ownLine) {
      final idx = state.lines.indexWhere((l) => l.key == key);
      if (idx >= 0) {
        changeQty(state.lines[idx], state.lines[idx].qty + addQty);
        return;
      }
    }

    if (pack != null) {
      final size = pack.size;
      final baseUnit =
          (product['units'] as Map?)?['short_name'] as String? ?? '';
      final line = CartLine(
        qty: addQty,
        key: key,
        productId: product['id'] as String,
        name: product['name'] as String,
        hsnCode: product['hsn_code'] as String? ?? '',
        unitName: pack.unit,
        baseUnitName: baseUnit,
        packSize: size,
        price: pack.price,
        retailPrice: pack.price,
        customerPrice: packCustomerPrice(
          state.customerPrices[priceKey],
          size,
          pack.price,
        ),
        wholesaleCustomer: state.wholesaleCustomer,
        gstRate: toDouble(product['gst_rate']),
        costPrice: toDouble(product['purchase_price']) * size,
        mrp: toDouble(product['mrp']) * size,
        availableStock: toDouble(product['current_stock']) / size,
      );
      line.price = line.defaultPrice ?? pack.price;
      state = state.copyWith(lines: [...state.lines, line]);
      return;
    }

    final retail = toDouble(
      variant?['selling_price'] ?? product['selling_price'],
    );
    final line = CartLine(
      qty: addQty,
      pieceId: pieceId,
      keepRemnant: keepRemnant,
      remnantReason: remnantReason,
      key: ownLine ? '$key:${DateTime.now().microsecondsSinceEpoch}' : key,
      productId: product['id'] as String,
      variantId: variantId,
      name: product['name'] as String,
      variantName: variant?['name'] as String? ?? '',
      hsnCode: product['hsn_code'] as String? ?? '',
      unitName: (product['units'] as Map?)?['short_name'] as String? ?? '',
      price: retail,
      retailPrice: retail,
      customerPrice: state.customerPrices[key],
      wholesaleCustomer: state.wholesaleCustomer,
      gstRate: toDouble(product['gst_rate']),
      costPrice: toDouble(
        variant?['purchase_price'] ?? product['purchase_price'],
      ),
      mrp: toDouble(variant?['mrp'] ?? product['mrp']),
      serialNo: serialNo,
      trackSerial: trackSerial,
      allowDecimal: (product['units'] as Map?)?['allow_decimal'] == true,
      availableStock: toDouble(
        variant?['current_stock'] ?? product['current_stock'],
      ),
      wholesalePrice: (product['wholesale_price'] as num?)?.toDouble(),
      wholesaleMinQty: (product['wholesale_min_qty'] as num?)?.toDouble(),
    );
    line.price = line.defaultPrice ?? retail;
    // Optional cutting charge (PD44): its own line, once per cut, billed
    // under the product's HSN and GST rate (the cut goes with the goods).
    final charge = toDouble(product['cutting_charge']);
    state = state.copyWith(
      lines: [
        ...state.lines,
        line,
        if ((pieceId != null || cutLength) && charge > 0)
          CartLine(
            key: 'cut:${line.key}',
            productId: '',
            name: 'Cutting charge — ${product['name']}',
            hsnCode: line.hsnCode,
            unitName: '',
            price: charge,
            retailPrice: charge,
            gstRate: line.gstRate,
            qty: 1,
            linkedTo: line.key,
          ),
      ],
    );
  }

  /// A line that isn't a stock item — a service or a typed charge from the
  /// calculator. It has no product, so no stock moves (like a cutting
  /// charge).
  void addChargeLine(CartLine line) =>
      state = state.copyWith(lines: [...state.lines, line]);

  void changeQty(CartLine line, double newQty) {
    if (newQty <= 0) {
      remove(line);
      return;
    }
    _update(line, (l) {
      l.qty = newQty;
      // Quantity tiers (wholesale from N units) follow the quantity unless
      // the price was set by hand.
      if (l.priceIsDefault && l.defaultPrice != null) l.price = l.defaultPrice!;
    });
  }

  void changePrice(CartLine line, double newPrice) => _update(line, (l) {
    l.price = newPrice;
    final def = l.defaultPrice;
    l.priceIsDefault = def != null && (newPrice - def).abs() < 0.005;
  });

  /// Applies the selected customer's agreed prices and wholesale status to
  /// every line and to lines added later (D15). Lines whose price was set
  /// by hand keep it.
  void applyCustomerPricing(
    Map<String, double> prices, {
    required bool wholesale,
  }) {
    state = state.copyWith(
      customerPrices: prices,
      wholesaleCustomer: wholesale,
      lines: [
        for (final l in state.lines)
          l.copy()..also((c) {
            final agreed = prices['${c.productId}:${c.variantId ?? ''}'];
            c.customerPrice = c.isPack
                ? packCustomerPrice(agreed, c.packSize!, c.retailPrice ?? 0)
                : agreed;
            c.wholesaleCustomer = wholesale;
            if (c.priceIsDefault && c.defaultPrice != null) {
              c.price = c.defaultPrice!;
            }
          }),
      ],
    );
  }

  void changeDiscount(CartLine line, double discount) =>
      _update(line, (l) => l.discount = discount);

  void changeDiscountMode(CartLine line, bool isPercent) =>
      _update(line, (l) => l.discountIsPercent = isPercent);

  void changeSerial(CartLine line, String serial) =>
      _update(line, (l) => l.serialNo = serial);

  /// Refreshes the stock snapshot a line was added with, e.g. after topping
  /// up stock from a "not enough stock" warning.
  void updateAvailableStock(CartLine line, double stock) =>
      _update(line, (l) => l.availableStock = stock);

  void remove(CartLine line) => state = state.copyWith(
    lines: state.lines
        .where((l) => l.key != line.key && l.linkedTo != line.key)
        .toList(),
  );

  void setCustomer(Map<String, dynamic>? customer) =>
      state = state.copyWith(customer: customer);

  void setBillDiscount(double v) => state = state.copyWith(billDiscount: v);

  void setBillDiscountMode(bool isPercent) =>
      state = state.copyWith(billDiscountIsPercent: isPercent);

  void setApplyGst(bool v) => state = state.copyWith(applyGst: v);

  void clear() => state = const CartState();

  /// Puts a held bill back on the counter (held_bills.dart).
  void restore(CartState cart) => state = cart;

  /// Wholesale-replaces the cart — used only to load an existing invoice's
  /// items into the cart for editing (see [invoiceItemsToCartLines]).
  void replaceAll(CartState newState) => state = newState;

  void _update(CartLine line, void Function(CartLine) fn) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.key == line.key) (l.copy()..also(fn)) else l,
      ],
    );
  }
}

extension _Also on CartLine {
  CartLine also(void Function(CartLine) fn) {
    fn(this);
    return this;
  }
}

/// Converts a quantity entered in a bulk/secondary unit (Bags, Rods) to the
/// base unit stock is tracked in, rounded to the DB's 3 decimal places.
/// 1 secondary = [factor] base units; null/absent factor means no conversion.
double toBaseQty(double enteredQty, double? factor) =>
    ((enteredQty * (factor ?? 1)) * 1000).round() / 1000;

/// Kirana "sell by amount": ₹[amount] worth at [rate] per unit → quantity,
/// rounded to the 3 decimal places the DB stores. The line total then
/// recomputes as qty × rate, so it can drift from the asked amount by a
/// paisa or two — the bill's existing round-off line absorbs that.
double qtyForAmount(double amount, double rate) {
  if (rate <= 0 || amount <= 0) return 0;
  return ((amount / rate) * 1000).round() / 1000;
}

/// Resolves POS split-payment rows (mode, amount) against a bill: which
/// rows count as money actually collected, and what `payment_mode` to send
/// when there's no single obvious one. A 'credit' row is deliberately
/// excluded from `collected`/`realPayments` — it isn't a real payment, it's
/// the same as leaving that portion uncovered (it only ever shows up as
/// `due`, same as create_invoice's own handling of an unpaid remainder).
({
  double collected,
  List<(String mode, double amount)> realPayments,
  String mode,
})
resolveSplitPayments(List<(String mode, double amount)> entries) {
  final real = [
    for (final e in entries)
      if (e.$1 != 'credit' && e.$2 > 0) e,
  ];
  final collected = real.fold<double>(0, (s, e) => s + e.$2);
  final distinctModes = real.map((e) => e.$1).toSet();
  final mode = distinctModes.isEmpty
      ? 'credit'
      : (distinctModes.length > 1 ? 'other' : distinctModes.first);
  return (collected: collected, realPayments: real, mode: mode);
}

/// Reconstructs cart lines from an already-saved invoice's items — the
/// inverse of the per-line math in [buildInvoicePayload] — so an existing
/// invoice can be reopened for editing through the exact same cart/checkout
/// machinery used to create it. `invoice_items.unit_price`/`discount_amount`
/// are stored pre-tax (divided by `1 + gst_rate/100`); [CartLine.price]/
/// [CartLine.discount] are GST-inclusive, so both get multiplied back by
/// that same divisor here. The original entry mode (₹ vs %) for line/bill
/// discounts isn't persisted — only the resolved ₹ amount is — so
/// reconstructed lines always come back in ₹ mode; that's a cosmetic loss,
/// not a numeric one. Expects each item optionally embedded with
/// `products(track_serial, current_stock, units(allow_decimal))` and
/// `product_variants(current_stock)` (current stock is fetched fresh, not
/// the sold-at-the-time snapshot, so the "not enough stock" warning still
/// works correctly if a line's quantity is increased during the edit).
List<CartLine> invoiceItemsToCartLines(List<Map<String, dynamic>> items) {
  return [for (final it in items) _invoiceItemToCartLine(it)];
}

CartLine _invoiceItemToCartLine(Map<String, dynamic> it) {
  final gstRate = toDouble(it['gst_rate']);
  final divisor = 1 + gstRate / 100;
  final product = it['products'] as Map?;
  final variant = it['product_variants'] as Map?;
  final variantId = it['variant_id'] as String?;
  // A line sold by the pack comes back as packs at the pack price (0061).
  final factor = toDouble(it['alt_factor']);
  final size = it['sold_as_pack'] == true && factor > 0 ? factor : null;
  final per = size ?? 1;
  final listPrice = (it['list_price'] as num?)?.toDouble();
  return CartLine(
    // A dedicated key (the invoice_item's own id) rather than the usual
    // productId:variantId — an invoice can legitimately have more than one
    // line for the same product (e.g. serial-tracked units sold one per
    // line), and each must stay independently editable/removable, not
    // merge the way a fresh `addProduct` call would.
    key: 'inv:${it['id']}',
    productId: it['product_id'] as String? ?? '',
    variantId: variantId,
    name: it['product_name'] as String? ?? '',
    variantName: it['variant_name'] as String? ?? '',
    hsnCode: it['hsn_code'] as String? ?? '',
    unitName: size != null
        ? it['alt_unit_name'] as String? ?? ''
        : it['unit_name'] as String? ?? '',
    baseUnitName: size != null ? it['unit_name'] as String? ?? '' : '',
    packSize: size,
    price: toDouble(it['unit_price']) * divisor * per,
    qty: toDouble(it['quantity']) / per,
    discount: toDouble(it['discount_amount']) * divisor,
    gstRate: gstRate,
    costPrice: toDouble(it['cost_price']) * per,
    mrp: toDouble(it['mrp']) * per,
    serialNo: it['serial_no'] as String? ?? '',
    trackSerial: product?['track_serial'] == true,
    allowDecimal:
        size == null && (product?['units'] as Map?)?['allow_decimal'] == true,
    availableStock:
        toDouble((variantId != null ? variant : product)?['current_stock']) /
        per,
    // The default price recorded on the bill (0043), so the editor can show
    // how far below default the bill is; an edit keeps the charged price.
    retailPrice: listPrice == null ? null : listPrice * per,
    priceIsDefault: false,
  );
}

/// Builds the `create_invoice` RPC payload from the cart (PRD 7.7).
Map<String, dynamic> buildInvoicePayload({
  required CartState cart,
  required String invoiceType, // gst | non_gst | cash_memo | estimate
  required double paidAmount,
  required String paymentMode,
  List<Map<String, dynamic>>? payments,
  String notes = '',
  String? localId,
  bool offlineCreated = false,
  DateTime? invoiceDate,
}) {
  final gst = invoiceType == 'gst';
  double r2(double v) => (v * 100).roundToDouble() / 100;

  final items = cart.lines.map((l) {
    final rate = gst ? l.gstRate : 0.0;
    final divisor = 1 + rate / 100;
    // The server keeps quantities in the base unit: a pack line goes as
    // its pieces at the pack price per piece, flagged "pack" (0061).
    final per = l.packSize ?? 1;
    return {
      // A cutting charge has no product (no stock moves).
      'product_id': l.productId.isEmpty ? null : l.productId,
      if (l.pieceId != null) 'piece_id': l.pieceId,
      if (l.keepRemnant != null) 'keep_remnant': l.keepRemnant,
      if (l.remnantReason.isNotEmpty) 'remnant_reason': l.remnantReason,
      'variant_id': l.variantId,
      'product_name': l.name,
      'variant_name': l.variantName,
      'hsn_code': l.hsnCode,
      'serial_no': l.serialNo,
      'quantity': l.isPack ? toBaseQty(l.qty, per) : l.qty,
      'unit_name': l.isPack ? l.baseUnitName : l.unitName,
      // A pack price spread over its pieces needn't divide evenly (₹190 a
      // tray of 30): 4 decimals keep the line at the pack price (0062).
      'unit_price': l.isPack
          ? (l.price / per / divisor * 10000).roundToDouble() / 10000
          : r2(l.price / divisor),
      'mrp': l.mrp / per,
      'cost_price': l.costPrice / per,
      if (l.isPack) 'pack': true,
      'discount_amount': r2(l.discountAmount / divisor),
      'gst_rate': rate,
      'tax_amount': r2(l.gross - l.gross / divisor),
      'line_total': r2(l.gross),
    };
  }).toList();

  // Bill discount is applied post-tax (on the gross), so
  // server total = sum(net) - discount + sum(tax) + round == cart.total.
  return {
    'invoice_type': invoiceType,
    'customer_id': cart.customer?['id'],
    'customer_name': cart.customer?['name'] ?? '',
    'customer_phone': cart.customer?['phone'] ?? '',
    'discount_amount': r2(cart.billDiscountAmount),
    'round_off': r2(cart.roundOff),
    'paid_amount': r2(paidAmount),
    'payment_mode': paymentMode,
    if (payments != null && payments.isNotEmpty) 'payments': payments,
    'notes': notes,
    'items': items,
    if (localId != null) 'local_id': localId,
    'offline_created': offlineCreated,
    if (invoiceDate != null)
      'invoice_date': invoiceDate.toUtc().toIso8601String(),
  };
}
