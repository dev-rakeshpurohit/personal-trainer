// Riverpod providers (src/data/hooks.ts counterparts) over an in-memory DB.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/session_service.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/state/providers.dart';

import '../data/harness.dart';

void main() {
  final seed = loadSeed();
  late Stores s;
  late ProviderContainer c;
  var now = DateTime(2026, 12, 3, 8); // Thursday

  setUp(() {
    s = memoryStores();
    now = DateTime(2026, 12, 3, 8);
    c = ProviderContainer.test(overrides: [
      storesProvider.overrideWithValue(s),
      clockProvider.overrideWithValue(() => now),
      idGenProvider.overrideWithValue(counterIds()),
      seedDataProvider.overrideWith((ref) async => seed),
    ]);
  });
  tearDown(() => s.db.close());

  Future<void> onboard({String onboardedAt = '2026-11-29T10:00:00.000Z'}) async {
    final b = await c.read(planBuilderProvider.future);
    await b.importProgramTemplate(trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat]);
    await b.importDietTemplate();
    await s.profile.put(backupProfile());
    await s.setMeta('onboardedAt', onboardedAt);
  }

  /// Latest value of a stream provider after pending writes have propagated.
  Future<T> latest<T>(ProviderListenable<AsyncValue<T>> p) async {
    final sub = c.listen(p, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 20 && !sub.read().hasValue; i++) {
      await pumpEventQueue();
    }
    await pumpEventQueue();
    return sub.read().requireValue;
  }

  test('profile: null before onboarding, then live', () async {
    final sub = c.listen(profileProvider, (_, _) {}, fireImmediately: true);
    expect(await c.read(profileProvider.future), isNull);
    await s.profile.put(backupProfile());
    await pumpEventQueue();
    expect(sub.read().value?.name, 'Test');
  });

  test('program bundle: days by weekday, planned by order; diet by time', () async {
    await onboard();
    final b = (await latest(programBundleProvider))!;
    expect(b.days.map((d) => d.weekday), kWeekdays);
    final orders = b.planned.map((p) => p.order).toList();
    expect(orders, [...orders]..sort());
    final tue = b.days.firstWhere((d) => d.weekday == Weekday.tue);
    expect(b.plannedFor(tue.id), hasLength(6));
    final diet = (await latest(dietProvider))!;
    expect(diet.meals.map((m) => m.time).toList(), [...diet.meals.map((m) => m.time)]..sort());
    expect((await latest(exerciseMapProvider)).containsKey('dumbbell-goblet-squat'), isTrue);
  });

  test('week plan: missed Tue/Wed move to Thu onwards; "keep original" switches it off; since counts', () async {
    await onboard();
    final day = DateTime(2026, 12, 3);
    var w = (await latest(weekPlanProvider(day)))!;
    expect(w.off, isFalse);
    expect(w.adjusted, isTrue);
    expect(w.missed.map((m) => m.date), ['2026-12-01', '2026-12-02']);
    expect(w.byDate['2026-12-03']!.title, contains('Strength A'));

    await s.setMeta(replanOffKey(day), true);
    w = (await latest(weekPlanProvider(day)))!;
    expect(w.off, isTrue);
    expect(w.adjusted, isFalse);
    expect(w.byDate['2026-12-03']!.id, w.original['2026-12-03']!.id);
    expect(w.missed, hasLength(2));
    expect(w.dropped, isEmpty);
  });

  test('week plan: days before onboarding are never missed', () async {
    await onboard(onboardedAt: DateTime(2026, 12, 3, 7).toUtc().toIso8601String());
    final w = (await latest(weekPlanProvider(DateTime(2026, 12, 3))))!;
    expect(w.missed, isEmpty);
    expect(w.adjusted, isFalse);
  });

  test('active session, player state and today sessions follow the workout', () async {
    await onboard();
    expect(await latest(activeSessionProvider), isNull);
    final svc = c.read(sessionServiceProvider);
    final w = (await latest(weekPlanProvider(DateTime(2026, 12, 3))))!;
    final day = w.byDate['2026-12-03']!;
    final p = (await svc.prepareSession(day.id, SessionMode.full))!;
    final id = await svc.startSession(p, SessionMode.full);
    expect((await latest(activeSessionProvider))!.session.id, id);
    expect((await latest(todaySessionsProvider)).map((x) => x.id), [id]);
    await svc.logAndAdvance(0, 0, const SetValues(weightKg: 16, reps: 8));
    final st = (await latest(playerStateProvider))!;
    expect(st.sets, hasLength(1));
    expect(st.idx, 1);
    await svc.finishSession(id);
    expect(await latest(activeSessionProvider), isNull);
    // the make-up session counts: Tuesday is no longer missed and today shows its original day
    final w2 = (await latest(weekPlanProvider(DateTime(2026, 12, 3))))!;
    expect(w2.missed.map((m) => m.date), ['2026-12-02']);
    expect(w2.byDate['2026-12-03']!.id, w2.original['2026-12-03']!.id);
  });

  test('day logs and habit defs', () async {
    await onboard();
    final repo = c.read(repoProvider);
    await repo.setHabit('2026-12-03', 'water', 500);
    await repo.upsertBody('2026-12-03', weightKg: 79.5);
    expect((await latest(habitLogsForDayProvider('2026-12-03'))).single.value, 500);
    expect((await latest(habitDefsProvider)).map((h) => h.order), [0, 1, 2, 3, 4]);
    expect((await latest(bodyLogsProvider)).single.weightKg, 79.5);
    expect(await latest(metaProvider('onboardedAt')), '2026-11-29T10:00:00.000Z');
  });
}
