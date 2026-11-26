// Pure-domain tests for balance.dart (the web app covers this module in src/data/plan-check.test.ts
// against the seeded DB; here the days, plan and library are hand-built).
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/balance.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';

Exercise ex(
  String id,
  String name, {
  required String pattern,
  required List<String> primary,
  List<String> secondary = const [],
  List<String> equipment = const ['body only'],
  Category category = Category.strength,
  Unit unit = Unit.reps,
  int? level,
  String source = 'curated',
}) =>
    Exercise(
      id: id,
      name: name,
      pattern: pattern,
      primaryMuscles: primary,
      secondaryMuscles: secondary,
      equipment: equipment,
      category: category,
      defaultUnit: unit,
      level: level,
      source: source,
    );

int _order = 0;
PlannedExercise pe(String dayId, String exerciseId, int sets, {Unit unit = Unit.reps, String? swap}) => PlannedExercise(
      id: 'p${_order++}',
      dayId: dayId,
      order: _order,
      slot: 'A',
      exerciseId: exerciseId,
      swapExerciseId: swap,
      sets: sets,
      repsMin: 8,
      repsMax: 12,
      unit: unit,
      perSide: false,
      restSec: 60,
    );

// Plan exercises
final squat = ex('squat', 'Goblet squat', pattern: 'squat', primary: ['quadriceps'], secondary: ['glutes', 'calves', 'abdominals'], equipment: ['kettlebells']);
final rdl = ex('rdl', 'Dumbbell Romanian deadlift', pattern: 'hinge', primary: ['hamstrings'], secondary: ['glutes', 'lower back'], equipment: ['dumbbell']);
final lunge = ex('lunge', 'Dumbbell reverse lunge', pattern: 'lunge/single-leg', primary: ['quadriceps'], secondary: ['glutes', 'hamstrings'], equipment: ['dumbbell']);
final bench = ex('bench', 'Dumbbell bench press', pattern: 'horizontal push', primary: ['chest'], secondary: ['triceps', 'shoulders'], equipment: ['dumbbell']);
final row = ex('row', 'Seated cable row', pattern: 'horizontal pull', primary: ['middle back'], secondary: ['biceps'], equipment: ['cable']);
final plank = ex('plank', 'Front plank', pattern: 'core anti-extension', primary: [], category: Category.core, unit: Unit.seconds);
final bike = ex('bike', 'Stationary bike', pattern: 'conditioning/cardio', primary: ['quadriceps'], category: Category.cardio, unit: Unit.minutes, equipment: ['machine']);
final hipThrust = ex('thrust', 'Hip thrust machine', pattern: 'glute', primary: ['hamstrings'], equipment: ['machine']);

// Library-only options for fixes
final calfMachine = ex('calf-m', 'Machine standing calf raise', pattern: 'calves', primary: ['calves'], equipment: ['leverage machine'], level: 2, source: 'dataset');
final calfDb = ex('calf-db', 'Dumbbell standing calf raise', pattern: 'calves', primary: ['calves'], equipment: ['dumbbell'], level: 2, source: 'dataset');
final calfBw = ex('calf-bw', 'Bodyweight standing calf raise', pattern: 'calves', primary: ['calves'], level: 1, source: 'dataset');
final calfBall = ex('calf-ball', 'Calf raise on exercise ball', pattern: 'calves', primary: ['calves'], equipment: ['stability ball'], level: 2, source: 'dataset');
final calfOdd = ex('calf-odd', 'Smith one leg floor calf raise', pattern: 'calves', primary: ['calves'], equipment: ['smith machine'], level: 2, source: 'dataset');
final legCurl = ex('leg-curl', 'Machine lying leg curl', pattern: 'knee flexion', primary: ['hamstrings'], equipment: ['leverage machine'], level: 2, source: 'dataset');
final curl = ex('curl', 'Dumbbell biceps curl', pattern: 'elbow flexion', primary: ['biceps'], equipment: ['dumbbell'], level: 2);
final pushdown = ex('pushdown', 'Rope triceps pushdown', pattern: 'elbow extension', primary: ['triceps'], equipment: ['cable'], level: 1);
final dbExt = ex('db-ext', 'Dumbbell standing triceps extension', pattern: 'elbow extension', primary: ['triceps'], equipment: ['dumbbell'], level: 2, source: 'dataset');
final lateral = ex('lateral', 'Dumbbell lateral raise', pattern: 'lateral delt', primary: ['shoulders'], equipment: ['dumbbell'], level: 2);
final crunch = ex('crunch', 'Crunch', pattern: 'core flexion', primary: ['abdominals'], category: Category.core, level: 1);
final walkCardio = ex('walk', 'Outdoor walk', pattern: 'calves', primary: ['calves'], unit: Unit.minutes);

