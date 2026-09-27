import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/formatters.dart';
import '../../core/gst.dart';
import '../../core/widgets.dart';

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
    final isGst = invoice['invoice_type'] == 'gst';
    List<int> bytes = [];

    bytes += generator.text(
      business['name'] as String? ?? '',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    if ((business['address'] as String? ?? '').isNotEmpty) {
      bytes += generator.text(
        business['address'] as String,
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if ((business['phone'] as String? ?? '').isNotEmpty) {
      bytes += generator.text(
        'Ph: ${business['phone']}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    final composition = business['tax_preference'] == 'composition';
    if ((isGst || composition) &&
        (business['gst_number'] as String? ?? '').isNotEmpty) {
      bytes += generator.text(
        'GSTIN: ${business['gst_number']}',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }
    // Composition shops issue bills of supply (migration 0048).
    if (composition && invoice['invoice_type'] != 'estimate') {
      bytes += generator.text(
        'BILL OF SUPPLY',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'Composition taxable person, not eligible to collect tax on supplies',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(
        text: '${invoice['invoice_no']}',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: dateStr(invoice['invoice_date']),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    if ((invoice['customer_name'] as String? ?? '').isNotEmpty) {
      bytes += generator.text('Customer: ${invoice['customer_name']}');
    }
    final customerGstin = invoice['customer_gstin'] as String? ?? '';
    if (isGst && customerGstin.isNotEmpty) {
      bytes += generator.text('GSTIN: $customerGstin');
    }
    final pos = gstStateLabel(invoice['place_of_supply'] as String?);
    if (isGst && pos.isNotEmpty) {
      bytes += generator.text('Place of supply: $pos');
    }
    bytes += generator.hr();

    for (final it in items) {
      var name = it['product_name'] as String? ?? '';
      if ((it['variant_name'] as String? ?? '').isNotEmpty) {
        name = '$name (${it['variant_name']})';
      }
      bytes += generator.text(name, styles: const PosStyles(bold: true));
      final rate =
          toDouble(it['unit_price']) *
          (isGst ? 1 + toDouble(it['gst_rate']) / 100 : 1);
      bytes += generator.row([
        PosColumn(
          text: '${qty(it['quantity'] as num?)} x ${rate.toStringAsFixed(2)}',
          width: 7,
        ),
        PosColumn(
          text: toDouble(it['line_total']).toStringAsFixed(2),
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      if ((it['serial_no'] as String? ?? '').isNotEmpty) {
        bytes += generator.text('S/N: ${it['serial_no']}');
      }
    }
    bytes += generator.hr();

    void totalRow(String label, num? value, {bool bold = false}) {
      bytes += generator.row([
        PosColumn(
          text: label,
          width: 7,
          styles: PosStyles(bold: bold),
        ),
        PosColumn(
          text: toDouble(value).toStringAsFixed(2),
          width: 5,
          styles: PosStyles(align: PosAlign.right, bold: bold),
        ),
      ]);
    }

    if (toDouble(invoice['discount_amount']) > 0) {
      totalRow('Discount', -toDouble(invoice['discount_amount']));
    }
    if (isGst && toDouble(invoice['tax_amount']) > 0) {
      totalRow('Taxable value', gstTaxableTotal(items));
      for (final (label, amount) in gstBreakupRows(items)) {
        totalRow('Incl. $label', amount);
      }
    }
    if (toDouble(invoice['round_off']) != 0) {
      totalRow('Round off', invoice['round_off'] as num?);
    }
    totalRow('TOTAL', invoice['total'] as num?, bold: true);
    if (invoice['invoice_type'] != 'estimate') {
      final payments = List<Map<String, dynamic>>.from(
        invoice['invoice_payments'] as List? ?? [],
      );
      if (payments.length > 1) {
        for (final p in payments) {
          totalRow('Paid (${p['payment_mode']})', p['amount'] as num?);
        }
      } else {
        totalRow(
          'Paid (${invoice['payment_mode']})',
          invoice['paid_amount'] as num?,
        );
      }
      if (toDouble(invoice['due_amount']) > 0) {
        totalRow('DUE', invoice['due_amount'] as num?, bold: true);
      }
    }
    bytes += generator.feed(1);
    bytes += generator.text(
      'Thank you! Visit again.',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }
}
