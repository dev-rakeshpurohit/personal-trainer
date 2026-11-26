// Riverpod providers: the Flutter counterpart of src/data/hooks.ts. Keep these thin; logic lives in
// data/services and domain/. Every reactive provider re-runs only when one of the stores it reads
// is written (see Stores.live).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_db.dart';
import '../data/db/store.dart';
import '../data/seed/library_builder.dart';
import '../data/seed/seed_loader.dart';
import '../data/services/backup_service.dart';
import '../data/services/coach_client.dart';
import '../data/services/common.dart';
import '../data/services/library_service.dart';
import '../data/services/plan_builder.dart';
import '../data/services/plan_edit.dart';
import '../data/services/progression_data.dart';
import '../data/services/repo.dart';
import '../data/services/session_service.dart';
import '../domain/models.dart';
import '../domain/replan.dart';
import '../domain/schedule.dart';

/* ------------------------------------------------------------ infrastructure (override in tests) */

/// The local database. Tests override with `Stores(AppDb(NativeDatabase.memory()))`.
final storesProvider = Provider<Stores>((ref) {
  final db = AppDb();
  ref.onDispose(db.close);
  return Stores(db);
});

/// "Now" for services and date-dependent providers.
final clockProvider = Provider<Clock>((ref) => systemNow);

/// Id generator (uuid v4).
final idGenProvider = Provider<IdGen>((ref) => defaultIdGen);

/// Every bundled seed, parsed once.
final seedDataProvider = FutureProvider<SeedData>((ref) => SeedLoader().load());

/* ------------------------------------------------------------ services */

final libraryServiceProvider = FutureProvider<LibraryService>(
  (ref) async => LibraryService(ref.watch(storesProvider), await ref.watch(seedDataProvider.future)),
);

final planBuilderProvider = FutureProvider<PlanBuilder>(
  (ref) async => PlanBuilder(
    ref.watch(storesProvider),
    await ref.watch(seedDataProvider.future),
    newId: ref.watch(idGenProvider),
    now: ref.watch(clockProvider),
  ),
);

final planEditProvider = Provider<PlanEdit>((ref) => PlanEdit(ref.watch(storesProvider), newId: ref.watch(idGenProvider)));

final repoProvider = Provider<Repo>((ref) => Repo(ref.watch(storesProvider), newId: ref.watch(idGenProvider), now: ref.watch(clockProvider)));

final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(ref.watch(storesProvider), newId: ref.watch(idGenProvider), now: ref.watch(clockProvider)),
);

final progressionDataProvider = Provider<ProgressionData>((ref) => ProgressionData(ref.watch(storesProvider)));

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(storesProvider), now: ref.watch(clockProvider)));

final coachClientProvider = Provider<CoachClient>((ref) {
  final c = CoachClient(ref.watch(storesProvider), now: ref.watch(clockProvider));
  ref.onDispose(c.client.close);
  return c;
});

/* ------------------------------------------------------------ hooks.ts */

/// The profile; null = not onboarded (useProfile).
final profileProvider = StreamProvider<Profile?>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'profile'}, () => s.profile.get(Profile.id));
});

/// Active program with its days (by weekday) and planned exercises (by order).
class ProgramBundle {
  const ProgramBundle({required this.program, required this.days, required this.planned});
  final Program program;
  final List<ProgramDay> days;
  final List<PlannedExercise> planned;

  List<PlannedExercise> plannedFor(String dayId) => planned.where((p) => p.dayId == dayId).toList();
}

Future<ProgramBundle?> loadProgramBundle(Stores s) async {
  final program = await s.activeProgram();
  if (program == null) return null;
  final days = (await s.programDays.whereK1(program.id))..sort((a, b) => a.weekday.index - b.weekday.index);
  final planned = (await s.plannedExercises.whereK1In(days.map((d) => d.id)))..sort((a, b) => a.order - b.order);
  return ProgramBundle(program: program, days: days, planned: planned);
}

/// useProgram: null = no active program.
final programBundleProvider = StreamProvider<ProgramBundle?>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'programs', 'programDays', 'plannedExercises'}, () => loadProgramBundle(s));
});

/// useExerciseMap: every library exercise by id.
final exerciseMapProvider = StreamProvider<Map<String, Exercise>>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'exercises'}, () async => {for (final e in await s.exercises.all()) e.id: e});
});

/// Active diet plan with its meals (by time, then order).
class DietBundle {
  const DietBundle({required this.plan, required this.meals});
  final DietPlan plan;
  final List<PlannedMeal> meals;
}

/// useDiet: null = no active diet.
final dietProvider = StreamProvider<DietBundle?>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'dietPlans', 'plannedMeals'}, () async {
    final plan = await s.activeDiet();
    if (plan == null) return null;
    final meals = (await s.plannedMeals.whereK1(plan.id))
      ..sort((a, b) {
        final c = a.time.compareTo(b.time);
        return c != 0 ? c : a.order - b.order;
      });
    return DietBundle(plan: plan, meals: meals);
  });
});

/// Meta key of "Keep original plan" for the week of [date].
String replanOffKey(DateTime date) => 'replanOff:${dayKey(weekStartOf(date))}';

