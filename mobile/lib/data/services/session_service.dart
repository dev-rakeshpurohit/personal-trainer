// Port of src/features/workout/session.ts plus the data logic of the workout Player and Summary
// (set logging with PR detection, flow/next step, extra sets, rest timer, hold/pain suggestions,
// resume, summary stats). UI-only effects (toasts, notifications, haptics, wake lock) stay in the UI.
import 'dart:math' as math;

import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/schedule.dart';
import '../../domain/session_flow.dart';
import '../../domain/session_plan.dart';
import '../../domain/units.dart';
import '../db/store.dart';
import 'common.dart';
import 'progression_data.dart';
import 'repo.dart' show Undo;

/// A session ready to start (Prestart screen).
class Prepared {
  const Prepared({
    required this.day,
    required this.plan,
    required this.adaptation,
    this.hiit,
    this.week,
    required this.cycleWeek,
    required this.deload,
    required this.estMin,
  });
  final ProgramDay day;
  final List<SessionExercise> plan;
  final Adaptation adaptation;

  /// HIIT ramp level 1–3 (conditioning days only).
  final int? hiit;
  final WeekFocus? week;
  final int cycleWeek;
  final bool deload;
  final int estMin;
}

/// Values of one set (TS `Pick<SetLog, 'weightKg' | 'reps' | 'seconds' | 'meters' | 'rir'>`).
class SetValues {
  const SetValues({this.weightKg, this.reps, this.seconds, this.meters, this.rir});
  final double? weightKg;
  final int? reps;
  final int? seconds;
  final double? meters;
  final int? rir;

  SetValues withoutWeight() => SetValues(reps: reps, seconds: seconds, meters: meters, rir: rir);

  /// Override with any non-null field of [o] (TS `{ ...draft, ...override }`).
  SetValues merge(SetValues? o) => o == null
      ? this
      : SetValues(
          weightKg: o.weightKg ?? weightKg,
          reps: o.reps ?? reps,
          seconds: o.seconds ?? seconds,
          meters: o.meters ?? meters,
          rir: o.rir ?? rir,
        );

  @override
  bool operator ==(Object other) =>
      other is SetValues && other.weightKg == weightKg && other.reps == reps && other.seconds == seconds && other.meters == meters && other.rir == rir;
  @override
  int get hashCode => Object.hash(weightKg, reps, seconds, meters, rir);
  @override
  String toString() => 'SetValues(weightKg: $weightKg, reps: $reps, seconds: $seconds, meters: $meters, rir: $rir)';
}

/// The live session: active state plus its session row.
class ActiveSessionView {
  const ActiveSessionView({required this.active, required this.session});
  final ActiveSessionState active;
  final Session session;
}

/// Everything the Player needs to resume exactly where it left off.
class PlayerState {
  PlayerState({required this.active, required this.session, required this.sets});
  final ActiveSessionState active;
  final Session session;

  /// Sets logged in this session.
  final List<SetLog> sets;

  List<SessionExercise> get plan => active.plan ?? const [];

  /// Current exercise index (clamped to the plan).
  int get idx => math.min(math.max(0, active.exerciseIdx), math.max(0, plan.length - 1));
  SessionExercise? get current => plan.isEmpty ? null : plan[idx];

  int totalSets(int i) => totalSetsOf(active, i);
  List<SetLog> setsFor(int i) => setsForExercise(plan, sets, i);
  late final List<Step> flow = flowOf(active);
  late final Set<String> doneKeys = doneKeysOf(plan, sets);
  bool get allDone => flow.isNotEmpty && flow.every((s) => doneKeys.contains(stepKey(s)));

  /// First set of the current exercise that isn't logged yet (null when all are done).
  int? get nextSetIdx => nextSetIndexOf(active, sets, idx);

  DateTime? get restEndsAt => active.restEndsAt == null ? null : parseIsoLocal(active.restEndsAt!);
}

/// Result of [SessionService.logAndAdvance].
class LoggedSet {
  const LoggedSet({required this.row, required this.prs, required this.showPr, this.next, this.restEndsAt, required this.restSec});
  final SetLog row;

  /// PR types of this set against every earlier working set of the exercise.
  final List<PRType> prs;

  /// True the first time a PR happens for this exercise in this session (show the toast).
  final bool showPr;

