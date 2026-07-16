import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Spotlight walkthrough system (no external packages).
///
/// Real widgets are marked with [CoachTarget]; each page's guide steps
/// reference target ids. Running a guide dims the screen, cuts a bright
/// spotlight around the current step's actual widget (auto-scrolling to
/// it when needed) and shows an explainer card beside it. Steps whose
/// target isn't on screen (other layout, empty list) render as a
/// centered card instead, so a tour never breaks.
///
/// - First visit to a page auto-runs its tour once (SharedPreferences).
/// - The `?` [GuideButton] on every page replays it anytime.

// ============================ model ============================

class CoachStep {
  const CoachStep({
    this.id,
    required this.icon,
    required this.title,
    required this.body,
  });

  /// [CoachTarget] id to spotlight; null = centered informational step.
  final String? id;
  final IconData icon;
  final String title;
  final String body;
}

class PageGuide {
  const PageGuide(this.title, this.steps);
  final String title;
  final List<CoachStep> steps;
}

// ====================== target registry ======================

class CoachRegistry {
  static final Map<String, List<State>> _targets = {};

  static String _key(String page, String id) => '$page::$id';

  static void register(String page, String id, State state) {
    _targets.putIfAbsent(_key(page, id), () => []).add(state);
  }

  static void unregister(String page, String id, State state) {
    _targets[_key(page, id)]?.remove(state);
  }

  /// The build context of a currently-mounted target, if any.
  static BuildContext? contextOf(String page, String id) {
    final list = _targets[_key(page, id)];
    if (list == null) return null;
    for (final s in list.reversed) {
      if (s.mounted) return s.context;
    }
    return null;
  }

  static bool has(String page, String id) => contextOf(page, id) != null;
}

/// Wrap any widget to make it spotlight-able as (page, id).
class CoachTarget extends StatefulWidget {
  const CoachTarget({
    super.key,
    required this.page,
    required this.id,
    required this.child,
  });

  final String page;
  final String id;
  final Widget child;

  @override
  State<CoachTarget> createState() => _CoachTargetState();
}

class _CoachTargetState extends State<CoachTarget> {
  @override
  void initState() {
    super.initState();
    CoachRegistry.register(widget.page, widget.id, this);
  }

  @override
  void dispose() {
    CoachRegistry.unregister(widget.page, widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ========================= run logic =========================

bool _running = false;

/// Auto-run a page's tour the first time that page is seen.
Future<void> maybeShowWalkthrough(BuildContext context, String pageKey) async {
  if (_running || !pageGuides.containsKey(pageKey)) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('walkthrough_seen_$pageKey') ?? false) return;
  if (_running) return; // re-check after the await
  await prefs.setBool('walkthrough_seen_$pageKey', true);
  if (context.mounted) await showWalkthrough(context, pageKey);
}

/// Run a page's tour (used by the ? buttons — works anytime).
Future<void> showWalkthrough(BuildContext context, String pageKey) async {
  final guide = pageGuides[pageKey];
  if (guide == null || _running) return;
  _running = true;
  try {
    // Give slow-loading pages a moment to build their anchored widgets
    // (data lists, async cards) before deciding whether anything is
    // anchorable at all.
    final ids = guide.steps.map((s) => s.id).whereType<String>().toList();
    var waited = 0;
    while (waited < 2500 && !ids.any((id) => CoachRegistry.has(pageKey, id))) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      waited += 250;
      if (!context.mounted) return;
    }
    if (!context.mounted) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null || !ids.any((id) => CoachRegistry.has(pageKey, id))) {
      // Nothing anchorable (empty page / unexpected layout): plain
      // carousel fallback keeps the tour available.
      await _showCarouselSheet(context, guide);
      return;
    }

    final done = Completer<void>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoachOverlay(
        pageKey: pageKey,
        guide: guide,
        onDone: () {
          entry.remove();
          done.complete();
        },
      ),
    );
    overlay.insert(entry);
    await done.future;
  } finally {
    _running = false;
  }
}

