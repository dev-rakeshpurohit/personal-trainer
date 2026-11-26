// Progress-tab logic: lift series with PR markers, strength levels, and the weekly card summary.
// Pure Dart over domain models (no Flutter imports).
import 'dart:math' as math;

import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/schedule.dart';
import '../../domain/stats.dart';

/* ------------------------------------------------------------------ lift series */

class LiftPoint {
  const LiftPoint({required this.t, required this.v, required this.pr, required this.sessionId, required this.weighted});
  final DateTime t;

  /// Best e1RM (kg) of the session, or best reps / seconds when nothing was weighted.
  final double v;

  /// Higher than every earlier session (the first session is never a PR).
  final bool pr;
  final String sessionId;
  final bool weighted;
}

/// One point per completed session: its best set. [sessions] maps session id → done session.
List<LiftPoint> liftSeries(Iterable<SetLog> sets, Map<String, Session> sessions) {
  final bySession = <String, List<SetLog>>{};
  for (final s in sets) {
    if (s.isWarmup || !sessions.containsKey(s.sessionId)) continue;
    (bySession[s.sessionId] ??= []).add(s);
  }
  final ids = bySession.keys.toList()..sort((a, b) => sessions[a]!.startedAt.compareTo(sessions[b]!.startedAt));
  final out = <LiftPoint>[];
  var best = 0.0;
  for (final id in ids) {
    final list = bySession[id]!;
    final e = list.map((x) => e1rm(x.weightKg, x.reps) ?? 0.0).fold(0.0, math.max);
    final alt = list.map((x) => (x.seconds ?? x.reps ?? 0).toDouble()).fold(0.0, math.max);
    final v = e > 0 ? e : alt;
    if (v <= 0) continue;
    final t = DateTime.tryParse(sessions[id]!.startedAt)?.toLocal() ?? fromDayKey(sessions[id]!.dayKey);
    out.add(LiftPoint(t: t, v: v, pr: out.isNotEmpty && v > best + 1e-9, sessionId: id, weighted: e > 0));
    best = math.max(best, v);
  }
  return out;
}

enum ChartRange {
  m1('1M', 30),
  m3('3M', 91),
  m6('6M', 182),
  y1('1Y', 365);

  const ChartRange(this.label, this.days);
  final String label;
  final int days;
}

List<LiftPoint> inRange(List<LiftPoint> pts, ChartRange r, DateTime now) {
  final from = addDays(dateOnly(now), -r.days);
  return pts.where((p) => !p.t.isBefore(from)).toList();
}

/// Main lifts: the plan's A/B slots (the heavy compound work), in plan order, without duplicates.
List<String> mainLiftIds(List<PlannedExercise> planned, Map<String, Exercise> exercises) {
  final out = <String>[];
  for (final p in planned) {
    if (!RegExp(r'^[AB]').hasMatch(p.slot) || p.unit != Unit.reps) continue;
    final ex = exercises[p.exerciseId];
    if (ex == null || ex.isBodyweight == true) continue;
    if (!out.contains(p.exerciseId)) out.add(p.exerciseId);
  }
  return out;
}

/* ------------------------------------------------------------------ strength level */

enum StrengthLevel {
  beginner('Beginner'),
  novice('Novice'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const StrengthLevel(this.label);
  final String label;
}

enum LiftKind { squat, hinge, bench, overhead, pull }

LiftKind? liftKindOf(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'deadlift|romanian|\brdl\b|hip thrust|good morning').hasMatch(n)) return LiftKind.hinge;
  if (RegExp(r'squat|leg press|lunge|step-up|step up').hasMatch(n)) return LiftKind.squat;
  if (RegExp(r'shoulder press|overhead press|military|arnold').hasMatch(n)) return LiftKind.overhead;
  if (RegExp(r'bench|chest press|incline.*press|decline.*press|\bdip').hasMatch(n)) return LiftKind.bench;
  if (RegExp(r'row|pulldown|pull-up|pull up|chin').hasMatch(n)) return LiftKind.pull;
  return null;
}

/// e1RM ÷ body weight at which Novice / Intermediate / Advanced start, for a man on a barbell.
const Map<LiftKind, List<double>> _ratios = {
  LiftKind.squat: [0.75, 1.25, 1.75],
  LiftKind.hinge: [1.0, 1.5, 2.0],
  LiftKind.bench: [0.5, 0.85, 1.25],
  LiftKind.overhead: [0.35, 0.55, 0.8],
  LiftKind.pull: [0.5, 0.8, 1.1],
};