  /// Next pending step, or null when every set is done.
  final Step? next;
  final DateTime? restEndsAt;
  final int restSec;
  bool get allDone => next == null;
}

/// Progression suggestion for the current exercise, with feedback holds applied.
class ActiveSuggestion {
  const ActiveSuggestion({required this.suggestion, this.last});
  final Suggestion suggestion;

  /// "20 kg × 10, 20 kg × 9" of the last session (null without history).
  final String? last;
}

/// Post-workout summary data (Summary screen).
class SessionSummary {
  const SessionSummary({
    required this.session,
    required this.sets,
    required this.prior,
    required this.planned,
    required this.durationSec,
    required this.volume,
    required this.count,
    required this.prs,
    required this.exercises,
  });
  final Session session;
  final List<SetLog> sets;

  /// Per exercise: sets from earlier (non-abandoned) sessions.
  final Map<String, List<SetLog>> prior;

  /// Planned exercises of the session's program day (for "replace disliked exercise").
  final List<PlannedExercise> planned;
  final double durationSec;
  final double volume;
  final int count;
  final List<({String exerciseId, List<PRType> types})> prs;
  final List<String> exercises;
}

/* ------------------------------------------------------------ pure player helpers */

int totalSetsOf(ActiveSessionState a, int i) {
  final plan = a.plan ?? const [];
  if (i < 0 || i >= plan.length) return 0;
  return plan[i].sets + (a.extraSets?[plan[i].plannedExerciseId] ?? 0);
}

List<Step> flowOf(ActiveSessionState a) {
  final plan = a.plan ?? const <SessionExercise>[];
  return buildFlow([for (var i = 0; i < plan.length; i++) (sets: totalSetsOf(a, i), supersetGroup: plan[i].supersetGroup)]);
}

List<SetLog> setsForExercise(List<SessionExercise> plan, List<SetLog> sets, int i) {
  if (i < 0 || i >= plan.length) return [];
  return sets.where((s) => s.plannedExerciseId == plan[i].plannedExerciseId).toList()..sort((a, b) => a.setIndex - b.setIndex);
}

Set<String> doneKeysOf(List<SessionExercise> plan, List<SetLog> sets) => {
      for (var i = 0; i < plan.length; i++)
        for (final s in setsForExercise(plan, sets, i)) stepKey((ex: i, set: s.setIndex)),
    };

int? nextSetIndexOf(ActiveSessionState a, List<SetLog> sets, int i) {
  final logged = setsForExercise(a.plan ?? const [], sets, i);
  for (var s = 0; s < totalSetsOf(a, i); s++) {
    if (!logged.any((l) => l.setIndex == s)) return s;
  }
  return null;
}

/// Pre-filled values for a set (Player draftFor): the suggestion's prefill, and the weight of the
/// last set logged today for this exercise.
SetValues draftFor(SessionExercise se, Suggestion? sug, List<SetLog> loggedForExercise, int setIndex) {
  final p = sug == null || sug.prefill.isEmpty ? null : (setIndex < sug.prefill.length ? sug.prefill[setIndex] : sug.prefill[0]);
  final same = loggedForExercise.where((x) => x.exerciseId == se.exerciseId).toList();
  final prev = same.isEmpty ? null : same.last;
  final w = prev?.weightKg ?? p?.weightKg;
  return switch (se.unit) {
    Unit.reps => SetValues(reps: p?.reps ?? se.repsMin, weightKg: w),
    Unit.meters => SetValues(meters: p?.meters ?? se.repsMin.toDouble(), weightKg: w),
    _ => SetValues(seconds: p?.seconds ?? (se.unit == Unit.minutes ? se.repsMin * 60 : se.repsMin), weightKg: w),
  };
}

/* ------------------------------------------------------------ service */

class SessionService {
  SessionService(this.s, {IdGen? newId, Clock? now})
      : newId = newId ?? defaultIdGen,
        now = now ?? systemNow,
        progression = ProgressionData(s);
  final Stores s;
  final IdGen newId;
  final Clock now;
  final ProgressionData progression;

  Future<List<SessionFeedback>> recentFeedback(String programDayId, {int n = 3}) async {
    final l = (await s.sessions.whereK2('done')).where((x) => x.programDayId == programDayId && x.feedback != null).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return l.take(n).map((x) => x.feedback!).toList();
  }

