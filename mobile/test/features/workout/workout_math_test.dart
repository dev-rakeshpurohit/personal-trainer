// Pure helpers of the logger: target lines, plates, steps, effort, swap ranking, narration.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/services/session_service.dart';
import 'package:repmate/domain/equipment.dart' as eq;
import 'package:repmate/domain/models.dart';
import 'package:repmate/domain/progression.dart';
import 'package:repmate/features/workout/workout_math.dart';

SessionExercise se({int min = 8, int max = 10, Unit unit = Unit.reps, int? rir = 2, bool perSide = false, String? cue}) => SessionExercise(
      plannedExerciseId: 'p1',
      exerciseId: 'e1',
      originalExerciseId: 'e1',
      slot: 'A1',
      sets: 4,
      repsMin: min,
      repsMax: max,
      unit: unit,
      perSide: perSide,
      restSec: 90,
      rir: rir,
      isMain: true,
      cue: cue,
    );

Exercise ex(String id, String name, List<String> equipment, {String? pattern, int? level, List<String>? alternates, String? source, bool? bodyweight}) => Exercise(
      id: id,
      name: name,
      equipment: equipment,
      pattern: pattern,
      level: level,
      alternates: alternates,
      source: source,
      isBodyweight: bodyweight,
    );

void main() {
  test('target line: sets × range @ reps left', () {
    expect(targetLine(se(), 4), '4 × 8–10 @ 2 left');
    expect(targetLine(se(min: 10, max: 10, rir: null), 3), '3 × 10');
    expect(targetLine(se(min: 30, max: 45, unit: Unit.seconds, perSide: true), 3), '3 × 30–45 s / side');
    expect(targetLine(se(rir: 0), 2), '2 × 8–10 · to the limit');
  });

  test('calibration copy stops two short of the could-do number', () {
    expect(calibrationCopy(se()), 'Find a weight you could do 12 times; stop at 10.');
  });

  test('plates per side on a 20 kg bar', () {
    expect(plateLine(75, 'kg'), 'Per side: 20 + 5 + 2.5');
    expect(plateLine(20, 'kg'), 'Just the bar');
    expect(plateLine(15, 'kg'), 'Lighter than the 20 kg bar');
    expect(plateLine(102.5, 'kg'), 'Per side: 20 + 20 + 1.25');
    expect(plateLine(61, 'kg'), 'Per side: 20 (closest)');
    expect(platesPerSide(135, bar: kBarLb, plates: kLbPlates)!.plates, [45]);
  });

  test('implement line: barbell plates, two dumbbells, one dumbbell', () {
    final bench = ex('b', 'Barbell bench press', ['barbell']);
    final db = ex('d', 'Dumbbell bench press', ['dumbbell']);
    final goblet = ex('g', 'Dumbbell goblet squat', ['dumbbell']);
    expect(implementLine(bench, 60, 'kg'), 'Per side: 20');
    expect(implementLine(db, 20, 'kg'), '2 × 20 kg dumbbells');
    expect(implementLine(goblet, 16, 'kg'), '1 × 16 kg dumbbell');
    expect(implementLine(ex('p', 'Push-up', [], bodyweight: true), 0, 'kg'), isNull);
  });

  test('weight step follows the profile step for the equipment bucket', () {
    const step = StepKg(dumbbell: 2, barbell: 5, machine: 5);
    expect(weightStep(ex('b', 'Barbell squat', ['barbell']), step, 'kg'), 2.5);
    expect(weightStep(ex('d', 'Dumbbell row', ['dumbbell']), step, 'kg'), 2);
    expect(weightStep(ex('m', 'Leg press', ['machine']), step, 'kg'), 5);
    expect(weightStep(ex('b', 'Barbell squat', ['barbell']), step, 'lb'), 5);
  });

  test('effort answers are stored as reps in reserve and nudge calibration', () {
    expect(Effort.values.map((e) => e.rir), [4, 2, 1, 0]);
    expect(Effort.ofRir(3), Effort.easy);
    expect(Effort.ofRir(0), Effort.max);
    expect(calibratedWeight(Effort.easy, 20, 2.5), 22.5);
    expect(calibratedWeight(Effort.max, 20, 2.5), 17.5);
    expect(calibratedWeight(Effort.twoLeft, 20, 2.5), isNull);
  });

  test('set text in the user units', () {
    expect(setText(const SetValues(weightKg: 40, reps: 10), Unit.reps, 'kg'), '40 kg × 10');
    expect(setText(const SetValues(reps: 12), Unit.reps, 'kg'), '12 reps');
    expect(setText(const SetValues(seconds: 45, weightKg: 10), Unit.seconds, 'kg'), '45 s · 10 kg');
    expect(shortSetText(const SetValues(weightKg: 80, reps: 8), Unit.reps, 'kg'), '80 × 8');
  });

  group('swap ranking', () {
    final squat = ex('bb-squat', 'Barbell back squat', ['barbell'], pattern: 'squat', level: 3, alternates: ['goblet', 'leg-press', 'smith']);
    final lib = {
      for (final e in [
        squat,
        ex('goblet', 'Dumbbell goblet squat', ['dumbbell'], pattern: 'squat', level: 2),
        ex('leg-press', 'Leg press', ['machine'], pattern: 'squat', level: 2),
        ex('smith', 'Smith machine squat', ['machine'], pattern: 'squat', level: 3),
        ex('front', 'Barbell front squat', ['barbell'], pattern: 'squat', level: 4, source: 'dataset'),
        ex('air', 'Bodyweight squat', [], pattern: 'squat', level: 1, bodyweight: true),
      ])
        e.id: e,
    };

    test('three options with reasons, never needing missing equipment', () {
      final opts = rankAlternatives(
        original: squat,
        currentId: squat.id,
        library: lib,
        equipment: const [eq.Equip.dumbbells, eq.Equip.bench],
        reason: SwapReason.notInGym,
      );
      expect(opts.map((o) => o.exercise.id), containsAll(['goblet', 'air']));
      expect(opts.every((o) => eq.isAvailable(o.exercise, const [eq.Equip.dumbbells, eq.Equip.bench])), isTrue);
      expect(opts.first.reason, isNotEmpty);
      expect(opts.length, lessThanOrEqualTo(3));
    });

    test('busy prefers other kit; hurts prefers easier and steadier', () {
      final busy = rankAlternatives(original: squat, currentId: squat.id, library: lib, equipment: eq.kPresets['full_gym']!, reason: SwapReason.busy);
      expect(busy.first.exercise.id, isNot('front'));
      final hurts = rankAlternatives(original: squat, currentId: squat.id, library: lib, equipment: eq.kPresets['full_gym']!, reason: SwapReason.hurts);
      expect(hurts.map((o) => o.exercise.id), isNot(contains('front')));
      expect(hurts.first.exercise.level, lessThanOrEqualTo(3));
    });

    test('after a swap the planned exercise comes back first', () {
      final opts = rankAlternatives(original: squat, currentId: 'goblet', library: lib, equipment: eq.kPresets['full_gym']!, reason: SwapReason.change);
      expect(opts.first.exercise.id, squat.id);
      expect(opts.first.reason, startsWith('Back to your planned exercise'));
    });
  });

  test('narration and ordinals', () {
    const top = SetLog(id: 's', sessionId: 'x', exerciseId: 'e', setIndex: 0, weightKg: 40, reps: 10, completedAt: '');
    const up = Suggestion(kind: SuggestionKind.increase, weightKg: 42.5, message: '↑ Try 42.5 kg', prefill: []);
    expect(narrateExercise(name: 'Bench press', top: top, unit: Unit.reps, units: 'kg', next: up), 'Bench press 40 kg × 10 — next time 42.5.');
    expect(closingLine(ordinal: 1, prCount: 0, allDone: true), 'Great start!');
    expect(topSet(const [
      SetLog(id: 'a', sessionId: 'x', exerciseId: 'e', setIndex: 0, weightKg: 40, reps: 8, completedAt: ''),
      SetLog(id: 'b', sessionId: 'x', exerciseId: 'e', setIndex: 1, weightKg: 40, reps: 10, completedAt: ''),
    ])!.id, 'b');
    expect([1, 2, 3, 11, 22].map(ordinalSuffix), ['1st', '2nd', '3rd', '11th', '22nd']);
  });

  test('form cues: plan cue first, short sentences, at most three', () {
    final e = ex('e1', 'Goblet squat', ['dumbbell']).copyWith(cue: 'Chest up. Sit between your heels.', instructions: ['Hold the bell at your chest.', 'Drive through the whole foot.']);
    expect(formCues(se(cue: 'Brace first.'), e), ['Brace first.', 'Chest up.', 'Sit between your heels.']);
  });
}
