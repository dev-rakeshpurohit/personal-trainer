// Typed collections over the document table (the Dexie-like API the rest of the app uses).
import 'dart:convert';

import 'dart:async';

import 'package:drift/drift.dart';

import '../../domain/models.dart';
import 'app_db.dart';

/// Index keys per store: k1 / k2 (mirrors the Dexie indexes the PWA queries by).
class StoreKeys<T> {
  const StoreKeys(this.k1, [this.k2]);
  final String? Function(T)? k1;
  final String? Function(T)? k2;
}

class Collection<T> {
  Collection(this.db, this.name, this.fromJson, this.toJson, this.idOf, [this.keys = const StoreKeys(null)]);

  final AppDb db;
  final String name;
  final T Function(Map<String, Object?>) fromJson;
  final Map<String, Object?> Function(T) toJson;
  final String Function(T) idOf;
  final StoreKeys<T> keys;

  /// Called after every write through this collection (set by [Stores] to drive [Stores.live]).
  void Function(String store)? onWrite;

  // The statement is dispatched before the counter moves (the argument is evaluated first), and drift
  // runs statements in order, so a live query started after the bump always sees this write.
  Future<V> _w<V>(Future<V> f) {
    onWrite?.call(name);
    return f;
  }

  T _decode(DocRow r) => fromJson((jsonDecode(r.data) as Map).cast<String, Object?>());

  DocsCompanion _row(T v) => DocsCompanion.insert(
        store: name,
        id: idOf(v),
        k1: Value(keys.k1?.call(v)),
        k2: Value(keys.k2?.call(v)),
        data: jsonEncode(toJson(v)),
      );

  SimpleSelectStatement<$DocsTable, DocRow> _q() => db.select(db.docs)..where((t) => t.store.equals(name));