  /// Feel of every completed conditioning session, latest first.
  Future<List<Feel?>> conditioningHistory() async {
    final ids = {for (final d in await s.programDays.all()) if (d.type == DayType.conditioning) d.id};
    final l = (await s.sessions.whereK2('done')).where((x) => x.programDayId != null && ids.contains(x.programDayId)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return l.map((x) => x.feedback?.feel).toList();
  }

  Future<Prepared?> prepareSession(String dayId, SessionMode mode, {DateTime? date}) async {
    final when = date ?? now();
    final day = await s.programDays.get(dayId);
    if (day == null) return null;
    final program = await s.programs.get(day.programId);
    if (program == null) return null;
    final planned = (await s.plannedExercises.whereK1(dayId))..sort((a, b) => a.order - b.order);
    final cw = cycleWeek(when, program.startedOn);
    final deload = isDeloadWeek(cw, program.progression.cycle);
    WeekFocus? week;
    for (final w in program.progression.weeks ?? const <WeekFocus>[]) {
      if (w.week == cw) {
        week = w;
        break;
      }
    }
    final adaptation = adaptFromFeedback(await recentFeedback(dayId));
    final hiit = day.type == DayType.conditioning ? hiitLevel(await conditioningHistory()) : null;
    final plan = buildSessionPlan(
      planned: planned,
      dayType: day.type,
      mode: mode,
      deload: deload,
      week: week,
      fallbackRir: targetRir(cw, program.progression.cycle),
      hiit: hiit,
      adaptation: adaptation,
    );
    return Prepared(day: day, plan: plan, adaptation: adaptation, hiit: hiit, week: week, cycleWeek: cw, deload: deload, estMin: estimateMinutes(plan));
  }

  /// Start (or return the already active) session. Returns the session id.
  Future<String> startSession(Prepared p, SessionMode mode, {DateTime? date}) async {
    final when = date ?? now();
    final existing = await s.activeSession.get(ActiveSessionState.id);
    if (existing != null) {
      final cur = await s.sessions.get(existing.sessionId);
      if (cur?.status == 'active') return cur!.id;
    }
    final session = Session(
      id: newId(),
      dayKey: dayKey(when),
      programDayId: p.day.id,
      title: p.day.title,
      startedAt: isoString(when),
      status: 'active',
      cycleWeek: p.cycleWeek,
      deload: p.deload,
      mode: mode,
    );
    final active = ActiveSessionState(
      sessionId: session.id,
      exerciseIdx: 0,
      setIdx: 0,
      swaps: const {},
      plan: p.plan,
      prShown: const [],
      hold: p.adaptation.holdProgression,
      pain: p.adaptation.pain,
    );
    await s.transaction(() async {
      await s.sessions.put(session);
      await s.activeSession.put(active);
    });
    return session.id;
  }

  /// The live session, or null (none, or its session is no longer active).
  Future<ActiveSessionView?> activeSession() async {
    final a = await s.activeSession.get(ActiveSessionState.id);
    if (a == null) return null;
    final ss = await s.sessions.get(a.sessionId);
    if (ss == null || ss.status != 'active') return null;
    return ActiveSessionView(active: a, session: ss);
  }

  /// Resume after an app kill: active state + logged sets (current exercise, next set, rest timer).
  Future<PlayerState?> resume() async {
    final v = await activeSession();
    if (v == null) return null;
    return PlayerState(active: v.active, session: v.session, sets: await s.sets.whereK1(v.session.id));
  }

  /// Dexie-style patch of the active state (null removes a key).
  Future<ActiveSessionState?> patchActive(Map<String, Object?> patch) => s.activeSession.patch(ActiveSessionState.id, patch);

  Future<void> goToExercise(int i) async {
    final a = await s.activeSession.get(ActiveSessionState.id);
    if (a == null || i < 0 || i >= (a.plan?.length ?? 0)) return;
    await patchActive({'exerciseIdx': i});
  }

  /// "+ Add set" on an exercise.
  Future<void> addExtraSet(String plannedExerciseId) async {
    final a = await s.activeSession.get(ActiveSessionState.id);
    if (a == null) return;
    final extra = {...?a.extraSets};
    extra[plannedExerciseId] = (extra[plannedExerciseId] ?? 0) + 1;
    await patchActive({'extraSets': extra});
  }

  Future<void> skipRest() => patchActive({'restEndsAt': null}).then((_) {});

  /// ±seconds on the rest timer (never ends in the past; total stays ≥ 1 s).
  Future<void> adjustRest(int deltaSec) async {
    final a = await s.activeSession.get(ActiveSessionState.id);
    if (a?.restEndsAt == null) return;
    final ends = DateTime.parse(a!.restEndsAt!).millisecondsSinceEpoch + deltaSec * 1000;
    final n = math.max(now().millisecondsSinceEpoch, ends);
    await patchActive({
      'restEndsAt': isoString(DateTime.fromMillisecondsSinceEpoch(n)),
      'restTotalSec': math.max(1, (a.restTotalSec ?? 60) + deltaSec),
    });
  }

  /// Log one set: written immediately (never lose a log).
  Future<SetLog> logSet(String sessionId, SessionExercise se, int setIndex, SetValues v) async {
    final row = SetLog(
      id: newId(),
      sessionId: sessionId,
      exerciseId: se.exerciseId,
      plannedExerciseId: se.plannedExerciseId,
      swappedFromExerciseId: se.exerciseId != se.originalExerciseId ? se.originalExerciseId : null,
      setIndex: setIndex,
      weightKg: v.weightKg,
      reps: v.reps,
      seconds: v.seconds,
      meters: v.meters,
      rir: v.rir,
      completedAt: isoString(now()),
      isWarmup: false,
    );
    await s.sets.put(row);
    return row;
  }

  /// The Player's "Log set": validates, logs, detects PRs (once per exercise per session),
  /// moves to the next step of the flow (supersets alternate) and starts the rest timer.
  /// Throws [ArgumentError] 'Enter your reps first' when a reps set has no reps.
  Future<LoggedSet> logAndAdvance(int idx, int setIndex, SetValues values, {Exercise? exercise}) async {
    final a = await s.activeSession.get(ActiveSessionState.id);
    if (a == null) throw StateError('No active session');
    final plan = a.plan ?? const <SessionExercise>[];
    final se = plan[idx];
    var v = values;
    if (se.unit == Unit.reps && (v.reps == null || v.reps == 0)) throw ArgumentError('Enter your reps first');
    final ex = exercise ?? await s.exercises.get(se.exerciseId);
    if (ex?.isBodyweight == true) v = v.withoutWeight();
    final prior = (await s.sets.whereK2(se.exerciseId)).where((x) => !x.isWarmup).map((x) => x.toWorkSet()).toList();
    final row = await logSet(a.sessionId, se, setIndex, v);

    final prs = detectPRs(row.toWorkSet(), prior);
    final shown = a.prShown ?? const <String>[];
    final showPr = prs.isNotEmpty && !shown.contains(se.exerciseId);
    if (showPr) await patchActive({'prShown': [...shown, se.exerciseId]});

    final sets = await s.sets.whereK1(a.sessionId);
    final done = doneKeysOf(plan, sets)..add(stepKey((ex: idx, set: setIndex)));
    final nxt = nextStep(flowOf(a), done, from: (ex: idx, set: setIndex));
    final rest = nxt != null ? se.restSec : 0;
    final endsAt = rest > 0 ? now().add(Duration(seconds: rest)) : null;
    await patchActive({
      'exerciseIdx': nxt?.ex ?? idx,
      'setIdx': nxt?.set ?? setIndex,
      'restEndsAt': endsAt == null ? null : isoString(endsAt),
      'restTotalSec': rest == 0 ? null : rest,
    });
    return LoggedSet(row: row, prs: prs, showPr: showPr, next: nxt, restEndsAt: endsAt, restSec: rest);
  }

  /// Dexie-style patch of a logged set (e.g. `{'rir': 2}` or edited values; null removes a key).
  Future<void> updateSet(String id, Map<String, Object?> patch) => s.sets.patch(id, patch).then((_) {});

  /// Delete a logged set; returns an undo.
  Future<Undo> deleteSet(String id) async {
    final prev = await s.sets.get(id);
    await s.sets.delete(id);
    return () async {
      if (prev != null) await s.sets.put(prev);
    };
  }

  /// Swap exercise [idx] of the active session for today and, with [always], in the plan too.
  Future<void> swapExercise(int idx, String exerciseId, {bool always = false}) async {
    final a = await s.activeSession.get(ActiveSessionState.id);
    if (a == null) return;
    final plan = [...?a.plan];
    final cur = plan[idx];
    final ex = await s.exercises.get(exerciseId);
    final unit = ex?.defaultUnit ?? cur.unit;
    final planned = await s.plannedExercises.get(cur.plannedExerciseId);
    final UnitTargets base = planned != null
        ? (repsMin: planned.repsMin, repsMax: planned.repsMax, unit: planned.unit)
        : (repsMin: cur.repsMin, repsMax: cur.repsMax, unit: cur.unit);
    final t = unit == base.unit ? (repsMin: cur.repsMin, repsMax: cur.repsMax, unit: cur.unit) : targetsForUnit(base, unit);
    plan[idx] = SessionExercise.fromJson({
      ...cur.toJson(),
      'exerciseId': exerciseId,
      'unit': t.unit.wire,
      'repsMin': t.repsMin,
      'repsMax': t.repsMax,
    });
    final swaps = {...a.swaps};
    if (exerciseId == cur.originalExerciseId) {
      swaps.remove(cur.plannedExerciseId);
    } else {
      swaps[cur.plannedExerciseId] = exerciseId;
    }
    await patchActive({'plan': plan.map((p) => p.toJson()).toList(), 'swaps': swaps});
    if (always && planned != null) await makePermanentSwap(planned.id, exerciseId);
  }

  /// Make a swap permanent: the planned exercise changes, the old one becomes its swap / alternate.
  Future<void> makePermanentSwap(String plannedExerciseId, String exerciseId) async {
    final pe = await s.plannedExercises.get(plannedExerciseId);
    if (pe == null || pe.exerciseId == exerciseId) return;
    final ex = await s.exercises.get(exerciseId);
    final patch = <String, Object?>{
      'exerciseId': exerciseId,
      'swapExerciseId': pe.swapExerciseId == exerciseId ? pe.exerciseId : pe.swapExerciseId,
    };
    if (ex != null && ex.defaultUnit != pe.unit) {
      final t = targetsForUnit((repsMin: pe.repsMin, repsMax: pe.repsMax, unit: pe.unit), ex.defaultUnit);
      patch.addAll({'repsMin': t.repsMin, 'repsMax': t.repsMax, 'unit': t.unit.wire});
    }
    await s.plannedExercises.patch(pe.id, patch);
    // keep the alternates list on the new exercise so it can be swapped back
    final orig = await s.exercises.get(pe.exerciseId);
    if (ex != null && orig?.alternates != null && (ex.alternates?.isEmpty ?? true)) {
      await s.exercises.put(ex.copyWith(
        alternates: [orig!.id, ...orig.alternates!.where((x) => x != ex.id)],
        pattern: ex.pattern ?? orig.pattern,
      ));
    }
  }

  /// Finish: status done + end time (+ notes), clears the active state. With [feedback], also saves it.
  Future<void> finishSession(String sessionId, {String? notes, SessionFeedback? feedback}) async {
    await s.transaction(() async {
      await s.sessions.patch(sessionId, {
        'status': 'done',
        'endedAt': isoString(now()),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
      await s.activeSession.delete(ActiveSessionState.id);
    });
    if (feedback != null) await saveFeedback(sessionId, feedback);
  }

  /// Throw the session away (its sets too).
  Future<void> discardSession(String sessionId) => s.transaction(() async {
        await s.sets.deleteWhereK1(sessionId);
        await s.sessions.delete(sessionId);
        await s.activeSession.delete(ActiveSessionState.id);
      });

  /// Post-session feedback; returns what it changes about the next session of this day.
  Future<Adaptation> saveFeedback(String sessionId, SessionFeedback fb) async {
    await s.sessions.patch(sessionId, {'feedback': fb.toJson(), 'rpe': fb.rpe, 'notes': fb.note});
    return adaptFromFeedback([fb]);
  }

  /// Suggestion for exercise [idx] of the active session (Player): history-based double progression,
  /// held at last weight when the last session felt too hard or the exercise hurt.
  Future<ActiveSuggestion> suggestionForActive(
    ActiveSessionState active,
    int idx,
    Profile profile, {
    Exercise? exercise,
  }) async {
    final se = active.plan![idx];
    final ex = exercise ?? await s.exercises.get(se.exerciseId);
    final history = await progression.loadHistory(se.exerciseId, excludeSessionId: active.sessionId);
    var sug = suggestNext(
      planned: se.setTarget,
      sets: totalSetsOf(active, idx),
      history: history,
      targetRir: se.rir,
      increment: ex != null ? incrementFor(ex, profile.stepKg) : profile.stepKg.dumbbell,
      bodyweight: ex?.isBodyweight ?? false,
    );
    final pain = active.pain ?? const <String>[];
    final painful = pain.contains(se.exerciseId) || pain.contains(se.originalExerciseId);
    if ((active.hold == true || painful) && (sug.kind == SuggestionKind.increase || sug.kind == SuggestionKind.timeIncrease)) {
      double? lastW;
      if (history.isNotEmpty && history[0].isNotEmpty) {
        final m = history[0].map((x) => x.weightKg ?? 0.0).reduce(math.max);
        lastW = m == 0 ? null : m;
      }
      sug = Suggestion(
        kind: SuggestionKind.hold,
        weightKg: lastW,
        message: painful ? 'Pain last time: keep the weight, move carefully' : 'Holding weight today: last session felt very hard',
        prefill: [
          for (final p in sug.prefill) Prefill(weightKg: lastW ?? p.weightKg, reps: p.reps, seconds: p.seconds, meters: p.meters),
        ],
      );
    }
    final units = profile.units;
    final last = history.isEmpty
        ? null
        : history[0].map((x) {
            if (x.seconds != null) return se.unit == Unit.minutes ? '${jsRound(x.seconds! / 60)} min' : '${x.seconds}s';
            if (x.meters != null) return '${jsNum(x.meters!)} m';
            final w = x.weightKg != null && x.weightKg != 0 ? '${displayWeight(x.weightKg, units)} $units × ' : '';
            return '$w${x.reps ?? ''}';
          }).join(', ');
    return ActiveSuggestion(suggestion: sug, last: last);
  }

  /// Summary of a finished session: duration, volume, PRs vs earlier sessions.
  Future<SessionSummary?> summary(String sessionId) async {
    final session = await s.sessions.get(sessionId);
    if (session == null) return null;
    final sets = (await s.sets.whereK1(sessionId))..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final exIds = {for (final x in sets) x.exerciseId}.toList();
    final prior = <String, List<SetLog>>{};
    for (final id in exIds) {
      final all = await s.sets.whereK2(id);
      final sessions = await s.sessions.bulkGet({for (final x in all) x.sessionId});
      final before = {
        for (final ss in sessions)
          if (ss != null && ss.startedAt.compareTo(session.startedAt) < 0 && ss.status != 'abandoned') ss.id,
      };
      prior[id] = all.where((x) => before.contains(x.sessionId)).toList();
    }
    final planned = session.programDayId == null
        ? <PlannedExercise>[]
        : ((await s.plannedExercises.whereK1(session.programDayId!))..sort((a, b) => a.order - b.order));
    final dur = session.endedAt == null
        ? 0.0
        : DateTime.parse(session.endedAt!).difference(DateTime.parse(session.startedAt)).inMilliseconds / 1000;
    final byEx = <String, List<SetLog>>{};
    for (final x in sets) {
      (byEx[x.exerciseId] ??= []).add(x);
    }
    final prs = <({String exerciseId, List<PRType> types})>[];
    for (final e in byEx.entries) {
      final types = <PRType>{};
      final seen = [...prior[e.key]!.map((x) => x.toWorkSet())];
      for (final x in e.value) {
        if (prior[e.key]!.isNotEmpty) types.addAll(detectPRs(x.toWorkSet(), seen));
        seen.add(x.toWorkSet());
      }
      if (types.isNotEmpty) prs.add((exerciseId: e.key, types: types.toList()));
    }
    return SessionSummary(
      session: session,
      sets: sets,
      prior: prior,
      planned: planned,
      durationSec: dur,
      volume: volume(sets.map((x) => x.toWorkSet()).toList()),
      count: sets.length,
      prs: prs,
      exercises: byEx.keys.toList(),
    );
  }
}
