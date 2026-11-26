// Port of src/domain/sessionPlan.ts. Pure Dart: no Flutter imports.
// Builds the concrete exercise list for a session: periodization (RIR per week, deload, accessory
// set bumps), Express mode, gradual HIIT ramp for conditioning days, and adaptations from previous
// feedback. See docs/09-RESEARCH.md + DECISIONS.md.
import 'dart:math' as math;

import 'package:collection/collection.dart' show mergeSort;

import 'models.dart';
import 'schedule.dart';

final _mainSlotRe = RegExp(r'^[AB]', caseSensitive: false);

/// JS truthiness for an optional string ('' counts as absent).
bool _present(String? s) => s != null && s.isNotEmpty;

/// JS Math.round (halves round towards +∞).
int _jsRound(double x) => (x + 0.5).floor();

bool isMainSlot(String slot, DayType dayType) => dayType == DayType.strength && _mainSlotRe.hasMatch(slot);

/// Intervals: timed, ≥ 4 rounds, not part of a circuit (e.g. "30 s hard / 90 s easy × 6").
bool isInterval(PlannedExercise pe) => pe.unit == Unit.seconds && pe.sets >= 4 && !_present(pe.supersetGroup);

/// HIIT ramp level 1–3 from completed conditioning sessions' feel (latest first; null = no feedback).
int hiitLevel(List<Feel?> history) {
  final good = history.where((f) => f != Feel.tooHard).length;
  var level = math.min(3, 1 + good ~/ 2);
  if (history.isNotEmpty && history[0] == Feel.tooHard) level = math.max(1, level - 1);
  return level;
}

class Adaptation {
  Adaptation({
    this.holdProgression = false,
    this.accessorySetsDelta = 0,
    this.preferExpress = false,
    List<String>? pain,
    List<String>? reasons,
  })  : pain = pain ?? [],
        reasons = reasons ?? [];
  bool holdProgression;
  int accessorySetsDelta;
  bool preferExpress;
  List<String> pain;
  final List<String> reasons;
}

/// Adapt the next session of a program day from its recent feedback (latest first).
Adaptation adaptFromFeedback(List<SessionFeedback> recent) {
  final a = Adaptation();
  if (recent.isEmpty) return a;
  final last = recent[0];
  if (last.feel == Feel.tooHard || last.rpe >= 9) {
    a.holdProgression = true;
    a.accessorySetsDelta = -1;
    a.reasons.add('Last time felt very hard: holding weights and trimming 1 accessory set.');
  } else if (recent.length >= 2 && recent.take(2).every((f) => f.feel == Feel.tooEasy || f.rpe <= 5)) {
    a.accessorySetsDelta = 1;
    a.reasons.add('Two easy sessions in a row: +1 set on accessories.');
  }
  if (last.ranOutOfTime) {
    a.preferExpress = true;
    a.reasons.add('You ran out of time last time: Express mode suggested.');
  }
  if (last.energy == 'low' && !a.holdProgression) a.reasons.add('Low energy last time: sleep and protein first.');
  a.pain = last.pain.toSet().toList();
  if (a.pain.isNotEmpty) a.reasons.add('Pain reported last time: consider the alternate and keep the weight.');
  return a;
}

int _minutesExpress(int n) => math.max(10, _jsRound(n * 2 / 3 / 5) * 5);

