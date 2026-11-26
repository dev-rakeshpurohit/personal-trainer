// Port of src/domain/progression.ts. Pure Dart: no Flutter imports.
// Double progression, time progression, Epley e1RM, PR detection and volume.
import 'dart:math' as math;

import 'package:collection/collection.dart' show mergeSort;

import 'models.dart';

/// Increment bucket for an exercise.
enum Equip with Wire {
  dumbbell('dumbbell'),
  barbell('barbell'),
  machine('machine');

  const Equip(this.wire);
  @override
  final String wire;
}

final _barbellRe = RegExp(r'trap.?bar|barbell|e-z');
final _machineRe = RegExp(r'machine|cable|leg press|pulldown|smith');

/// Map an exercise's equipment/name onto an increment bucket.
Equip equipmentBucket(Exercise ex) => equipmentBucketOf(ex.equipment, ex.name);

/// Same as [equipmentBucket] for callers that only have the equipment list and name.
Equip equipmentBucketOf(List<String> equipment, String name) {
  final all = [...equipment, name].join(' ').toLowerCase();
  if (_barbellRe.hasMatch(all)) return Equip.barbell;
  if (_machineRe.hasMatch(all)) return Equip.machine;
  return Equip.dumbbell;
}

/// Weight increment (kg) for an exercise from the profile's step settings.
double incrementFor(Exercise ex, StepKg step) => switch (equipmentBucket(ex)) {
      Equip.dumbbell => step.dumbbell,
      Equip.barbell => step.barbell,
      Equip.machine => step.machine,
    };

/// One logged working set, as the progression logic sees it
/// (TS: `Pick<SetLog, 'weightKg' | 'reps' | 'seconds' | 'meters' | 'rir' | 'setIndex'>`).
/// [isWarmup] is only read by [volume].
class WorkSet {
  const WorkSet({this.weightKg, this.reps, this.seconds, this.meters, this.rir, this.setIndex = 0, this.isWarmup = false});
  final double? weightKg;
  final int? reps;
  final int? seconds;
  final double? meters;
  final int? rir;
  final int setIndex;
  final bool isWarmup;

  factory WorkSet.fromLog(SetLog s) => WorkSet(
        weightKg: s.weightKg,
        reps: s.reps,
        seconds: s.seconds,
        meters: s.meters,
        rir: s.rir,
        setIndex: s.setIndex,
        isWarmup: s.isWarmup,
      );
}

extension SetLogToWorkSet on SetLog {
  WorkSet toWorkSet() => WorkSet.fromLog(this);
}

/// History for one exercise: past sessions' working sets, most recent session first.
typedef History = List<List<WorkSet>>;

/// The planned targets progression needs
/// (TS: `Pick<PlannedExercise, 'sets' | 'repsMin' | 'repsMax' | 'unit'>`).
typedef SetTarget = ({int sets, int repsMin, int repsMax, Unit unit});

extension PlannedExerciseSetTarget on PlannedExercise {
  SetTarget get setTarget => (sets: sets, repsMin: repsMin, repsMax: repsMax, unit: unit);
}

extension SessionExerciseSetTarget on SessionExercise {
  SetTarget get setTarget => (sets: sets, repsMin: repsMin, repsMax: repsMax, unit: unit);
}

enum SuggestionKind with Wire {
  first('first'),
  increase('increase'),
  hold('hold'),
  decrease('decrease'),
  timeIncrease('time_increase'),
  timeCap('time_cap');

  const SuggestionKind(this.wire);
  @override
  final String wire;
}

/// Pre-filled values for one set.
class Prefill {
  const Prefill({this.weightKg, this.reps, this.seconds, this.meters});
  final double? weightKg;
  final int? reps;
  final int? seconds;
  final double? meters;

  Prefill copyWith({double? weightKg, int? reps, int? seconds, double? meters}) => Prefill(
        weightKg: weightKg ?? this.weightKg,
        reps: reps ?? this.reps,
        seconds: seconds ?? this.seconds,
        meters: meters ?? this.meters,
      );

  @override
  bool operator ==(Object other) =>
      other is Prefill && other.weightKg == weightKg && other.reps == reps && other.seconds == seconds && other.meters == meters;

  @override
  int get hashCode => Object.hash(weightKg, reps, seconds, meters);

  @override
  String toString() => 'Prefill(weightKg: $weightKg, reps: $reps, seconds: $seconds, meters: $meters)';
}

