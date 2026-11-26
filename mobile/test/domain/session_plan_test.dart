// Port of src/domain/sessionPlan.test.ts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/domain/session_plan.dart';

/// The seed lives at the repo root (../seed from mobile/); fall back to a synced asset copy.
Map<String, Object?> _loadSeed() {
  const name = 'program.lean-athletic-v2.json';
  final file = [File('../seed/$name'), File('assets/seed/$name')].firstWhere((f) => f.existsSync());
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();
}

void main() {
  final seed = _loadSeed();

  List<PlannedExercise> plannedFor(String weekday) {
    final day = (seed['days'] as List).cast<Map<String, Object?>>().firstWhere((d) => d['weekday'] == weekday);
    final exercises = (day['exercises'] as List? ?? const []).cast<Map<String, Object?>>();
    return [
      for (var i = 0; i < exercises.length; i++)
        () {
          final e = exercises[i];
          final t = (e['target'] as Map).cast<String, Object?>();
          return PlannedExercise(
            id: 'p$i',
            dayId: weekday,
            order: i,
            slot: e['slot'] as String,
            exerciseId: e['name'] as String,
            supersetGroup: e['supersetGroup'] as String?,
            sets: t['sets'] as int,
            repsMin: t['repsMin'] as int,
            repsMax: t['repsMax'] as int,
            unit: Unit.parse(t['unit']),
            perSide: t['perSide'] == true,
            restSec: e['restSec'] as int,
          );
        }(),
    ];
  }

  SessionFeedback fb({int rpe = 7, Feel feel = Feel.justRight, List<String> pain = const [], bool ranOutOfTime = false}) =>
      SessionFeedback(rpe: rpe, feel: feel, pain: pain, disliked: const [], ranOutOfTime: ranOutOfTime);

  group('session plan', () {
    test('full strength day keeps everything, flags A/B as main lifts', () {
      final plan = buildSessionPlan(planned: plannedFor('TUE'), dayType: DayType.strength, mode: SessionMode.full, deload: false, fallbackRir: 2);
      expect(plan, hasLength(6));
      expect(plan.where((p) => p.isMain).map((p) => p.slot).toList(), ['A1', 'A2', 'B1', 'B2']);
      expect(plan[0].rir, 2);
    });
    test('express strength keeps A/B slots, 2 sets, shorter rest, ~40 min', () {
      final plan = buildSessionPlan(planned: plannedFor('TUE'), dayType: DayType.strength, mode: SessionMode.express, deload: false);
      expect(plan.map((p) => p.slot).toList(), ['A1', 'A2', 'B1', 'B2']);
      expect(plan.every((p) => p.sets == 2 && p.restSec <= 90), isTrue);
      expect(estimateMinutes(plan), lessThanOrEqualTo(40));
      expect(
        estimateMinutes(buildSessionPlan(planned: plannedFor('TUE'), dayType: DayType.strength, mode: SessionMode.full, deload: false)),
        greaterThan(40),
      );
    });
    test('express cardio day shortens steady cardio and keeps 2 core moves', () {
      final plan = buildSessionPlan(planned: plannedFor('WED'), dayType: DayType.cardio, mode: SessionMode.express, deload: false);
      expect(plan, hasLength(3));
      expect(plan[0].repsMax, 20);
    });
    test('deload halves sets after everything else', () {
      final plan = buildSessionPlan(planned: plannedFor('TUE'), dayType: DayType.strength, mode: SessionMode.full, deload: true);
      expect(plan[0].sets, 2);
    });
    test('HIIT ramp: beginner level 1 = 4 × 20 s intervals and fewer sets', () {
      final fri = plannedFor('FRI');
      expect(isInterval(fri[5]), isTrue);
      final l1 = buildSessionPlan(planned: fri, dayType: DayType.conditioning, mode: SessionMode.full, deload: false, hiit: 1);
      final bike = l1.firstWhere((p) => p.slot == '4');
      expect([bike.sets, bike.repsMax, bike.restSec], [4, 20, 120]);
      expect(l1.firstWhere((p) => p.slot == '1').sets, 3);
      expect(l1.firstWhere((p) => p.slot == '3a').sets, 2);
      final l3 = buildSessionPlan(planned: fri, dayType: DayType.conditioning, mode: SessionMode.full, deload: false, hiit: 3);
      expect(l3.firstWhere((p) => p.slot == '4').sets, 6);
    });
    test('HIIT level ramps every 2 good sessions and steps back after a too-hard one', () {
      expect(hiitLevel([]), 1);
      expect(hiitLevel([null, null]), 2);
      expect(hiitLevel([null, null, null, null]), 3);
      expect(hiitLevel([Feel.tooHard, null, null, null]), 1);
    });
    test('periodization: week 5 adds 1 accessory set (not to main lifts)', () {
      const week = WeekFocus(week: 5, rirMain: 1, rirAccessory: 2, focus: '', note: '', setsDelta: 1, deload: false);
      final plan = buildSessionPlan(planned: plannedFor('TUE'), dayType: DayType.strength, mode: SessionMode.full, deload: false, week: week);
      expect(plan[0].sets, 4);
      expect(plan[4].sets, 4);
      expect(plan[0].rir, 1);
      expect(plan[4].rir, 2);
    });
    test('today-only swaps replace the exercise id but keep the original', () {
      final plan = buildSessionPlan(
        planned: plannedFor('TUE'),
        dayType: DayType.strength,
        mode: SessionMode.full,
        deload: false,
        swaps: {'p1': 'floor'},
      );
      expect(plan[1].exerciseId, 'floor');
      expect(plan[1].originalExerciseId, 'Dumbbell bench press');
    });
    test('unit change gets sensible default targets', () {
      expect(targetsForUnit((unit: Unit.seconds, repsMin: 30, repsMax: 45), Unit.reps), (repsMin: 8, repsMax: 12, unit: Unit.reps));
    });
  });

  group('feedback adaptation', () {
    test('too hard → hold progression and trim accessories', () {
      final a = adaptFromFeedback([fb(feel: Feel.tooHard, rpe: 9)]);
      expect(a.holdProgression, isTrue);
      expect(a.accessorySetsDelta, -1);
      final plan = buildSessionPlan(planned: plannedFor('TUE'), dayType: DayType.strength, mode: SessionMode.full, deload: false, adaptation: a);
      expect(plan[4].sets, 2);
      expect(plan[0].sets, 4);
    });
    test('two easy sessions → +1 accessory set', () {
      expect(adaptFromFeedback([fb(feel: Feel.tooEasy), fb(rpe: 5)]).accessorySetsDelta, 1);
      expect(adaptFromFeedback([fb(feel: Feel.tooEasy)]).accessorySetsDelta, 0);
    });
    test('ran out of time → prefer express; pain is carried forward', () {
      final a = adaptFromFeedback([fb(ranOutOfTime: true, pain: ['x'])]);
      expect(a.preferExpress, isTrue);
      expect(a.pain, ['x']);
    });
  });
}
