// Port of src/domain/progression.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/domain/progression.dart';

void main() {
  const SetTarget planned = (sets: 3, repsMin: 8, repsMax: 10, unit: Unit.reps);
  WorkSet s(double weightKg, int reps, int setIndex, [int? rir]) => WorkSet(weightKg: weightKg, reps: reps, setIndex: setIndex, rir: rir);

  group('double progression', () {
    test('suggests +increment when all sets hit the top of the range', () {
      final r = suggestNext(planned: planned, sets: 3, history: [[s(14, 10, 0), s(14, 10, 1), s(14, 10, 2)]], targetRir: 2, increment: 2);
      expect(r.kind, SuggestionKind.increase);
      expect(r.weightKg, 16);
      expect(r.message, '↑ Try 16 kg');
      expect(r.prefill.every((p) => p.weightKg == 16 && p.reps == 8), isTrue);
    });
    test('does not progress when RIR was below target', () {
      expect(readyToProgress([s(14, 10, 0, 1), s(14, 10, 1, 2), s(14, 10, 2, 2)], planned, targetRir: 2), isFalse);
      expect(readyToProgress([s(14, 10, 0, 2), s(14, 10, 1, 3), s(14, 10, 2)], planned, targetRir: 2), isTrue);
    });
    test('does not progress with fewer sets than planned', () {
      expect(readyToProgress([s(14, 10, 0), s(14, 10, 1)], planned), isFalse);
    });
    test('holds weight and targets +1 rep on the lowest set', () {
      final r = suggestNext(planned: planned, sets: 3, history: [[s(14, 10, 0), s(14, 9, 1), s(14, 8, 2)]], increment: 2);
      expect(r.kind, SuggestionKind.hold);
      expect(r.weightKg, 14);
      expect(r.message, contains('set 3'));
      expect(r.prefill.map((p) => p.reps).toList(), [10, 9, 9]);
    });
    test('eases off after two consecutive sessions under repsMin', () {
      final bad = [s(20, 7, 0), s(20, 6, 1), s(20, 6, 2)];
      final r = suggestNext(planned: planned, sets: 3, history: [bad, bad], increment: 2);
      expect(r.kind, SuggestionKind.decrease);
      expect(r.weightKg, 18);
    });
    test('one bad session is not enough to ease off', () {
      final r = suggestNext(planned: planned, sets: 3, history: [[s(20, 7, 0)], [s(20, 9, 0)]], increment: 2);
      expect(r.kind, SuggestionKind.hold);
    });
    test('first-time prefill uses repsMin', () {
      final r = suggestNext(planned: planned, sets: 2, history: [], increment: 2);
      expect(r.kind, SuggestionKind.first);
      expect(r.prefill, const [Prefill(reps: 8), Prefill(reps: 8)]);
    });
    test('progresses time for seconds-based holds and caps at 60s', () {
      const SetTarget p = (sets: 3, repsMin: 30, repsMax: 45, unit: Unit.seconds);
      final hist = [
        [for (final i in [0, 1, 2]) WorkSet(seconds: 45, setIndex: i)],
      ];
      final r = suggestNext(planned: p, sets: 3, history: hist, increment: 2, bodyweight: true);
      expect(r.kind, SuggestionKind.timeIncrease);
      expect(r.prefill[0].seconds, 50);
      final capped = suggestNext(
        planned: p,
        sets: 3,
        history: [
          [for (final i in [0, 1, 2]) WorkSet(seconds: 60, setIndex: i)],
        ],
        increment: 2,
      );
      expect(capped.kind, SuggestionKind.timeCap);
    });
    test('uses deload-adjusted set counts for prefill', () {
      final r = suggestNext(planned: planned, sets: 2, history: [[s(14, 9, 0), s(14, 9, 1), s(14, 9, 2)]], increment: 2);
      expect(r.prefill, hasLength(2));
    });
    test('bodyweight at top of range suggests a harder variant', () {
      final r = suggestNext(
        planned: planned,
        sets: 3,
        history: [
          [for (final i in [0, 1, 2]) WorkSet(reps: 10, setIndex: i)],
        ],
        increment: 2,
        bodyweight: true,
      );
      expect(r.kind, SuggestionKind.hold);
      expect(r.message, matches(RegExp('harder variant')));
    });
    test('maps equipment to increment buckets', () {
      expect(equipmentBucket(const Exercise(id: 'a', equipment: ['dumbbell'], name: 'Goblet squat')), Equip.dumbbell);
      expect(equipmentBucket(const Exercise(id: 'b', equipment: ['other'], name: 'Trap-bar deadlift')), Equip.barbell);
      expect(equipmentBucket(const Exercise(id: 'c', equipment: ['cable'], name: 'Seated cable row')), Equip.machine);
    });
  });

  group('strength metrics', () {
    test('computes Epley e1RM and ignores >12 reps', () {
      expect(e1rm(100, 3), closeTo(110, 0.005));
      expect(e1rm(100, 13), isNull);
      expect(e1rm(null, 5), isNull);
    });
    test('detects weight, e1rm and reps PRs', () {
      const prior = [WorkSet(weightKg: 14, reps: 10), WorkSet(weightKg: 16, reps: 6)];
      expect(detectPRs(const WorkSet(weightKg: 18, reps: 5), prior), [PRType.weight, PRType.e1rm]);
      expect(detectPRs(const WorkSet(weightKg: 14, reps: 11), prior), [PRType.reps]);
      expect(detectPRs(const WorkSet(weightKg: 14, reps: 12), prior), [PRType.e1rm, PRType.reps]);
      expect(detectPRs(const WorkSet(weightKg: 12, reps: 8), prior), isEmpty);
      expect(detectPRs(const WorkSet(weightKg: 50, reps: 8), const []), isEmpty);
    });
    test('sums working-set volume', () {
      expect(volume(const [WorkSet(weightKg: 10, reps: 10, isWarmup: false), WorkSet(weightKg: 5, reps: 10, isWarmup: true)]), 100);
    });
  });
}
