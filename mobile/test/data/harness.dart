// Shared setup for the data-layer tests: seeds read from ../seed (cwd is mobile/ under
// `flutter test`), an in-memory drift DB, a fixed clock and counter ids.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:repmate/data/db/app_db.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/seed/library_builder.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';

Object? _read(String path) => jsonDecode(File(path).readAsStringSync());

SeedData? _seed;

/// Parsed seeds, cached across tests in a file.
SeedData loadSeed() => _seed ??= SeedData.fromJson(
      program: _read('../seed/program.lean-athletic-v2.json'),
      diet: _read('../seed/diet.lean-veg-egg-2000.json'),
      mediaIndex: _read('../public/media/exercises/index.json'),
      research: _read('../seed/alternates.research.json'),
      demoMap: _read('../seed/demo-map.json'),
      curatedMeta: _read('../seed/library.curated-meta.json'),
      dataset: _read('../seed/library.dataset.json'),
    );

/// Fresh in-memory stores.
Stores memoryStores() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return Stores(AppDb(NativeDatabase.memory()));
}

/// Deterministic ids: id0, id1, …
IdGen counterIds([String prefix = 'id']) {
  var n = 0;
  return () => '$prefix${n++}';
}

/// A settable clock.
class TestClock {
  TestClock(this.t);
  DateTime t;
  DateTime call() => t;
  void advance(Duration d) => t = t.add(d);
}

/// The profile used by src/data/plan-builder.test.ts.
Profile builderProfile({List<String>? equipment}) => Profile(
      name: 'T',
      sex: Sex.female,
      birthYear: 1995,
      heightCm: 165,
      startWeightKg: 68,
      goalWeightKg: 62,
      dietType: DietType.veg,
      intolerances: const ['lactose'],
      kcalTarget: 0,
      proteinTargetG: 0,
      trainingDays: const [Weekday.mon, Weekday.wed, Weekday.fri],
      sessionTime: '07:00',
      restTimer: const RestTimerPrefs(sound: true, vibrate: true, notify: false),
      stepKg: const StepKg(dumbbell: 2, barbell: 5, machine: 5),
      createdAt: '',
      goal: Goal.muscle,
      experience: Experience.beginner,
      sessionMin: 45,
      equipment: equipment ?? kPresets['dumbbells_only']!,
      planSource: 'generated',
      dietSource: 'generated',
    );

/// The profile used by src/data/backup.test.ts (and the onboarded user of the e2e specs).
Profile backupProfile({String createdAt = '2026-12-01T09:00:00.000Z', List<Weekday> trainingDays = const [Weekday.tue]}) => Profile(
      name: 'Test',
      sex: Sex.male,
      birthYear: 1990,
      heightCm: 178,
      startWeightKg: 80,
      goalWeightKg: 74,
      dietType: DietType.vegEgg,
      kcalTarget: 2000,
      proteinTargetG: 150,
      trainingDays: trainingDays,
      sessionTime: '09:15',
      createdAt: createdAt,
    );
