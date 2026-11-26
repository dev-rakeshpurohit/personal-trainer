// Port of src/domain/replan.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/domain/replan.dart';
import 'package:repmate/domain/schedule.dart';

void main() {
  ProgramDay day(int order, String id, Weekday weekday, DayType type, String title) =>
      ProgramDay(id: id, programId: 'prog', weekday: weekday, type: type, title: title, order: order);
  final days = [
    day(0, 'mon', Weekday.mon, DayType.rest, 'Rest'),
    day(1, 'A', Weekday.tue, DayType.strength, 'Strength A'),
    day(2, 'cardio', Weekday.wed, DayType.cardio, 'Cardio'),
    day(3, 'B', Weekday.thu, DayType.strength, 'Strength B'),
    day(4, 'power', Weekday.fri, DayType.conditioning, 'Power'),
    day(5, 'C', Weekday.sat, DayType.strength, 'Strength C'),
    day(6, 'sun', Weekday.sun, DayType.activeRecovery, 'Recovery'),
  ];
  // week of Mon 30 Nov 2026
  DateTime d(int date) => DateTime(2026, 11, 30 + date); // 0 = Mon 30 Nov
  String key(int n) {
    final x = d(n);
    return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }

  group('replanWeek', () {
    test('leaves the plan alone when nothing was missed', () {
      final p = replanWeek(days: days, today: d(2), done: [(programDayId: 'A', dayKey: key(1))]);
      expect(p.adjusted, isFalse);
      expect(p.byDate[key(2)]?.id, 'cardio');
    });
    test('missed Tuesday strength → done Wednesday, cardio is the one dropped', () {
      final p = replanWeek(days: days, today: d(2), done: []);
      expect(p.adjusted, isTrue);
      expect(p.missed.map((m) => m.day.id).toList(), ['A']);
      expect([2, 3, 4, 5].map((n) => p.byDate[key(n)]?.id).toList(), ['A', 'B', 'power', 'C']);
      // Sunday stays recovery: only cardio had to go, so no make-up slot is needed
      expect(p.byDate[key(6)]?.type, DayType.activeRecovery);
      expect(p.dropped.map((x) => x.id).toList(), ['cardio']);
    });
    test('drops the lowest priority session when even Sunday is not enough', () {
      // Missed Tue + Wed + Thu, today Fri
      final p = replanWeek(days: days, today: d(4), done: []);
      final assigned = [4, 5, 6].map((n) => p.byDate[key(n)]?.id).toList();
      expect(assigned, ['A', 'B', 'C']);
      expect(p.dropped.map((x) => x.id).toList()..sort(), ['cardio', 'power']);
    });
    test('does not touch today if a session is already done today', () {
      final p = replanWeek(days: days, today: d(2), done: [(programDayId: 'cardio', dayKey: key(2))]);
      expect(p.byDate[key(2)]?.id, 'cardio');
      expect(p.byDate[key(3)]?.id, 'A');
    });
    test('days before onboarding are never "missed"', () {
      final p = replanWeek(days: days, today: d(3), done: [], since: d(3));
      expect(p.adjusted, isFalse);
      expect(p.byDate[key(3)]?.id, 'B');
    });
    test('never schedules on a rest (gym closed) day', () {
      final p = replanWeek(days: days, today: d(6), done: []);
      expect(p.byDate[key(0)]?.type, DayType.rest);
      expect(p.byDate[key(6)]?.type, DayType.strength);
    });
    test('a make-up session covers the missed planned date for streaks', () {
      final cov = coveredDates(days, [(programDayId: 'A', dayKey: key(2))], weekDates(d(2)));
      expect(cov.contains(key(1)), isTrue);
      expect(cov.contains(key(2)), isTrue);
    });
  });

  group('allCoveredDates', () {
    test('adds the original planned date of a make-up session', () {
      final cov = allCoveredDates(days, [(programDayId: 'A', dayKey: key(3))]);
      expect(cov.toList()..sort(), [key(1), key(3)]..sort());
    });
  });
}
