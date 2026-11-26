// Parity with src/data/seed-import.test.ts and src/data/demo-map.test.ts.
// Reads the seeds straight from the web app (cwd is mobile/ under `flutter test`).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/seed/library_builder.dart';
import 'package:repmate/domain/models.dart';

Object? _read(String path) => jsonDecode(File(path).readAsStringSync());

SeedData _load() => SeedData.fromJson(
      program: _read('../seed/program.lean-athletic-v2.json'),
      diet: _read('../seed/diet.lean-veg-egg-2000.json'),
      mediaIndex: _read('../public/media/exercises/index.json'),
      research: _read('../seed/alternates.research.json'),
      demoMap: _read('../seed/demo-map.json'),
      curatedMeta: _read('../seed/library.curated-meta.json'),
      dataset: _read('../seed/library.dataset.json'),
    );

IdGen _counter() {
  var n = 0;
  return () => 'id${n++}';
}

void main() {
  final seed = _load();
  final rawDemoMap = (_read('../seed/demo-map.json') as Map).cast<String, Object?>();
  final map = (rawDemoMap['map'] as Map).cast<String, Object?>();
  final files = (rawDemoMap['files'] as Map).cast<String, Object?>();

  group('seed import', () {
    test('imports the program: 7 days, 5 with exercises, 42 media ids', () {
      final r = buildTemplateProgram(seed, today: DateTime(2026, 12, 1), newId: _counter());
      expect(r.days, hasLength(7));
      expect(r.daysWithExercises, 5);
      final ids = (_read('../seed/free-exercise-db-ids.json') as List).cast<String>();
      expect(ids, hasLength(42));
      final mediaIds = seed.mediaIndex.map((m) => m.id).toSet();
      expect(ids.every(mediaIds.contains), isTrue);
      expect(seed.mediaIndex.length, greaterThanOrEqualTo(42));
      final tue = r.days.firstWhere((d) => d.weekday == Weekday.tue);
      expect(tue.title, contains('Strength A'));
      final pes = r.planned.where((p) => p.dayId == tue.id).toList()..sort((a, b) => a.order - b.order);
      expect(pes, hasLength(6));
      expect(pes[1].swapExerciseId, 'dumbbell-floor-press');
      expect(r.program.startedOn, '2026-11-30');
      expect(r.program.templateId, seed.program.id);
      expect(r.program.active, isTrue);
    });

    test('template days and exercises match the seed TUE–SAT', () {
      final r = buildTemplateProgram(seed, trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat], today: DateTime(2026, 11, 26), newId: _counter());
      expect(r.days.map((d) => d.weekday), kWeekdays);
      expect(r.days.map((d) => d.order), [0, 1, 2, 3, 4, 5, 6]);
      for (final sd in seed.program.days) {
        final d = r.days.firstWhere((x) => x.weekday == sd.weekday);
        expect(d.title, sd.title);
        expect(d.type, sd.type);
        expect(d.durationMin, sd.durationMin);
        final pes = r.planned.where((p) => p.dayId == d.id).toList()..sort((a, b) => a.order - b.order);
        final exs = sd.exercises ?? const [];
        expect(pes.length, exs.length, reason: sd.title);
        for (var i = 0; i < exs.length; i++) {
          expect(pes[i].exerciseId, slugify(exs[i].name));
          expect(pes[i].slot, exs[i].slot);
          expect(pes[i].sets, exs[i].target.sets);
          expect(pes[i].unit, exs[i].target.unit);
          expect(pes[i].restSec, exs[i].restSec);
          expect(pes[i].supersetGroup, exs[i].supersetGroup);
          expect(pes[i].swapExerciseId, exs[i].swap == null ? null : slugify(exs[i].swap!.name));
          expect(r.exercises.containsKey(pes[i].exerciseId), isTrue);
          if (pes[i].swapExerciseId != null) expect(r.exercises.containsKey(pes[i].swapExerciseId), isTrue);
        }
      }
      final counts = {for (final d in r.days) d.weekday: r.planned.where((p) => p.dayId == d.id).length};
      expect(counts, {Weekday.mon: 0, Weekday.tue: 6, Weekday.wed: 6, Weekday.thu: 7, Weekday.fri: 6, Weekday.sat: 6, Weekday.sun: 0});
      expect(r.planned.map((p) => p.id).toSet().length, r.planned.length);
      // Warm-up items with a freeDbId key (even null) link to a library exercise.
      final warm = {for (final w in r.program.warmup) w.name: w.exerciseId};
      expect(warm['Easy cardio, any machine'], isNull);
      expect(warm['Bodyweight squat'], 'bodyweight-squat');
      expect(warm["World's greatest stretch"], 'worlds-greatest-stretch');
      expect(r.program.progression.cycle, hasLength(3));
    });

    test('every exercise with a freeDbId has local media', () {
      final exs = buildExercises(seed.program, seed.mediaIndex, research: seed.research, demoMap: seed.demoMap, curatedMeta: seed.curatedMeta);
      final mediaIds = seed.mediaIndex.map((m) => m.id).toSet();
      for (final e in exs.values) {
        if (e.freeDbId != null) expect(mediaIds.contains(e.freeDbId), isTrue, reason: e.id);
      }
      expect(exs['dumbbell-goblet-squat']!.isBodyweight, isFalse);
      expect(exs['front-plank']!.isBodyweight, isTrue);
    });

    test('adds research alternates, patterns and the weekly wave', () {
      final r = buildTemplateProgram(seed, today: DateTime(2026, 11, 26), newId: _counter());
      final goblet = r.exercises['dumbbell-goblet-squat']!;
      expect(goblet.pattern, 'squat');
      expect(goblet.alternates!.length, greaterThanOrEqualTo(3));
      final alt = r.exercises[goblet.alternates![0]]!;
      expect(alt.freeDbId, isNotNull);
      expect(alt.level, 1);
      expect(r.exercises['band-face-pull']!.freeDbId, 'Band_Pull_Apart');
      expect(r.program.progression.weeks, hasLength(8));
      expect(r.program.progression.weeks![7].deload, isTrue);
    });

    test('imports the diet with habits', () {
      final r = buildDietTemplate(seed.diet, newId: _counter());
      expect(r.meals, hasLength(7));
      expect(r.habits, hasLength(5));
      expect(r.habits.firstWhere((h) => h.id == 'water').target, 3000);
      expect(r.habits.firstWhere((h) => h.id == 'water').unit, 'ml');
      expect(r.habits.firstWhere((h) => h.id == 'creatine').kind, 'check');
      expect(r.habits.firstWhere((h) => h.id == 'steps').kind, 'number');
      expect(r.plan.kcalTarget, seed.diet.kcalTarget);
      expect(r.plan.active, isTrue);
      expect(r.meals.every((m) => m.dietPlanId == r.plan.id), isTrue);
      expect(r.meals.first.skipOnRestDay, isTrue);
      expect(r.adjustmentRules.first.keys, containsAll(['if', 'then']));
    });

    test('remaps training days to the chosen weekdays', () {
      final days = seed.program.days;
      expect(identical(remapDays(days, const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat], SeedDay.lens), days), isTrue);
      expect(identical(remapDays(days, null, SeedDay.lens), days), isTrue);
      final r = remapDays(days, const [Weekday.mon, Weekday.wed, Weekday.fri], SeedDay.lens);
      expect(r, hasLength(7));
      expect(r.firstWhere((d) => d.weekday == Weekday.mon).title, contains('Strength A'));
      expect(r.firstWhere((d) => d.weekday == Weekday.tue).type, DayType.rest);
      expect(r.firstWhere((d) => d.weekday == Weekday.tue).title, 'Rest');
      expect(r.firstWhere((d) => d.weekday == Weekday.sun).type, DayType.activeRecovery);
      expect(r.map((d) => d.weekday), kWeekdays);
    });

    test('remapDays works on ProgramDay via programDayLens', () {
      final t = buildTemplateProgram(seed, today: DateTime(2026, 11, 26), newId: _counter());
      final r = remapDays(t.days, const [Weekday.mon, Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat], programDayLens);
      expect(r.where((d) => d.type.isTraining), hasLength(5)); // only 5 training days in the template
      expect(r.firstWhere((d) => d.weekday == Weekday.mon).title, contains('Strength A'));
      expect(r.firstWhere((d) => d.weekday == Weekday.sat).type, DayType.rest);
    });

    test('slugifies names', () {
      expect(slugify("Farmer's carry"), 'farmers-carry');
      expect(slugify('Low box jump (30–45 cm)'), 'low-box-jump-30-45-cm');
      expect(slugify('Farmer’s march'), 'farmers-march');
    });

    test('blank program: one workout per chosen day', () {
      final b = createBlankProgram(const [Weekday.tue, Weekday.thu], 2000, 120,
          seedProgression: seed.program.progression, today: DateTime(2026, 12, 1), newId: _counter());
      expect(b.program.startedOn, '2026-11-30');
      expect(b.program.name, 'My plan');
      expect(b.days.map((d) => d.title), ['Rest', 'Workout', 'Rest', 'Workout', 'Rest', 'Rest', 'Rest']);
      expect(b.days.where((d) => d.type == DayType.strength), hasLength(2));
      expect(b.dietPlan.kcalTarget, 2000);
      expect(b.habits.map((h) => h.id), ['water', 'steps', 'sleep']);
    });

    test('rejects malformed seed JSON with a path', () {
      expect(
        () => SeedProgram.fromJson({'id': 'x', 'name': 'y', 'warmup': {'items': []}, 'cooldown': '', 'rules': [], 'progression': {'model': 'double_progression', 'dumbbellIncrementKg': 2, 'barIncrementKg': 5, 'cycle': []}, 'days': [{'weekday': 'XYZ', 'type': 'rest', 'title': 'Rest'}]}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('program.days[0].weekday'))),
      );
    });
  });

  group('demo map', () {
    test('covers every curated exercise and nothing else', () {
      final ids = curatedLibrary(seed).map((e) => e.id).toSet();
      expect(map.length, 216);
      expect(map.keys.toList()..sort(), ids.toList()..sort());
    });

    test('has a source file for every mapped demo', () {
      for (final id in map.values) {
        if (id != null) expect(files[id], matches(RegExp(r'^videos/\d{4}-\w+\.gif$')), reason: '$id');
      }
    });

    test('maps most of the library to an animated demo', () {
      final mapped = map.values.where((v) => v != null).length;
      expect(mapped / map.length, greaterThan(0.9));
    });

    test('full library has unique ids and a demo for every dataset exercise', () {
      final lib = staticLibrary(seed);
      expect(lib.map((e) => e.id).toSet().length, lib.length);
      expect(lib.length, greaterThan(1300));
      expect(lib.where((e) => e.source == 'dataset').every((e) => e.demoId != null && e.demoId!.isNotEmpty), isTrue);
      expect(identical(staticLibrary(seed), lib), isTrue); // cached
    });

    test('curated entries get demo metadata', () {
      final goblet = curatedLibrary(seed).firstWhere((e) => e.id == 'dumbbell-goblet-squat');
      expect(goblet.demoId, '1760');
      expect(goblet.source, 'curated');
      expect(goblet.instructions!.join(' ').toLowerCase(), contains('dumbbell'));
      expect(goblet.secondaryMuscles, contains('glutes'));
      expect(goblet.secondaryMuscles!.any(goblet.primaryMuscles.contains), isFalse);
      expect(goblet.bodyPart, isNotNull);
      expect(curatedLibrary(seed).every((e) => e.source == 'curated'), isTrue);
    });
  });

  group('library upgrade', () {
    test('adds missing rows and refreshes owned fields only', () {
      final lib = curatedLibrary(seed);
      final goblet = lib.firstWhere((e) => e.id == 'dumbbell-goblet-squat');
      final stale = Exercise.fromJson({...goblet.toJson(), 'demoId': null, 'cue': 'my cue', 'isBodyweight': true}..removeWhere((_, v) => v == null));
      final custom = Exercise.fromJson({...lib[1].toJson(), 'custom': true, 'demoId': '9999'});
      final up = planLibraryUpgrade(lib, {stale.id: stale, custom.id: custom});
      expect(up.missing, hasLength(lib.length - 2));
      expect(up.updates, hasLength(1));
      expect(up.updates.single.demoId, '1760');
      expect(up.updates.single.cue, 'my cue');
      expect(up.updates.single.isBodyweight, isTrue);
      expect(kLibraryVersion, 2);
      expect(kRefreshFields, contains('primaryMuscles'));
    });
  });
}
