// Train feature: view models and providers (week view with "what changed and why", Plan check
// with ranges, plan history) plus the small plan writes the shared PlanEdit service doesn't cover
// yet (remove / restore / update / reorder / activate). Logic is pure where possible so it can be
// moved into lib/domain or lib/data later without touching the screens.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/store.dart';
import '../../data/services/common.dart';
import '../../data/services/progression_data.dart';
import '../../domain/balance.dart';
import '../../domain/equipment.dart' show kPresets;
import '../../domain/models.dart';
import '../../domain/progression.dart' show SuggestionKind;
import '../../domain/schedule.dart';
import '../../domain/session_plan.dart';
import '../../state/providers.dart';

/* ------------------------------------------------------------------ block (8-week wave) */

/// A run of consecutive weeks with the same training intent ("Base wk 1–2").
class BlockPhase {
  const BlockPhase({required this.label, required this.from, required this.to, this.deload = false});
  final String label;
  final int from;
  final int to;
  final bool deload;
  bool contains(int week) => week >= from && week <= to;
  String get range => from == to ? 'wk $from' : 'wk $from–$to';
}

String _phaseLabel(int rir, bool deload) => deload
    ? 'Recovery'
    : rir >= 3
        ? 'Base'
        : rir == 2
            ? 'Build'
            : 'Peak';

/// Phases of the program's 8-week block, from the research week plan (or the simpler cycle).
List<BlockPhase> blockPhases(Program p) {
  final labels = List<({String label, bool deload})>.generate(8, (i) {
    final w = i + 1;
    final f = weekFocusOf(p, w);
    if (f != null) return (label: _phaseLabel(f.rirMain, f.deload), deload: f.deload);
    final c = cycleEntry(w, p.progression.cycle);
    return (label: _phaseLabel(c?.rir ?? 2, c?.deload ?? false), deload: c?.deload ?? false);
  });
  final out = <BlockPhase>[];
  var start = 1;
  for (var w = 2; w <= 9; w++) {
    if (w == 9 || labels[w - 1].label != labels[start - 1].label) {
      out.add(BlockPhase(label: labels[start - 1].label, from: start, to: w - 1, deload: labels[start - 1].deload));
      start = w;
    }
  }
  return out;
}

WeekFocus? weekFocusOf(Program p, int week) {
  for (final w in p.progression.weeks ?? const <WeekFocus>[]) {
    if (w.week == week) return w;
  }
  return null;
}

bool isDeload(Program p, int week) => (weekFocusOf(p, week)?.deload ?? false) || isDeloadWeek(week, p.progression.cycle);

/* ------------------------------------------------------------------ week view model */

/// One planned exercise in a week, with this week's target and what changed since last week.
class PlanRow {
  const PlanRow({required this.pe, required this.ex, required this.target, this.prev, this.suggestion, this.changes = const []});
  final PlannedExercise pe;
  final Exercise? ex;

  /// The session target this week (deload, accessory bumps and RIR applied).
  final SessionExercise target;

  /// Same slot last week (null in the first week of a program).
  final SessionExercise? prev;

  /// Progression suggestion (only for sessions still ahead this week).
  final PlannedSuggestion? suggestion;

  /// Plain-language reasons for each value the engine changed vs last week. Empty = unchanged.
  final List<String> changes;

  bool get changed => changes.isNotEmpty;
  String get name => ex?.name ?? pe.exerciseId;
  double? get weightKg => suggestion?.weightKg;
}

class TrainDay {
  const TrainDay({
    required this.date,
    required this.day,
    required this.rows,
    required this.isToday,
    required this.done,
    required this.moved,
  });
  final DateTime date;
  final ProgramDay? day;
  final List<PlanRow> rows;
  final bool isToday;
  final bool done;
  final bool moved;

  bool get isTraining => day != null && day!.type.isTraining;
  bool get startable => isToday && isTraining && rows.isNotEmpty && !done;
}

