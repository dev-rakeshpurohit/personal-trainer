// Port of src/domain/stats.ts. Pure Dart. Dates are local calendar dates;
// day keys are yyyy-MM-dd parsed to local midnight (like date-fns parseISO).
import 'schedule.dart';

/// A dated value (e.g. a weigh-in). Named `StatPoint` (TS: `Point`) to avoid clashing with dart:math.
typedef StatPoint = ({String dayKey, double value});

/// JS Math.round: halves round towards +∞.
int _jsRound(double x) {
  final r = x.roundToDouble();
  return (x - r == 0.5 ? r + 1 : r).toInt();
}

double _mean(Iterable<StatPoint> pts) => pts.fold<double>(0, (a, p) => a + p.value) / pts.length;

/// 7-day trailing moving average for each point (calendar-day window, handles gaps).
List<StatPoint> movingAverage7(List<StatPoint> points) {
  final sorted = [...points]..sort((a, b) => a.dayKey.compareTo(b.dayKey));
  return sorted.map((p) {
    final d = fromDayKey(p.dayKey);
    final win = sorted.where((q) {
      final diff = daysBetween(d, fromDayKey(q.dayKey));
      return diff >= 0 && diff < 7;
    });
    return (dayKey: p.dayKey, value: _mean(win));
  }).toList();
}

class WeeklyAvg {
  const WeeklyAvg({required this.weekStart, this.avg, required this.count, required this.valid, required this.needed});

  /// yyyy-MM-dd of the Monday.
  final String weekStart;
  final double? avg;
  final int count;
  final bool valid;
  final int needed;

  @override
  String toString() => 'WeeklyAvg($weekStart, avg: $avg, count: $count, valid: $valid, needed: $needed)';
}

const int kMinWeighinsPerWeek = 4;

/// Mean of weigh-ins in the ISO week (Monday start) containing [weekStart].
WeeklyAvg weeklyAverage(List<StatPoint> points, DateTime weekStart) {
  final ws = weekStartOf(weekStart);
  final end = addDays(ws, 7);
  final inWeek = points.where((p) {
    final d = fromDayKey(p.dayKey);
    return !d.isBefore(ws) && d.isBefore(end);
  }).toList();
  final count = inWeek.length;
  final needed = kMinWeighinsPerWeek - count;
  return WeeklyAvg(
    weekStart: dayKey(ws),
    count: count,
    valid: count >= kMinWeighinsPerWeek,
    needed: needed < 0 ? 0 : needed,
    avg: count > 0 ? _mean(inWeek) : null,
  );
}

/// Least-squares slope (y per x); null with < 2 points or zero x-variance.
double? linearSlope(List<({double x, double y})> xy) {
  final n = xy.length;
  if (n < 2) return null;
  final mx = xy.fold<double>(0, (a, p) => a + p.x) / n;
  final my = xy.fold<double>(0, (a, p) => a + p.y) / n;
  var num = 0.0;
  var den = 0.0;
  for (final p in xy) {
    num += (p.x - mx) * (p.y - my);
    den += (p.x - mx) * (p.x - mx);
  }
  return den == 0 ? null : num / den;
}

enum RateMethod { regression, weekly }

/// `lossPerWeek` is kg lost per week (positive = losing).
typedef Rate = ({double lossPerWeek, RateMethod method});

/// Rate of loss (doc 06 §4): regression over last 21 days (≥10 points), else consecutive valid weekly averages.
Rate? rateKgPerWeek(List<StatPoint> points, DateTime today) {
  final recent = points.where((p) {
    final diff = daysBetween(today, fromDayKey(p.dayKey));
    return diff >= 0 && diff < 21;
  }).toList();
  if (recent.length >= 10) {
    final slope = linearSlope([
      for (final p in recent) (x: -daysBetween(today, fromDayKey(p.dayKey)).toDouble(), y: p.value),
    ]);
    if (slope != null) return (lossPerWeek: -slope * 7, method: RateMethod.regression);
  }
  final weeks = weeklyAverages(points, today, 8).where((w) => w.valid).toList();
  if (weeks.length >= 2) {
    final a = weeks[weeks.length - 2].avg!;
    final b = weeks[weeks.length - 1].avg!;
    return (lossPerWeek: a - b, method: RateMethod.weekly);
  }
  return null;
}

/// The last [n] ISO weeks (oldest first) ending with the week containing [today].
List<WeeklyAvg> weeklyAverages(List<StatPoint> points, DateTime today, int n) {
  final cur = weekStartOf(today);
  return List.generate(n, (i) => weeklyAverage(points, addDays(cur, -7 * (n - 1 - i))));
}

/// Weekly loss for each pair of consecutive valid weeks (completed weeks only), oldest first.
List<double> weeklyLossChecks(List<StatPoint> points, DateTime today, {int n = 4}) {
  final weeks = weeklyAverages(points, addDays(weekStartOf(today), -1), n + 1);
  final out = <double>[];
  for (var i = 1; i < weeks.length; i++) {
    final a = weeks[i - 1];
    final b = weeks[i];
    if (a.valid && b.valid) out.add(a.avg! - b.avg!);
  }
  return out;
}

/// Mean of the points in the 7 calendar days ending [today]; null if none.
double? current7dAvg(List<StatPoint> points, DateTime today) {
  final win = points.where((p) {
    final diff = daysBetween(today, fromDayKey(p.dayKey));
    return diff >= 0 && diff < 7;
  }).toList();
  return win.isNotEmpty ? _mean(win) : null;
}

/// Projected goal date; only when losing faster than 0.1 kg/week and above goal.
/// Keeps [today]'s time of day (like date-fns addDays).
DateTime? projectedGoalDate(double? current, double goal, double? lossPerWeek, DateTime today) {
  if (current == null || lossPerWeek == null || lossPerWeek <= 0.1 || current <= goal) return null;
  final weeks = (current - goal) / lossPerWeek;
  return addDays(today, _jsRound(weeks * 7));
}

/// Training streak (doc 06 §7): consecutive *planned* training days completed, walking back from today.
/// Today counts if done; if not yet done it doesn't break the streak. Days before [since] are ignored.
int trainingStreak(bool Function(DateTime d) isPlanned, Set<String> doneDayKeys, DateTime today, {DateTime? since}) {
  var streak = 0;
  for (var i = 0; i < 400; i++) {
    final d = addDays(today, -i);
    if (since != null && d.isBefore(since)) break;
    if (!isPlanned(d)) continue;
    final done = doneDayKeys.contains(dayKey(d));
    if (done) {
      streak++;
    } else if (i == 0) {
      continue;
    } else {
      break;
    }
  }
  return streak;
}

/// Percentage change between first and last of a series (e.g. e1RM over 4 weeks).
/// Null with < 2 values or a zero/NaN first value.
double? pctChange(List<double> series) {
  if (series.length < 2 || series.first == 0 || series.first.isNaN) return null;
  return ((series.last - series.first) / series.first) * 100;
}
