// Parity with src/data/seed-import.test.ts (the DB writers: importProgramTemplate / importDietTemplate).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

void main() {
  final seed = loadSeed();
  late Stores s;
  late PlanBuilder b;

  setUp(() {
    s = memoryStores();
    b = PlanBuilder(s, seed, newId: counterIds(), now: () => DateTime(2026, 11, 26));
  });
  tearDown(() => s.db.close());

  test('imports the program: 7 days, 5 with exercises, 42 media ids', () async {
    final r = await b.importProgramTemplate(today: DateTime(2026, 12, 1));
    expect(r.days, 7);
    expect(r.daysWithExercises, 5);
    final ids = (jsonDecode(File('../seed/free-exercise-db-ids.json').readAsStringSync()) as List).cast<String>();
    expect(ids, hasLength(42));
    final mediaIds = seed.mediaIndex.map((m) => m.id).toSet();
    expect(ids.every(mediaIds.contains), isTrue);
    expect(r.mediaIds, greaterThanOrEqualTo(42));
    expect(await s.programDays.count(), 7);
    final tue = (await s.programDays.all()).firstWhere((d) => d.weekday == Weekday.tue);
    expect(tue.title, contains('Strength A'));
    final pes = (await s.plannedExercises.whereK1(tue.id))..sort((a, b) => a.order - b.order);
    expect(pes, hasLength(6));
    expect(pes[1].swapExerciseId, 'dumbbell-floor-press');
    expect((await s.programs.get(r.programId))!.startedOn, '2026-11-30');
  });

  test('every exercise with a freeDbId has local media', () async {
    await b.importProgramTemplate();
    final mediaIds = seed.mediaIndex.map((m) => m.id).toSet();
    for (final e in await s.exercises.all()) {
      if (e.freeDbId != null) expect(mediaIds.contains(e.freeDbId), isTrue, reason: e.id);
    }
    expect((await s.exercises.get('dumbbell-goblet-squat'))!.isBodyweight, isFalse);
    expect((await s.exercises.get('front-plank'))!.isBodyweight, isTrue);
  });

  test('adds research alternates, patterns and the weekly wave', () async {
    final r = await b.importProgramTemplate();
    final goblet = (await s.exercises.get('dumbbell-goblet-squat'))!;
    expect(goblet.pattern, 'squat');
    expect(goblet.alternates!.length, greaterThanOrEqualTo(3));
    final alt = (await s.exercises.get(goblet.alternates![0]))!;
    expect(alt.freeDbId, isNotNull);
    expect(alt.level, 1);
    expect((await s.exercises.get('band-face-pull'))!.freeDbId, 'Band_Pull_Apart');
    final prog = (await s.programs.get(r.programId))!;
    expect(prog.progression.weeks, hasLength(8));
    expect(prog.progression.weeks![7].deload, isTrue);
  });

  test('imports the diet with habits and meta', () async {
    final r = await b.importDietTemplate();
    expect(r.meals, 7);
    expect(r.habits, 5);
    expect((await s.habitDefs.get('water'))!.target, 3000);
    expect((await s.habitDefs.get('creatine'))!.kind, 'check');
    expect(await s.getMeta<List<Object?>>('adjustmentRules'), isNotEmpty);
    expect((await s.activeDiet())!.id, r.dietPlanId);
  });

  test('a second import replaces the active program and keeps one active', () async {
    final a = await b.importProgramTemplate();
    final c = await b.importProgramTemplate(trainingDays: const [Weekday.mon, Weekday.wed, Weekday.fri]);
    expect((await s.activeProgram())!.id, c.programId);
    expect((await s.programs.get(a.programId))!.active, isFalse);
    final days = await s.programDays.whereK1(c.programId);
    expect(days.firstWhere((d) => d.weekday == Weekday.mon).title, contains('Strength A'));
  });
}
