// "Show your working": the diff between the active plan and a coach proposal, its impact on weekly
// sets per muscle group / Plan check / session time, and the Adjust edits. Pure Dart (no Flutter).
import 'dart:math' as math;

import '../../domain/ai_plan.dart';
import '../../domain/balance.dart';
import '../../domain/models.dart';
import '../../domain/session_plan.dart';

enum DiffKind { added, removed, changed, replaced }

/// "4×6", "3×8–12", "3×30 s", "1×20 min".
String doseLabel(int sets, int repsMin, int repsMax, Unit unit) {
  final reps = repsMin == repsMax ? '$repsMin' : '$repsMin–$repsMax';
  return switch (unit) {
    Unit.reps => '$sets×$reps',
    Unit.seconds => '$sets×$reps s',
    Unit.minutes => '$sets×$reps min',
    Unit.meters => '$sets×$reps m',
  };
}

String doseOf(NormExercise e) => doseLabel(e.sets, e.repsMin, e.repsMax, e.unit);

bool _sameDose(NormExercise a, NormExercise b) => a.sets == b.sets && a.repsMin == b.repsMin && a.repsMax == b.repsMax && a.unit == b.unit;

/// One exercise-level change inside a day.
class DiffLine {
  const DiffLine({required this.kind, required this.weekday, this.from, this.to});
  final DiffKind kind;

  /// The proposed day the line belongs to (for a removed day: the weekday it was on).
  final Weekday weekday;
  final NormExercise? from;
  final NormExercise? to;

  /// The exercise this line is about in the proposed plan (null for removed lines).
  String? get proposedId => to?.exerciseId;
  String get key => '${weekday.wire}:${from?.exerciseId ?? ''}>${to?.exerciseId ?? ''}';
}

/// Changes for one training day of the week.
class DayDiff {
  const DayDiff({required this.weekday, required this.title, this.fromTitle, this.movedFrom, this.isNewDay = false, this.isDropped = false, required this.lines, this.unchanged = 0});
  final Weekday weekday;
  final String title;

  /// Old title when the day was renamed ("Upper → Push").
  final String? fromTitle;

  /// Set when the session moved to another weekday ("Legs Sat → Wed").
  final Weekday? movedFrom;
  final bool isNewDay;
  final bool isDropped;
  final List<DiffLine> lines;
  final int unchanged;

  bool get hasChanges => lines.isNotEmpty || movedFrom != null || fromTitle != null || isNewDay || isDropped;
}

class WorkoutDiff {
  const WorkoutDiff(this.days);
  final List<DayDiff> days;
  bool get isEmpty => days.every((d) => !d.hasChanges);
  int get changeCount => days.fold(0, (s, d) => s + d.lines.length + (d.movedFrom != null ? 1 : 0));
}

List<NormDay> _trainingDays(NormWorkout? w) => w == null ? const [] : w.days.where((d) => d.type.isTraining && d.exercises.isNotEmpty).toList();

double _overlap(NormDay a, NormDay b) {
  final x = a.exercises.map((e) => e.exerciseId).toSet();
  final y = b.exercises.map((e) => e.exerciseId).toSet();
  final union = x.union(y).length;
  return union == 0 ? 0 : x.intersection(y).length / union;
}

bool _similar(Exercise? a, Exercise? b) {
  if (a == null || b == null) return false;
  if (a.pattern != null && a.pattern!.isNotEmpty && a.pattern == b.pattern) return true;
  return a.primaryMuscles.isNotEmpty && b.primaryMuscles.isNotEmpty && a.primaryMuscles.first == b.primaryMuscles.first;
}

/// Pair current and proposed training days: by shared exercises first, then by weekday and title.
List<(NormDay?, NormDay?)> _pairDays(List<NormDay> before, List<NormDay> after) {
  final cands = <(double, int, int)>[];
  for (var i = 0; i < before.length; i++) {
    for (var j = 0; j < after.length; j++) {
      final b = before[i], a = after[j];
      final score = _overlap(b, a) + (b.weekday == a.weekday ? 0.35 : 0) + (b.title.trim().toLowerCase() == a.title.trim().toLowerCase() ? 0.3 : 0);
      if (score >= 0.3) cands.add((score, i, j));
    }
  }
  cands.sort((x, y) {
    final c = y.$1.compareTo(x.$1);
    return c != 0 ? c : (x.$2 - y.$2);
  });
  final usedB = <int>{}, usedA = <int>{};
  final pairs = <(NormDay?, NormDay?)>[];
  for (final (_, i, j) in cands) {
    if (usedB.contains(i) || usedA.contains(j)) continue;
    usedB.add(i);
    usedA.add(j);
    pairs.add((before[i], after[j]));
  }
  for (var i = 0; i < before.length; i++) {
    if (!usedB.contains(i)) pairs.add((before[i], null));
  }
  for (var j = 0; j < after.length; j++) {
    if (!usedA.contains(j)) pairs.add((null, after[j]));
  }
  pairs.sort((x, y) => (x.$2 ?? x.$1)!.weekday.index - (y.$2 ?? y.$1)!.weekday.index);
  return pairs;
}

