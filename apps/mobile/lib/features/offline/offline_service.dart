import 'dart:async';
import 'dart:convert';
import '../invoices/invoice_providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../products/product_providers.dart';
import '../stock/stock_screens.dart';
import '../pos/pos_providers.dart';
import '../customers/customer_providers.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network.dart';
import '../../core/supabase_providers.dart';
import 'local_db.dart';

/// true when the device reports an active network.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  yield !(await Connectivity().checkConnectivity()).contains(
    ConnectivityResult.none,
  );
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
  bool _catalogSyncing = false;
  DateTime? _lastCatalogSync;
  String? _lastCatalogUser;

  LocalDb get _db => _ref.read(localDbProvider);

  void dispose() => _sub?.cancel();

  // ---------- Product / customer cache ----------

  /// Downloads the whole active catalogue and customer list into this
  /// account's cache, page by page, then drops rows that no longer exist
  /// (finding 6: the cache used to hold only the first 100 products).
  /// Throttled; call freely. Failures leave the previous cache intact.
  Future<void> syncCatalog({bool force = false}) async {
    final client = _ref.read(supabaseProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null || _catalogSyncing) return;
    if (!force &&
        uid == _lastCatalogUser &&
        _lastCatalogSync != null &&
        DateTime.now().difference(_lastCatalogSync!) < const Duration(minutes: 10)) {
      return;
    }
    _catalogSyncing = true;
    final db = _db;
    final started = DateTime.now();
    const page = 500;
    try {
      for (var from = 0; ; from += page) {
        final rows = List<Map<String, dynamic>>.from(
          await client
              .from('products')
              .select(posProductColumns)
              .eq('is_active', true)
              .order('id')
              .range(from, from + page - 1),
        );
        await cacheProducts(rows, db: db, at: started);
        if (rows.length < page) break;
      }
      // Everything still active was re-stamped above; the rest is stale.
      await (db.delete(db.cachedProducts)
            ..where((t) => t.updatedAt.isSmallerThanValue(started)))
          .go();

      for (var from = 0; ; from += page) {
        final rows = List<Map<String, dynamic>>.from(
          await client
              .from('customers')
              .select('id, name, phone, address, due_amount, credit_limit, credit_unlimited')
              .eq('is_active', true)
              .order('id')
              .range(from, from + page - 1),
        );
        await cacheCustomers(rows, db: db, at: started);
        if (rows.length < page) break;
      }
      await (db.delete(db.cachedCustomers)
            ..where((t) => t.updatedAt.isSmallerThanValue(started)))
          .go();

      _lastCatalogSync = DateTime.now();
      _lastCatalogUser = uid;
    } catch (_) {
      // Offline or refused — keep the existing cache; retry later.
    } finally {
      _catalogSyncing = false;
    }
  }

  Future<void> cacheProducts(
    List<Map<String, dynamic>> products, {
    LocalDb? db,
    DateTime? at,
  }) async {
    final target = db ?? _db;
    final now = at ?? DateTime.now();
    await target.batch((b) {
      b.insertAllOnConflictUpdate(target.cachedProducts, [
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

  Future<void> cacheCustomers(
    List<Map<String, dynamic>> customers, {
    LocalDb? db,
    DateTime? at,
  }) async {
    final target = db ?? _db;
    final now = at ?? DateTime.now();
    await target.batch((b) {
      b.insertAllOnConflictUpdate(target.cachedCustomers, [
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
      query.where(
        (t) => t.name.contains(q) | t.barcode.contains(q) | t.sku.contains(q),
      );
    }
    final rows = await query.get();
    return [
      for (final r in rows)
        Map<String, dynamic>.from(jsonDecode(r.data) as Map),
    ];
  }

  Future<Map<String, dynamic>?> findCachedByBarcode(String code) async {
    final rows =
        await (_db.select(_db.cachedProducts)
              ..where((t) => t.barcode.equals(code))
              ..limit(1))
            .get();
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(jsonDecode(rows.first.data) as Map);
  }

  Future<List<Map<String, dynamic>>> searchCachedCustomers(
    String search,
  ) async {
    final q = search.trim().toLowerCase();
    final query = _db.select(_db.cachedCustomers)
      ..orderBy([(t) => OrderingTerm.asc(t.name)])
      ..limit(50);
    if (q.isNotEmpty) {
      query.where((t) => t.name.contains(q) | t.phone.contains(q));
    }
    final rows = await query.get();
    return [
      for (final r in rows)
        Map<String, dynamic>.from(jsonDecode(r.data) as Map),
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
    await _db
        .into(_db.pendingBills)
        .insert(
          PendingBillsCompanion.insert(
            localId: localId,
            payload: jsonEncode(payload),
            displayNo: displayNo,
            total: total,
            customerName: Value(customerName),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<List<PendingBill>> pendingBills() async {
    await _claimLegacyBills();
    return (_db.select(
      _db.pendingBills,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  Future<int> pendingCount() async => (await pendingBills()).length;

  /// One-time upgrade step: before per-account files, every account shared
  /// one database. Its queued bills are handed to the first account that
  /// signs in after the upgrade (on a single-user device, their creator),
  /// and the shared file is emptied so nothing can be replayed twice.
  static bool _legacyChecked = false;
  Future<void> _claimLegacyBills() async {
    if (_legacyChecked) return;
    final uid = _ref.read(supabaseProvider).auth.currentUser?.id;
    if (uid == null) return;
    _legacyChecked = true;
    const doneKey = 'offline_legacy_bills_claimed';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(doneKey) ?? false) return;
      final legacy = LocalDb.legacyShared();
      try {
        final bills = await legacy.select(legacy.pendingBills).get();
        if (bills.isNotEmpty) {
          await _db.batch((b) {
            b.insertAll(_db.pendingBills, bills, mode: InsertMode.insertOrIgnore);
          });
        }
        await legacy.delete(legacy.pendingBills).go();
        await legacy.delete(legacy.cachedProducts).go();
        await legacy.delete(legacy.cachedCustomers).go();
      } finally {
        await legacy.close();
      }
      await prefs.setBool(doneKey, true);
    } catch (_) {
      _legacyChecked = false; // try again next time
    }
  }

  /// Push this account's pending bills to the server. `create_invoice` is
  /// idempotent on local_id, so retries never create duplicates (PRD 7.10).
  /// Bills live in their creator's database, so they are only ever sent
  /// under the account that made them.
  Future<void> syncPendingBills() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final client = _ref.read(supabaseProvider);
      if (client.auth.currentUser == null) return;
      final db = _db;
      final bills = await pendingBills();
      var synced = 0;
      for (final bill in bills) {
        try {
          await client.rpc(
            'create_invoice',
            params: {'payload': jsonDecode(bill.payload)},
          );
          await (db.delete(
            db.pendingBills,
          )..where((t) => t.localId.equals(bill.localId))).go();
          synced++;
        } catch (e) {
          if (isNetworkError(e)) break; // still offline — try again later
          // Server rejected the bill: keep it, mark failed for review.
          await (db.update(
            db.pendingBills,
          )..where((t) => t.localId.equals(bill.localId))).write(
            PendingBillsCompanion(
              status: const Value('failed'),
              error: Value(e.toString()),
            ),
          );
        }
      }
      // Replayed bills changed invoices, stock, dues and the pending badge
      // on the server — refresh every screen that shows them (kept-alive
      // tabs never refetch on their own).
      if (synced > 0) {
        _ref.invalidate(invoicesProvider);
        _ref.invalidate(recentInvoicesProvider);
        _ref.invalidate(dashboardStatsProvider);
        _ref.invalidate(productsProvider);
        _ref.invalidate(stockListProvider);
        _ref.invalidate(posProductsProvider);
        _ref.invalidate(customersProvider);
        _ref.invalidate(pendingBillCountProvider);
      }
    } finally {
      _syncing = false;
    }
    unawaited(syncCatalog());
  }

  Future<void> deletePendingBill(String localId) async {
    await (_db.delete(
      _db.pendingBills,
    )..where((t) => t.localId.equals(localId))).go();
  }
}

final pendingBillCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(offlineServiceProvider).pendingCount();
});
