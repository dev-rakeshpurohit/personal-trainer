// Local database (SQLite via drift). Mirrors the web app's Dexie stores as a document table:
// every record keeps the exact JSON shape of the PWA (so backups are interchangeable), plus up to
// two indexed keys per store for fast lookups. Reactive reads use drift's watch() streams.
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_db.g.dart';

@DataClassName('DocRow')
class Docs extends Table {
  /// Store name, e.g. 'exercises', 'sets'.
  TextColumn get store => text()();
  TextColumn get id => text()();

  /// Secondary keys (store-specific, see [kStoreKeys]).
  TextColumn get k1 => text().nullable()();
  TextColumn get k2 => text().nullable()();

  /// The record as JSON.
  TextColumn get data => text()();

  @override
  Set<Column> get primaryKey => {store, id};
}

@DriftDatabase(tables: [Docs])
class AppDb extends _$AppDb {
  AppDb([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'repmate'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX IF NOT EXISTS docs_k1 ON docs (store, k1)');
          await customStatement('CREATE INDEX IF NOT EXISTS docs_k2 ON docs (store, k2)');
        },
      );
}