class StrengthRating {
  const StrengthRating({required this.level, required this.ratio, this.next, this.nextKg, required this.progress});
  final StrengthLevel level;

  /// e1RM ÷ body weight.
  final double ratio;
  final StrengthLevel? next;

  /// e1RM needed for [next].
  final double? nextKg;

  /// 0..1 through the current band (1 at Advanced).
  final double progress;
}

/// Strength level from e1RM relative to body weight. Dumbbell loads are per hand, so their bands
/// are ×0.4; the leg press is ×1.8; women's bands ×0.65. A rough guide, explained in the UI.
StrengthRating? strengthRating({required Exercise exercise, required double e1rmKg, required double bodyweightKg, required Sex sex}) {
  final kind = liftKindOf(exercise.name);
  if (kind == null || bodyweightKg <= 0 || e1rmKg <= 0) return null;
  final name = exercise.name.toLowerCase();
  final bucket = equipmentBucket(exercise);
  var f = bucket == Equip.dumbbell ? 0.4 : 1.0;
  if (name.contains('leg press')) f = 1.8;
  f *= sex == Sex.female ? 0.65 : sex == Sex.other ? 0.8 : 1.0;
  final bands = [for (final r in _ratios[kind]!) r * f * bodyweightKg];
  final ratio = e1rmKg / bodyweightKg;
  var idx = 0;
  for (var i = 0; i < bands.length; i++) {
    if (e1rmKg >= bands[i]) idx = i + 1;
  }
  final level = StrengthLevel.values[idx];
  if (idx == 3) return StrengthRating(level: level, ratio: ratio, progress: 1);
  final lo = idx == 0 ? 0.0 : bands[idx - 1];
  final hi = bands[idx];
  return StrengthRating(level: level, ratio: ratio, next: StrengthLevel.values[idx + 1], nextKg: hi, progress: ((e1rmKg - lo) / (hi - lo)).clamp(0, 1).toDouble());
}

/* ------------------------------------------------------------------ weekly card */

class WeeklySummary {
  const WeeklySummary({
    required this.done,
    required this.planned,
    required this.liftsUp,
    required this.liftsTrained,
    this.trendKg,
    this.trendDeltaKg,
    required this.proteinHit,
    required this.sentence,
  });
  final int done;
  final int planned;

  /// Main lifts whose best this week beat their best before this week.
  final int liftsUp;
  final int liftsTrained;

  /// Smoothed (7-day average) weight today and its change vs a week ago.
  final double? trendKg;
  final double? trendDeltaKg;
  final int proteinHit;
  final String sentence;
}

WeeklySummary weeklySummary({
  required DateTime now,
  required int done,
  required int planned,
  required Map<String, List<LiftPoint>> mainSeries,
  required List<StatPoint> weights,
  required int proteinHit,
  required double goalWeightKg,
}) {
  final ws = weekStartOf(dateOnly(now));
  var up = 0;
  var trained = 0;
  for (final s in mainSeries.values) {
    final week = s.where((p) => !p.t.isBefore(ws)).toList();
    if (week.isEmpty) continue;
    trained++;
    final before = s.where((p) => p.t.isBefore(ws)).map((p) => p.v).fold(0.0, math.max);
    final best = week.map((p) => p.v).fold(0.0, math.max);
    if (before > 0 && best > before + 1e-9) up++;
  }
  final today = dateOnly(now);
  final trend = current7dAvg(weights, today);
  final prev = current7dAvg(weights, addDays(today, -7));
  final delta = trend != null && prev != null ? trend - prev : null;

  final parts = <String>[];
  final sessions = planned > 0 ? '$done/$planned sessions' : '$done session${done == 1 ? '' : 's'}';
  parts.add('$sessions and $proteinHit/7 protein days');
  String tail;
  final losing = goalWeightKg < (trend ?? goalWeightKg);
  if (planned > 0 && done >= planned && proteinHit >= 5) {
    tail = 'your best kind of week.';
  } else if (up > 0) {
    tail = '$up top set${up == 1 ? '' : 's'} beat your best.';
  } else if (delta != null && losing && delta < -0.05) {
    tail = 'trend weight is moving the right way.';
  } else if (done > 0) {
    tail = 'steady work, it adds up.';
  } else {
    tail = 'one session gets the week going.';
  }
  return WeeklySummary(
    done: done,
    planned: planned,
    liftsUp: up,
    liftsTrained: trained,
    trendKg: trend,
    trendDeltaKg: delta,
    proteinHit: proteinHit,
    sentence: '${parts.join()}: $tail',
  );
}
