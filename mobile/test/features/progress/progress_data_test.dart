// Pure Progress logic: lift series + PRs, strength levels, weekly summary.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/progress/progress_data.dart';

Session _session(String id, String day) =>
    Session(id: id, dayKey: day, title: 'S', startedAt: '${day}T09:15:00.000', status: 'done', cycleWeek: 1, deload: false);

SetLog _set(String session, double? w, int reps, {int i = 0}) =>
    SetLog(id: '$session-$i', sessionId: session, exerciseId: 'x', setIndex: i, weightKg: w, reps: reps, completedAt: '', isWarmup: false);

Exercise _ex(String name, List<String> equipment) =>
    Exercise(id: 'x', name: name, primaryMuscles: const [], equipment: equipment, category: Category.values.first, custom: false, defaultUnit: Unit.reps);

void main() {
  test('lift series: best set per session, PR when it beats every earlier session', () {
    final sessions = {
      for (final s in [_session('a', '2026-11-02'), _session('b', '2026-11-09'), _session('c', '2026-11-16'), _session('d', '2026-11-23')]) s.id: s,
    };
    final sets = [
      _set('a', 40, 8), _set('a', 42.5, 6, i: 1), //
      _set('b', 40, 8),
      _set('c', 45, 8),
      _set('d', 45, 8),
    ];
    final s = liftSeries(sets, sessions);
    expect(s.map((p) => p.sessionId), ['a', 'b', 'c', 'd']);
    expect(s.first.v, closeTo(42.5 * (1 + 6 / 30), 1e-9));
    expect(s.map((p) => p.pr), [false, false, true, false]);
    expect(s.every((p) => p.weighted), isTrue);
  });

  test('ranges keep only recent sessions', () {
    final sessions = {for (final s in [_session('a', '2026-06-01'), _session('b', '2026-11-20')]) s.id: s};
    final s = liftSeries([_set('a', 40, 8), _set('b', 40, 8)], sessions);
    expect(inRange(s, ChartRange.m1, DateTime(2026, 12, 3)), hasLength(1));
    expect(inRange(s, ChartRange.y1, DateTime(2026, 12, 3)), hasLength(2));
  });

  test('lift kinds from names', () {
    expect(liftKindOf('Dumbbell goblet squat'), LiftKind.squat);
    expect(liftKindOf('Trap-bar deadlift'), LiftKind.hinge);
    expect(liftKindOf('Dumbbell Romanian deadlift'), LiftKind.hinge);
    expect(liftKindOf('Incline dumbbell press'), LiftKind.bench);
    expect(liftKindOf('Standing dumbbell shoulder press'), LiftKind.overhead);
    expect(liftKindOf('Lat pulldown'), LiftKind.pull);
    expect(liftKindOf('Face pull'), isNull);
  });

  test('strength level: barbell bench 1.0× body weight is Intermediate; dumbbells scale per hand', () {
    final bench = strengthRating(exercise: _ex('Barbell bench press', ['barbell']), e1rmKg: 80, bodyweightKg: 80, sex: Sex.male)!;
    expect(bench.level, StrengthLevel.intermediate);
    expect(bench.next, StrengthLevel.advanced);
    expect(bench.nextKg, closeTo(100, 1e-9));
    final db = strengthRating(exercise: _ex('Dumbbell bench press', ['dumbbell']), e1rmKg: 30, bodyweightKg: 80, sex: Sex.male)!;
    expect(db.level, StrengthLevel.intermediate, reason: '30 kg per hand ≥ 0.85 × 0.4 × 80');
    final beginner = strengthRating(exercise: _ex('Barbell back squat', ['barbell']), e1rmKg: 40, bodyweightKg: 80, sex: Sex.male)!;
    expect(beginner.level, StrengthLevel.beginner);
    expect(beginner.progress, closeTo(40 / 60, 1e-9));
    final female = strengthRating(exercise: _ex('Barbell back squat', ['barbell']), e1rmKg: 40, bodyweightKg: 60, sex: Sex.female)!;
    expect(female.level, StrengthLevel.novice);
    expect(strengthRating(exercise: _ex('Face pull', ['cable']), e1rmKg: 40, bodyweightKg: 60, sex: Sex.male), isNull);
  });

  test('weekly summary: counts, top sets, trend and a positive sentence', () {
    final sessions = {for (final s in [_session('a', '2026-11-24'), _session('b', '2026-12-01')]) s.id: s};
    final series = liftSeries([_set('a', 40, 8), _set('b', 45, 8)], sessions);
    final weights = [
      for (var i = 0; i < 14; i++) (dayKey: '2026-11-${(20 + i).toString().padLeft(2, '0')}', value: 80 - i * 0.1),
    ].where((p) => p.dayKey.compareTo('2026-11-30') <= 0).toList()
      ..addAll([(dayKey: '2026-12-01', value: 78.6), (dayKey: '2026-12-02', value: 78.5), (dayKey: '2026-12-03', value: 78.4)]);
    final w = weeklySummary(
      now: DateTime(2026, 12, 3, 13),
      done: 2,
      planned: 5,
      mainSeries: {'x': series},
      weights: weights,
      proteinHit: 2,
      goalWeightKg: 74,
    );
    expect(w.liftsUp, 1);
    expect(w.liftsTrained, 1);
    expect(w.trendKg, isNotNull);
    expect(w.trendDeltaKg, lessThan(0));
    expect(w.sentence, '2/5 sessions and 2/7 protein days: 1 top set beat your best.');
    final best = weeklySummary(now: DateTime(2026, 12, 6), done: 5, planned: 5, mainSeries: const {}, weights: const [], proteinHit: 6, goalWeightKg: 74);
    expect(best.sentence, '5/5 sessions and 6/7 protein days: your best kind of week.');
    for (final s in [w.sentence, best.sentence]) {
      expect(s.toLowerCase(), isNot(contains('missed')));
      expect(s.toLowerCase(), isNot(contains('failed')));
    }
  });
}
