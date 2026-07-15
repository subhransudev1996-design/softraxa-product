import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase_providers.dart';
import '../offline/offline_service.dart';
import 'cart.dart';

class BillResult {
  BillResult({required this.invoiceNo, this.invoiceId, this.offline = false});

  final String invoiceNo;
  final String? invoiceId; // null for offline bills (not yet synced)
  final bool offline;
}

final billingServiceProvider = Provider<BillingService>(BillingService.new);

class BillingService {
  BillingService(this._ref);

  final Ref _ref;

  /// Creates the bill: online via `create_invoice`, or — when the network is
  /// down and offline billing is enabled — saves it locally for later sync.
  Future<BillResult> createBill({
    required CartState cart,
    required String invoiceType,
    required double paidAmount,
    required String paymentMode,
    List<Map<String, dynamic>>? payments,
    String notes = '',
  }) async {
    final localId = const Uuid().v4();
    final payload = buildInvoicePayload(
      cart: cart,
      invoiceType: invoiceType,
      paidAmount: paidAmount,
      paymentMode: paymentMode,
      payments: payments,
      notes: notes,
      localId: localId,
      invoiceDate: DateTime.now(),
    );

    try {
      final res =
          await _ref
                  .read(supabaseProvider)
                  .rpc('create_invoice', params: {'payload': payload})
                  .timeout(const Duration(seconds: 12))
              as Map<String, dynamic>;
      return BillResult(
        invoiceNo: res['invoice_no'] as String,
        invoiceId: res['id'] as String,
      );
    } catch (e) {
      final msg = e.toString();
      final isNetwork =
          msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('TimeoutException') ||
          msg.contains('Connection');
      final offlineAllowed =
          _ref.read(appContextProvider).value?.featureOn('offline_billing') ??
          true;
      if (!isNetwork || !offlineAllowed || invoiceType == 'estimate') rethrow;

      // Offline fallback: provisional number, marked as offline-created.
      final displayNo = 'OFF-${DateTime.now().millisecondsSinceEpoch % 100000}';
      await _ref
          .read(offlineServiceProvider)
          .savePendingBill(
            localId: localId,
            payload: {...payload, 'offline_created': true},
            displayNo: displayNo,
            total: cart.total,
            customerName: cart.customer?['name'] as String? ?? '',
          );
      return BillResult(invoiceNo: displayNo, offline: true);
    }
  }

  /// Saves edits to an already-issued invoice via `update_invoice`. Unlike
  /// [createBill] this always requires connectivity — there's no offline
  /// queue for edits, since merging an edit against a bill that might have
  /// changed elsewhere in the meantime is a much bigger problem than queuing
  /// a brand-new bill. `paid_amount`/`payment_mode`/`payments` are omitted:
  /// `update_invoice` never reads them — payments already recorded stay
  /// exactly as they were, only items/totals change.
  Future<BillResult> updateBill({
    required String invoiceId,
    required CartState cart,
    required String invoiceType,
    String notes = '',
  }) async {
    final payload = buildInvoicePayload(
      cart: cart,
      invoiceType: invoiceType,
      paidAmount: 0,
      paymentMode: 'cash',
      notes: notes,
    );
    final res =
        await _ref
                .read(supabaseProvider)
                .rpc(
                  'update_invoice',
                  params: {'p_invoice_id': invoiceId, 'payload': payload},
                )
                .timeout(const Duration(seconds: 12))
            as Map<String, dynamic>;
    return BillResult(
      invoiceNo: res['invoice_no'] as String,
      invoiceId: invoiceId,
    );
  }
}
