// Body / habit / meal helpers (src/data/repo.ts).
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/common.dart';
import 'package:repmate/data/services/repo.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

void main() {
  late Stores s;
  late Repo repo;
  final now = DateTime(2026, 12, 1, 13);
  const lunch = PlannedMeal(id: 'm1', dietPlanId: 'd', order: 2, time: '13:00', meal: 'Lunch', items: ['Dal'], proteinG: 30, kcal: 600);

  setUp(() {
    s = memoryStores();
    repo = Repo(s, newId: counterIds(), now: () => now);
  });
  tearDown(() => s.db.close());

  test('upsertBody keeps one row per day and patches only given fields', () async {
    await repo.upsertBody('2026-12-01', weightKg: 80, waistCm: 92);
    await repo.upsertBody('2026-12-01', weightKg: 79.6);
    final rows = await s.bodyLogs.all();
    expect(rows, hasLength(1));
    expect(rows.single.weightKg, 79.6);
    expect(rows.single.waistCm, 92);
    await repo.upsertBody('2026-12-01', clearWaist: true);
    expect((await repo.bodyFor('2026-12-01'))!.waistCm, isNull);
  });

  test('lastWeight / lastWaist pick the latest day that has the value', () async {
    await repo.upsertBody('2026-11-28', weightKg: 81, waistCm: 93);
    await repo.upsertBody('2026-12-01', weightKg: 80);
    await repo.upsertBody('2026-11-30', note: 'travel');
    expect(await repo.lastWeight(), 80);
    expect(await repo.lastWaist(), 93);
  });

  test('habits: set and read back, one row per day + habit', () async {
    expect(await repo.getHabit('2026-12-01', 'water'), 0);
    await repo.setHabit('2026-12-01', 'water', 250);
    await repo.setHabit('2026-12-01', 'water', 500);
    await repo.setHabit('2026-12-01', 'steps', 8000);
    expect(await repo.getHabit('2026-12-01', 'water'), 500);
    expect(await s.habitLogs.count(), 2);
  });

  test('logMeal: skipped logs zero, undo restores the previous state', () async {
    final undo1 = await repo.logMeal('2026-12-01', lunch, 'eaten');
    var log = (await s.mealLogs.all()).single;
    expect((log.kcal, log.proteinG, log.loggedAt), (600.0, 30.0, isoString(now)));
    final undo2 = await repo.logMeal('2026-12-01', lunch, 'skipped');
    log = (await s.mealLogs.all()).single;
    expect((log.state, log.kcal, log.proteinG), ('skipped', 0.0, 0.0));
    await undo2();
    expect((await s.mealLogs.all()).single.state, 'eaten');
    await undo1();
    expect(await s.mealLogs.count(), 0);

    await repo.logMeal('2026-12-01', lunch, 'swapped', label: 'Paneer wrap', proteinG: 28, chosenRotation: 'B');
    log = (await s.mealLogs.all()).single;
    expect((log.label, log.proteinG, log.kcal, log.chosenRotation), ('Paneer wrap', 28.0, 600.0, 'B'));
    final undo3 = await repo.clearMeal('2026-12-01', 'm1');
    expect(await s.mealLogs.count(), 0);
    await undo3();
    expect((await s.mealLogs.all()).single.label, 'Paneer wrap');
  });
}