/// This week's plan with the auto re-plan applied, or the original plan when the user kept it ([off]).
class LiveWeekPlan extends WeekPlan {
  const LiveWeekPlan({
    required super.byDate,
    required super.original,
    required super.missed,
    required super.dropped,
    required super.adjusted,
    required this.off,
  });
  final bool off;
}

/// useWeekPlan(date): pass a local date (the time of day is ignored). Null when there is no program.
final weekPlanProvider = StreamProvider.family<LiveWeekPlan?, DateTime>((ref, date) async* {
  final s = ref.watch(storesProvider);
  final bundle = await ref.watch(programBundleProvider.future);
  final day = dateOnly(date);
  final dates = weekDates(day).map(dayKey).toList();
  final stream = s.live({'sessions', 'meta'}, () async {
    final sessions = await s.sessions.k1Between(dates.first, dates.last);
    final off = (await s.getMeta<Object?>(replanOffKey(day))) == true;
    final since = await s.getMeta<String>('onboardedAt');
    return (
      since: since,
      done: [for (final x in sessions) if (x.status == 'done') (programDayId: x.programDayId, dayKey: x.dayKey)],
      off: off,
    );
  });
  await for (final data in stream) {
    if (bundle == null) {
      yield null;
      continue;
    }
    final plan = replanWeek(days: bundle.days, today: day, done: data.done, since: data.since == null ? null : parseIsoLocal(data.since!));
    yield data.off
        ? LiveWeekPlan(byDate: plan.original, original: plan.original, missed: plan.missed, dropped: const [], adjusted: false, off: true)
        : LiveWeekPlan(byDate: plan.byDate, original: plan.original, missed: plan.missed, dropped: plan.dropped, adjusted: plan.adjusted, off: false);
  }
});

/// useActiveSession: the live workout, or null.
final activeSessionProvider = StreamProvider<ActiveSessionView?>((ref) {
  final s = ref.watch(storesProvider);
  final svc = ref.watch(sessionServiceProvider);
  return s.live({'activeSession', 'sessions'}, svc.activeSession);
});

/// The Player's full state (active session + its logged sets), for resume and live updates.
final playerStateProvider = StreamProvider<PlayerState?>((ref) {
  final s = ref.watch(storesProvider);
  final svc = ref.watch(sessionServiceProvider);
  return s.live({'activeSession', 'sessions', 'sets'}, svc.resume);
});

/* ------------------------------------------------------------ day / log queries */

/// Sessions on a day (yyyy-MM-dd).
final sessionsForDayProvider = StreamProvider.family<List<Session>, String>((ref, key) {
  final s = ref.watch(storesProvider);
  return s.live({'sessions'}, () => s.sessions.whereK1(key));
});

/// Today's sessions (by the clock at build time).
final todaySessionsProvider = Provider<AsyncValue<List<Session>>>((ref) {
  final today = dayKey(ref.watch(clockProvider)());
  return ref.watch(sessionsForDayProvider(today));
});

/// Sessions of the week containing a date (Train tab).
final weekSessionsProvider = StreamProvider.family<List<Session>, DateTime>((ref, date) {
  final s = ref.watch(storesProvider);
  final dates = weekDates(dateOnly(date)).map(dayKey).toList();
  return s.live({'sessions'}, () => s.sessions.k1Between(dates.first, dates.last));
});

/// Every completed session (streaks, history).
final doneSessionsProvider = StreamProvider<List<Session>>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'sessions'}, () async => (await s.sessions.whereK2('done'))..sort((a, b) => a.startedAt.compareTo(b.startedAt)));
});

/// Sets logged in a session.
final sessionSetsProvider = StreamProvider.family<List<SetLog>, String>((ref, sessionId) {
  final s = ref.watch(storesProvider);
  return s.live({'sets'}, () async => (await s.sets.whereK1(sessionId))..sort((a, b) => a.setIndex - b.setIndex));
});

/// Meal logs of a day.
final mealLogsForDayProvider = StreamProvider.family<List<MealLog>, String>((ref, key) {
  final s = ref.watch(storesProvider);
  return s.live({'mealLogs'}, () => s.mealLogs.whereK1(key));
});

/// Habit logs of a day.
final habitLogsForDayProvider = StreamProvider.family<List<HabitLog>, String>((ref, key) {
  final s = ref.watch(storesProvider);
  return s.live({'habitLogs'}, () => s.habitLogs.whereK1(key));
});

/// Habit definitions (by order).
final habitDefsProvider = StreamProvider<List<HabitDef>>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'habitDefs'}, () async => (await s.habitDefs.all())..sort((a, b) => a.order - b.order));
});

/// Body logs, oldest first.
final bodyLogsProvider = StreamProvider<List<BodyLog>>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'bodyLogs'}, () async => (await s.bodyLogs.all())..sort((a, b) => a.dayKey.compareTo(b.dayKey)));
});

/// One meta value (e.g. 'onboardedAt', 'lastBackupAt', 'gymClosedDay').
final metaProvider = StreamProvider.family<Object?, String>((ref, key) {
  final s = ref.watch(storesProvider);
  return s.live({'meta'}, () => s.getMeta<Object?>(key));
});
