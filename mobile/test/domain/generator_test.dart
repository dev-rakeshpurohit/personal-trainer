// Port of src/domain/generator.test.ts.
//
// The web test uses `staticLibrary()` (curated seed exercises + the 3D dataset). The Dart data
// layer doesn't exist yet, so the dataset is loaded from ../seed/library.dataset.json and the
// curated part is a compact fixture of real curated exercises (same ids, names, equipment, levels,
// units and "parent with alternates" flags as the web build) covering every pattern the
// templates need.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/generator.dart';
import 'package:repmate/domain/models.dart';

List<Exercise> loadDataset() {
  final json = jsonDecode(File('../seed/library.dataset.json').readAsStringSync()) as Map<String, Object?>;
  return (json['exercises'] as List).map((e) => Exercise.fromJson((e as Map).cast())).toList();
}

/// A curated exercise. `parent` = the seed exercise carries ranked alternates (scores as a proven main lift).
Exercise c(
  String id,
  String name,
  String pattern,
  List<String> equipment, {
  int? level,
  Unit unit = Unit.reps,
  bool parent = false,
  bool bodyweight = false,
  Category category = Category.strength,
  String muscle = 'quadriceps',
}) =>
    Exercise(
      id: id,
      name: name,
      pattern: pattern,
      equipment: equipment,
      level: level,
      defaultUnit: unit,
      alternates: parent ? List.generate(5, (i) => '$id-alt$i') : null,
      isBodyweight: bodyweight,
      category: category,
      primaryMuscles: [muscle],
      source: 'curated',
    );