List<DiffLine> _exerciseLines(NormDay? b, NormDay? a, Weekday weekday, Map<String, Exercise> exMap) {
  final before = b?.exercises ?? const <NormExercise>[];
  final after = a?.exercises ?? const <NormExercise>[];
  final beforeIds = {for (final e in before) e.exerciseId: e};
  final afterIds = {for (final e in after) e.exerciseId: e};
  final removed = before.where((e) => !afterIds.containsKey(e.exerciseId)).toList();
  final lines = <DiffLine>[];
  for (final e in after) {
    final old = beforeIds[e.exerciseId];
    if (old != null) {
      if (!_sameDose(old, e)) lines.add(DiffLine(kind: DiffKind.changed, weekday: weekday, from: old, to: e));
      continue;
    }
    // a new exercise that stands in for a removed one of the same pattern = a swap
    final i = removed.indexWhere((r) => _similar(exMap[r.exerciseId], exMap[e.exerciseId]));
    if (i >= 0) {
      lines.add(DiffLine(kind: DiffKind.replaced, weekday: weekday, from: removed.removeAt(i), to: e));
    } else {
      lines.add(DiffLine(kind: DiffKind.added, weekday: weekday, to: e));
    }
  }
  for (final r in removed) {
    lines.add(DiffLine(kind: DiffKind.removed, weekday: weekday, from: r));
  }
  return lines;
}

/// Day-by-day diff of two weekly workouts. A null [before] means everything is new.
WorkoutDiff diffWorkouts(NormWorkout? before, NormWorkout? after, Map<String, Exercise> exMap) {
  if (after == null) return const WorkoutDiff([]);
  final days = <DayDiff>[];
  for (final (b, a) in _pairDays(_trainingDays(before), _trainingDays(after))) {
    final weekday = (a ?? b)!.weekday;
    final lines = _exerciseLines(b, a, weekday, exMap);
    final unchanged = (a?.exercises ?? const []).where((e) => b?.exercises.any((x) => x.exerciseId == e.exerciseId && _sameDose(x, e)) ?? false).length;
    final renamed = a != null && b != null && a.title.trim() != b.title.trim();
    days.add(DayDiff(
      weekday: weekday,
      title: (a ?? b)!.title,
      fromTitle: renamed ? b.title : null,
      movedFrom: a != null && b != null && a.weekday != b.weekday ? b.weekday : null,
      isNewDay: b == null,
      isDropped: a == null,
      lines: lines,
      unchanged: unchanged,
    ));
  }
  return WorkoutDiff(days);
}

/* ------------------------------------------------------------ diet */

enum MealChange { added, removed, changed }

class MealDiff {
  const MealDiff({required this.kind, this.from, this.to});
  final MealChange kind;
  final AiMeal? from;
  final AiMeal? to;
  String get meal => (to ?? from)!.meal;
}

class DietDiff {
  const DietDiff({this.kcalBefore, required this.kcalAfter, this.proteinBefore, required this.proteinAfter, required this.meals, this.unchangedMeals = 0});
  final double? kcalBefore;
  final double kcalAfter;
  final double? proteinBefore;
  final double proteinAfter;
  final List<MealDiff> meals;
  final int unchangedMeals;
}

String _norm(String s) => s.trim().toLowerCase();

DietDiff? diffDiets(AiDiet? before, AiDiet? after) {
  if (after == null) return null;
  final old = [...?before?.meals];
  final out = <MealDiff>[];
  var same = 0;
  for (final m in after.meals) {
    var i = old.indexWhere((o) => _norm(o.meal) == _norm(m.meal));
    if (i < 0) i = old.indexWhere((o) => o.time.padLeft(5, '0') == m.time.padLeft(5, '0'));
    if (i < 0) {
      out.add(MealDiff(kind: MealChange.added, to: m));
      continue;
    }
    final o = old.removeAt(i);
    final itemsSame = o.items.map(_norm).join('|') == m.items.map(_norm).join('|');
    if (itemsSame && o.kcal.round() == m.kcal.round() && o.proteinG.round() == m.proteinG.round()) {
      same++;
    } else {
      out.add(MealDiff(kind: MealChange.changed, from: o, to: m));
    }
  }
  for (final o in old) {
    out.add(MealDiff(kind: MealChange.removed, from: o));
  }
  return DietDiff(
    kcalBefore: before?.kcalTarget,
    kcalAfter: after.kcalTarget,
    proteinBefore: before?.proteinTargetG,
    proteinAfter: after.proteinTargetG,
    meals: out,
    unchangedMeals: same,
  );
}