/// Build today's session from the planned exercises.
/// [hiit] is the ramp level 1–3 (see [hiitLevel]); [swaps] maps plannedExerciseId → exerciseId for today.
List<SessionExercise> buildSessionPlan({
  required List<PlannedExercise> planned,
  required DayType dayType,
  required SessionMode mode,
  required bool deload,
  WeekFocus? week,
  int? fallbackRir,
  int? hiit,
  Adaptation? adaptation,
  Map<String, String>? swaps,
}) {
  var list = [...planned];
  mergeSort(list, compare: (x, y) => x.order - y.order);

  // Express (~40 min): keep the essentials (doc 09)
  if (mode == SessionMode.express) {
    if (dayType == DayType.strength) {
      final ab = list.where((p) => _mainSlotRe.hasMatch(p.slot)).toList();
      list = ab.isNotEmpty ? ab : list.take(4).toList();
    } else if (dayType == DayType.conditioning) {
      list = list.where((p) => !_present(p.supersetGroup)).toList();
    } else if (dayType == DayType.cardio) {
      final steady = list.where((p) => p.unit == Unit.minutes).take(1);
      final core = list.where((p) => p.unit != Unit.minutes).take(2);
      list = [...steady, ...core];
    } else {
      list = list.take(4).toList();
    }
  }

  return list.map((p) {
    final main = isMainSlot(p.slot, dayType);
    var sets = p.sets;
    var repsMin = p.repsMin;
    var repsMax = p.repsMax;
    var restSec = p.restSec;
    final notes = <String>[];

    // Gradual HIIT ramp on conditioning days
    if (dayType == DayType.conditioning && hiit != null && hiit != 0 && hiit < 3) {
      if (isInterval(p)) {
        sets = hiit == 1 ? math.min(sets, 4) : math.min(sets, 5);
        final secs = hiit == 1 ? 20 : 25;
        repsMin = math.min(repsMin, secs);
        repsMax = math.min(repsMax, secs);
        restSec = restSec + (hiit == 1 ? 30 : 15);
        notes.add('Ramp level $hiit/3: $sets × ${repsMax}s, easy pace between.');
      } else if (_present(p.supersetGroup)) {
        sets = math.min(sets, hiit == 1 ? 2 : 3);
      } else {
        sets = math.min(sets, 3);
      }
    }

    // Accessory set bumps (periodization + feedback), full mode only
    if (!main && mode == SessionMode.full && !deload) {
      final bump = (week?.setsDelta ?? 0) + (adaptation?.accessorySetsDelta ?? 0);
      if (bump != 0) sets = math.max(2, math.min(p.sets + 1, sets + bump));
    }

    if (mode == SessionMode.express) {
      sets = math.min(sets, dayType == DayType.conditioning ? 3 : 2);
      if (p.unit == Unit.minutes) {
        repsMin = _minutesExpress(repsMin);
        repsMax = _minutesExpress(repsMax);
      }
      if (isInterval(p)) sets = math.min(sets, 4);
      restSec = math.min(restSec, main ? 90 : 45);
    }
    if (deload) sets = deloadSets(sets);
    final rir = week != null ? (main ? week.rirMain : week.rirAccessory) : fallbackRir;

    return SessionExercise(
      plannedExerciseId: p.id,
      exerciseId: swaps?[p.id] ?? p.exerciseId,
      originalExerciseId: p.exerciseId,
      slot: p.slot,
      supersetGroup: p.supersetGroup,
      sets: math.max(1, sets),
      repsMin: repsMin,
      repsMax: repsMax,
      unit: p.unit,
      perSide: p.perSide,
      restSec: restSec,
      rir: p.unit == Unit.reps ? rir : null,
      isMain: main,
      cue: p.cue,
      note: notes.isEmpty ? null : notes.join(' '),
    );
  }).toList();
}

/// Targets for a slot: reps range plus unit.
typedef UnitTargets = ({int repsMin, int repsMax, Unit unit});

/// Default targets when an alternate uses a different unit from the planned slot.
UnitTargets targetsForUnit(UnitTargets current, Unit unit) {
  if (unit == current.unit) return (repsMin: current.repsMin, repsMax: current.repsMax, unit: unit);
  return switch (unit) {
    Unit.reps => (repsMin: 8, repsMax: 12, unit: unit),
    Unit.seconds => (repsMin: 20, repsMax: 40, unit: unit),
    Unit.meters => (repsMin: 20, repsMax: 30, unit: unit),
    Unit.minutes => (repsMin: 10, repsMax: 20, unit: unit),
  };
}

/// Rough session length in minutes (rounded to 5), including warm-up (+ cool-down for full sessions).
int estimateMinutes(List<SessionExercise> plan) {
  final express = plan.length <= 4 && plan.every((e) => e.sets <= 3);
  var sec = express ? 300 : 600 + 300;
  for (final e in plan) {
    final work = e.unit == Unit.minutes ? e.repsMax * 60 : e.unit == Unit.seconds ? e.repsMax : 45;
    sec += e.sets * (work + e.restSec + 20);
  }
  return _jsRound(sec / 60 / 5) * 5;
}
