import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/platform.dart';

part 'local_db.g.dart';

/// Product rows cached for offline billing (PRD 7.10).
/// `data` is the full product JSON (including units + variants).
class CachedProducts extends Table {
  TextColumn get id => text()();
  TextColumn get data => text()();
  TextColumn get name => text()();
  TextColumn get barcode => text().withDefault(const Constant(''))();
  TextColumn get sku => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedCustomers extends Table {
  TextColumn get id => text()();
  TextColumn get data => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Bills created offline, waiting to sync (PRD 7.10).
class PendingBills extends Table {
  TextColumn get localId => text()();
  TextColumn get payload => text()(); // create_invoice RPC payload JSON
  TextColumn get displayNo => text()(); // provisional number shown to user
  RealColumn get total => real()();
  TextColumn get customerName => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending | failed
  TextColumn get error => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

@DriftDatabase(tables: [CachedProducts, CachedCustomers, PendingBills])
class LocalDb extends _$LocalDb {
  // drift_flutter's default location is the OS documents directory. On
  // Windows that folder is often redirected/synced (OneDrive) or otherwise
  // restricted, which caused SqliteException(14): "unable to open database
  // file" on every desktop launch — offline cache never worked there.
  // Desktop builds now use the per-app support directory instead
  // (guaranteed writable, not cloud-synced). Mobile keeps the original
  // documents-dir default so existing installs keep their cached data and
  // any queued offline bills.
  LocalDb()
      : super(driftDatabase(
          name: 'softraxa_local',
          native: isDesktopPlatform
              ? const DriftNativeOptions(
                  databaseDirectory: getApplicationSupportDirectory,
                )
              : null,
        ));

  @override
  int get schemaVersion => 1;
}

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb();
  ref.onDispose(db.close);
  return db;
});
