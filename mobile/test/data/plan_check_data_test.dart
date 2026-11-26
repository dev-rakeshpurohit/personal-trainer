// Parity with src/data/plan-check.test.ts (the DB part): Plan check on the seeded template,
// applying suggestions with PlanEdit.addExerciseToDay, and the library upgrade.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/seed/library_builder.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/data/services/plan_edit.dart';
import 'package:repmate/domain/balance.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

void main() {
  final seed = loadSeed();
  late Stores s;
  late PlanBuilder b;
  late PlanEdit edit;
  const tueSat = [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat];

  setUp(() {
    s = memoryStores();
    final ids = counterIds();
    b = PlanBuilder(s, seed, newId: ids, now: () => DateTime(2026, 12, 1));
    edit = PlanEdit(s, newId: ids);
  });
  tearDown(() => s.db.close());

  Future<({List<DayLite> days, List<ProgramDay> raw, List<PlannedExercise> planned, Map<String, Exercise> exMap})> load() async {
    final days = await edit.activeDays();
    final planned = await s.plannedExercises.whereK1In(days.map((d) => d.id));
    final exMap = {for (final e in await s.exercises.all()) e.id: e};
    return (days: days.map(DayLite.of).toList(), raw: days, planned: planned, exMap: exMap);
  }

  group('plan check on the default lean-athletic template', () {
    test('finds the calf gap and suggests a plain, available calf raise on a strength day', () async {
      await b.importProgramTemplate(trainingDays: tueSat);
      await b.ensureLibrary();
      final d = await load();
      final res = planCheck(days: d.days, planned: d.planned, exMap: d.exMap, library: staticLibrary(seed), equipment: kPresets['full_gym']!, goal: Goal.lean);
      expect(res.sets[MuscleGroup.calves]!, lessThan(res.targets[MuscleGroup.calves]!));
      final calves = res.suggestions.firstWhere((x) => x.group == MuscleGroup.calves);
      expect(calves.options[0].name.toLowerCase(), contains('calf raise'));
      expect(d.raw.firstWhere((x) => x.id == calves.dayId).type, DayType.strength);
      for (final x in res.suggestions) {
        for (final o in x.options) {
          expect(isAvailable(o, kPresets['full_gym']!), isTrue);
        }
      }
      expect(res.suggestions.any((x) => x.group == MuscleGroup.quads || x.group == MuscleGroup.back), isFalse);
    });

    test('applying a suggestion closes the gap', () async {
      await b.importProgramTemplate(trainingDays: tueSat);
      await b.ensureLibrary();
      var d = await load();
      final res = planCheck(days: d.days, planned: d.planned, exMap: d.exMap, library: staticLibrary(seed), equipment: kPresets['full_gym']!, goal: Goal.lean);
      for (final x in res.suggestions) {
        await edit.addExerciseToDay(x.dayId, x.options[0].id, sets: x.sets, repsMin: x.repsMin, repsMax: x.repsMax, restSec: x.restSec);
      }
      d = await load();
      final after = planCheck(days: d.days, planned: d.planned, exMap: d.exMap, library: staticLibrary(seed), equipment: kPresets['full_gym']!, goal: Goal.lean);
      expect(after.suggestions.length, lessThan(res.suggestions.length));
      expect(weeklySets(d.days, d.planned, d.exMap)[MuscleGroup.calves]!, greaterThanOrEqualTo(after.targets[MuscleGroup.calves]!));
    });

    test('dumbbells-only gym never gets machine suggestions', () async {
      await b.importProgramTemplate(trainingDays: tueSat);
      await b.ensureLibrary();
      final d = await load();
      final res = planCheck(days: d.days, planned: d.planned, exMap: d.exMap, library: staticLibrary(seed), equipment: kPresets['dumbbells_only']!, goal: Goal.muscle);
      for (final x in res.suggestions) {
        for (final o in x.options) {
          expect(isAvailable(o, kPresets['dumbbells_only']!), isTrue);
        }
      }
    });
  });

  group('plan edit', () {
    test('addExerciseToDay: defaults by unit, appends after the last order, turns a rest day into strength', () async {
      await b.importProgramTemplate(trainingDays: tueSat);
      final days = await edit.activeDays();
      expect(days.map((x) => x.weekday), kWeekdays);
      final mon = days.firstWhere((x) => x.weekday == Weekday.mon);
      expect(mon.type, DayType.rest);
      final pe = await edit.addExerciseToDay(mon.id, 'front-plank');
      expect(pe.order, 0);
      expect(pe.slot, '1');
      expect(pe.unit, Unit.seconds);
      expect((pe.repsMin, pe.repsMax, pe.restSec, pe.sets), (30, 45, 75, 3));
      expect((await s.programDays.get(mon.id))!.type, DayType.strength);
      final tue = days.firstWhere((x) => x.weekday == Weekday.tue);
      final lunge = await edit.addExerciseToDay(tue.id, 'dumbbell-goblet-squat');
      expect(lunge.order, 6);
      expect(lunge.slot, '7');
      expect((lunge.repsMin, lunge.repsMax), (8, 12));
      expect(lunge.perSide, isFalse);
    });
  });

  group('library upgrade', () {
    test('adds dataset exercises and refreshes curated metadata without touching user edits', () async {
      await b.importProgramTemplate();
      final cur = (await s.exercises.get('dumbbell-goblet-squat'))!;
      await s.exercises.put(Exercise.fromJson({...cur.toJson(), 'isBodyweight': true, 'cue': 'my cue', 'instructions': ['old']}..remove('demoId')));
      final r = await b.ensureLibrary();
      expect(r.added, greaterThan(1000));
      final ex = (await s.exercises.get('dumbbell-goblet-squat'))!;
      expect(ex.isBodyweight, isTrue);
      expect(ex.cue, 'my cue');
      expect(ex.demoId, '1760');
      expect(ex.instructions![0].toLowerCase(), contains('dumbbell'));
      expect(ex.secondaryMuscles, contains('glutes'));
      expect((await b.ensureLibrary()).added, 0); // idempotent
    });

    test('upgradeLibraryIfNeeded runs once per version and only after onboarding', () async {
      expect(await b.library.upgradeLibraryIfNeeded(), isFalse); // no profile yet
      await s.profile.put(backupProfile());
      expect(await b.library.upgradeLibraryIfNeeded(), isTrue);
      expect(await s.exercises.count(), staticLibrary(seed).length);
      expect(await b.library.upgradeLibraryIfNeeded(), isFalse);
    });
  });
}
