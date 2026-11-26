// Port of src/domain/replan.ts. Pure Dart: no Flutter imports.
//
// Missed-session auto re-plan (see DECISIONS.md).
// If a planned training day earlier this week was missed, the remaining sessions are re-flowed
// onto the remaining training slots: missed sessions are done next, in order. If there are more
// sessions than slots, an active-recovery day (e.g. Sunday) becomes a make-up slot for strength work,
// and only then is the lowest-priority session (cardio → conditioning → strength) dropped.
// Rest days (gym closed) are never used.
import 'models.dart';
import 'schedule.dart';

/// A completed session: which program day it was and the day it was done on.
typedef DoneDay = ({String? programDayId, String dayKey});

/// A planned training day that was missed, with its original date (yyyy-MM-dd).
typedef MissedDay = ({ProgramDay day, String date});

class WeekPlan {
  const WeekPlan({required this.byDate, required this.original, required this.missed, required this.dropped, required this.adjusted});

  /// What to do on each date of the week (dayKey → program day, or null = rest/nothing).
  final Map<String, ProgramDay?> byDate;

  /// Original plan for each date, for "moved from" labels.
  final Map<String, ProgramDay?> original;
  final List<MissedDay> missed;
  final List<ProgramDay> dropped;
  final bool adjusted;

  WeekPlan copyWith({Map<String, ProgramDay?>? byDate, List<MissedDay>? missed, List<ProgramDay>? dropped, bool? adjusted}) => WeekPlan(
        byDate: byDate ?? this.byDate,
        original: original,
        missed: missed ?? this.missed,
        dropped: dropped ?? this.dropped,
        adjusted: adjusted ?? this.adjusted,
      );
}

int _priority(DayType t) => switch (t) {
      DayType.strength => 3,
      DayType.conditioning => 2,
      DayType.cardio => 1,
      DayType.activeRecovery => 0,
      DayType.rest => 0,
    };

/// Re-plan the week containing [today].
/// [done] lists sessions completed (status done) this week. Planned days before [since]
/// (e.g. onboarding) never count as missed.
WeekPlan replanWeek({
  required List<ProgramDay> days,
  required DateTime today,
  required List<DoneDay> done,
  String weekStart = 'mon',
  DateTime? since,
}) {
  final now = dateOnly(today);
  final todayKey = dayKey(now);
  final dates = weekDates(now, weekStart: weekStart);
  ProgramDay? dayFor(DateTime d) => getDayPlan(days, d, (x) => x.weekday);
  final original = <String, ProgramDay?>{for (final d in dates) dayKey(d): dayFor(d)};
  final doneIds = {for (final x in done) if (x.programDayId != null && x.programDayId!.isNotEmpty) x.programDayId!};
  final doneToday = done.any((x) => x.dayKey == todayKey);

  final training = <({DateTime date, ProgramDay day})>[
    for (final d in dates)
      if (dayFor(d) case final day? when day.type.isTraining) (date: d, day: day),
  ];
  final sinceDay = since == null ? null : dateOnly(since);
  final missed = training
      .where((x) => x.date.isBefore(now) && !doneIds.contains(x.day.id) && !(sinceDay != null && x.date.isBefore(sinceDay)))
      .toList();
  final upcoming = training.where((x) => !x.date.isBefore(now) && !doneIds.contains(x.day.id)).toList();

  final byDate = Map<String, ProgramDay?>.of(original);
  if (missed.isEmpty) {
    return WeekPlan(byDate: byDate, original: original, missed: const [], dropped: const [], adjusted: false);
  }

  // training slots from today on (today only if nothing has been done yet today)
  final slots = training
      .where((x) => !x.date.isBefore(now))
      .where((x) => !(doneToday && dayKey(x.date) == todayKey))
      .map((x) => x.date)
      .toList();
  final queue = [...missed, ...upcoming].map((x) => x.day).toList();

  // Make-up slots: active-recovery days still ahead, used only for strength that would otherwise be dropped
  final recovery = dates.where((d) => !d.isBefore(now) && dayFor(d)?.type == DayType.activeRecovery).toList();
  var over = queue.length - slots.length;
  bool strengthAtRisk() {
    // Only the multiset of types in the first `over` entries matters, so sort stability is irrelevant.
    final sorted = [...queue]..sort((a, b) => _priority(a.type) - _priority(b.type));
    return sorted.take(over < 0 ? 0 : over).any((d) => d.type == DayType.strength);
  }

  while (over > 0 && recovery.isNotEmpty && strengthAtRisk()) {
    slots.add(recovery.removeAt(0));
    over--;
  }
  slots.sort((a, b) => a.compareTo(b));

  final dropped = <ProgramDay>[];
  while (queue.length > slots.length) {
    // drop the lowest-priority session; ties → the later one
    var idx = 0;
    for (var i = 0; i < queue.length; i++) {
      if (_priority(queue[i].type) <= _priority(queue[idx].type)) idx = i;
    }
    dropped.add(queue.removeAt(idx));
  }

  // clear training days from today on, then assign the queue in order
  for (var d = now; !d.isAfter(dates[6]); d = addDays(d, 1)) {
    final k = dayKey(d);
    final o = original[k];
    if (o != null && o.type.isTraining) byDate[k] = null;
  }
  for (var i = 0; i < slots.length; i++) {
    if (i < queue.length) byDate[dayKey(slots[i])] = queue[i];
  }
  if (doneToday) byDate[todayKey] = original[todayKey];

  return WeekPlan(
    byDate: byDate,
    original: original,
    missed: [for (final m in missed) (day: m.day, date: dayKey(m.date))],
    dropped: dropped,
    adjusted: true,
  );
}

/// Planned dates whose session was completed (on the day, or as a make-up later that week).
Set<String> coveredDates(List<ProgramDay> days, List<DoneDay> done, List<DateTime> weekDatesList) {
  final out = {for (final d in done) d.dayKey};
  for (final d in weekDatesList) {
    final p = getDayPlan(days, d, (x) => x.weekday);
    if (p != null && done.any((x) => x.programDayId == p.id)) out.add(dayKey(d));
  }
  return out;
}

/// All planned dates covered by done sessions (on the day or as a make-up within the same Mon–Sun week).
Set<String> allCoveredDates(List<ProgramDay> days, List<DoneDay> done) {
  final out = <String>{};
  for (final s in done) {
    out.add(s.dayKey);
    ProgramDay? p;
    for (final d in days) {
      if (d.id == s.programDayId) {
        p = d;
        break;
      }
    }
    if (p == null) continue;
    final k = fromDayKey(s.dayKey);
    final noon = DateTime(k.year, k.month, k.day, 12);
    for (final d in weekDates(noon)) {
      if (weekdayOf(d) == p.weekday) {
        out.add(dayKey(d));
        break;
      }
    }
  }
  return out;
}
