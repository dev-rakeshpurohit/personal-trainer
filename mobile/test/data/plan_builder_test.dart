// Parity with src/data/plan-builder.test.ts, plus the AI coach writers and blank program.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/seed/library_builder.dart';
import 'package:repmate/data/services/common.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/ai_plan.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

void main() {
  final seed = loadSeed();
  final profile = builderProfile();
  late Stores s;
  late PlanBuilder b;
  final today = DateTime(2026, 12, 1, 9, 15);

  setUp(() {
    s = memoryStores();
    b = PlanBuilder(s, seed, newId: counterIds(), now: () => today);
  });
  tearDown(() => s.db.close());

  Future<({List<ProgramDay> days, List<PlannedExercise> planned})> plannedExercises() async {
    final prog = await s.activeProgram();
    final days = await s.programDays.whereK1(prog!.id);
    return (days: days, planned: await s.plannedExercises.whereK1In(days.map((d) => d.id)));
  }

  Future<Map<String, Exercise>> exMap() async => {for (final e in await s.exercises.all()) e.id: e};

  group('plan builder', () {
    test('saves a generated program that only uses available equipment', () async {
      await b.saveGeneratedProgram(profile);
      final r = await plannedExercises();
      expect(r.days, hasLength(7));
      expect(r.days.where((d) => d.type == DayType.strength), hasLength(3));
      final ex = await exMap();
      for (final p in r.planned) {
        expect(isAvailable(ex[p.exerciseId]!, kPresets['dumbbells_only']!), isTrue, reason: p.exerciseId);
      }
      final prog = (await s.activeProgram())!;
      expect(prog.startedOn, '2026-11-30');
      expect(prog.templateId, 'generated:muscle');
      expect(prog.progression.weeks, hasLength(8));
      // bands are in the dumbbells-only preset: the band warm-up stays
      expect(prog.warmup.map((w) => w.exerciseId), contains('band-pull-apart'));
      expect(await s.getMeta<int>('libraryVersion'), kLibraryVersion);
    });

    test('saves a generated diet with targets', () async {
      final d = await b.saveGeneratedDiet(profile);
      expect(d.kcalTarget, greaterThan(1400));
      expect(await s.plannedMeals.count(), greaterThanOrEqualTo(6));
      expect(await s.habitDefs.count(), greaterThan(0));
      final plan = (await s.activeDiet())!;
      expect(plan.name, 'My ${thousands(d.kcalTarget)} kcal plan');
      expect(plan.name, matches(RegExp(r'^My \d,\d{3} kcal plan$')));
    });

    test('adapts the template to a dumbbells-only gym: nothing unavailable remains', () async {
      await b.importProgramTemplate(today: today);
      final changes = await b.adaptActivePlanToEquipment(kPresets['dumbbells_only']!);
      expect(changes.length, greaterThan(3));
      final r = await plannedExercises();
      final ex = await exMap();
      for (final p in r.planned) {
        expect(isAvailable(ex[p.exerciseId]!, kPresets['dumbbells_only']!), isTrue);
        if (p.swapExerciseId != null) expect(isAvailable(ex[p.swapExerciseId]!, kPresets['dumbbells_only']!), isTrue);
      }
    });

    test('applySetup keeps history and rebuilds on request', () async {
      await b.saveGeneratedProgram(profile);
      await s.sessions.put(const Session(
          id: 's1', dayKey: '2026-12-01', title: 'x', startedAt: '2026-12-01T07:00:00Z', status: 'done', cycleWeek: 1, deload: false));
      final notes = await b.applySetup(profile.copyWith(goal: Goal.strength, trainingDays: [Weekday.tue, Weekday.thu]),
          rebuildWorkout: true, rebuildDiet: true);
      expect(notes[0], contains('rebuilt'));
      expect(notes.last, 'Diet plan rebuilt');
      expect(await s.sessions.count(), 1);
      final r = await plannedExercises();
      expect(r.days.where((d) => d.type == DayType.strength).map((d) => d.weekday.wire).toList()..sort(), ['THU', 'TUE']);
      expect((await s.programs.all()).where((p) => p.active), hasLength(1));
      expect((await s.dietPlans.all()).where((p) => p.active), hasLength(1));
      expect(await s.getMeta<String>('setupChangedAt'), isoString(today));
    });

    test('applySetup without rebuild only adapts equipment', () async {
      await b.importProgramTemplate(today: today);
      final notes = await b.applySetup(profile.copyWith(planSource: 'template'), rebuildWorkout: false, rebuildDiet: false);
      expect(notes, isNotEmpty);
      expect(notes.every((n) => n.contains(': ')), isTrue);
    });

    test('previewProgram is pure (nothing saved)', () async {
      final g = b.previewProgram(profile);
      expect(g.days, hasLength(7));
      expect(g.name, contains('3 days'));
      expect(await s.programs.count(), 0);
    });
  });

  group('AI coach writers', () {
    test('saveAiWorkout adds an equipment-safe swap and keeps the old program inactive', () async {
      await b.saveGeneratedProgram(profile);
      final w = NormWorkout(name: 'AI plan', days: [
        NormDay(weekday: Weekday.mon, type: DayType.strength, title: 'Push', exercises: [
          NormExercise(slot: 'A', exerciseId: 'dumbbell-goblet-squat', sets: 3, repsMin: 8, repsMax: 12, unit: Unit.reps, perSide: false, restSec: 90),
          NormExercise(slot: 'B', exerciseId: 'dumbbell-bench-press', sets: 3, repsMin: 8, repsMax: 12, unit: Unit.reps, perSide: false, restSec: 90),
        ]),
        for (final wd in [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat, Weekday.sun])
          NormDay(weekday: wd, type: DayType.rest, title: 'Rest', exercises: const []),
      ]);
      final id = await b.saveAiWorkout(profile, w);
      final prog = (await s.activeProgram())!;
      expect(prog.id, id);
      expect(prog.templateId, 'ai-coach');
      expect((await s.programs.all()).where((p) => p.active), hasLength(1));
      final r = await plannedExercises();
      final ex = await exMap();
      expect(r.planned, hasLength(2));
      for (final p in r.planned) {
        expect(p.swapExerciseId, isNotNull);
        expect(p.swapExerciseId, isNot(anyOf('dumbbell-goblet-squat', 'dumbbell-bench-press')));
        expect(isAvailable(ex[p.swapExerciseId]!, kPresets['dumbbells_only']!), isTrue);
      }
      final mon = r.days.firstWhere((d) => d.weekday == Weekday.mon);
      expect(mon.durationMin, 45); // falls back to the profile's session length
    });

    test('saveAiDiet pads times, rounds numbers and adds default habits once', () async {
      const diet = AiDiet(kcalTarget: 2100, proteinTargetG: 140, meals: [
        AiMeal(time: '7:30', meal: 'Breakfast', items: ['Oats'], kcal: 450.4, proteinG: 25.6),
        AiMeal(time: '13:00', meal: 'Lunch', items: ['Dal', 'Rice'], kcal: 700, proteinG: 30, optional: false),
      ]);
      await b.saveAiDiet(diet);
      final plan = (await s.activeDiet())!;
      expect(plan.name, 'AI coach · 2,100 kcal');
      expect(plan.kcalTarget, 2100);
      final meals = (await s.plannedMeals.whereK1(plan.id))..sort((a, b) => a.order - b.order);
      expect(meals.map((m) => m.time), ['07:30', '13:00']);
      expect(meals.first.kcal, 450);
      expect(meals.first.proteinG, 26);
      expect((await s.habitDefs.all()).map((h) => h.id), unorderedEquals(['water', 'steps', 'sleep']));
      await b.saveAiDiet(diet);
      expect((await s.dietPlans.all()).where((p) => p.active), hasLength(1));
      expect(await s.habitDefs.count(), 3);
    });
  });

  group('blank program', () {
    test('one workout per chosen day, rest otherwise, diet + habits', () async {
      final id = await b.createBlankProgram([Weekday.tue, Weekday.thu], 2000, 120, today: today);
      final prog = (await s.activeProgram())!;
      expect(prog.id, id);
      expect(prog.name, 'My plan');
      final days = (await s.programDays.whereK1(id))..sort((a, b) => a.order - b.order);
      expect(days.map((d) => d.title), ['Rest', 'Workout', 'Rest', 'Workout', 'Rest', 'Rest', 'Rest']);
      expect((await s.activeDiet())!.kcalTarget, 2000);
      expect((await s.habitDefs.all()).map((h) => h.id), unorderedEquals(['water', 'steps', 'sleep']));
    });
  });
}