/* ------------------------------------------------------------ impact */

class GroupImpact {
  const GroupImpact(this.group, this.before, this.after, this.target);
  final MuscleGroup group;
  final double before;
  final double after;
  final int target;
  bool get changed => before != after;
}

class PlanImpact {
  const PlanImpact({required this.groups, required this.gapsBefore, required this.gapsAfter, this.minutesBefore, this.minutesAfter});
  final List<GroupImpact> groups;
  final List<MuscleGroup> gapsBefore;
  final List<MuscleGroup> gapsAfter;
  final int? minutesBefore;
  final int? minutesAfter;

  bool get balanced => gapsAfter.isEmpty;

  /// The groups worth showing in the strip: every change, or the three biggest when nothing moved.
  List<GroupImpact> get highlights {
    final changed = groups.where((g) => g.changed).toList()..sort((a, b) => (b.after - b.before).abs().compareTo((a.after - a.before).abs()));
    if (changed.isNotEmpty) return changed;
    return ([...groups]..sort((a, b) => b.after.compareTo(a.after))).take(3).toList();
  }
}

/// [weeklySets] over a [NormWorkout] (synthetic day / planned ids).
Map<MuscleGroup, double> weeklySetsOf(NormWorkout? w, Map<String, Exercise> exMap) {
  if (w == null) return {for (final g in MuscleGroup.values) g: 0.0};
  final days = <DayLite>[];
  final planned = <PlannedExercise>[];
  for (var i = 0; i < w.days.length; i++) {
    final d = w.days[i];
    days.add(DayLite(id: 'd$i', title: d.title, weekday: d.weekday, type: d.type));
    for (var j = 0; j < d.exercises.length; j++) {
      final e = d.exercises[j];
      planned.add(PlannedExercise(
        id: 'd$i-$j',
        dayId: 'd$i',
        order: j,
        slot: e.slot,
        exerciseId: e.exerciseId,
        supersetGroup: e.supersetGroup,
        sets: e.sets,
        repsMin: e.repsMin,
        repsMax: e.repsMax,
        unit: e.unit,
        perSide: e.perSide,
        restSec: e.restSec,
      ));
    }
  }
  return weeklySets(days, planned, exMap);
}

/// Average estimated session length (minutes, rounded to 5) over the training days; null if none.
int? averageSessionMinutes(NormWorkout? w) {
  final days = _trainingDays(w);
  if (days.isEmpty) return null;
  final mins = [
    for (final d in days)
      estimateMinutes([
        for (final e in d.exercises)
          SessionExercise(
            plannedExerciseId: '',
            exerciseId: e.exerciseId,
            originalExerciseId: e.exerciseId,
            slot: e.slot,
            supersetGroup: e.supersetGroup,
            sets: e.sets,
            repsMin: e.repsMin,
            repsMax: e.repsMax,
            unit: e.unit,
            perSide: e.perSide,
            restSec: e.restSec,
            isMain: isMainSlot(e.slot, d.type),
          ),
      ]),
  ];
  return ((mins.reduce((a, b) => a + b) / mins.length) / 5).round() * 5;
}

PlanImpact impactOf(NormWorkout? before, NormWorkout? after, Map<String, Exercise> exMap, Goal? goal) {
  final b = weeklySetsOf(before, exMap);
  final a = weeklySetsOf(after, exMap);
  final t = targets(goal);
  return PlanImpact(
    groups: [for (final g in MuscleGroup.values) GroupImpact(g, b[g]!, a[g]!, t[g]!)],
    gapsBefore: before == null ? const [] : [for (final g in MuscleGroup.values) if (b[g]! < t[g]!) g],
    gapsAfter: [for (final g in MuscleGroup.values) if (a[g]! < t[g]!) g],
    minutesBefore: averageSessionMinutes(before),
    minutesAfter: averageSessionMinutes(after),
  );
}