class TrainWeek {
  const TrainWeek({
    required this.program,
    required this.offset,
    required this.cycleWeek,
    required this.focus,
    required this.deload,
    required this.days,
    required this.dropped,
    required this.phases,
    required this.currentCycleWeek,
  });
  final Program program;

  /// Weeks from the current calendar week (0 = this week).
  final int offset;
  final int cycleWeek;
  final int currentCycleWeek;
  final WeekFocus? focus;
  final bool deload;
  final List<TrainDay> days;
  final List<ProgramDay> dropped;
  final List<BlockPhase> phases;

  BlockPhase? get phase => phases.where((p) => p.contains(cycleWeek)).firstOrNull;
  DateTime get start => days.first.date;
  DateTime get end => days.last.date;
}

String _setsWord(int n) => n == 1 ? 'set' : 'sets';

/// Reasons a target differs from last week's (pure; [focus] is this week's focus).
List<String> changeReasons({
  required SessionExercise cur,
  required SessionExercise? prev,
  required bool deload,
  required bool prevDeload,
  required WeekFocus? focus,
  required int cycleWeek,
  PlannedSuggestion? suggestion,
  String units = 'kg',
}) {
  final out = <String>[];
  if (prev != null) {
    if (cur.sets != prev.sets) {
      if (deload) {
        out.add('Recovery week: ${prev.sets} → ${cur.sets} ${_setsWord(cur.sets)}, same weights. Lighter on purpose.');
      } else if (prevDeload) {
        out.add('Back to ${cur.sets} ${_setsWord(cur.sets)} after the recovery week.');
      } else if (cur.sets > prev.sets) {
        out.add('Week $cycleWeek${focus != null ? ' (${focus.focus})' : ''} adds ${cur.sets - prev.sets} ${_setsWord(cur.sets - prev.sets)}: ${prev.sets} → ${cur.sets}.');
      } else {
        out.add('Week $cycleWeek${focus != null ? ' (${focus.focus})' : ''} drops back to ${cur.sets} ${_setsWord(cur.sets)}.');
      }
    }
    if (cur.rir != null && prev.rir != null && cur.rir != prev.rir) {
      out.add(cur.rir! < prev.rir!
          ? 'Effort goes up: stop with ${cur.rir} ${cur.rir == 1 ? 'rep' : 'reps'} in reserve (was ${prev.rir}).'
          : 'Effort eases: stop with ${cur.rir} reps in reserve (was ${prev.rir}).');
    }
  }
  final sg = suggestion;
  if (sg != null) {
    switch (sg.kind) {
      case SuggestionKind.increase:
        out.add('Weight up to ${_kg(sg.weightKg, units)}: you hit the top of the range on every set last time.');
      case SuggestionKind.decrease:
        out.add('Weight eases to ${_kg(sg.weightKg, units)}: reps came in under the range two sessions running, so we rebuild.');
      case SuggestionKind.timeIncrease:
        out.add('Longer hold: ${sg.message.replaceAll('↑ ', '')}. You held the full time on every set last time.');
      default:
        break;
    }
  }
  return out;
}

String _kg(double? kg, String units) {
  if (kg == null) return '–';
  final v = units == 'kg' ? kg : kg / 0.45359237;
  final r = units == 'kg' ? (v * 4).round() / 4 : (v * 2).round() / 2;
  return '${r == r.roundToDouble() ? r.toInt() : r} $units';
}

/// "3 × 8–12" / "3 × 30–45 s / side".
String targetText(SessionExercise t) {
  final reps = t.repsMin == t.repsMax ? '${t.repsMax}' : '${t.repsMin}–${t.repsMax}';
  final unit = switch (t.unit) { Unit.reps => '', Unit.seconds => ' s', Unit.minutes => ' min', Unit.meters => ' m' };
  return '${t.sets} × $reps$unit${t.perSide ? ' / side' : ''}';
}

