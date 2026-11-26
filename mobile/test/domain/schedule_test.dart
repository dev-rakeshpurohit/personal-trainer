import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/domain/schedule.dart';
import 'package:repmate/domain/units.dart';

void main() {
  const cycle = [
    CycleEntry(weeks: [1, 2], rir: 3),
    CycleEntry(weeks: [3, 4, 5, 6, 7], rir: 2),
    CycleEntry(weeks: [8], rir: 3, deload: true),
  ];

  group('schedule', () {
    test('maps dates to weekdays', () {
      expect(weekdayOf(DateTime(2026, 12, 1)), Weekday.tue);
      expect(weekdayOf(DateTime(2026, 11, 29)), Weekday.sun);
      expect(weekdayOf(DateTime(2026, 11, 30)), Weekday.mon);
    });
    test('finds the day plan or null for rest', () {
      final days = [(wd: Weekday.tue, title: 'A')];
      expect(getDayPlan(days, DateTime(2026, 12, 1), (d) => d.wd)?.title, 'A');
      expect(getDayPlan(days, DateTime(2026, 12, 2), (d) => d.wd), isNull);
    });
    test('computes the 8-week cycle', () {
      expect(cycleWeek(DateTime(2026, 1, 1), '2026-01-01'), 1);
      expect(cycleWeek(DateTime(2026, 1, 7), '2026-01-01'), 1);
      expect(cycleWeek(DateTime(2026, 1, 8), '2026-01-01'), 2);
      expect(cycleWeek(DateTime(2026, 2, 19), '2026-01-01'), 8);
      expect(cycleWeek(DateTime(2026, 2, 26), '2026-01-01'), 1);
      expect(cycleWeek(DateTime(2025, 12, 1), '2026-01-01'), 1);
    });
    test('flags deload and halves sets rounding up', () {
      expect(isDeloadWeek(8, cycle), isTrue);
      expect(isDeloadWeek(5, cycle), isFalse);
      expect(targetRir(4, cycle), 2);
      expect(deloadSets(3), 2);
      expect(deloadSets(4), 2);
      expect(effectiveSets(3, false), 3);
    });
    test('formats day keys in local time and round-trips', () {
      expect(dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(fromDayKey('2026-03-29'), DateTime(2026, 3, 29));
    });
    test('week starts on Monday or Sunday', () {
      expect(dayKey(weekStartOf(DateTime(2026, 12, 3))), '2026-11-30');
      expect(dayKey(weekStartOf(DateTime(2026, 11, 29))), '2026-11-23');
      expect(dayKey(weekStartOf(DateTime(2026, 12, 3), weekStart: 'sun')), '2026-11-29');
      expect(weekDates(DateTime(2026, 12, 3)).map(dayKey).last, '2026-12-06');
    });
  });

  group('units', () {
    test('displays weights', () {
      expect(displayWeight(20, 'kg'), '20');
      expect(displayWeight(22.5, 'kg'), '22.5');
      expect(displayWeight(null, 'kg'), '–');
      expect(displayWeight(20, 'lb'), '44');
    });
    test('durations', () {
      expect(formatDuration(65), '1:05');
      expect(formatDuration(3725), '1:02:05');
      expect(formatDuration(-3), '0:00');
    });
  });
}
