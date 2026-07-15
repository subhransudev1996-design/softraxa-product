import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import 'local_db.dart';

/// true when the device reports an active network.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  yield !(await Connectivity().checkConnectivity()).contains(ConnectivityResult.none);
  await for (final results in Connectivity().onConnectivityChanged) {
    yield !results.contains(ConnectivityResult.none);
  }
});

final offlineServiceProvider = Provider<OfflineService>((ref) {
  final service = OfflineService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Handles the offline-billing fallback (PRD 7.10):
/// - caches products & customers locally for offline search
/// - stores bills created offline and syncs them when internet returns
class OfflineService {
  OfflineService(this._ref) {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        syncPendingBills();
      }
    });
  }

  final Ref _ref;
  StreamSubscription? _sub;
  bool _syncing = false;

  LocalDb get _db => _ref.read(localDbProvider);

  void dispose() => _sub?.cancel();

  // ---------- Product / customer cache ----------

  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.cachedProducts, [
        for (final p in products)
          CachedProductsCompanion.insert(
            id: p['id'] as String,
            data: jsonEncode(p),
            name: (p['name'] as String? ?? '').toLowerCase(),
            barcode: Value(p['barcode'] as String? ?? ''),
            sku: Value((p['sku'] as String? ?? '').toLowerCase()),
            updatedAt: now,
          ),
      ]);
    });
  }

  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) async {
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.cachedCustomers, [
        for (final c in customers)
          CachedCustomersCompanion.insert(
            id: c['id'] as String,
            data: jsonEncode(c),
            name: (c['name'] as String? ?? '').toLowerCase(),
            phone: Value(c['phone'] as String? ?? ''),
            updatedAt: now,
          ),
      ]);
    });
  }

  Future<List<Map<String, dynamic>>> searchCachedProducts(String search) async {
    final q = search.trim().toLowerCase();
    final query = _db.select(_db.cachedProducts)
      ..orderBy([(t) => OrderingTerm.asc(t.name)])
      ..limit(100);
    if (q.isNotEmpty) {
      query.where((t) =>
          t.name.contains(q) | t.barcode.contains(q) | t.sku.contains(q));
    }
    final rows = await query.get();
    return [
      for (final r in rows) Map<String, dynamic>.from(jsonDecode(r.data) as Map)
    ];
  }

  Future<Map<String, dynamic>?> findCachedByBarcode(String code) async {
    final rows = await (_db.select(_db.cachedProducts)
          ..where((t) => t.barcode.equals(code))
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(jsonDecode(rows.first.data) as Map);
  }

  Future<List<Map<String, dynamic>>> searchCachedCustomers(String search) async {
    final q = search.trim().toLowerCase();
    final query = _db.select(_db.cachedCustomers)
      ..orderBy([(t) => OrderingTerm.asc(t.name)])
      ..limit(50);
    if (q.isNotEmpty) {
      query.where((t) => t.name.contains(q) | t.phone.contains(q));
    }
    final rows = await query.get();
    return [
      for (final r in rows) Map<String, dynamic>.from(jsonDecode(r.data) as Map)
    ];
  }

  // ---------- Pending bill queue ----------

  Future<void> savePendingBill({
    required String localId,
    required Map<String, dynamic> payload,
    required String displayNo,
    required double total,
    required String customerName,
  }) async {
    await _db.into(_db.pendingBills).insert(PendingBillsCompanion.insert(
          localId: localId,
          payload: jsonEncode(payload),
          displayNo: displayNo,
          total: total,
          customerName: Value(customerName),
          createdAt: DateTime.now(),
        ));
  }

  Future<List<PendingBill>> pendingBills() =>
      (_db.select(_db.pendingBills)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<int> pendingCount() async =>
      (await _db.select(_db.pendingBills).get()).length;

  /// Push all pending bills to the server. `create_invoice` is idempotent on
  /// local_id, so retries can never create duplicates (PRD 7.10).
  Future<void> syncPendingBills() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final client = _ref.read(supabaseProvider);
      if (client.auth.currentUser == null) return;
      final bills = await pendingBills();
      for (final bill in bills) {
        try {
          await client.rpc('create_invoice', params: {
            'payload': jsonDecode(bill.payload),
          });
          await (_db.delete(_db.pendingBills)
                ..where((t) => t.localId.equals(bill.localId)))
              .go();
        } catch (e) {
          final msg = e.toString();
          final isNetwork = msg.contains('SocketException') ||
              msg.contains('Failed host lookup') ||
              msg.contains('Connection');
          if (isNetwork) break; // still offline — try again later
          // Server rejected the bill: keep it, mark failed for review.
          await (_db.update(_db.pendingBills)
                ..where((t) => t.localId.equals(bill.localId)))
              .write(PendingBillsCompanion(
                  status: const Value('failed'), error: Value(msg)));
        }
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> deletePendingBill(String localId) async {
    await (_db.delete(_db.pendingBills)..where((t) => t.localId.equals(localId))).go();
  }
}

final pendingBillCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(offlineServiceProvider).pendingCount();
});
