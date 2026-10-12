import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'formatters.dart';
import 'i18n.dart';
import 'theme.dart';

/// A UPI ID as banks issue them: name@bank.
bool isValidUpiId(String upi) =>
    RegExp(r'^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$').hasMatch(upi);

/// "upi://pay" link any UPI app (GPay, PhonePe, Paytm, BHIM) opens with the
/// payee and the amount already filled in.
String upiPayLink({
  required String upiId,
  required String payee,
  required double amount,
  String note = '',
}) => Uri(
  scheme: 'upi',
  host: 'pay',
  queryParameters: {
    'pa': upiId.trim(),
    'pn': payee.trim(),
    'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    if (note.trim().isNotEmpty) 'tn': note.trim(),
  },
).toString();

/// The QR the customer scans, with the amount and who it goes to.
class UpiQr extends StatelessWidget {
  const UpiQr({
    super.key,
    required this.upiId,
    required this.payee,
    required this.amount,
    this.size = 180,
  });

  final String upiId;
  final String payee;
  final double amount;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          // Always white behind the code: scanners need dark-on-light.
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: upiPayLink(
            upiId: upiId,
            payee: payee,
            amount: amount,
            note: payee,
          ),
          size: size,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        money(amount),
        style: TextStyle(
          fontSize: size > 200 ? 28 : 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(
        upiId,
        style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
      ),
    ],
  );
}

/// The QR big on its own screen, to turn the phone or monitor towards the
/// customer.
Future<void> showUpiQrFullScreen(
  BuildContext context, {
  required String upiId,
  required String payee,
  required double amount,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            payee,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            t('Scan with any UPI app to pay'),
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          UpiQr(upiId: upiId, payee: payee, amount: amount, size: 280),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Close')),
          ),
        ],
      ),
    ),
  ),
);
