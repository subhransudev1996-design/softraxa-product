import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Lightweight per-page walkthrough system (no external packages).
///
/// - First visit to a page auto-opens its guide once (tracked per page in
///   SharedPreferences).
/// - Every page shows a `?` [GuideButton] in its AppBar so anyone can
///   replay the guide anytime.
/// - "App walkthrough" in More replays the welcome tour.
class WalkthroughStep {
  const WalkthroughStep(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class PageGuide {
  const PageGuide(this.title, this.steps);
  final String title;
  final List<WalkthroughStep> steps;
}

const Map<String, PageGuide> pageGuides = {
  'home': PageGuide('Welcome to SOFTRAXA Inventory', [
    WalkthroughStep(Icons.storefront_outlined, 'Your shop, in one app',
        'Billing, stock, purchases, customers, dues, expenses and reports — everything your shop needs, together in one place.'),
    WalkthroughStep(Icons.dashboard_outlined, "Today at a glance",
        "The dashboard shows today's sales and profit, your stock value, low-stock alerts, and how much customers owe you / you owe suppliers."),
    WalkthroughStep(Icons.receipt_long_outlined, 'Make a bill in seconds',
        'Tap "New Bill" to open billing. Search or scan a barcode, take payment (cash, UPI, card, credit or split), and print or share the invoice.'),
    WalkthroughStep(Icons.inventory_2_outlined, 'Stock updates itself',
        'Every sale, purchase and return moves stock automatically. You only adjust it by hand for damage or corrections.'),
    WalkthroughStep(Icons.help_outline, 'Help on every page',
        'See the ? icon at the top of each page? Tap it anytime to replay that page\'s guide. You can also replay this tour from More → App walkthrough.'),
  ]),
  'pos': PageGuide('Billing (POS)', [
    WalkthroughStep(Icons.search, 'Add items',
        'Type a product name in the search box, or scan a barcode with the camera / a USB scanner. Tap a result to add it to the bill.'),
    WalkthroughStep(Icons.exposure, 'Change qty, price or discount',
        'Tap a line in the cart to edit its quantity, price or discount. Loose quantities (like 500 g or ₹50 worth) are supported for weighable items.'),
    WalkthroughStep(Icons.person_add_alt, 'Attach a customer',
        'Select a customer to track credit (due) sales and see their balance. Walk-in sales work without one.'),
    WalkthroughStep(Icons.payments_outlined, 'Take payment',
        'At checkout choose cash, UPI, card or credit — or split one bill across several modes. Any unpaid part becomes the customer\'s due automatically.'),
    WalkthroughStep(Icons.print_outlined, 'Print or share',
        'After saving, print to a thermal printer, save an A4 PDF, or share the invoice on WhatsApp.'),
  ]),
  'products': PageGuide('Products', [
    WalkthroughStep(Icons.add_box_outlined, 'Add your items',
        'Use + to add a product: name, prices, GST, barcode, opening stock and a low-stock alert level.'),
    WalkthroughStep(Icons.category_outlined, 'Organise with master data',
        'Categories, brands and units live under the list icon in the top bar. Units control whether an item can be sold in fractions (kg, metre…).'),
    WalkthroughStep(Icons.style_outlined, 'Variants',
        'One product can have variants (size / colour / model / storage), each with its own price, barcode and stock.'),
    WalkthroughStep(Icons.qr_code_2_outlined, 'Barcodes',
        'Attach a barcode per product or variant — type it or scan it. Billing then finds the item instantly.'),
  ]),
  'invoices': PageGuide('Invoices', [
    WalkthroughStep(Icons.filter_list, 'Find any bill',
        'Search by number or customer, and filter by paid / partial / credit status or date.'),
    WalkthroughStep(Icons.receipt_long_outlined, 'Open a bill',
        'Tap an invoice to see its items and payments, print or share it again, record a due payment, edit it, or cancel it (stock is restored).'),
    WalkthroughStep(Icons.assignment_return_outlined, 'Returns',
        'Customer brought something back? Open the invoice and create a sale return — stock and dues update automatically.'),
  ]),
  'purchases': PageGuide('Purchases', [
    WalkthroughStep(Icons.add_shopping_cart, 'Record what you buy',
        'Tap + to enter a supplier bill: items, quantities, cost prices, GST and any extra charges.'),
    WalkthroughStep(Icons.account_balance_wallet_outlined, 'Pay now or later',
        'Mark the purchase paid, partial or unpaid. Unpaid amounts are tracked as what you owe that supplier.'),
    WalkthroughStep(Icons.trending_up, 'Stock goes up automatically',
        'Saving a purchase adds the quantities to stock — no separate stock entry needed.'),
  ]),
  'customers': PageGuide('Customers', [
    WalkthroughStep(Icons.person_add_alt, 'Save your customers',
        'Add name, phone and address. Set an optional credit limit to get warned before a customer\'s due grows too big.'),
    WalkthroughStep(Icons.currency_rupee, 'Track dues',
        'Every credit sale adds to the customer\'s due. Tap a customer to see their full ledger — bills, payments and returns.'),
    WalkthroughStep(Icons.payments_outlined, 'Receive payments',
        'Use "Receive payment" to record money received. It settles the oldest unpaid bills first.'),
  ]),
  'suppliers': PageGuide('Suppliers', [
    WalkthroughStep(Icons.local_shipping_outlined, 'Your suppliers',
        'Save the people you buy from. Their balance shows how much you still owe them.'),
    WalkthroughStep(Icons.receipt_outlined, 'Ledger',
        'Tap a supplier to see every purchase, payment and return with a running balance.'),
    WalkthroughStep(Icons.payments_outlined, 'Pay suppliers',
        '"Pay supplier" records a payment and settles your oldest unpaid purchases first.'),
  ]),
  'stock': PageGuide('Stock', [
    WalkthroughStep(Icons.inventory_2_outlined, 'Everything in one list',
        'Current stock for every product, with its value. Use the filters to see only low-stock or out-of-stock items.'),
    WalkthroughStep(Icons.tune, 'Adjust when needed',
        'Use adjust stock for corrections, and damaged/lost for breakage — each change is recorded with a reason.'),
    WalkthroughStep(Icons.history, 'Full history',
        'Open a product\'s movement history to see every in/out with date and source (sale, purchase, return, adjustment…).'),
  ]),
  'expenses': PageGuide('Expenses', [
    WalkthroughStep(Icons.add_card, 'Note daily expenses',
        'Rent, electricity, transport, chai — add an amount, pick a category, done.'),
    WalkthroughStep(Icons.event_outlined, 'See any period',
        'Use the quick chips (Today / This week / This month / Last month) or pick your own dates. The total updates instantly.'),
    WalkthroughStep(Icons.pie_chart_outline, 'Where money goes',
        'The expense report shows a category-wise breakdown so you know exactly where cash is going.'),
  ]),
  'reports': PageGuide('Reports', [
    WalkthroughStep(Icons.query_stats, 'Pick a report',
        'Sales, profit, stock, GST, dues, purchases, expenses and more — each opens with a chart and a detailed table.'),
    WalkthroughStep(Icons.date_range, 'Choose the period',
        'Most reports have a date filter at the top. Change it and everything recalculates.'),
    WalkthroughStep(Icons.picture_as_pdf_outlined, 'Export as PDF',
        'Every report can be saved or shared as a PDF — handy for your accountant or GST filing.'),
  ]),
  'import': PageGuide('Excel import', [
    WalkthroughStep(Icons.download_outlined, '1. Download the template',
        'Get the sample Excel file first — its columns are exactly what the import expects.'),
    WalkthroughStep(Icons.edit_note, '2. Fill in your products',
        'One row per product: name, prices, GST %, barcode, opening stock. Don\'t reorder the columns.'),
    WalkthroughStep(Icons.upload_file_outlined, '3. Upload and check',
        'Upload the file — every row is validated and duplicates are caught. Fix any red rows and import again; already-imported rows won\'t duplicate.'),
  ]),
  'job_cards': PageGuide('Job cards (repairs & services)', [
    WalkthroughStep(Icons.build_outlined, 'Take in a job',
        'Customer brings something to repair or wants on-site work? Create a job card with the item, problem, estimate, advance and location.'),
    WalkthroughStep(Icons.flag_outlined, 'Track the status',
        'Move the job through statuses — received, in progress, waiting for parts, ready, delivered — the customer history is kept.'),
    WalkthroughStep(Icons.handyman_outlined, 'Add parts and labour',
        'Spare parts come straight from your stock (and reduce it); labour charges come from your service catalog or free-typed.'),
    WalkthroughStep(Icons.receipt_long_outlined, 'Close with one bill',
        'When done, close the job — parts + labour become one invoice, the advance is deducted, and warranty can be set.'),
  ]),
  'services': PageGuide('Service catalog', [
    WalkthroughStep(Icons.home_repair_service_outlined, 'Your service menu',
        'List the services you offer — display replacement, stitching, installation — with price, GST and warranty.'),
    WalkthroughStep(Icons.bolt_outlined, 'Used in job cards',
        'When adding labour to a job card you can pick from this catalog instead of typing charges every time.'),
  ]),
  'sale_returns': PageGuide('Sale returns', [
    WalkthroughStep(Icons.assignment_return_outlined, 'Take items back',
        'Pick the original invoice, choose which items and how many are coming back — you can never return more than was sold.'),
    WalkthroughStep(Icons.currency_rupee, 'Refund or adjust',
        'The amount can be refunded, or adjusted against the customer\'s due. Stock goes back automatically.'),
  ]),
  'purchase_returns': PageGuide('Purchase returns', [
    WalkthroughStep(Icons.assignment_return_outlined, 'Return to supplier',
        'Pick the purchase, choose items and quantities to send back. You can only return what is still in stock.'),
    WalkthroughStep(Icons.account_balance_wallet_outlined, 'Settlement',
        'The return reduces stock and adjusts what you owe the supplier.'),
  ]),
  'offline_bills': PageGuide('Offline bills', [
    WalkthroughStep(Icons.wifi_off_outlined, 'No internet? Keep billing',
        'When the connection drops, bills are saved here with a temporary number. Products and customers come from the local cache.'),
    WalkthroughStep(Icons.sync, 'They sync themselves',
        'As soon as internet returns, pending bills upload and get real invoice numbers. Failed ones can be retried from this list.'),
  ]),
};

bool _sheetOpen = false;

/// Auto-show a page's guide the first time that page is seen.
Future<void> maybeShowWalkthrough(BuildContext context, String pageKey) async {
  if (_sheetOpen || !pageGuides.containsKey(pageKey)) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('walkthrough_seen_$pageKey') ?? false) return;
  if (_sheetOpen) return; // re-check after the await
  await prefs.setBool('walkthrough_seen_$pageKey', true);
  if (context.mounted) await showWalkthrough(context, pageKey);
}

/// Show a page's guide (used by the ? button — works anytime).
Future<void> showWalkthrough(BuildContext context, String pageKey) async {
  final guide = pageGuides[pageKey];
  if (guide == null || _sheetOpen) return;
  _sheetOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => _WalkthroughSheet(guide: guide),
    );
  } finally {
    _sheetOpen = false;
  }
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