  Future<T?> get(String id) async {
    final r = await (_q()..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _decode(r);
  }

  Future<List<T?>> bulkGet(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return [];
    final rows = await (_q()..where((t) => t.id.isIn(list))).get();
    final by = {for (final r in rows) r.id: _decode(r)};
    return [for (final id in list) by[id]];
  }

  Future<List<T>> all() async => (await _q().get()).map(_decode).toList();
  Future<List<T>> whereK1(String v) async => (await (_q()..where((t) => t.k1.equals(v))).get()).map(_decode).toList();
  Future<List<T>> whereK1In(Iterable<String> vs) async {
    final l = vs.toList();
    if (l.isEmpty) return [];
    return (await (_q()..where((t) => t.k1.isIn(l))).get()).map(_decode).toList();
  }

  Future<List<T>> whereK2(String v) async => (await (_q()..where((t) => t.k2.equals(v))).get()).map(_decode).toList();
  Future<List<T>> k1Between(String lo, String hi) async =>
      (await (_q()..where((t) => t.k1.isBetweenValues(lo, hi))).get()).map(_decode).toList();
  Future<int> count() async {
    final c = countAll();
    final q = db.selectOnly(db.docs)
      ..addColumns([c])
      ..where(db.docs.store.equals(name));
    return (await q.getSingle()).read(c) ?? 0;
  }

  Future<List<String>> ids() async {
    final q = db.selectOnly(db.docs)
      ..addColumns([db.docs.id])
      ..where(db.docs.store.equals(name));
    return (await q.get()).map((r) => r.read(db.docs.id)!).toList();
  }

  Stream<T?> watchOne(String id) => (_q()..where((t) => t.id.equals(id))).watchSingleOrNull().map((r) => r == null ? null : _decode(r));
  Stream<List<T>> watchAll() => _q().watch().map((rows) => rows.map(_decode).toList());
  Stream<List<T>> watchK1(String v) => (_q()..where((t) => t.k1.equals(v))).watch().map((rows) => rows.map(_decode).toList());
  Stream<List<T>> watchK1In(Iterable<String> vs) {
    final l = vs.toList();
    return (_q()..where((t) => t.k1.isIn(l))).watch().map((rows) => rows.map(_decode).toList());
  }

  Stream<List<T>> watchK1Between(String lo, String hi) =>
      (_q()..where((t) => t.k1.isBetweenValues(lo, hi))).watch().map((rows) => rows.map(_decode).toList());

  Future<void> put(T v) => _w(db.into(db.docs).insertOnConflictUpdate(_row(v)));
  Future<void> putAll(Iterable<T> vs) => _w(db.batch((b) => b.insertAllOnConflictUpdate(db.docs, vs.map(_row).toList())));

  /// Insert only rows whose id doesn't exist yet.
  Future<void> addMissing(Iterable<T> vs) =>
      _w(db.batch((b) => b.insertAll(db.docs, vs.map(_row).toList(), mode: InsertMode.insertOrIgnore)));
  Future<void> delete(String id) => _w((db.delete(db.docs)..where((t) => t.store.equals(name) & t.id.equals(id))).go());
  Future<void> deleteWhereK1(String v) => _w((db.delete(db.docs)..where((t) => t.store.equals(name) & t.k1.equals(v))).go());
  Future<void> clear() => _w((db.delete(db.docs)..where((t) => t.store.equals(name))).go());

  /// Read-modify-write one record (no-op when missing).
  Future<T?> update(String id, T Function(T) change) async {
    final cur = await get(id);
    if (cur == null) return null;
    final next = change(cur);
    await put(next);
    return next;
  }

  /// Dexie-style `update(id, patch)` on the JSON shape: keys set to null are removed (like
  /// `undefined` in the PWA), other keys are replaced. No-op (returns null) when the row is missing.
  Future<T?> patch(String id, Map<String, Object?> changes) =>
      update(id, (cur) => fromJson({...toJson(cur), ...changes}..removeWhere((_, v) => v == null)));
}

/// A free-form key/value row (the PWA's `meta` store).
class MetaEntry {
  const MetaEntry(this.key, this.value);
  final String key;
  final Object? value;
  factory MetaEntry.fromJson(Map<String, Object?> j) => MetaEntry(j['key'] as String, j['value']);
  Map<String, Object?> toJson() => {'key': key, 'value': value};
}

/// All stores, named exactly like the PWA's Dexie tables (backups use these names).
class Stores {
  Stores(this.db)
      : profile = Collection(db, 'profile', Profile.fromJson, (p) => p.toJson(), (_) => Profile.id),
        exercises = Collection(db, 'exercises', Exercise.fromJson, (e) => e.toJson(), (e) => e.id, StoreKeys((e) => e.name.toLowerCase())),
        programs = Collection(db, 'programs', Program.fromJson, (p) => p.toJson(), (p) => p.id, StoreKeys((p) => p.active ? '1' : '0')),
        programDays = Collection(db, 'programDays', ProgramDay.fromJson, (d) => d.toJson(), (d) => d.id, StoreKeys((d) => d.programId)),
        plannedExercises =
            Collection(db, 'plannedExercises', PlannedExercise.fromJson, (p) => p.toJson(), (p) => p.id, StoreKeys((p) => p.dayId, (p) => p.exerciseId)),
        sessions = Collection(db, 'sessions', Session.fromJson, (s) => s.toJson(), (s) => s.id, StoreKeys((s) => s.dayKey, (s) => s.status)),
        sets = Collection(db, 'sets', SetLog.fromJson, (s) => s.toJson(), (s) => s.id, StoreKeys((s) => s.sessionId, (s) => s.exerciseId)),
        activeSession = Collection(db, 'activeSession', ActiveSessionState.fromJson, (s) => s.toJson(), (_) => ActiveSessionState.id),
        dietPlans = Collection(db, 'dietPlans', DietPlan.fromJson, (d) => d.toJson(), (d) => d.id, StoreKeys((d) => d.active ? '1' : '0')),
        plannedMeals = Collection(db, 'plannedMeals', PlannedMeal.fromJson, (m) => m.toJson(), (m) => m.id, StoreKeys((m) => m.dietPlanId)),
        mealLogs = Collection(db, 'mealLogs', MealLog.fromJson, (m) => m.toJson(), (m) => m.id, StoreKeys((m) => m.dayKey, (m) => m.plannedMealId)),
        habitDefs = Collection(db, 'habitDefs', HabitDef.fromJson, (h) => h.toJson(), (h) => h.id),
        habitLogs = Collection(db, 'habitLogs', HabitLog.fromJson, (h) => h.toJson(), (h) => h.id, StoreKeys((h) => h.dayKey, (h) => h.habitId)),
        bodyLogs = Collection(db, 'bodyLogs', BodyLog.fromJson, (b) => b.toJson(), (b) => b.id, StoreKeys((b) => b.dayKey)),
        photos = Collection(db, 'photos', Photo.fromJson, (p) => p.toJson(), (p) => p.id, StoreKeys((p) => p.dayKey)),
        media = Collection(db, 'media', MediaBlob.fromJson, (m) => m.toJson(), (m) => m.id, StoreKeys((m) => m.kind)),
        clips = Collection(db, 'clips', ExerciseClip.fromJson, (c) => c.toJson(), (c) => c.exerciseId),
        meta = Collection(db, 'meta', MetaEntry.fromJson, (m) => m.toJson(), (m) => m.key) {
    for (final c in _all) {
      c.onWrite = _bump;
    }
  }