/// The selected week of the Train tab ([offset] weeks from this week).
final trainWeekProvider = FutureProvider.family<TrainWeek?, int>((ref, offset) async {
  final now = ref.watch(clockProvider)();
  final today = dateOnly(now);
  final bundle = await ref.watch(programBundleProvider.future);
  if (bundle == null) return null;
  final exMap = await ref.watch(exerciseMapProvider.future);
  final profile = await ref.watch(profileProvider.future);
  final anchor = addDays(today, offset * 7);
  final dates = weekDates(anchor);
  final live = offset == 0 ? await ref.watch(weekPlanProvider(today).future) : null;
  final sessions = await ref.watch(weekSessionsProvider(anchor).future);
  final progression = ref.watch(progressionDataProvider);
  final program = bundle.program;

  final cw = cycleWeek(anchor, program.startedOn);
  final currentCw = cycleWeek(today, program.startedOn);
  final focus = weekFocusOf(program, cw);
  final deload = isDeload(program, cw);
  final prevCw = cw == 1 ? 8 : cw - 1;
  final prevFocus = weekFocusOf(program, prevCw);
  final prevDeload = isDeload(program, prevCw);
  // the previous week only exists once the program has run for a week
  final hasPrev = daysBetween(dates.first, fromDayKey(program.startedOn)) >= 7;
  final units = profile?.units ?? 'kg';

  final days = <TrainDay>[];
  for (final date in dates) {
    final k = dayKey(date);
    final day = live != null ? live.byDate[k] : getDayPlan(bundle.days, date, (d) => d.weekday);
    final isToday = k == dayKey(today);
    final done = sessions.any((x) => x.dayKey == k && x.status == 'done');
    final moved = live != null && live.adjusted && live.original[k]?.id != day?.id;
    final rows = <PlanRow>[];
    if (day != null) {
      final planned = bundle.plannedFor(day.id);
      final cur = buildSessionPlan(planned: planned, dayType: day.type, mode: SessionMode.full, deload: deload, week: focus, fallbackRir: targetRir(cw, program.progression.cycle));
      final prev = hasPrev
          ? buildSessionPlan(planned: planned, dayType: day.type, mode: SessionMode.full, deload: prevDeload, week: prevFocus, fallbackRir: targetRir(prevCw, program.progression.cycle))
          : null;
      final ahead = offset == 0 && !date.isBefore(today) && !done && day.type.isTraining;
      for (var i = 0; i < planned.length; i++) {
        final pe = planned[i];
        final ex = exMap[pe.exerciseId];
        PlannedSuggestion? sg;
        if (ahead && profile != null && pe.unit != Unit.minutes) {
          sg = await progression.suggestionFor(pe, pe.exerciseId, ex, profile, program, date);
        }
        rows.add(PlanRow(
          pe: pe,
          ex: ex,
          target: cur[i],
          prev: prev?[i],
          suggestion: sg,
          changes: changeReasons(cur: cur[i], prev: prev?[i], deload: deload, prevDeload: prevDeload, focus: focus, cycleWeek: cw, suggestion: sg, units: units),
        ));
      }
    }
    days.add(TrainDay(date: date, day: day, rows: rows, isToday: isToday, done: done, moved: moved));
  }
  return TrainWeek(
    program: program,
    offset: offset,
    cycleWeek: cw,
    currentCycleWeek: currentCw,
    focus: focus,
    deload: deload,
    days: days,
    dropped: live?.dropped ?? const [],
    phases: blockPhases(program),
  );
});

/* ------------------------------------------------------------------ Plan check */

enum VolumeState { below, inRange, above }

/// Weekly hard sets above which recovery, not growth, becomes the limit (independent of goal).
const Map<MuscleGroup, int> kVolumeCeiling = {
  MuscleGroup.chest: 22,
  MuscleGroup.back: 22,
  MuscleGroup.shoulders: 22,
  MuscleGroup.biceps: 16,
  MuscleGroup.triceps: 16,
  MuscleGroup.quads: 22,
  MuscleGroup.hamstrings: 22,
  MuscleGroup.glutes: 22,
  MuscleGroup.calves: 16,
  MuscleGroup.core: 24,
};