class Suggestion {
  const Suggestion({required this.kind, this.weightKg, required this.message, required this.prefill});
  final SuggestionKind kind;
  final double? weightKg;
  final String message;
  final List<Prefill> prefill;

  /// Note: [weightKg] can only be replaced, not cleared; use the constructor to clear it.
  Suggestion copyWith({SuggestionKind? kind, double? weightKg, String? message, List<Prefill>? prefill}) => Suggestion(
        kind: kind ?? this.kind,
        weightKg: weightKg ?? this.weightKg,
        message: message ?? this.message,
        prefill: prefill ?? this.prefill,
      );
}

const int kSecondsCap = 60;

double? _maxWeight(List<WorkSet> sets) {
  final ws = [for (final s in sets) if (s.weightKg != null && s.weightKg! > 0) s.weightKg!];
  return ws.isEmpty ? null : ws.reduce(math.max);
}

num? _valueOf(WorkSet s, Unit unit) => switch (unit) {
      Unit.reps => s.reps,
      Unit.meters => s.meters,
      _ => s.seconds != null ? (unit == Unit.minutes ? s.seconds! / 60 : s.seconds) : null,
    };

/// Stable sort by setIndex (JS Array.sort is stable; Dart's List.sort is not guaranteed to be).
List<WorkSet> _sortedBySetIndex(List<WorkSet> sets) {
  final copy = [...sets];
  mergeSort(copy, compare: (a, b) => a.setIndex - b.setIndex);
  return copy;
}

WorkSet? _bySetIndex(List<WorkSet> sets, int i) {
  final sorted = _sortedBySetIndex(sets);
  return i >= 0 && i < sorted.length ? sorted[i] : null;
}

bool readyToProgress(List<WorkSet> sets, SetTarget planned, {int? targetRir}) {
  if (sets.length < planned.sets || sets.isEmpty) return false;
  return sets.every((s) {
    final v = _valueOf(s, planned.unit) ?? 0;
    final rirOk = s.rir == null || targetRir == null || s.rir! >= targetRir;
    return v >= planned.repsMax && rirOk;
  });
}

String _fmt(double w) => w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

