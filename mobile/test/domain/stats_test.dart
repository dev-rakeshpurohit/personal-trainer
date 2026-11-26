import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/schedule.dart';
import 'package:repmate/domain/stats.dart';

/// Jest toBeCloseTo(expected, digits): |actual − expected| < 10^−digits / 2.
Matcher closeToDigits(double expected, [int digits = 2]) => closeTo(expected, 0.5 * _pow10(-digits));
double _pow10(int e) {
  var r = 1.0;
  for (var i = 0; i < e.abs(); i++) {
    r *= 10;
  }
  return e < 0 ? 1 / r : r;
}

final today = DateTime(2026, 12, 20); // Sunday

List<StatPoint> series(int days, double start, double perDay, [bool Function(int i)? skip]) => [
      for (var i = 0; i < days; i++)
        if (skip == null || !skip(i)) (dayKey: dayKey(addDays(today, -(days - 1 - i))), value: start + perDay * i),
    ];

void main() {
  group('body stats', () {
    test('weekly average needs ≥4 weigh-ins', () {
      final pts = <StatPoint>[
        for (final i in [0, 1, 2]) (dayKey: dayKey(addDays(DateTime(2026, 12, 14), i)), value: 80),
      ];
      final w = weeklyAverage(pts, DateTime(2026, 12, 14));
      expect(w.valid, isFalse);
      expect(w.needed, 1);
      pts.add((dayKey: '2026-12-18', value: 76));
      final w2 = weeklyAverage(pts, DateTime(2026, 12, 16));
      expect(w2.valid, isTrue);
      expect(w2.avg, 79);
    });

    test('7-day moving average handles gaps', () {
      final ma = movingAverage7([
        (dayKey: '2026-12-01', value: 80),
        (dayKey: '2026-12-03', value: 78),
        (dayKey: '2026-12-09', value: 76),
      ]);
      expect(ma[1].value, 79);
      expect(ma[2].value, 77);
    });

    test('regression rate over 21 days', () {
      final pts = series(21, 80, -0.1); // −0.7 kg/week
      final r = rateKgPerWeek(pts, today)!;
      expect(r.method, RateMethod.regression);
      expect(r.lossPerWeek, closeToDigits(0.7, 5));
    });

    test('falls back to weekly averages with sparse data', () {
      final pts = series(21, 80, -0.1, (i) => i % 2 == 1); // 11 pts → still regression
      expect(rateKgPerWeek(pts, today)?.method, RateMethod.regression);
      final sparse = series(21, 80, -0.1, (i) => i % 3 != 0); // 7 pts → too few
      expect(rateKgPerWeek(sparse, today), isNull);
    });

    test('linear slope', () {
      expect(linearSlope([(x: 0, y: 1), (x: 1, y: 3)]), 2);
      expect(linearSlope([(x: 0, y: 1)]), isNull);
    });

    test('projects goal date only when losing > 0.1 kg/week', () {
      expect(projectedGoalDate(79, 73, 0.6, today), addDays(today, 70));
      expect(projectedGoalDate(79, 73, 0.05, today), isNull);
      expect(projectedGoalDate(72, 73, 0.6, today), isNull);
    });

    test('current 7-day average', () {
      expect(current7dAvg(series(10, 80, 0), today), 80);
    });

    test('weekly loss checks use completed weeks only', () {
      final pts = series(35, 80, -0.1);
      final checks = weeklyLossChecks(pts, today);
      expect(checks.length, greaterThanOrEqualTo(3));
      for (final c in checks) {
        expect(c, closeToDigits(0.7, 5));
      }
    });

    test('pct change', () {
      expect(pctChange([100, 110]), closeToDigits(10));
      expect(pctChange([100]), isNull);
    });

    // Extra Dart-side checks.
    test('weekly rate fallback uses consecutive valid weeks', () {
      // 4 weigh-ins in each of the two weeks before today's week; nothing in the last 21 days is dense enough.
      final pts = <StatPoint>[
        for (final d in ['2026-12-07', '2026-12-08', '2026-12-09', '2026-12-10']) (dayKey: d, value: 80),
        for (final d in ['2026-12-14', '2026-12-15', '2026-12-16', '2026-12-17']) (dayKey: d, value: 79.5),
      ];
      final r = rateKgPerWeek(pts, today)!;
      expect(r.method, RateMethod.weekly);
      expect(r.lossPerWeek, closeToDigits(0.5, 5));
    });

    test('weekly averages are oldest first and Monday-based', () {
      final ws = weeklyAverages(const [], today, 3);
      expect(ws.map((w) => w.weekStart).toList(), ['2026-11-30', '2026-12-07', '2026-12-14']);
      expect(ws.first.avg, isNull);
      expect(ws.first.needed, kMinWeighinsPerWeek);
    });

    test('pct change from zero is null', () {
      expect(pctChange([0, 10]), isNull);
    });
  });

  group('training streak', () {
    bool planned(DateTime d) {
      final js = d.weekday % 7; // JS getDay(): Sun = 0
      return js >= 2 && js <= 6; // Tue–Sat
    }

    test('counts planned days done, rest days do not break it', () {
      // today = Sun 20 Dec. Tue 15–Sat 19 done, plus Sat 12 done, Fri 11 missed
      final done = {'2026-12-15', '2026-12-16', '2026-12-17', '2026-12-18', '2026-12-19', '2026-12-12'};
      expect(trainingStreak(planned, done, today), 6);
    });

    test('today not yet done does not break the streak', () {
      final tue = DateTime(2026, 12, 22);
      final done = {'2026-12-19', '2026-12-18'};
      expect(trainingStreak(planned, done, tue), 2);
    });

    test('a missed planned day breaks it', () {
      final done = {'2026-12-19', '2026-12-17'};
      expect(trainingStreak(planned, done, today), 1);
    });

    test('stops at since', () {
      final done = {'2026-12-15', '2026-12-16', '2026-12-17', '2026-12-18', '2026-12-19', '2026-12-12'};
      expect(trainingStreak(planned, done, today, since: DateTime(2026, 12, 14)), 5);
    });
  });
}