/// The weekly hard-set range for a group: the goal minimum up to the recovery ceiling.
({int lo, int hi}) aimRange(MuscleGroup g, int need) => (lo: need, hi: math.max(need + 4, kVolumeCeiling[g]!));

VolumeState volumeState(MuscleGroup g, double have, int need) {
  final r = aimRange(g, need);
  if (have < r.lo) return VolumeState.below;
  if (have > r.hi) return VolumeState.above;
  return VolumeState.inRange;
}

const _singular = {MuscleGroup.chest, MuscleGroup.back, MuscleGroup.core};

String setsText(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class PlanCheckView {
  const PlanCheckView({required this.result, required this.days});
  final PlanCheckResult result;
  final List<ProgramDay> days;

  VolumeState stateOf(MuscleGroup g) => volumeState(g, result.sets[g]!, result.targets[g]!);
  List<MuscleGroup> get below => [for (final g in MuscleGroup.values) if (stateOf(g) == VolumeState.below) g];
  List<MuscleGroup> get above => [for (final g in MuscleGroup.values) if (stateOf(g) == VolumeState.above) g];
  Suggestion? fixFor(MuscleGroup g) => result.suggestions.where((s) => s.group == g).firstOrNull;
  ProgramDay? dayOf(String id) => days.where((d) => d.id == id).firstOrNull;

  /// "Hamstrings 4 sets — aim 9–14".
  String line(MuscleGroup g) {
    final r = aimRange(g, result.targets[g]!);
    final have = result.sets[g]!;
    return '${g.label} ${setsText(have)} ${have == 1 ? 'set' : 'sets'} — aim ${r.lo}–${r.hi}';
  }

  /// One-sentence verdict, words before numbers.
  String get summary {
    final b = below;
    final a = above;
    String names(List<MuscleGroup> l) {
      final n = l.map((g) => g.label.toLowerCase()).toList();
      return n.length <= 1 ? n.join() : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
    }

    if (b.isEmpty && a.isEmpty) return 'Balanced: every muscle group gets the right amount of work this week.';
    final aboveNote = a.isEmpty ? '' : ' ${_cap(names(a))} ${a.length == 1 && _singular.contains(a.first) ? 'is' : 'are'} above range: fine for a block, watch recovery.';
    if (b.isEmpty) return 'Everything is covered.$aboveNote';
    if (b.length == 1) {
      final g = b.first;
      final r = aimRange(g, result.targets[g]!);
      return '${g.label} ${_singular.contains(g) ? 'needs' : 'need'} more work: ${setsText(result.sets[g]!)} sets a week, aim ${r.lo}–${r.hi}.$aboveNote';
    }
    return '${b.length} areas need more work: ${names(b)}.$aboveNote';
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Weekly sets per muscle for the active plan, with fixes for gaps.
final planCheckProvider = FutureProvider<PlanCheckView?>((ref) async {
  final bundle = await ref.watch(programBundleProvider.future);
  if (bundle == null) return null;
  final exMap = await ref.watch(exerciseMapProvider.future);
  final profile = await ref.watch(profileProvider.future);
  // IndexedDB primary-key order, which the balance tie-breaks expect
  final library = exMap.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  final res = planCheck(
    days: bundle.days.map(DayLite.of).toList(),
    planned: bundle.planned,
    exMap: exMap,
    library: library,
    equipment: profile == null ? kPresets['full_gym']! : equipmentOf(profile),
    goal: profile?.goal,
  );
  return PlanCheckView(result: res, days: bundle.days);
});


/* ------------------------------------------------------------------ plan history */

enum PlanAuthor { you, coach, generated, template }

PlanAuthor authorOf(Program p) {
  final t = p.templateId;
  if (t == null || t.isEmpty || t == 'blank' || t == 'custom') return PlanAuthor.you;
  if (t == 'ai-coach' || t.startsWith('ai')) return PlanAuthor.coach;
  if (t.startsWith('generated')) return PlanAuthor.generated;
  return PlanAuthor.template;
}

String authorLabel(PlanAuthor a) => switch (a) {
      PlanAuthor.you => 'Built by you',
      PlanAuthor.coach => 'Written by the AI coach',
      PlanAuthor.generated => 'Generated from your setup',
      PlanAuthor.template => 'Repfellow template',
    };

class PlanVersion {
  const PlanVersion({required this.program, required this.trainingDays, required this.exerciseIds});
  final Program program;
  final int trainingDays;
  final List<String> exerciseIds;
}

/// Every program on the device, active first, then newest first.
final planVersionsProvider = StreamProvider<List<PlanVersion>>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'programs', 'programDays', 'plannedExercises'}, () async {
    final programs = await s.programs.all();
    final out = <PlanVersion>[];
    for (final p in programs) {
      final days = await s.programDays.whereK1(p.id);
      final planned = await s.plannedExercises.whereK1In(days.map((d) => d.id));
      out.add(PlanVersion(
        program: p,
        trainingDays: days.where((d) => d.type.isTraining).length,
        exerciseIds: planned.map((x) => x.exerciseId).toList(),
      ));
    }
    out.sort((a, b) {
      if (a.program.active != b.program.active) return a.program.active ? -1 : 1;
      return b.program.startedOn.compareTo(a.program.startedOn);
    });
    return out;
  });
});