/// "12", "10.5".
String setsLabel(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/* ------------------------------------------------------------ Adjust (edits to the proposed plan) */

NormExercise _withDose(NormExercise e, {int? sets, int? repsMin, int? repsMax}) {
  final lo = repsMin ?? e.repsMin;
  final hi = math.max(lo, repsMax ?? e.repsMax);
  return NormExercise(
    slot: e.slot,
    exerciseId: e.exerciseId,
    supersetGroup: e.supersetGroup,
    sets: sets ?? e.sets,
    repsMin: lo,
    repsMax: hi,
    unit: e.unit,
    perSide: e.perSide,
    restSec: e.restSec,
    cue: e.cue,
  );
}

NormExercise _copy(NormExercise e) => _withDose(e);

/// Re-letter slots after an edit: A, B, C… with superset partners sharing a letter (A1/A2).
List<NormExercise> _reslot(List<NormExercise> list) {
  // a superset needs two partners
  for (final x in list) {
    if (x.supersetGroup != null && list.where((y) => y.supersetGroup == x.supersetGroup).length < 2) x.supersetGroup = null;
  }
  var letter = 0;
  final groupLetter = <String, String>{};
  final groupCount = <String, int>{};
  for (final x in list) {
    final g = x.supersetGroup;
    if (g != null) {
      final l = groupLetter.putIfAbsent(g, () => String.fromCharCode(65 + letter++));
      final n = (groupCount[l] ?? 0) + 1;
      groupCount[l] = n;
      x.slot = '$l$n';
      x.supersetGroup = l;
    } else {
      x.slot = String.fromCharCode(65 + letter++);
    }
  }
  return list;
}

NormPlan _withWorkout(NormPlan p, NormWorkout w) => NormPlan(summary: p.summary, workout: w, diet: p.diet, warnings: p.warnings);

NormWorkout _mapDay(NormWorkout w, Weekday weekday, NormDay Function(NormDay d) f) =>
    NormWorkout(name: w.name, days: [for (final d in w.days) d.weekday == weekday ? f(d) : d]);

NormDay _dayWith(NormDay d, List<NormExercise> exercises, {DayType? type, String? title}) {
  final list = _reslot(exercises.map(_copy).toList());
  final empty = list.isEmpty && (type ?? d.type).isTraining;
  return NormDay(
    weekday: d.weekday,
    type: empty ? DayType.rest : (type ?? d.type),
    title: empty ? 'Rest' : (title ?? d.title),
    durationMin: d.durationMin,
    notes: d.notes,
    exercises: list,
  );
}

/// Adjust: change sets/reps of an exercise in the proposed plan.
NormPlan setDose(NormPlan plan, Weekday weekday, String exerciseId, {required int sets, required int repsMin, required int repsMax}) {
  final w = plan.workout;
  if (w == null) return plan;
  return _withWorkout(
    plan,
    _mapDay(w, weekday, (d) => _dayWith(d, [for (final e in d.exercises) e.exerciseId == exerciseId ? _withDose(e, sets: sets, repsMin: repsMin, repsMax: repsMax) : e])),
  );
}

/// Adjust: drop a diff line, i.e. keep that part of the current plan as it is.
NormPlan revertLine(NormPlan plan, DiffLine line, NormWorkout? before) {
  final w = plan.workout;
  if (w == null) return plan;
  final from = line.from;
  final to = line.to;
  NormDay? beforeDay() {
    if (before == null || from == null) return null;
    for (final d in before.days) {
      if (d.exercises.any((e) => e.exerciseId == from.exerciseId)) return d;
    }
    return null;
  }

  switch (line.kind) {
    case DiffKind.added:
      return _withWorkout(plan, _mapDay(w, line.weekday, (d) => _dayWith(d, d.exercises.where((e) => e.exerciseId != to!.exerciseId).toList())));
    case DiffKind.changed:
      return setDose(plan, line.weekday, to!.exerciseId, sets: from!.sets, repsMin: from.repsMin, repsMax: from.repsMax);
    case DiffKind.replaced:
      return _withWorkout(plan, _mapDay(w, line.weekday, (d) => _dayWith(d, [for (final e in d.exercises) e.exerciseId == to!.exerciseId ? _copy(from!) : e])));
    case DiffKind.removed:
      final src = beforeDay();
      return _withWorkout(
        plan,
        _mapDay(w, line.weekday, (d) {
          if (d.exercises.any((e) => e.exerciseId == from!.exerciseId)) return d;
          final wasRest = !d.type.isTraining || d.exercises.isEmpty;
          return _dayWith(d, [...d.exercises, _copy(from!)..supersetGroup = null],
              type: wasRest ? (src?.type ?? DayType.strength) : null, title: wasRest ? (src?.title ?? d.title) : null);
        }),
      );
  }
}