final library = [
  squat, rdl, lunge, bench, row, plank, bike, hipThrust, //
  calfOdd, calfBall, calfMachine, calfDb, calfBw, legCurl, curl, pushdown, dbExt, lateral, crunch, walkCardio,
];
final exMap = {for (final e in library) e.id: e};

const lower = DayLite(id: 'lower', title: 'Lower', weekday: Weekday.tue, type: DayType.strength);
const upper = DayLite(id: 'upper', title: 'Upper', weekday: Weekday.thu, type: DayType.strength);
const cardio = DayLite(id: 'cardio', title: 'Cardio + core', weekday: Weekday.sat, type: DayType.cardio);
const rest = DayLite(id: 'rest', title: 'Rest', weekday: Weekday.sun, type: DayType.rest);
const days = [lower, upper, cardio, rest];

/// A plan with plenty of compound work and no direct calf work.
List<PlannedExercise> basePlan() => [
      pe('lower', 'squat', 4),
      pe('lower', 'rdl', 4),
      pe('lower', 'lunge', 3),
      pe('upper', 'bench', 6),
      pe('upper', 'row', 6),
      pe('cardio', 'bike', 1, unit: Unit.minutes),
      pe('cardio', 'plank', 3, unit: Unit.seconds),
    ];

void main() {
  group('weeklySets', () {
    test('helper-muscle weights: calves helper counts 0, core helper 0.25, others 0.5', () {
      final s = weeklySets([lower], [pe('lower', 'squat', 4)], exMap);
      expect(s[MuscleGroup.quads], 4);
      expect(s[MuscleGroup.glutes], 2);
      expect(s[MuscleGroup.calves], 0);
      expect(s[MuscleGroup.core], 1);
    });
    test('rounds to the nearest half set like JS Math.round', () {
      // 3 × 0.25 = 0.75 → 1; 1 × 0.25 = 0.25 → 0.5
      expect(weeklySets([lower], [pe('lower', 'squat', 3)], exMap)[MuscleGroup.core], 1);
      expect(weeklySets([lower], [pe('lower', 'squat', 1)], exMap)[MuscleGroup.core], 0.5);
    });
    test('hinge, lunge and glute patterns count glutes fully even when listed as a helper', () {
      final s = weeklySets([lower], [pe('lower', 'rdl', 3), pe('lower', 'lunge', 3), pe('lower', 'thrust', 2)], exMap);
      expect(s[MuscleGroup.glutes], 8);
      expect(s[MuscleGroup.hamstrings], 3 + 1.5 + 2);
      expect(s[MuscleGroup.quads], 3);
    });
    test('core-category exercises without mapped muscles count as core', () {
      expect(weeklySets([cardio], [pe('cardio', 'plank', 3, unit: Unit.seconds)], exMap)[MuscleGroup.core], 3);
    });
    test('steady cardio (minutes), rest days and unknown exercises do not count', () {
      final s = weeklySets(days, [pe('cardio', 'bike', 1, unit: Unit.minutes), pe('rest', 'squat', 4), pe('lower', 'missing', 4)], exMap);
      expect(s.values.every((v) => v == 0), isTrue);
    });
    test('targets by goal', () {
      expect(targets(Goal.lean), {
        MuscleGroup.chest: 6, MuscleGroup.back: 6, MuscleGroup.shoulders: 5, MuscleGroup.biceps: 4, MuscleGroup.triceps: 4, //
        MuscleGroup.quads: 6, MuscleGroup.hamstrings: 5, MuscleGroup.glutes: 5, MuscleGroup.calves: 4, MuscleGroup.core: 6,
      });
      expect(targets(Goal.muscle)[MuscleGroup.chest], 10);
      expect(targets(Goal.muscle)[MuscleGroup.biceps], 6);
      expect(targets(Goal.strength)[MuscleGroup.calves], 3);
      expect(targets(null)[MuscleGroup.shoulders], 5);
    });
  });

  group('planCheck', () {
    test('finds the calf gap and suggests a plain, available calf raise on a related strength day', () {
      final full = kPresets['full_gym']!;
      final res = planCheck(days: days, planned: basePlan(), exMap: exMap, library: library, equipment: full, goal: Goal.lean);
      expect(res.sets[MuscleGroup.calves], lessThan(res.targets[MuscleGroup.calves]!));
      final calves = res.suggestions.firstWhere((s) => s.group == MuscleGroup.calves);
      expect(calves.options.first.name, matches(RegExp('calf raise', caseSensitive: false)));
      expect(calves.options.map((o) => o.id), ['calf-db', 'calf-m', 'calf-bw']); // staples first (name order on ties), odd variants never
      expect(calves.dayId, 'lower');
      expect(calves.dayLabel, 'Lower');
      expect(days.firstWhere((d) => d.id == calves.dayId).type, DayType.strength);
      expect((calves.have, calves.need, calves.sets, calves.repsMin, calves.repsMax, calves.restSec), (0, 4, 4, 12, 15, 45));
      for (final s in res.suggestions) {
        for (final o in s.options) {
          expect(isAvailable(o, full), isTrue);
        }
      }
      // big compound groups are already covered
      expect(res.suggestions.any((s) => s.group == MuscleGroup.quads || s.group == MuscleGroup.back), isFalse);
    });

    test('suggestions only use available equipment (dumbbells only: no machines, cables or balls)', () {
      final eq = kPresets['dumbbells_only']!;
      final res = planCheck(days: days, planned: basePlan(), exMap: exMap, library: library, equipment: eq, goal: Goal.muscle);
      expect(res.suggestions, isNotEmpty);
      for (final s in res.suggestions) {
        for (final o in s.options) {
          expect(isAvailable(o, eq), isTrue, reason: o.name);
        }
      }
      final calves = res.suggestions.firstWhere((s) => s.group == MuscleGroup.calves);
      expect(calves.options.map((o) => o.id), ['calf-db', 'calf-bw']);
      final triceps = res.suggestions.firstWhere((s) => s.group == MuscleGroup.triceps);
      expect(triceps.options.map((o) => o.id), ['db-ext']);
    });

    test('never suggests exercises already in the plan (main or swap) or timed in minutes', () {
      final plan = [...basePlan(), pe('upper', 'curl', 1, swap: 'calf-m')];
      final res = planCheck(days: days, planned: plan, exMap: exMap, library: library, equipment: kPresets['full_gym']!, goal: Goal.lean);
      final ids = res.suggestions.expand((s) => s.options.map((o) => o.id)).toSet();
      expect(ids.intersection({'curl', 'calf-m', 'walk', 'squat', 'rdl'}), isEmpty);
    });

    test('adding the suggested work closes the gap', () {
      final full = kPresets['full_gym']!;
      final res = planCheck(days: days, planned: basePlan(), exMap: exMap, library: library, equipment: full, goal: Goal.lean);
      final plan = [...basePlan(), for (final s in res.suggestions) pe(s.dayId, s.options.first.id, s.sets)];
      final after = planCheck(days: days, planned: plan, exMap: exMap, library: library, equipment: full, goal: Goal.lean);
      expect(after.suggestions.length, lessThan(res.suggestions.length));
      expect(weeklySets(days, plan, exMap)[MuscleGroup.calves], greaterThanOrEqualTo(after.targets[MuscleGroup.calves]!));
    });

    test('no strength days: totals but no suggestions', () {
      final res = planCheck(days: [cardio, rest], planned: basePlan(), exMap: exMap, library: library, equipment: kPresets['full_gym']!);
      expect(res.sets[MuscleGroup.core], 3);
      expect(res.suggestions, isEmpty);
    });
  });
}
