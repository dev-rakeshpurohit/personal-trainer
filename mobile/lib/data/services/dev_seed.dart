// Port of src/data/devSeed.ts. Dev-only: replaces logs with ~30 days of realistic demo data so every
// chart and coach card can be checked (screenshots, tests). Never touches the plan or profile
// (except the program's start date, moved to the start of the demo period).
import 'dart:math' as math;

import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/schedule.dart';
import '../db/store.dart';
import 'common.dart';

/// The PWA's seeded LCG (same sequence for the same seed).
double Function() demoRng(int seed) {
  var s = seed;
  return () {
    s = (s * 1664525 + 1013904223) % 4294967296;
    return s / 4294967296;
  };
}

final _barbell = RegExp('barbell|trap', caseSensitive: false);
final _compound = RegExp('press|row|pulldown|leg', caseSensitive: false);

double _r1(double x) => jsRound(x * 10) / 10;

Future<({int sessions, int sets, int weighIns})> seedDemoData(Stores s, {int days = 30, DateTime? today, IdGen? newId}) async {
  final id = newId ?? defaultIdGen;
  final now = today ?? DateTime.now();
  final rand = demoRng(42);
  final profile = await s.profile.get(Profile.id);
  final program = await s.activeProgram();
  if (profile == null || program == null) throw StateError('Finish onboarding first');
  final programDays = await s.programDays.whereK1(program.id);
  final planned = (await s.plannedExercises.whereK1In(programDays.map((d) => d.id)))..sort((a, b) => a.order - b.order);
  final exercises = {for (final e in await s.exercises.all()) e.id: e};
  final diet = await s.activeDiet();
  final meals = diet == null ? <PlannedMeal>[] : ((await s.plannedMeals.whereK1(diet.id))..sort((a, b) => a.order - b.order));
  final start = addDays(now, -days);

  await s.transaction(() async {
    for (final c in [s.sessions.clear, s.sets.clear, s.mealLogs.clear, s.habitLogs.clear, s.bodyLogs.clear, s.activeSession.clear]) {
      await c();
    }
    await s.programs.put(program.copyWith(startedOn: dayKey(weekStartOf(start, weekStart: 'mon'))));
    await s.setMeta('onboardedAt', isoString(start));
    await s.setMeta('lastBackupAt', isoString(addDays(now, -35)));

    final body = <BodyLog>[];
    final sessions = <Session>[];
    final sets = <SetLog>[];
    final mealLogs = <MealLog>[];
    final habits = <HabitLog>[];
    final baseW = profile.startWeightKg + 0.8;
    final sessionCount = <String, int>{};

    for (var i = 0; i < days; i++) {
      final d = addDays(start, i);
      final k = dayKey(d);
      final waist = i % 14 == 0 ? _r1(92 - i * 0.07) : null;
      if (rand() < 0.8) {
        body.add(BodyLog(id: id(), dayKey: k, weightKg: _r1(baseW - 0.085 * i + (rand() - 0.5) * 0.6), waistCm: waist));
      } else if (i % 14 == 0) {
        body.add(BodyLog(id: id(), dayKey: k, waistCm: waist));
      }

      final day = getDayPlan(programDays, d, (x) => x.weekday);
      if (day != null && day.type.isTraining && rand() < 0.9) {
        final n = sessionCount[day.id] ?? 0;
        sessionCount[day.id] = n + 1;
        final startedAt = DateTime(d.year, d.month, d.day, 9, 15);
        final endedAt = startedAt.add(Duration(minutes: 60 + jsRound(rand() * 20)));
        final rpe = 6 + jsRound(rand() * 3);
        final feel = rand() < 0.15 ? Feel.tooHard : Feel.justRight;
        final ss = Session(
          id: id(),
          dayKey: k,
          programDayId: day.id,
          title: day.title,
          startedAt: isoString(startedAt),
          endedAt: isoString(endedAt),
          status: 'done',
          cycleWeek: i ~/ 7 + 1,
          deload: false,
          mode: SessionMode.full,
          rpe: rpe,
          feedback: SessionFeedback(rpe: 7, feel: feel, pain: const [], disliked: const [], ranOutOfTime: false, energy: 'ok'),
        );
        sessions.add(ss);
        for (final pe in planned.where((p) => p.dayId == day.id)) {
          final ex = exercises[pe.exerciseId];
          final inc = ex != null ? incrementFor(ex, profile.stepKg) : 2.0;
          final name = ex?.name ?? '';
          final double? base = ex?.isBodyweight == true
              ? null
              : (_barbell.hasMatch(name) ? 40 : _compound.hasMatch(name) ? 14 : 10) + inc * (n ~/ 2);
          for (var si = 0; si < pe.sets; si++) {
            final t = startedAt.add(Duration(minutes: 6 + si * 3 + pe.order * 9));
            final span = pe.repsMax - pe.repsMin + 1;
            final reps = span <= 0 ? pe.repsMin : math.min(pe.repsMax, pe.repsMin + ((n + si) % span));
            sets.add(SetLog(
              id: id(),
              sessionId: ss.id,
              exerciseId: pe.exerciseId,
              plannedExerciseId: pe.id,
              setIndex: si,
              weightKg: base,
              reps: pe.unit == Unit.reps ? reps : null,
              seconds: pe.unit == Unit.seconds
                  ? (pe.repsMin + n * 3 < 60 ? pe.repsMin + n * 3 : 60)
                  : pe.unit == Unit.minutes
                      ? pe.repsMin * 60
                      : null,
              meters: pe.unit == Unit.meters ? pe.repsMin.toDouble() : null,
              rir: pe.unit == Unit.reps ? 2 : null,
              completedAt: isoString(t),
              isWarmup: false,
            ));
          }
        }
      }
      final rest = day == null || !day.type.isTraining;
      for (final m in meals) {
        if (rest && m.skipOnRestDay == true) continue;
        if (m.optional == true && rand() < 0.7) continue;
        final r = rand();
        final at = isoString(d);
        if (r < 0.82) {
          mealLogs.add(MealLog(id: id(), dayKey: k, plannedMealId: m.id, state: 'eaten', proteinG: m.proteinG, kcal: m.kcal, loggedAt: at));
        } else if (r < 0.9) {
          mealLogs.add(MealLog(
              id: id(),
              dayKey: k,
              plannedMealId: m.id,
              state: 'swapped',
              label: 'Something similar',
              proteinG: jsRound(m.proteinG * 0.8).toDouble(),
              kcal: m.kcal,
              loggedAt: at));
        } else if (r < 0.95) {
          mealLogs.add(MealLog(id: id(), dayKey: k, plannedMealId: m.id, state: 'skipped', proteinG: 0, kcal: 0, loggedAt: at));
        }
      }
      habits.add(HabitLog(id: id(), dayKey: k, habitId: 'water', value: (2000 + jsRound(rand() * 6) * 250).toDouble()));
      habits.add(HabitLog(id: id(), dayKey: k, habitId: 'steps', value: (5000 + jsRound(rand() * 12) * 500).toDouble()));
      habits.add(HabitLog(id: id(), dayKey: k, habitId: 'sleep', value: 6 + jsRound(rand() * 4) / 2));
      if (rand() < 0.85) habits.add(HabitLog(id: id(), dayKey: k, habitId: 'creatine', value: 1));
      if (rand() < 0.75) habits.add(HabitLog(id: id(), dayKey: k, habitId: 'oil', value: 1));
    }
    await s.bodyLogs.putAll(body);
    await s.sessions.putAll(sessions);
    await s.sets.putAll(sets);
    await s.mealLogs.putAll(mealLogs);
    await s.habitLogs.putAll(habits);
  });
  return (
    sessions: await s.sessions.count(),
    sets: await s.sets.count(),
    weighIns: (await s.bodyLogs.all()).where((b) => b.weightKg != null).length,
  );
}