final List<Exercise> curatedFixture = [
  // squat
  c('dumbbell-goblet-squat', 'Dumbbell goblet squat', 'squat', ['kettlebells'], parent: true),
  c('leg-press', 'Leg press', 'squat', ['machine'], level: 2, parent: true),
  c('barbell-back-squat', 'Barbell back squat', 'squat', ['barbell'], level: 4),
  c('bodyweight-squat', 'Bodyweight squat', 'squat', ['body only'], level: 1, bodyweight: true),
  // hinge
  c('dumbbell-romanian-deadlift', 'Dumbbell Romanian deadlift', 'hinge', ['dumbbell'], parent: true, muscle: 'hamstrings'),
  c('trap-bar-deadlift', 'Trap-bar deadlift', 'hinge', ['other'], level: 3, parent: true),
  c('kettlebell-swing', 'Kettlebell swing', 'hinge', ['kettlebells'], level: 2, parent: true, muscle: 'hamstrings'),
  c('glute-bridge', 'Glute bridge', 'hinge', ['body only'], level: 1, bodyweight: true, muscle: 'glutes'),
  c('band-good-morning', 'Band good morning', 'hinge', ['bands'], level: 1, bodyweight: true, muscle: 'hamstrings'),
  // lunge / single-leg
  c('bulgarian-split-squat', 'Bulgarian split squat', 'lunge/single-leg', ['dumbbell'], parent: true),
  c('dumbbell-reverse-lunge', 'Dumbbell reverse lunge', 'lunge/single-leg', ['dumbbell'], level: 2, parent: true),
  c('bodyweight-walking-lunge', 'Bodyweight walking lunge', 'lunge/single-leg', ['body only'], level: 1, bodyweight: true),
  // horizontal push
  c('dumbbell-bench-press', 'Dumbbell bench press', 'horizontal push', ['dumbbell'], level: 2, parent: true, muscle: 'chest'),
  c('incline-dumbbell-press', 'Incline dumbbell press', 'horizontal push', ['dumbbell'], parent: true, muscle: 'chest'),
  c('push-up', 'Push-up', 'horizontal push', ['body only'], level: 2, bodyweight: true, muscle: 'chest'),
  c('machine-chest-press', 'Machine chest press', 'horizontal push', ['machine'], level: 2, muscle: 'chest'),
  // vertical push
  c('standing-dumbbell-shoulder-press', 'Standing dumbbell shoulder press', 'vertical push', ['dumbbell'], parent: true, muscle: 'shoulders'),
  c('machine-shoulder-press', 'Machine shoulder press', 'vertical push', ['machine'], level: 2, muscle: 'shoulders'),
  c('band-shoulder-press', 'Band shoulder press', 'vertical push', ['bands'], level: 1, bodyweight: true, muscle: 'shoulders'),
  // horizontal pull
  c('seated-cable-row', 'Seated cable row', 'horizontal pull', ['cable'], level: 2, parent: true, muscle: 'middle back'),
  c('dumbbell-bent-over-row', 'Dumbbell bent-over row', 'horizontal pull', ['dumbbell'], parent: true, muscle: 'middle back'),
  c('one-arm-dumbbell-row', 'One-arm dumbbell row', 'horizontal pull', ['dumbbell'], level: 2, muscle: 'middle back'),
  // vertical pull
  c('lat-pulldown', 'Lat pulldown', 'vertical pull', ['cable'], level: 2, parent: true, muscle: 'lats'),
  c('assisted-pull-up-machine-or-pulldown', 'Assisted pull-up machine or pulldown', 'vertical pull', ['cable'], parent: true, muscle: 'lats'),
  c('band-assisted-pull-up', 'Band-assisted pull-up', 'vertical pull', ['other'], level: 3, parent: true, muscle: 'lats'),
  c('chin-up', 'Chin-up', 'vertical pull', ['body only'], level: 4, bodyweight: true, muscle: 'lats'),
  // arms and shoulders
  c('dumbbell-hammer-curl', 'Dumbbell hammer curl', 'elbow flexion', ['dumbbell'], parent: true, muscle: 'biceps'),
  c('dumbbell-biceps-curl', 'Dumbbell biceps curl', 'elbow flexion', ['dumbbell'], level: 2, muscle: 'biceps'),
  c('dumbbell-overhead-triceps-extension', 'Dumbbell overhead triceps extension', 'elbow extension', ['kettlebells'], parent: true, muscle: 'triceps'),
  c('rope-triceps-pushdown', 'Rope triceps pushdown', 'elbow extension', ['cable'], level: 1, muscle: 'triceps'),
  c('dumbbell-lateral-raise', 'Dumbbell lateral raise', 'lateral delt', ['dumbbell'], parent: true, muscle: 'shoulders'),
  c('band-lateral-raise', 'Band lateral raise', 'lateral delt', ['bands'], level: 1, bodyweight: true, muscle: 'shoulders'),
  c('face-pull', 'Face pull', 'rear delt/scap', ['cable'], parent: true, muscle: 'shoulders'),
  c('band-face-pull', 'Band face pull', 'rear delt/scap', ['bands'], parent: true, bodyweight: true, muscle: 'shoulders'),
  c('band-pull-apart', 'Band pull-apart', 'rear delt/scap', ['bands'], level: 1, bodyweight: true, muscle: 'shoulders'),
  // core
  c('dead-bug', 'Dead bug', 'core anti-extension', ['body only'], level: 1, parent: true, bodyweight: true, category: Category.core, muscle: 'abdominals'),
  c('front-plank', 'Front plank', 'core anti-extension', ['body only'], level: 1, unit: Unit.seconds, parent: true, bodyweight: true, category: Category.core, muscle: 'abdominals'),
  c('side-plank', 'Side plank', 'core anti-rotation', ['body only'], level: 1, unit: Unit.seconds, parent: true, bodyweight: true, category: Category.core, muscle: 'abdominals'),
  c('cable-woodchop', 'Cable woodchop', 'core anti-rotation', ['cable'], level: 3, parent: true, category: Category.core, muscle: 'abdominals'),
  c('cable-crunch', 'Cable crunch', 'core flexion', ['cable'], parent: true, category: Category.core, muscle: 'abdominals'),
  c('reverse-crunch-on-a-mat', 'Reverse crunch on a mat', 'core flexion', ['body only'], parent: true, bodyweight: true, category: Category.core, muscle: 'abdominals'),
  // carry
  c('farmers-carry', "Farmer's carry", 'carry', ['other'], unit: Unit.meters, parent: true, muscle: 'forearms'),
  c('suitcase-carry-one-dumbbell-switch-hands', 'Suitcase carry (one dumbbell, switch hands)', 'carry', ['other'], level: 3, unit: Unit.meters, muscle: 'forearms'),
  // power
  c('bodyweight-squat-jump', 'Bodyweight squat jump', 'power/plyometric', ['body only'], parent: true, bodyweight: true),
  c('low-box-jump-30-45-cm', 'Low box jump (30–45 cm)', 'power/plyometric', ['other'], parent: true, category: Category.power, muscle: 'hamstrings'),
  c('medicine-ball-slam', 'Medicine-ball slam', 'power/plyometric', ['medicine ball'], parent: true, category: Category.core, muscle: 'abdominals'),
  c('explosive-push-up', 'Explosive push-up', 'power/plyometric', ['body only'], level: 3, bodyweight: true, category: Category.power, muscle: 'chest'),
  // conditioning / cardio (steady = minutes, intervals = seconds)
  c('steady-cardio-any-free-machine', 'Steady cardio (any free machine)', 'conditioning/cardio', ['machine'], unit: Unit.minutes, parent: true, bodyweight: true, category: Category.cardio),
  c('outdoor-brisk-walk-later-in-the-day', 'Outdoor brisk walk later in the day', 'conditioning/cardio', [], unit: Unit.minutes, parent: true, bodyweight: true, category: Category.cardio),
  c('bike-intervals', 'Bike intervals', 'conditioning/cardio', ['machine'], unit: Unit.seconds, parent: true, bodyweight: true, category: Category.cardio),
  c('mountain-climber', 'Mountain climber', 'conditioning/cardio', ['body only'], level: 2, unit: Unit.seconds, parent: true, bodyweight: true, category: Category.power),
  // mobility
  c('mobility-flow', 'Mobility flow', 'mobility', ['body only'], unit: Unit.minutes, parent: true, bodyweight: true, category: Category.cardio, muscle: 'hamstrings'),
  c('worlds-greatest-stretch', "World's greatest stretch", 'mobility', ['body only'], level: 2, bodyweight: true, category: Category.cardio, muscle: 'hamstrings'),
];