/// Double progression (doc 06 §2). Pure.
/// [sets] is the planned set count *for this session* (already deload-adjusted).
Suggestion suggestNext({
  required SetTarget planned,
  required int sets,
  required History history,
  int? targetRir,
  required double increment,
  bool bodyweight = false,
}) {
  final n = sets;
  final last = history.isEmpty ? null : history[0];
  final unit = planned.unit;
  List<Prefill> fill(Prefill Function(int i) f) => List.generate(n < 0 ? 0 : n, f);

  if (last == null || last.isEmpty) {
    return Suggestion(
      kind: SuggestionKind.first,
      message: 'First time: pick a weight you could lift for a couple more reps.',
      prefill: fill((_) => unit == Unit.reps
          ? Prefill(reps: planned.repsMin)
          : unit == Unit.meters
              ? Prefill(meters: planned.repsMin.toDouble())
              : Prefill(seconds: unit == Unit.minutes ? planned.repsMin * 60 : planned.repsMin)),
    );
  }

  final lastW = bodyweight ? null : _maxWeight(last);

  if (unit == Unit.seconds) {
    final allHit = last.length >= planned.sets && last.every((s) => (s.seconds ?? 0) >= planned.repsMax);
    final best = [for (final s in last) s.seconds ?? 0, planned.repsMin].reduce(math.max);
    if (allHit) {
      if (best >= kSecondsCap) {
        return Suggestion(
          kind: SuggestionKind.timeCap,
          weightKg: lastW,
          message: 'You own ${kSecondsCap}s. Try a harder variant.',
          prefill: fill((_) => Prefill(seconds: kSecondsCap, weightKg: lastW)),
        );
      }
      final next = math.min(kSecondsCap, math.max(best, planned.repsMax) + 5);
      return Suggestion(
        kind: SuggestionKind.timeIncrease,
        weightKg: lastW,
        message: '↑ Hold ${next}s',
        prefill: fill((_) => Prefill(seconds: next, weightKg: lastW)),
      );
    }
    return Suggestion(
      kind: SuggestionKind.hold,
      weightKg: lastW,
      message: 'Same time, add a few seconds where you can.',
      prefill: fill((i) => Prefill(seconds: _bySetIndex(last, i)?.seconds ?? planned.repsMin, weightKg: lastW)),
    );
  }

  if (unit == Unit.minutes || unit == Unit.meters) {
    return Suggestion(
      kind: SuggestionKind.hold,
      weightKg: lastW,
      message: 'Match last time.',
      prefill: fill((i) {
        final s = _bySetIndex(last, i);
        return unit == Unit.minutes
            ? Prefill(seconds: s?.seconds ?? planned.repsMin * 60, weightKg: lastW)
            : Prefill(meters: s?.meters ?? planned.repsMin.toDouble(), weightKg: lastW);
      }),
    );
  }

  // reps
  if (readyToProgress(last, planned, targetRir: targetRir)) {
    if (lastW != null) {
      final w = lastW + increment;
      return Suggestion(
        kind: SuggestionKind.increase,
        weightKg: w,
        message: '↑ Try ${_fmt(w)} kg',
        prefill: fill((_) => Prefill(weightKg: w, reps: planned.repsMin)),
      );
    }
    return Suggestion(
      kind: SuggestionKind.hold,
      message: 'Top of the range: slow the tempo or try a harder variant.',
      prefill: fill((_) => Prefill(reps: planned.repsMax)),
    );
  }

  final prev = history.length > 1 ? history[1] : null;
  bool under(List<WorkSet>? s) => s != null && s.isNotEmpty && s.any((x) => (x.reps ?? 0) < planned.repsMin);
  if (under(last) && under(prev) && lastW != null) {
    final w = math.max(0.0, lastW - increment);
    return Suggestion(
      kind: SuggestionKind.decrease,
      weightKg: w,
      message: 'Ease off: ${_fmt(w)} kg and own the reps',
      prefill: fill((i) => Prefill(weightKg: w, reps: math.max(planned.repsMin, _bySetIndex(last, i)?.reps ?? planned.repsMin))),
    );
  }

  final sorted = _sortedBySetIndex(last);
  var lowest = 0;
  for (var i = 0; i < sorted.length; i++) {
    if ((sorted[i].reps ?? 0) < (sorted[lowest].reps ?? 0)) lowest = i;
  }
  return Suggestion(
    kind: SuggestionKind.hold,
    weightKg: lastW,
    message: 'Same weight, aim +1 rep on set ${lowest + 1}',
    prefill: fill((i) => Prefill(
          weightKg: lastW,
          reps: math.min(planned.repsMax, (_bySetIndex(last, i)?.reps ?? planned.repsMin) + (i == lowest ? 1 : 0)),
        )),
  );
}

/// Epley estimated 1RM; only valid for 1–12 reps.
double? e1rm(double? weightKg, int? reps) {
  if (weightKg == null || weightKg == 0 || weightKg.isNaN || reps == null || reps == 0 || reps < 1 || reps > 12) return null;
  return weightKg * (1 + reps / 30);
}

enum PRType with Wire {
  weight('weight'),
  e1rm('e1rm'),
  reps('reps');

  const PRType(this.wire);
  @override
  final String wire;
}

/// Detect PRs for a newly completed set against all prior sets of the same exercise.
/// Only [WorkSet.weightKg] and [WorkSet.reps] are read.
List<PRType> detectPRs(WorkSet set, List<WorkSet> prior) {
  final sw = set.weightKg;
  final sr = set.reps;
  if (prior.isEmpty || sw == null || sw == 0 || sw.isNaN || sr == null || sr == 0) return [];
  final out = <PRType>[];
  final maxW = prior.fold<double>(0, (m, p) => math.max(m, p.weightKg ?? 0.0));
  if (sw > maxW) out.add(PRType.weight);
  final best = prior.fold<double>(0, (m, p) => math.max(m, e1rm(p.weightKg, p.reps) ?? 0.0));
  final mine = e1rm(sw, sr);
  if (mine != null && mine != 0 && best > 0 && mine > best + 1e-9) out.add(PRType.e1rm);
  final sameW = prior.where((p) => p.weightKg == sw).toList();
  if (sameW.isNotEmpty && sr > sameW.map((p) => p.reps ?? 0).reduce(math.max)) out.add(PRType.reps);
  return out;
}

/// Total working-set volume (kg × reps), warm-ups excluded.
double volume(List<WorkSet> sets) =>
    sets.where((s) => !s.isWarmup).fold<double>(0, (a, s) => a + (s.weightKg ?? 0) * (s.reps ?? 0));
