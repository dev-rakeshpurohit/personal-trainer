// Pure helpers for the Today tab (no widgets): greeting, phase label, weekly goal, life status,
// the week strip's per-day state and the single coach note.
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/replan.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';

String greeting(int hour) => hour < 5
    ? 'Up late'
    : hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

/// "Week 3 of 8 · Accumulate" from the program's 8-week wave and start date.
class Phase {
  const Phase({required this.week, required this.total, required this.focus, required this.deload, this.note});
  final int week;
  final int total;
  final String? focus;
  final bool deload;
  final String? note;
  String get label => 'Week $week of $total${focus == null || focus!.isEmpty ? '' : ' · $focus'}';
}

Phase phaseOf(Program p, DateTime now) {
  final cw = cycleWeek(now, p.startedOn);
  final weeks = p.progression.weeks ?? const <WeekFocus>[];
  WeekFocus? f;
  for (final w in weeks) {
    if (w.week == cw) f = w;
  }
  var total = weeks.length;
  if (total == 0) {
    for (final c in p.progression.cycle) {
      for (final w in c.weeks) {
        if (w > total) total = w;
      }
    }
  }
  if (total == 0) total = 8;
  final deload = f?.deload ?? isDeloadWeek(cw, p.progression.cycle);
  return Phase(week: cw, total: total, focus: f?.focus ?? (deload ? 'Deload' : null), deload: deload, note: f?.note ?? cycleEntry(cw, p.progression.cycle)?.note);
}

/// Weekly goal: training sessions planned this week (minus any the re-plan had to drop) vs done.
({int done, int planned}) weeklyGoal(LiveWeekPlan? week, List<Session> weekSessions) {
  final planned = week == null ? 0 : week.original.values.where((d) => d != null && d.type.isTraining).length - (week.off ? 0 : week.dropped.length);
  final done = weekSessions.where((s) => s.status == 'done').length;
  return (done: done, planned: planned < 0 ? 0 : planned);
}

String weeklyGoalWords(int done, int planned) {
  if (planned == 0) return 'No sessions planned this week.';
  if (done >= planned) return 'Weekly goal hit. Rest days count as on plan.';
  final left = planned - done;
  return '$left more to hit this week\'s goal. Rest days are part of the plan.';
}

/* ------------------------------------------------------------ life happens */

enum LifeStatus {
  sick('sick', 'Sick', 'Rest is on plan while you recover. Your weekly goal is paused, nothing is lost.'),
  travelling('travelling', 'Travelling', 'Train if you find a gym, skip if you don\'t. Your weekly goal is paused.'),
  festival('festival', 'Festival', 'Enjoy it. Your weekly goal is paused; eat well and get back when you\'re ready.');

  const LifeStatus(this.wire, this.label, this.note);
  final String wire;
  final String label;
  final String note;

  static LifeStatus? parse(Object? meta) {
    final kind = meta is Map ? meta['kind'] : meta;
    for (final s in values) {
      if (s.wire == kind) return s;
    }
    return null;
  }
}

const kLifeStatusMeta = 'lifeStatus';

/// Meta key: the user's choice on this week's missed-session card ('shift' | 'skip').
String replanChoiceKey(DateTime date) => 'replanChoice:${dayKey(weekStartOf(date))}';

/* ------------------------------------------------------------ week strip */

enum DayMark { done, today, planned, missed, rest }

class StripDay {
  const StripDay({required this.date, required this.day, required this.mark, required this.isToday});
  final DateTime date;
  final ProgramDay? day;
  final DayMark mark;
  final bool isToday;

  String get semantic {
    final name = DateFormat('EEEE').format(date);
    final what = day != null && day!.type.isTraining ? day!.title : 'rest';
    final state = switch (mark) {
      DayMark.done => 'done',
      DayMark.today => 'today',
      DayMark.planned => 'planned',
      DayMark.missed => 'not done',
      DayMark.rest => 'rest day',
    };
    return '$name, $what, $state';
  }
}

List<StripDay> weekStrip(DateTime now, LiveWeekPlan? week, List<Session> weekSessions, {List<ProgramDay> days = const []}) {
  final today = dateOnly(now);
  // A make-up session later in the week also ticks the day it was planned for.
  final doneKeys = coveredDates(
    days,
    [for (final s in weekSessions) if (s.status == 'done') (programDayId: s.programDayId, dayKey: s.dayKey)],
    weekDates(today),
  );
  return [
    for (final d in weekDates(today))
      () {
        final k = dayKey(d);
        // Past days show what was originally planned; today and later show the re-planned week.
        final day = d.isBefore(today) ? week?.original[k] : week?.byDate[k];
        final training = day != null && day.type.isTraining;
        final isToday = k == dayKey(today);
        final mark = doneKeys.contains(k)
            ? DayMark.done
            : isToday
                ? DayMark.today
                : !training
                    ? DayMark.rest
                    : d.isBefore(today)
                        ? DayMark.missed
                        : DayMark.planned;
        return StripDay(date: d, day: day, mark: mark, isToday: isToday);
      }(),
  ];
}

/// "Missed Tuesday's Pull and Wednesday's Legs".
String missedWords(LiveWeekPlan week) {
  final parts = [for (final m in week.missed) "${DateFormat('EEEE').format(fromDayKey(m.date))}'s ${shortTitle(m.day.title)}"];
  if (parts.length <= 1) return 'Missed ${parts.join()}';
  return 'Missed ${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

/// "Strength A – Lower" → "Strength A".
String shortTitle(String t) => t.split(' –').first.split(' - ').first;