void main() {
  final library = [...curatedFixture, ...loadDataset()];
  final byId = {for (final e in library) e.id: e};
  const days = <int, List<Weekday>>{
    2: [Weekday.tue, Weekday.fri],
    3: [Weekday.mon, Weekday.wed, Weekday.fri],
    4: [Weekday.mon, Weekday.tue, Weekday.thu, Weekday.fri],
    5: [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat],
    6: [Weekday.mon, Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat],
  };
  const exps = Experience.values; // beginner, intermediate, advanced (same order as the TS test)

  GenProgram gen(Goal goal, Experience exp, List<Weekday> d, int min, List<String> eq) =>
      generateProgram(GenInput(goal: goal, experience: exp, days: d, sessionMin: min, equipment: eq, library: library));

  group('program generator', () {
    test('library has patterns for generation', () {
      expect(library.where((e) => e.pattern != null && e.pattern!.isNotEmpty).length, greaterThan(150));
    });

    for (final preset in ['full_gym', 'dumbbells_only', 'home']) {
      for (final goal in Goal.values) {
        for (final n in [2, 3, 4, 5, 6]) {
          test('$preset · ${goal.wire} · $n days: valid, equipment-safe, no repeats in a day', () {
            final eq = kPresets[preset]!;
            final p = gen(goal, exps[n % 3], days[n]!, 60, eq);
            expect(p.days, hasLength(7));
            final training = p.days.where((d) => d.exercises.isNotEmpty).toList();
            expect(training.length, greaterThanOrEqualTo(preset == 'home' ? n - 1 : n));
            for (final d in training) {
              final ids = d.exercises.map((e) => e.exerciseId).toList();
              expect(ids.toSet().length, ids.length);
              expect(d.exercises.length, lessThanOrEqualTo(6));
              for (final e in d.exercises) {
                expect(isAvailable(byId[e.exerciseId]!, eq), isTrue);
                if (e.swapExerciseId != null) expect(isAvailable(byId[e.swapExerciseId]!, eq), isTrue);
                expect(e.repsMin, lessThanOrEqualTo(e.repsMax));
                expect(e.sets, greaterThan(0));
              }
              if (d.type == DayType.strength && preset != 'home') expect(d.exercises.length, greaterThanOrEqualTo(4));
            }
          });
        }
      }
    }

    test('session length limits strength slots', () {
      final p30 = gen(Goal.muscle, Experience.intermediate, days[3]!, 30, kPresets['full_gym']!);
      final p90 = gen(Goal.muscle, Experience.intermediate, days[3]!, 90, kPresets['full_gym']!);
      int maxLen(GenProgram p) => p.days.map((d) => d.exercises.length).reduce((a, b) => a > b ? a : b);
      expect(maxLen(p30), 4);
      expect(maxLen(p90), greaterThan(4));
    });
    test('strength goal uses low reps on main lifts; muscle uses 8–12', () {
      final s = gen(Goal.strength, Experience.advanced, days[3]!, 75, kPresets['full_gym']!);
      expect(s.days.firstWhere((d) => d.exercises.isNotEmpty).exercises[0].repsMax, 6);
      final m = gen(Goal.muscle, Experience.intermediate, days[3]!, 75, kPresets['full_gym']!);
      final first = m.days.firstWhere((d) => d.exercises.isNotEmpty).exercises[0];
      expect((first.repsMin, first.repsMax), (8, 12));
    });
    test('fat loss 5 days mirrors the proven structure with an active-recovery day', () {
      final p = gen(Goal.fatLoss, Experience.beginner, days[5]!, 75, kPresets['full_gym']!);
      expect(p.days.map((d) => d.type), [
        DayType.rest,
        DayType.strength,
        DayType.cardio,
        DayType.strength,
        DayType.conditioning,
        DayType.strength,
        DayType.activeRecovery,
      ]);
    });
    test('beginners get easier variations', () {
      final b = gen(Goal.muscle, Experience.beginner, days[3]!, 60, kPresets['full_gym']!);
      for (final d in b.days) {
        for (final e in d.exercises) {
          expect(byId[e.exerciseId]!.level ?? 1, lessThanOrEqualTo(3));
        }
      }
    });
    test('program name and rest-day notes match the web app', () {
      final p = gen(Goal.lean, Experience.beginner, days[3]!, 60, kPresets['full_gym']!);
      expect(p.name, 'Lean & athletic · 3 days');
      expect(gen(Goal.lean, Experience.beginner, [Weekday.tue], 60, kPresets['full_gym']!).name, 'Lean & athletic · 1 day');
      final sun = p.days.last;
      expect((sun.weekday, sun.type, sun.notes), (Weekday.sun, DayType.activeRecovery, '30–45 min brisk walk + 10 min mobility.'));
      final strength = gen(Goal.strength, Experience.beginner, days[3]!, 60, kPresets['full_gym']!);
      expect(strength.days.where((d) => d.type == DayType.activeRecovery), isEmpty);
    });
    test('superset labels only survive when both partners exist', () {
      for (final preset in kPresets.values) {
        final p = gen(Goal.muscle, Experience.intermediate, days[4]!, 90, preset);
        for (final d in p.days) {
          for (final e in d.exercises.where((e) => e.supersetGroup != null)) {
            expect(d.exercises.where((x) => x.supersetGroup == e.supersetGroup).length, greaterThanOrEqualTo(2));
          }
        }
      }
    });
  });

  group('prescription', () {
    test('roles and goals', () {
      expect(prescription(Goal.lean, Experience.beginner, SlotRole.steady, Unit.minutes, 45), (sets: 1, repsMin: 20, repsMax: 20, restSec: 0));
      expect(prescription(Goal.lean, Experience.beginner, SlotRole.steady, Unit.minutes, 60), (sets: 1, repsMin: 30, repsMax: 30, restSec: 0));
      expect(prescription(Goal.lean, Experience.advanced, SlotRole.interval, Unit.seconds, 60), (sets: 6, repsMin: 30, repsMax: 30, restSec: 90));
      expect(prescription(Goal.lean, Experience.beginner, SlotRole.carry, Unit.meters, 60), (sets: 3, repsMin: 30, repsMax: 30, restSec: 60));
      expect(prescription(Goal.lean, Experience.beginner, SlotRole.core, Unit.seconds, 60), (sets: 2, repsMin: 20, repsMax: 30, restSec: 45));
      expect(prescription(Goal.strength, Experience.beginner, SlotRole.main, Unit.reps, 60), (sets: 3, repsMin: 6, repsMax: 8, restSec: 150));
      expect(prescription(Goal.muscle, Experience.advanced, SlotRole.acc, Unit.reps, 60), (sets: 3, repsMin: 10, repsMax: 15, restSec: 60));
      expect(prescription(Goal.fatLoss, Experience.beginner, SlotRole.acc, Unit.reps, 60), (sets: 2, repsMin: 10, repsMax: 12, restSec: 45));
    });
  });

  group('isolation work from the 3D library', () {
    test('lower days for muscle goals get a plain leg curl and calf raise, never odd variants', () {
      final p = gen(Goal.muscle, Experience.intermediate, [Weekday.mon, Weekday.tue, Weekday.thu, Weekday.fri], 75, kPresets['full_gym']!);
      final names = p.days.expand((d) => d.exercises.map((e) => byId[e.exerciseId]!.name)).toList();
      expect(names.any((n) => RegExp('leg curl', caseSensitive: false).hasMatch(n)), isTrue);
      expect(names.any((n) => RegExp('calf raise', caseSensitive: false).hasMatch(n)), isTrue);
      expect(names.any((n) => RegExp(r'exercise ball|bosu|arm blaster|\(v\d\)', caseSensitive: false).hasMatch(n)), isFalse);
    });

    test('curated main lifts still win over dataset variants', () {
      final p = gen(Goal.lean, Experience.beginner, [Weekday.tue, Weekday.thu, Weekday.sat], 60, kPresets['full_gym']!);
      final mains = p.days.expand((d) => d.exercises.where((e) => e.slot.startsWith('A')).map((e) => byId[e.exerciseId]!)).toList();
      expect(mains, isNotEmpty);
      expect(mains.every((e) => e.source == 'curated'), isTrue);
    });
  });
}