/// One-line difference of [v] against [current] ("4 days · 3 exercises differ").
String diffLine(PlanVersion v, PlanVersion? current) {
  final base = '${v.trainingDays} training ${v.trainingDays == 1 ? 'day' : 'days'} · ${v.exerciseIds.length} exercises';
  if (current == null || current.program.id == v.program.id) return base;
  final mine = v.exerciseIds.toSet();
  final theirs = current.exerciseIds.toSet();
  final added = mine.difference(theirs).length;
  final removed = theirs.difference(mine).length;
  if (added == 0 && removed == 0) return '$base · same exercises as now';
  return '$base · ${[if (added > 0) '+$added', if (removed > 0) '−$removed'].join(' / ')} vs now';
}

/* ------------------------------------------------------------------ plan writes */

/// Plan edits the Train feature needs beyond PlanEdit.addExerciseToDay (candidates for PlanEdit).
class PlanOps {
  PlanOps(this.s);
  final Stores s;

  /// Remove a planned exercise; returns it so the caller can offer Undo.
  Future<PlannedExercise?> remove(String plannedId) async {
    final pe = await s.plannedExercises.get(plannedId);
    if (pe != null) await s.plannedExercises.delete(plannedId);
    return pe;
  }

  Future<void> restore(PlannedExercise pe) => s.plannedExercises.put(pe);

  Future<void> update(PlannedExercise pe) => s.plannedExercises.put(pe);

  /// Rewrite the order of a day's exercises to match [ids].
  Future<void> reorder(List<PlannedExercise> ordered) => s.transaction(() async {
        await s.plannedExercises.putAll([for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(order: i)]);
      });

  Future<void> updateDay(ProgramDay d) => s.programDays.put(d);

  /// Make [programId] the active plan. Returns the previously active id (for Undo).
  Future<String?> activate(String programId) async {
    final prev = await s.activeProgram();
    final target = await s.programs.get(programId);
    if (target == null) return prev?.id;
    await s.transaction(() async {
      final active = await s.programs.whereK1('1');
      await s.programs.putAll(active.map((p) => p.copyWith(active: false)));
      await s.programs.put(target.copyWith(active: true));
    });
    return prev?.id;
  }
}

final planOpsProvider = Provider<PlanOps>((ref) => PlanOps(ref.watch(storesProvider)));