  final AppDb db;
  final Collection<Profile> profile;
  final Collection<Exercise> exercises;
  final Collection<Program> programs;
  final Collection<ProgramDay> programDays;
  final Collection<PlannedExercise> plannedExercises;
  final Collection<Session> sessions;
  final Collection<SetLog> sets;
  final Collection<ActiveSessionState> activeSession;
  final Collection<DietPlan> dietPlans;
  final Collection<PlannedMeal> plannedMeals;
  final Collection<MealLog> mealLogs;
  final Collection<HabitDef> habitDefs;
  final Collection<HabitLog> habitLogs;
  final Collection<BodyLog> bodyLogs;
  final Collection<Photo> photos;
  final Collection<MediaBlob> media;
  final Collection<ExerciseClip> clips;
  final Collection<MetaEntry> meta;

  // Only for store-independent members (name, onWrite): typed members like toJson can't be used through it.
  List<Collection<Object?>> get _all => [
        profile, exercises, programs, programDays, plannedExercises, sessions, sets, activeSession, dietPlans, //
        plannedMeals, mealLogs, habitDefs, habitLogs, bodyLogs, photos, media, clips, meta,
      ];

  final Map<String, int> _versions = {};

  void _bump(String store) => _versions[store] = (_versions[store] ?? 0) + 1;

  /// Write counter of a store (changes whenever a collection of that name is written).
  int versionOf(String store) => _versions[store] ?? 0;

  /// Reactive query: emits [query] now and again after each committed write that touched one of
  /// [stores] (store names, e.g. 'sessions'). All stores share one SQLite table, so this skips
  /// re-running a query when an unrelated store changed (e.g. the 1,320-row exercise list on a set log).
  Stream<R> live<R>(Set<String> stores, Future<R> Function() query) async* {
    int sig() => stores.fold(0, (a, s) => a + versionOf(s));
    var seen = sig();
    yield await query();
    await for (final _ in db.tableUpdates(TableUpdateQuery.onTable(db.docs))) {
      final now = sig();
      if (now == seen) continue;
      seen = now;
      yield await query();
    }
  }

  Future<T?> getMeta<T>(String key) async => (await meta.get(key))?.value as T?;
  Future<void> setMeta(String key, Object? value) => meta.put(MetaEntry(key, value));

  /// Run several writes atomically.
  Future<R> transaction<R>(Future<R> Function() body) => db.transaction(body);

  Future<Program?> activeProgram() async {
    final l = await programs.whereK1('1');
    return l.isEmpty ? null : l.first;
  }

  Future<DietPlan?> activeDiet() async {
    final l = await dietPlans.whereK1('1');
    return l.isEmpty ? null : l.first;
  }
}
