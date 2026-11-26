// Port of src/domain/schedule.ts. Pure Dart. All dates are local calendar dates.
import 'models.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// yyyy-MM-dd in local time.
String dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Parse a yyyy-MM-dd day key to local midnight.
DateTime fromDayKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Local midnight of a date.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day difference a − b (DST-safe: compares dates, not hours).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second, d.millisecond);

Weekday weekdayOf(DateTime d) => Weekday.ofDate(d);

T? getDayPlan<T>(List<T> days, DateTime date, Weekday Function(T) weekdayOfDay) {
  final wd = weekdayOf(date);
  for (final d in days) {
    if (weekdayOfDay(d) == wd) return d;
  }
  return null;
}

/// Week of the 8-week cycle (1..8) for a date, counted from the program's start.
int cycleWeek(DateTime date, String startedOn) {
  final since = daysBetween(date, fromDayKey(startedOn));
  if (since < 0) return 1;
  return (since ~/ 7) % 8 + 1;
}

CycleEntry? cycleEntry(int week, List<CycleEntry> cycle) {
  for (final c in cycle) {
    if (c.weeks.contains(week)) return c;
  }
  return null;
}

bool isDeloadWeek(int week, List<CycleEntry> cycle) => cycleEntry(week, cycle)?.deload ?? false;

int? targetRir(int week, List<CycleEntry> cycle) => cycleEntry(week, cycle)?.rir;

int deloadSets(int sets) => (sets / 2).ceil();

int effectiveSets(int sets, bool deload) => deload ? deloadSets(sets) : sets;

/// Monday- (or Sunday-) based week start for a date (local midnight).
DateTime weekStartOf(DateTime d, {String weekStart = 'mon'}) {
  final day = dateOnly(d);
  final offset = weekStart == 'mon' ? (d.weekday - DateTime.monday) : (d.weekday % 7);
  return addDays(day, -offset);
}

List<DateTime> weekDates(DateTime d, {String weekStart = 'mon'}) {
  final s = weekStartOf(d, weekStart: weekStart);
  return List.generate(7, (i) => addDays(s, i));
}
