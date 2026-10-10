import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/whatsapp_helper.dart';
import '../../core/widgets.dart';
import '../jobcards/job_card_detail_screen.dart' show PartPicker;
import '../jobcards/job_estimates.dart' show EstimateDraftLine;
import '../pos/cart.dart';
import '../services/service_providers.dart';
import 'calc_engine.dart';

/// A calculator that knows the shop's prices: tap a product or a service
/// and its price goes in. The answer can become a bill, a job card
/// estimate or a WhatsApp price quote.
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  var _calc = const CalcState();
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _set(CalcState s) => setState(() => _calc = s);

  /// Typing on a PC keyboard: digits, + - * / %, Enter, Backspace, Esc.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace) {
      _set(_calc.backspace());
    } else if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.delete) {
      _set(const CalcState());
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _set(_calc.equals());
    } else {
      final c = e.character;
      if (c == null) return KeyEventResult.ignored;
      if (RegExp(r'^[0-9.]$').hasMatch(c)) {
        _set(_calc.digit(c));
      } else if (c == '+') {
        _set(_calc.op(calcPlus));
      } else if (c == '-') {
        _set(_calc.op(calcMinus));
      } else if (c == '*' || c == 'x' || c == 'X') {
        _set(_calc.op(calcTimes));
      } else if (c == '/') {
        _set(_calc.op(calcDivide));
      } else if (c == '%') {
        _set(_calc.percent());
      } else if (c == '=') {
        _set(_calc.equals());
      } else {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.handled;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- products and services ----------------

  Future<void> _pickProduct() async {
    final search = TextEditingController();
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: PartPicker(searchController: search),
      ),
    );
    search.dispose();
    if (picked == null || !mounted) return;
    final product = picked['product'] as Map<String, dynamic>;
    final variant = picked['variant'] as Map<String, dynamic>?;
    final name =
        '${product['name']}${variant != null ? ' (${variant['name']})' : ''}';
    final single = toDouble(
      variant?['selling_price'] ?? product['selling_price'],
    );
    final gst = toDouble(product['gst_rate']);
    final pack = packOf(product, variant);
    var asPack = false;
    if (pack != null) {
      final unit = (product['units'] as Map?)?['short_name'] as String? ?? '';
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(name),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                '1 ${unit.isEmpty ? t('piece') : unit} — ${money(single)}',
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                '1 ${pack.unit} (${qty(pack.size)}) — ${money(pack.price)}',
              ),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      asPack = choice;
    }
    _set(
      _calc.addItem(
        CalcItem(
          kind: 'product',
          name: name,
          price: asPack ? pack!.price : single,
          gstRate: gst,
          product: product,
          variant: variant,
          packSize: asPack ? pack!.size : null,
          unit: asPack ? pack!.unit : '',
        ),
      ),
    );
    _focus.requestFocus();
  }

  Future<void> _pickService() async {
    List<Map<String, dynamic>> services;
    try {
      services = await ref.read(servicesProvider.future);
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    if (services.isEmpty) {
      _snack(t('No services yet. Add them in Service catalog.'));
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ServicePicker(services: services),
    );
    if (picked == null || !mounted) return;
    final gst = toDouble(picked['gst_rate']);
    final withGst = toDouble(picked['price']) * (1 + gst / 100);
    _set(
      _calc.addItem(
        CalcItem(
          kind: 'service',
          name: picked['name'] as String? ?? '',
          price: (withGst * 100).roundToDouble() / 100,
          gstRate: gst,
          service: picked,
        ),
      ),
    );
    _focus.requestFocus();
  }

  // ---------------- what the answer becomes ----------------

  Future<void> _toBill(CalcResult r) async {
    final app = ref.read(appContextProvider).value;
    if (!(app?.canCreateInvoice ?? true)) {
      _snack(t('You don\'t have permission to make bills.'));
      return;
    }
    final editing = ref.read(editingInvoiceProvider);
    if (editing != null) {
      _snack(t('Finish modifying bill {v1} first.', {'v1': editing.invoiceNo}));
      return;
    }
    final notifier = ref.read(cartProvider.notifier);
    final onCounter = ref.read(cartProvider).lines.length;
    if (onCounter > 0) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('New Bill already has items')),
          content: Text(
            t(
              '{v1} items are on the bill now. Add these to them, or start a fresh bill?',
              {'v1': onCounter},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'fresh'),
              child: Text(t('Start fresh')),
            ),
            FilledButton(
              style: dialogActionStyle,
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: Text(t('Add to them')),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'fresh') notifier.clear();
    }

    var discount = 0.0;
    var n = 0;
    String key(String kind) =>
        'calc:$kind:${DateTime.now().microsecondsSinceEpoch}:${n++}';
    for (final l in r.lines) {
      final i = l.item;
      if (i == null) {
        if (l.amount < 0) {
          discount += -l.amount;
        } else if (l.amount > 0) {
          notifier.addChargeLine(
            CartLine(
              key: key('other'),
              productId: '',
              name: 'Other charges',
              price: l.amount,
              retailPrice: l.amount,
            ),
          );
        }
      } else if (i.kind == 'product') {
        notifier.addProduct(
          i.product!,
          variant: i.variant,
          addQty: l.qty,
          asPack: i.isPack,
        );
      } else {
        notifier.addChargeLine(
          CartLine(
            key: key('service'),
            productId: '',
            name: i.name,
            hsnCode: i.service?['sac_code'] as String? ?? '',
            price: i.price,
            retailPrice: i.price,
            gstRate: i.gstRate,
            qty: l.qty,
          ),
        );
      }
    }
    if (discount > 0) {
      final already = ref.read(cartProvider).billDiscountAmount;
      notifier
        ..setBillDiscountMode(false)
        ..setBillDiscount(((already + discount) * 100).roundToDouble() / 100);
    }
    if (mounted) context.go('/pos');
  }

  void _toJobCard(CalcResult r) {
    if (r.lines.any((l) => l.item == null && l.amount < 0)) {
      _snack(
        t(
          'A job card estimate can\'t have a minus amount. Remove it, or give the discount when billing.',
        ),
      );
      return;
    }
    double r2(double v) => (v * 100).roundToDouble() / 100;
    final lines = <EstimateDraftLine>[];
    for (final l in r.lines) {
      final i = l.item;
      if (i == null) {
        if (l.amount == 0) continue;
        lines.add(
          EstimateDraftLine(
            itemType: 'labor',
            name: 'Other charges',
            price: l.amount,
          ),
        );
      } else if (i.kind == 'product') {
        // Estimates are priced before GST, by the piece; the calculator
        // works in shop prices with GST, maybe by the box.
        final per = i.packSize ?? 1;
        lines.add(
          EstimateDraftLine(
            itemType: 'part',
            name: i.name,
            productId: i.product!['id'] as String,
            variantId: i.variant?['id'] as String?,
            hsn: i.product!['hsn_code'] as String? ?? '',
            quantity: double.parse((l.qty * per).toStringAsFixed(3)),
            price: r2(i.price / per / (1 + i.gstRate / 100)),
            gst: i.gstRate,
          ),
        );
      } else {
        lines.add(
          EstimateDraftLine(
            itemType: 'labor',
            name: i.name,
            serviceId: i.service?['id'] as String?,
            hsn: i.service?['sac_code'] as String? ?? '',
            quantity: l.qty,
            price: toDouble(i.service?['price']),
            gst: i.gstRate,
          ),
        );
      }
    }
    context.push('/job-cards/new', extra: lines);
  }

  Future<void> _sendQuote(CalcResult r) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Send price quote')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('Customer name (optional)'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t('WhatsApp number (optional)'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            style: dialogActionStyle,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Send')),
          ),
        ],
      ),
    );
    final customerName = name.text;
    final customerPhone = phone.text;
    name.dispose();
    phone.dispose();
    if (ok != true || !mounted) return;
    final app = ref.read(appContextProvider).value;
    final shop = app?.businessName ?? '';
    await sendWhatsAppText(
      customerPhone,
      calcQuoteMessage(
        r,
        shopName: shop,
        shopPhone: app?.business?['phone'] as String? ?? '',
        customerName: customerName,
      ),
      subject: 'Price quote — $shop',
    );
  }

  // ---------------- layout ----------------

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appContextProvider).value;
    final doesJobs =
        (app?.category.jobCards ?? true) &&
        (app?.featureOn('service_module') ?? true) &&
        (app?.canManageServices ?? false);
    final r = _calc.evaluate();
    final usable =
        r.total != null &&
        r.total! > 0 &&
        r.problem == null &&
        r.lines.isNotEmpty;

    final display = _Display(calc: _calc, result: r);
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: usable && r.hasItems ? () => _toBill(r) : null,
          icon: const Icon(Icons.receipt_long, size: 18),
          label: Text(t('Make bill')),
        ),
        if (doesJobs)
          OutlinedButton.icon(
            onPressed: usable && r.hasItems ? () => _toJobCard(r) : null,
            icon: const Icon(Icons.assignment_outlined, size: 18),
            label: Text(t('Job card estimate')),
          ),
        OutlinedButton.icon(
          onPressed: usable ? () => _sendQuote(r) : null,
          icon: const Icon(Icons.chat_outlined, size: 18),
          label: Text(t('WhatsApp quote')),
        ),
      ],
    );
    final itemButtons = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickProduct,
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text(t('Product')),
          ),
        ),
        if (app?.category.jobCards ?? true) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickService,
              icon: const Icon(Icons.build_outlined, size: 18),
              label: Text(t('Service')),
            ),
          ),
        ],
      ],
    );
    final keypad = _Keypad(
      onDigit: (d) => _set(_calc.digit(d)),
      onOp: (o) => _set(_calc.op(o)),
      onPercent: () => _set(_calc.percent()),
      onBack: () => _set(_calc.backspace()),
      onClear: () => _set(const CalcState()),
      onEquals: () => _set(_calc.equals()),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t('Calculator')),
        actions: [
          IconButton(
            tooltip: t('Clear'),
            onPressed: _calc.isEmpty ? null : () => _set(const CalcState()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth >= 760) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: display),
                            const SizedBox(height: 12),
                            actions,
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 380,
                        child: Column(
                          children: [
                            itemButtons,
                            const SizedBox(height: 12),
                            Expanded(child: keypad),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: display),
                    const SizedBox(height: 8),
                    actions,
                    const SizedBox(height: 8),
                    itemButtons,
                    const SizedBox(height: 8),
                    SizedBox(height: box.maxHeight * 0.42, child: keypad),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Why a sum can't become a bill (calc_engine's problems), for the screen.
String _problemText(String p) => switch (p) {
  'Two items are multiplied together' => t(
    'Two items are multiplied. Use + between items.',
  ),
  'An item is divided' => t('An item is divided. Divide only numbers.'),
  'An item has a minus or zero quantity' => t(
    'An item has a minus or zero quantity.',
  ),
  _ => p,
};

/// The tape (each part of the sum with its amount) and the answer.
class _Display extends StatelessWidget {
  const _Display({required this.calc, required this.result});

  final CalcState calc;
  final CalcResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final trailingOp =
        calc.tokens.isNotEmpty && calc.tokens.last.kind == CalcTokenKind.op
        ? calc.tokens.last.text
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: calc.isEmpty
                  ? Center(
                      child: Text(
                        t(
                          'Type numbers, or tap Product or Service to use their prices.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    )
                  : ListView(
                      reverse: true,
                      children: [
                        if (trailingOp != null)
                          Text(
                            trailingOp,
                            style: TextStyle(
                              fontSize: 20,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        for (final l in r.lines.reversed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (l.item != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 6,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      l.item!.kind == 'product'
                                          ? Icons.inventory_2_outlined
                                          : Icons.build_outlined,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    l.label,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  money(l.amount),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(),
            if (r.problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _problemText(r.problem!),
                  style: const TextStyle(color: AppColors.orange),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  r.total == null ? '—' : '= ${money(r.total)}',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onOp,
    required this.onPercent,
    required this.onBack,
    required this.onClear,
    required this.onEquals,
  });

  final ValueChanged<String> onDigit;
  final ValueChanged<String> onOp;
  final VoidCallback onPercent;
  final VoidCallback onBack;
  final VoidCallback onClear;
  final VoidCallback onEquals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(
      String label,
      VoidCallback onTap, {
      Color? background,
      Color? foreground,
      IconData? icon,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: background ?? scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: foreground)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: foreground ?? scheme.onSurface,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    Widget digit(String d) => key(d, () => onDigit(d));
    Widget op(String o) => key(
      o,
      () => onOp(o),
      background: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
    );
    Widget row(List<Widget> keys) => Expanded(child: Row(children: keys));

    return Column(
      children: [
        row([
          key(
            'C',
            onClear,
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          ),
          key('', onBack, icon: Icons.backspace_outlined),
          key('%', onPercent),
          op(calcDivide),
        ]),
        row([digit('7'), digit('8'), digit('9'), op(calcTimes)]),
        row([digit('4'), digit('5'), digit('6'), op(calcMinus)]),
        row([digit('1'), digit('2'), digit('3'), op(calcPlus)]),
        row([
          digit('00'),
          digit('0'),
          digit('.'),
          key(
            '=',
            onEquals,
            background: scheme.primary,
            foreground: scheme.onPrimary,
          ),
        ]),
      ],
    );
  }
}

/// The service catalog with a search box.
class _ServicePicker extends StatefulWidget {
  const _ServicePicker({required this.services});

  final List<Map<String, dynamic>> services;

  @override
  State<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends State<_ServicePicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final s in widget.services)
        if (q.isEmpty || (s['name'] as String? ?? '').toLowerCase().contains(q))
          s,
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t('Search services'),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final gst = toDouble(s['gst_rate']);
                  return ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: Text(s['name'] as String? ?? ''),
                    subtitle: gst > 0
                        ? Text(
                            t('{v1} + {v2}% GST', {
                              'v1': money(toDouble(s['price'])),
                              'v2': qty(gst),
                            }),
                          )
                        : null,
                    trailing: Text(
                      money(toDouble(s['price']) * (1 + gst / 100)),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => Navigator.pop(context, s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