// ===================== spotlight overlay =====================

class _CoachOverlay extends StatefulWidget {
  const _CoachOverlay({
    required this.pageKey,
    required this.guide,
    required this.onDone,
  });

  final String pageKey;
  final PageGuide guide;
  final VoidCallback onDone;

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> {
  late final List<CoachStep> _steps;
  int _index = 0;
  Rect? _rect; // spotlight rect (null = centered step)
  bool _measuring = true;

  @override
  void initState() {
    super.initState();
    // Only keep steps that are anchored right now or deliberately
    // unanchored (id == null); drop steps whose target is absent.
    _steps = [
      for (final s in widget.guide.steps)
        if (s.id == null || CoachRegistry.has(widget.pageKey, s.id!)) s,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _steps.length) {
      widget.onDone();
      return;
    }
    setState(() {
      _index = i;
      _measuring = true;
    });
    final step = _steps[i];
    Rect? rect;
    if (step.id != null) {
      final targetCtx = CoachRegistry.contextOf(widget.pageKey, step.id!);
      if (targetCtx != null && targetCtx.mounted) {
        try {
          await Scrollable.ensureVisible(
            targetCtx,
            alignment: 0.45,
            duration: const Duration(milliseconds: 250),
          );
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (!mounted) return;
        final ro = targetCtx.findRenderObject();
        if (ro is RenderBox && ro.attached && ro.hasSize) {
          final topLeft = ro.localToGlobal(Offset.zero);
          rect = topLeft & ro.size;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _rect = rect;
      _measuring = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final step = _steps[_index];
    final spot = _rect?.inflate(6);
    final last = _index == _steps.length - 1;

    // Card placement: below the spotlight when there's room, else above;
    // centered when the step has no anchor.
    const cardWidth = 330.0;
    const cardMargin = 14.0;
    double? cardTop, cardLeft;
    if (spot != null) {
      final below = spot.bottom + cardMargin;
      cardTop = below + 240 < size.height
          ? below
          : (spot.top - cardMargin - 230).clamp(12.0, size.height - 250);
      cardLeft = (spot.center.dx - cardWidth / 2)
          .clamp(12.0, size.width - cardWidth - 12);
    }

    return Stack(children: [
      // dim + cutout; tap anywhere advances
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _goTo(_index + 1),
          child: AnimatedOpacity(
            opacity: _measuring ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            child: CustomPaint(
              painter: _SpotlightPainter(spot),
              size: size,
            ),
          ),
        ),
      ),
      if (!_measuring)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          top: cardTop ?? (size.height / 2 - 130),
          left: cardLeft ?? (size.width / 2 - cardWidth / 2),
          width: cardWidth,
          child: _CoachCard(
            guideTitle: widget.guide.title,
            step: step,
            index: _index,
            total: _steps.length,
            onBack: _index > 0 ? () => _goTo(_index - 1) : null,
            onNext: () => _goTo(_index + 1),
            onSkip: widget.onDone,
            isLast: last,
          ),
        ),
    ]);
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.spot);
  final Rect? spot;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    if (spot == null) {
      canvas.drawPath(dim, paint);
      return;
    }
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(spot!, const Radius.circular(14)));
    canvas.drawPath(Path.combine(PathOperation.difference, dim, hole), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(spot!, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.spot != spot;
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.guideTitle,
    required this.step,
    required this.index,
    required this.total,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
  });

  final String guideTitle;
  final CoachStep step;
  final int index;
  final int total;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(step.icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(step.title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
              Text('${index + 1}/$total',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
            ]),
            const SizedBox(height: 8),
            Text(step.body,
                style: TextStyle(
                    fontSize: 13, height: 1.45, color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            Row(children: [
              InkWell(
                onTap: onSkip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Skip tour',
                      style:
                          TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                ),
              ),
              const Spacer(),
              if (onBack != null)
                OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14)),
                  child: const Text('Back'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 18)),
                child: Text(isLast ? 'Done' : 'Next'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ================== carousel fallback (no anchors) ==================

Future<void> _showCarouselSheet(BuildContext context, PageGuide guide) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _WalkthroughSheet(guide: guide),
  );
}

class _WalkthroughSheet extends StatefulWidget {
  const _WalkthroughSheet({required this.guide});
  final PageGuide guide;

  @override
  State<_WalkthroughSheet> createState() => _WalkthroughSheetState();
}

class _WalkthroughSheetState extends State<_WalkthroughSheet> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.guide.steps;
    final last = _page == steps.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(widget.guide.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Text('${_page + 1}/${steps.length}',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 20, color: AppColors.inkSoft),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: PageView.builder(
              controller: _controller,
              itemCount: steps.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final s = steps[i];
                return Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(s.icon, size: 32, color: AppColors.primary),
                  ),
                  const SizedBox(height: 14),
                  Text(s.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(s.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13.5, height: 1.45, color: AppColors.inkSoft)),
                    ),
                  ),
                ]);
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < steps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.primary : AppColors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            if (_page > 0)
              OutlinedButton(
                onPressed: () => _controller.previousPage(
                    duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: const Text('Back'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip'),
              ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 24)),
              onPressed: () {
                if (last) {
                  Navigator.pop(context);
                } else {
                  _controller.nextPage(
                      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                }
              },
              child: Text(last ? 'Done' : 'Next'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// `?` AppBar button: replays the page guide on tap, and auto-opens it
/// the first time the page is ever shown.
class GuideButton extends StatefulWidget {
  const GuideButton(this.pageKey, {super.key, this.color});
  final String pageKey;
  final Color? color;

  @override
  State<GuideButton> createState() => _GuideButtonState();
}

class _GuideButtonState extends State<GuideButton> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWalkthrough(context, widget.pageKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Page guide',
      icon: Icon(Icons.help_outline, color: widget.color),
      onPressed: () => showWalkthrough(context, widget.pageKey),
    );
  }
}

// ========================= page guides =========================
// Step `id`s reference CoachTarget wraps in the screens; a step whose
// target isn't mounted is skipped (or shown centered when id is null).

const Map<String, PageGuide> pageGuides = {
  'home': PageGuide('Welcome to SOFTRAXA Inventory', [
    CoachStep(
        icon: Icons.storefront_outlined,
        title: 'Your shop, in one app',
        body:
            'Billing, stock, purchases, customers, dues, expenses and reports — everything your shop needs, together in one place. Let\'s take a quick look around.'),
    CoachStep(
        id: 'stats',
        icon: Icons.dashboard_outlined,
        title: 'Today at a glance',
        body:
            "These tiles show today's sales and profit, your total stock value, low-stock alerts and dues — they update live as you bill."),
    CoachStep(
        id: 'new_bill',
        icon: Icons.receipt_long_outlined,
        title: 'Start billing here',
        body:
            'This button opens the billing screen. Search or scan a product, take payment, print or share the invoice — all in seconds.'),
    CoachStep(
        id: 'quick_actions',
        icon: Icons.bolt_outlined,
        title: 'Quick actions',
        body:
            'Shortcuts for the things you do most — new bill, add product, new purchase and barcode scan.'),
    CoachStep(
        id: 'recent',
        icon: Icons.history,
        title: 'Recent invoices',
        body:
            'Your latest bills with payment status. Tap any of them to reprint, edit, record a payment or make a return.'),
    CoachStep(
        icon: Icons.help_outline,
        title: 'Help on every page',
        body:
            'Every page has a ? icon at the top — tap it anytime to replay that page\'s tour. This welcome tour is always available from More → App walkthrough.'),
  ]),
  'pos': PageGuide('Billing (POS)', [
    CoachStep(
        id: 'search',
        icon: Icons.search,
        title: 'Find products here',
        body:
            'Type a name, SKU or barcode — or scan with a USB scanner straight into this box. Matching products appear below; tap one to add it to the bill.'),
    CoachStep(
        id: 'scan',
        icon: Icons.qr_code_scanner,
        title: 'Camera scanning',
        body:
            'Tap to scan barcodes with the camera — keep scanning item after item and they\'re added automatically.'),
    CoachStep(
        id: 'customer',
        icon: Icons.person_add_alt,
        title: 'Who is this bill for?',
        body:
            'Attach a customer to track credit (due) sales — or leave as walk-in. You can also add a brand-new customer from here.'),
    CoachStep(
        id: 'cart',
        icon: Icons.shopping_cart_outlined,
        title: 'The bill lives here',
        body:
            'Every added item shows here. Tap a line to change quantity, price or give a line discount; swipe or use the buttons to remove.'),
    CoachStep(
        id: 'charge',
        icon: Icons.payments_outlined,
        title: 'Take payment',
        body:
            'When the bill is ready, tap here: choose cash, UPI, card or credit — or split across several. Then print or share the invoice.'),
  ]),
  'products': PageGuide('Products', [
    CoachStep(
        id: 'search',
        icon: Icons.search,
        title: 'Search your catalog',
        body: 'Find any product by name, SKU or barcode as you type.'),
    CoachStep(
        id: 'master',
        icon: Icons.category_outlined,
        title: 'Categories, brands & units',
        body:
            'Manage the master lists here. Units decide whether an item can sell in fractions (kg, metre, litre).'),
    CoachStep(
        id: 'add',
        icon: Icons.add_box_outlined,
        title: 'Add a product',
        body:
            'Name, prices, GST, barcode, opening stock, low-stock alert — and variants (size/colour/model) if one product comes in versions.'),
    CoachStep(
        id: 'list',
        icon: Icons.inventory_2_outlined,
        title: 'Your products',
        body:
            'Tap any product to see its detail — stock, variants, barcode, history — or to edit it.'),
  ]),
  'invoices': PageGuide('Invoices', [
    CoachStep(
        id: 'search',
        icon: Icons.search,
        title: 'Find any bill',
        body: 'Search by invoice number or customer name.'),
    CoachStep(
        id: 'filters',
        icon: Icons.filter_list,
        title: 'Filter by payment',
        body:
            'One tap to see only Paid, Partial or Credit bills — great for chasing dues.'),
    CoachStep(
        id: 'list',
        icon: Icons.receipt_long_outlined,
        title: 'Open a bill',
        body:
            'Tap an invoice to reprint/share it, record a due payment, edit it, make a return, or cancel it (stock is restored).'),
  ]),
  'purchases': PageGuide('Purchases', [
    CoachStep(
        id: 'presets',
        icon: Icons.event_outlined,
        title: 'Quick date filters',
        body: 'Jump between today, this week, this month — one tap.'),
    CoachStep(
        id: 'status',
        icon: Icons.account_balance_wallet_outlined,
        title: 'Paid / Partial / Credit',
        body: 'Filter purchases by how much you\'ve paid the supplier.'),
    CoachStep(
        id: 'add',
        icon: Icons.add_shopping_cart,
        title: 'Record a purchase',
        body:
            'Enter a supplier bill — items, quantities, cost prices, GST. Stock goes up automatically when you save.'),
  ]),
  'customers': PageGuide('Customers', [
    CoachStep(
        id: 'list',
        icon: Icons.people_outline,
        title: 'Your customers',
        body:
            'Each entry shows the due balance. Tap one for the full ledger — bills, payments and returns.'),
    CoachStep(
        id: 'add',
        icon: Icons.person_add_alt,
        title: 'Add a customer',
        body:
            'Save name, phone and address; set an optional credit limit to get warned before dues grow too big.'),
  ]),
  'suppliers': PageGuide('Suppliers', [
    CoachStep(
        id: 'list',
        icon: Icons.local_shipping_outlined,
        title: 'Who you buy from',
        body:
            'Each supplier shows how much you still owe. Tap for the full ledger of purchases and payments.'),
    CoachStep(
        id: 'add',
        icon: Icons.add,
        title: 'Add a supplier',
        body: 'Save their contact details, then record purchases against them.'),
  ]),
  'stock': PageGuide('Stock', [
    CoachStep(
        id: 'filters',
        icon: Icons.tune,
        title: 'Low & out of stock',
        body:
            'These filters instantly show what needs restocking — the same alerts as the dashboard tiles.'),
    CoachStep(
        id: 'list',
        icon: Icons.inventory_2_outlined,
        title: 'Every product\'s stock',
        body:
            'Tap a product to adjust stock, record damage, or see its full in/out movement history.'),
  ]),
  'expenses': PageGuide('Expenses', [
    CoachStep(
        id: 'presets',
        icon: Icons.event_outlined,
        title: 'Pick a period',
        body: 'Today, this week, this month, last month — or use the calendar for any range.'),
    CoachStep(
        id: 'total',
        icon: Icons.summarize_outlined,
        title: 'Total for the period',
        body: 'The sum updates instantly as you change filters or add expenses.'),
    CoachStep(
        id: 'add',
        icon: Icons.add_card,
        title: 'Add an expense',
        body: 'Amount + category + note. Rent, electricity, transport, chai — everything counts.'),
  ]),
  'reports': PageGuide('Reports', [
    CoachStep(
        id: 'list',
        icon: Icons.query_stats,
        title: 'Pick any report',
        body:
            'Sales, profit, stock, GST, dues, purchases, expenses — each opens with a chart, a table, a date filter and PDF export.'),
  ]),
  'import': PageGuide('Excel import', [
    CoachStep(
        id: 'template',
        icon: Icons.download_outlined,
        title: '1. Download the template',
        body: 'Start here — the sample file has exactly the columns the import expects.'),
    CoachStep(
        id: 'upload',
        icon: Icons.upload_file_outlined,
        title: '2. Upload your file',
        body:
            'Every row is checked and duplicates are caught before anything is saved. Fix red rows and import again safely.'),
  ]),
  'job_cards': PageGuide('Job cards (repairs & services)', [
    CoachStep(
        id: 'filters',
        icon: Icons.flag_outlined,
        title: 'Track by status',
        body:
            'Filter jobs by stage — received, in progress, waiting for parts, ready, delivered.'),
    CoachStep(
        id: 'add',
        icon: Icons.build_outlined,
        title: 'Take in a new job',
        body:
            'Repair or on-site work? Record the item, problem, estimate, advance and service location. Parts + labour become one invoice at closing.'),
  ]),
  'services': PageGuide('Service catalog', [
    CoachStep(
        id: 'add',
        icon: Icons.home_repair_service_outlined,
        title: 'Your service menu',
        body:
            'Add the services you offer — repairs, stitching, installation — with price, GST and warranty. Job cards pick labour charges from this list.'),
  ]),
  'sale_returns': PageGuide('Sale returns', [
    CoachStep(
        id: 'add',
        icon: Icons.assignment_return_outlined,
        title: 'Take items back',
        body:
            'Pick the original invoice and choose what\'s coming back — you can never return more than was sold. Refund or adjust against dues.'),
  ]),
  'purchase_returns': PageGuide('Purchase returns', [
    CoachStep(
        id: 'add',
        icon: Icons.assignment_return_outlined,
        title: 'Return to supplier',
        body:
            'Pick the purchase and choose items to send back — only what\'s still in stock can be returned. Your supplier balance adjusts.'),
  ]),
  'offline_bills': PageGuide('Offline bills', [
    CoachStep(
        icon: Icons.wifi_off_outlined,
        title: 'No internet? Keep billing',
        body:
            'When the connection drops, bills are saved here with temporary numbers and sync automatically when internet returns. Failed ones can be retried from this list.'),
  ]),
};
