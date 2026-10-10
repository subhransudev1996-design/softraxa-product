import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/widgets.dart';
import 'bill_layout.dart';

/// Bluetooth ESC/POS thermal printing (PRD 7.8).
class ThermalPrinterService {
  /// Shows a device picker, connects, prints the receipt.
  static Future<void> printInvoice(
    BuildContext context, {
    required Map<String, dynamic> business,
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) => _print(
    context,
    () => _buildTicket(business: business, invoice: invoice, items: items),
  );

  /// A short test slip, used by the setup wizard's printer check.
  static Future<void> printTestPage(BuildContext context, String shopName) =>
      _print(context, () async {
        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm80, profile);
        return [
          ...generator.text(
            shopName,
            styles: const PosStyles(align: PosAlign.center, bold: true),
          ),
          ...generator.text(
            'Printer test - Dukania',
            styles: const PosStyles(align: PosAlign.center),
          ),
          ...generator.text(
            dateTimeStr(DateTime.now().toIso8601String()),
            styles: const PosStyles(align: PosAlign.center),
          ),
          ...generator.hr(),
          ...generator.text('If you can read this, billing will print.'),
          ...generator.feed(2),
          ...generator.cut(),
        ];
      });

  static Future<void> _print(
    BuildContext context,
    Future<List<int>> Function() build,
  ) async {
    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) {
        if (context.mounted) showError(context, 'Turn on Bluetooth to print');
        return;
      }
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) {
        if (context.mounted) {
          showError(
            context,
            'No paired Bluetooth printer found. Pair it in phone settings first.',
          );
        }
        return;
      }
      if (!context.mounted) return;
      final device = await showModalBottomSheet<BluetoothInfo>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select printer',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final d in devices)
                ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(d.name),
                  subtitle: Text(d.macAdress),
                  onTap: () => Navigator.pop(ctx, d),
                ),
            ],
          ),
        ),
      );
      if (device == null) return;

      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress,
      );
      if (!connected) {
        if (context.mounted) {
          showError(context, 'Could not connect to ${device.name}');
        }
        return;
      }
      final bytes = await build();
      await PrintBluetoothThermal.writeBytes(bytes);
      await PrintBluetoothThermal.disconnect;
      if (context.mounted) showSuccess(context, 'Sent to printer');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static Future<List<int>> _buildTicket({
    required Map<String, dynamic> business,
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    final bill = BillLayout(business: business, invoice: invoice, items: items);
    final isGst = bill.isGst;
    final logo = await _logoImage(business);
    List<int> bytes = [];
    const center = PosStyles(align: PosAlign.center);
    const right = PosStyles(align: PosAlign.right);
    const bold = PosStyles(bold: true);
    const boldRight = PosStyles(align: PosAlign.right, bold: true);
    String s(Object? v) => (v as String? ?? '').trim();
    String n(num v) => billMoney(v);

    // ---- shop ----
    if (logo != null) bytes += generator.imageRaster(logo);
    bytes += generator.text(
      s(business['name']),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    if (s(business['address']).isNotEmpty) {
      bytes += generator.text(s(business['address']), styles: center);
    }
    if (s(business['phone']).isNotEmpty) {
      bytes += generator.text('Ph: ${s(business['phone'])}', styles: center);
    }
    if (s(business['email']).isNotEmpty) {
      bytes += generator.text(s(business['email']), styles: center);
    }
    final composition = business['tax_preference'] == 'composition';
    // Composition shops issue bills of supply (migration 0048).
    final title = composition && !bill.isEstimate
        ? 'BILL OF SUPPLY'
        : switch (invoice['invoice_type']) {
            'gst' => 'TAX INVOICE',
            'cash_memo' => 'CASH MEMO',
            'estimate' => 'ESTIMATE / QUOTATION',
            _ => 'SALES INVOICE',
          };
    bytes += generator.text(title, styles: center.copyWith(bold: true));
    if ((isGst || composition) && s(business['gst_number']).isNotEmpty) {
      bytes += generator.text(
        'GSTIN: ${s(business['gst_number'])}',
        styles: center.copyWith(bold: true),
      );
    }
    if (composition && !bill.isEstimate) {
      bytes += generator.text(
        'Composition taxable person, not eligible to collect tax on supplies',
        styles: center,
      );
    }

    // ---- bill and customer ----
    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(
        text: 'Bill No: ${invoice['invoice_no']}',
        width: 7,
        styles: bold,
      ),
      PosColumn(
        text: dateTimeStr(invoice['invoice_date']),
        width: 5,
        styles: right,
      ),
    ]);
    final cust = s(invoice['customer_name']);
    final mob = s(invoice['customer_phone']);
    if (cust.isNotEmpty || mob.isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Cust: $cust', width: 6),
        PosColumn(
          text: mob.isEmpty ? '' : 'Mob: $mob',
          width: 6,
          styles: right,
        ),
      ]);
    }
    final customerGstin = s(invoice['customer_gstin']);
    if (isGst && customerGstin.isNotEmpty) {
      bytes += generator.text('GSTIN: $customerGstin');
    }
    final pos = gstStateLabel(invoice['place_of_supply'] as String?);
    if (isGst && pos.isNotEmpty) {
      bytes += generator.text('Place of supply: $pos');
    }

    // ---- items: name line, then Qty | Rate | Amount | Disc | Total ----
    final anyDisc = bill.lines.any((l) => l.discount > 0);
    final anySku = bill.lines.any((l) => l.sku.isNotEmpty);
    // 12 columns: 2 qty, then the money columns.
    final widths = anyDisc ? [2, 2, 3, 2, 3] : [2, 3, 3, 4];
    List<PosColumn> cols(List<String> c, {bool b = false}) => [
      for (var i = 0; i < c.length; i++)
        PosColumn(
          text: c[i],
          width: widths[i],
          styles: PosStyles(
            align: i == 0 ? PosAlign.left : PosAlign.right,
            bold: b,
          ),
        ),
    ];
    bytes += generator.hr();
    bytes += generator.text(
      anySku ? 'Stock No  Item Description' : 'Item',
      styles: bold,
    );
    bytes += generator.row(
      cols(['Qty', 'Rate', 'Amount', if (anyDisc) 'Disc', 'Total'], b: true),
    );
    bytes += generator.hr();
    for (final l in bill.lines) {
      final size = l.size.isEmpty ? '' : ' - ${l.size}';
      bytes += generator.text(
        l.sku.isEmpty ? '${l.name}$size' : '${l.sku}  ${l.name}$size',
      );
      bytes += generator.row(
        cols([
          l.isPack ? qtyUnit(l.qty, l.unit) : qty(l.qty),
          n(l.rate),
          n(l.amount),
          if (anyDisc) n(l.discount),
          n(l.total),
        ]),
      );
    }
    bytes += generator.hr();
    bytes += generator.row(
      cols([
        qty(bill.totalQty),
        '',
        n(bill.totalAmount),
        if (anyDisc) n(bill.totalLineDiscount),
        n(bill.linesTotal),
      ], b: true),
    );
    bytes += generator.hr();

    void totalRow(String label, num value, {bool strong = false}) {
      bytes += generator.row([
        PosColumn(
          text: label,
          width: 7,
          styles: PosStyles(bold: strong),
        ),
        PosColumn(text: n(value), width: 5, styles: strong ? boldRight : right),
      ]);
    }

    if (bill.billDiscount > 0) totalRow('Bill discount', -bill.billDiscount);
    if (bill.roundOff != 0) totalRow('Round off', bill.roundOff);
    bytes += generator.row([
      PosColumn(
        text: 'Net Bill Amount',
        width: 7,
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
      PosColumn(
        text: n(bill.netAmount),
        width: 5,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    ]);
    bytes += generator.text('Amount In Words:', styles: bold);
    bytes += generator.text(bill.amountInWords);

    // ---- payment ----
    if (bill.payments.isNotEmpty || bill.due > 0) {
      bytes += generator.hr();
      bytes += generator.text('Payment Details', styles: bold);
      for (final (mode, amount) in bill.payments) {
        totalRow(mode, amount);
      }
      if (bill.due > 0) totalRow('DUE', bill.due, strong: true);
    }

    // ---- GST summary: GST% | Taxable | CGST | SGST | Total (or IGST) ----
    final gst = bill.gstSummary;
    if (gst.isNotEmpty) {
      final igst = bill.gstIsInterState;
      final gw = igst ? [2, 4, 3, 3] : [2, 3, 2, 2, 3];
      List<PosColumn> g(List<String> c, {bool b = false}) => [
        for (var i = 0; i < c.length; i++)
          PosColumn(
            text: c[i],
            width: gw[i],
            styles: PosStyles(
              align: i == 0 ? PosAlign.left : PosAlign.right,
              bold: b,
            ),
          ),
      ];
      double sum(double Function(GstSummaryRow) f) =>
          gst.fold(0.0, (t, r) => t + f(r));
      bytes += generator.hr();
      bytes += generator.text('GST Summary', styles: bold);
      bytes += generator.row(
        g([
          'GST%',
          'Taxable',
          if (igst) 'IGST' else ...['CGST', 'SGST'],
          'Total',
        ], b: true),
      );
      for (final r in gst) {
        bytes += generator.row(
          g([
            '${qty(r.rate)}%',
            n(r.taxable),
            if (igst) n(r.igst) else ...[n(r.cgst), n(r.sgst)],
            n(r.totalTax),
          ]),
        );
      }
      if (gst.length > 1) {
        bytes += generator.row(
          g([
            'Total',
            n(sum((r) => r.taxable)),
            if (igst)
              n(sum((r) => r.igst))
            else ...[
              n(sum((r) => r.cgst)),
              n(sum((r) => r.sgst)),
            ],
            n(sum((r) => r.totalTax)),
          ], b: true),
        );
      }
    }

    // ---- terms and footer ----
    if (bill.terms.isNotEmpty) {
      bytes += generator.hr();
      bytes += generator.text('Terms & Conditions:', styles: bold);
      for (var i = 0; i < bill.terms.length; i++) {
        bytes += generator.text('${i + 1}. ${bill.terms[i]}');
      }
    }
    if (bill.footer.isNotEmpty) {
      bytes += generator.feed(1);
      bytes += generator.text(bill.footer, styles: center);
    }
    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }

  /// The shop's logo for the printer: on white, in grey, at most 280 dots
  /// wide. Null without a logo, or when it can't be loaded or read; the
  /// bill then prints without it.
  static Future<img.Image?> _logoImage(Map<String, dynamic> business) async {
    final data = await loadBillLogo(business);
    if (data == null) return null;
    try {
      final src = img.decodeImage(data);
      if (src == null) return null;
      final sized = src.width > 280 ? img.copyResize(src, width: 280) : src;
      final white = img.Image(width: sized.width, height: sized.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.compositeImage(white, sized);
      return img.grayscale(white);
    } catch (_) {
      return null;
    }
  }
}
