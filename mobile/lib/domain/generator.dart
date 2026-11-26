// Port of src/domain/generator.ts. Rule-based program generator (pure). Builds a weekly plan from
// goal, experience, training days, session length and available equipment, using the
// movement-pattern library (doc 09). Never includes an exercise whose equipment isn't available.
import 'equipment.dart';
import 'models.dart';

class GoalOption {
  const GoalOption(this.id, this.label, this.sub, this.emoji);
  final Goal id;
  final String label;
  final String sub;
  final String emoji;
}

const List<GoalOption> kGoals = [
  GoalOption(Goal.fatLoss, 'Lose fat', 'Drop weight, keep muscle', '🔥'),
  GoalOption(Goal.lean, 'Lean & athletic', 'Leaner, stronger, fitter', '⚡'),
  GoalOption(Goal.muscle, 'Build muscle', 'Size with a small surplus', '💪'),
  GoalOption(Goal.strength, 'Get stronger', 'Heavier lifts, lower reps', '🏋️'),
  GoalOption(Goal.general, 'General fitness', 'Feel good, move well', '🌿'),
];

/// Movement patterns used by the templates (the value is the library's `pattern` string).
enum MovePattern {
  squat('squat'),
  hinge('hinge'),
  lunge('lunge/single-leg'),
  hpush('horizontal push'),
  vpush('vertical push'),
  hpull('horizontal pull'),
  vpull('vertical pull'),
  curl('elbow flexion'),
  ext('elbow extension'),
  lat('lateral delt'),
  rear('rear delt/scap'),
  antiExt('core anti-extension'),
  antiRot('core anti-rotation'),
  flex('core flexion'),
  carry('carry'),
  power('power/plyometric'),
  cardio('conditioning/cardio'),
  mobility('mobility'),
  kneeFlex('knee flexion'),
  kneeExt('knee extension'),
  calves('calves'),
  fly('chest fly'),
  glute('glute');

  const MovePattern(this.value);
  final String value;
}

enum SlotRole { main, acc, core, steady, interval, power, carry, mobility }

class _SlotT {
  const _SlotT(this.slot, this.p, this.role, [this.group]);
  final String slot;
  final MovePattern p;
  final SlotRole role;
  final String? group;
}

class _DayT {
  const _DayT(this.key, this.title, this.type, this.slots);
  final String key;
  final String title;
  final DayType type;
  final List<_SlotT> slots;
}

typedef _S = _SlotT;
const _m = SlotRole.main, _a = SlotRole.acc, _c = SlotRole.core;
typedef _M = MovePattern;

final Map<String, _DayT> _t = {
  for (final d in [
    _DayT('FB_A', 'Full body A', DayType.strength, [_S('A1', _M.squat, _m, 'A'), _S('A2', _M.hpush, _m, 'A'), _S('B1', _M.vpull, _m, 'B'), _S('B2', _M.hinge, _m, 'B'), _S('C', _M.vpush, _a), _S('D', _M.antiExt, _c), _S('E', _M.flex, _c), _S('F', _M.calves, _a)]),
    _DayT('FB_B', 'Full body B', DayType.strength, [_S('A1', _M.squat, _m, 'A'), _S('A2', _M.hpush, _m, 'A'), _S('B1', _M.hpull, _m, 'B'), _S('B2', _M.lunge, _m, 'B'), _S('C', _M.rear, _a), _S('D1', _M.curl, _a, 'D'), _S('D2', _M.ext, _a, 'D'), _S('E', _M.kneeFlex, _a)]),
    _DayT('FB_C', 'Full body C – heavier', DayType.strength, [_S('A', _M.hinge, _m), _S('B1', _M.vpull, _m, 'B'), _S('B2', _M.hpush, _m, 'B'), _S('C', _M.lunge, _a), _S('D1', _M.lat, _a, 'D'), _S('D2', _M.antiRot, _c, 'D'), _S('E', _M.carry, SlotRole.carry), _S('F', _M.glute, _a)]),
    _DayT('UA', 'Upper A', DayType.strength, [_S('A1', _M.hpush, _m, 'A'), _S('A2', _M.hpull, _m, 'A'), _S('B1', _M.vpush, _m, 'B'), _S('B2', _M.vpull, _m, 'B'), _S('C1', _M.lat, _a, 'C'), _S('C2', _M.rear, _a, 'C'), _S('D1', _M.curl, _a, 'D'), _S('D2', _M.ext, _a, 'D')]),
    _DayT('UB', 'Upper B', DayType.strength, [_S('A1', _M.vpull, _m, 'A'), _S('A2', _M.hpush, _m, 'A'), _S('B1', _M.hpull, _m, 'B'), _S('B2', _M.vpush, _m, 'B'), _S('C1', _M.rear, _a, 'C'), _S('C2', _M.lat, _a, 'C'), _S('D1', _M.ext, _a, 'D'), _S('D2', _M.curl, _a, 'D')]),
    _DayT('LA', 'Lower A', DayType.strength, [_S('A', _M.squat, _m), _S('B', _M.hinge, _m), _S('C', _M.lunge, _a), _S('D1', _M.kneeFlex, _a, 'D'), _S('D2', _M.calves, _a, 'D'), _S('E', _M.antiExt, _c), _S('F', _M.flex, _c), _S('G', _M.carry, SlotRole.carry)]),
    _DayT('LB', 'Lower B', DayType.strength, [_S('A', _M.hinge, _m), _S('B', _M.squat, _m), _S('C', _M.lunge, _a), _S('D1', _M.kneeExt, _a, 'D'), _S('D2', _M.glute, _a, 'D'), _S('E', _M.antiRot, _c), _S('F', _M.calves, _a), _S('G', _M.carry, SlotRole.carry)]),
    _DayT('PUSH', 'Push', DayType.strength, [_S('A', _M.hpush, _m), _S('B', _M.vpush, _m), _S('C', _M.hpush, _a), _S('D1', _M.lat, _a, 'D'), _S('D2', _M.ext, _a, 'D'), _S('E', _M.fly, _a), _S('F', _M.antiExt, _c)]),
    _DayT('PULL', 'Pull', DayType.strength, [_S('A', _M.vpull, _m), _S('B', _M.hpull, _m), _S('C', _M.hpull, _a), _S('D1', _M.rear, _a, 'D'), _S('D2', _M.curl, _a, 'D'), _S('E', _M.carry, SlotRole.carry)]),
    _DayT('LEGS', 'Legs', DayType.strength, [_S('A', _M.squat, _m), _S('B', _M.hinge, _m), _S('C', _M.lunge, _a), _S('D1', _M.kneeFlex, _a, 'D'), _S('D2', _M.kneeExt, _a, 'D'), _S('E', _M.calves, _a), _S('F', _M.flex, _c), _S('G', _M.antiRot, _c)]),
    _DayT('CARDIO', 'Steady cardio + core', DayType.cardio, [_S('1', _M.cardio, SlotRole.steady), _S('2', _M.flex, _c), _S('3', _M.antiExt, _c), _S('4', _M.antiRot, _c), _S('5', _M.mobility, SlotRole.mobility)]),
    _DayT('COND', 'Athletic power + intervals', DayType.conditioning, [_S('1', _M.power, SlotRole.power), _S('2', _M.power, SlotRole.power), _S('3a', _M.hinge, SlotRole.power, 'C'), _S('3b', _M.carry, SlotRole.carry, 'C'), _S('4', _M.cardio, SlotRole.interval)]),
  ])
    d.key: d,
};

const Map<Goal, Map<int, List<String>>> _splits = {
  Goal.fatLoss: {1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['FB_A', 'CARDIO', 'FB_B', 'FB_C'], 5: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C'], 6: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C', 'CARDIO']},
  Goal.lean: {1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['FB_A', 'COND', 'FB_B', 'FB_C'], 5: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C'], 6: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C', 'CARDIO']},
  Goal.muscle: {1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['UA', 'LA', 'UB', 'LB'], 5: ['UA', 'LA', 'PUSH', 'PULL', 'LEGS'], 6: ['PUSH', 'PULL', 'LEGS', 'PUSH', 'PULL', 'LEGS']},
  Goal.strength: {1: ['FB_C'], 2: ['FB_A', 'FB_C'], 3: ['FB_A', 'FB_B', 'FB_C'], 4: ['UA', 'LA', 'UB', 'LB'], 5: ['UA', 'LA', 'UB', 'LB', 'FB_C'], 6: ['UA', 'LA', 'UB', 'LB', 'UA', 'LB']},
  Goal.general: {1: ['FB_A'], 2: ['FB_A', 'FB_B'], 3: ['FB_A', 'CARDIO', 'FB_B'], 4: ['FB_A', 'CARDIO', 'FB_B', 'FB_C'], 5: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C'], 6: ['FB_A', 'CARDIO', 'FB_B', 'COND', 'FB_C', 'CARDIO']},
};

const Map<int, int> kSlotsForMinutes = {30: 4, 45: 5, 60: 6, 75: 7, 90: 8};

class GenInput {
  const GenInput({
    required this.goal,
    required this.experience,
    required this.days,
    required this.sessionMin,
    required this.equipment,
    required this.library,
  });
  final Goal goal;
  final Experience experience;
  final List<Weekday> days;
  final int sessionMin;
  final List<String> equipment;
  final List<Exercise> library;
}

class GenExercise {
  GenExercise({
    required this.slot,
    required this.exerciseId,
    this.swapExerciseId,
    this.supersetGroup,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.unit,
    required this.perSide,
    required this.restSec,
    this.cue,
  });
  final String slot;
  final String exerciseId;
  final String? swapExerciseId;
  String? supersetGroup;
  final int sets;
  final int repsMin;
  final int repsMax;
  final Unit unit;
  final bool perSide;
  final int restSec;
  final String? cue;

  /// Same shape as the web app's GenExercise (undefined fields omitted).
  Map<String, Object?> toJson() => {
        'slot': slot,
        'exerciseId': exerciseId,
        if (swapExerciseId != null) 'swapExerciseId': swapExerciseId,
        if (supersetGroup != null) 'supersetGroup': supersetGroup,
        'sets': sets,
        'repsMin': repsMin,
        'repsMax': repsMax,
        'unit': unit.wire,
        'perSide': perSide,
        'restSec': restSec,
        if (cue != null) 'cue': cue,
      };
}

class GenDay {
  const GenDay({required this.weekday, required this.type, required this.title, this.durationMin, this.notes, required this.exercises});
  final Weekday weekday;
  final DayType type;
  final String title;
  final int? durationMin;
  final String? notes;
  final List<GenExercise> exercises;

  Map<String, Object?> toJson() => {
        'weekday': weekday.wire,
        'type': type.wire,
        'title': title,
        if (durationMin != null) 'durationMin': durationMin,
        if (notes != null) 'notes': notes,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}

class GenProgram {
  const GenProgram({required this.name, required this.days});
  final String name;
  final List<GenDay> days;
}

typedef Presc = ({int sets, int repsMin, int repsMax, int restSec});

Presc prescription(Goal goal, Experience exp, SlotRole role, Unit unit, int sessionMin) {
  final beginner = exp == Experience.beginner;
  switch (role) {
    case SlotRole.steady:
      final m = sessionMin <= 45 ? 20 : 30;
      return (sets: 1, repsMin: m, repsMax: m, restSec: 0);
    case SlotRole.mobility:
      return (sets: 1, repsMin: 8, repsMax: 8, restSec: 0);
    case SlotRole.interval:
      return (sets: 6, repsMin: 30, repsMax: 30, restSec: 90);
    case SlotRole.power:
      return (sets: beginner ? 3 : 4, repsMin: 5, repsMax: 6, restSec: 60);
    case SlotRole.carry:
      return unit == Unit.meters ? (sets: 3, repsMin: 30, repsMax: 30, restSec: 60) : (sets: 3, repsMin: 30, repsMax: 40, restSec: 60);
    case SlotRole.core:
      if (unit == Unit.seconds) {
        return beginner ? (sets: 2, repsMin: 20, repsMax: 30, restSec: 45) : (sets: 3, repsMin: 30, repsMax: 45, restSec: 45);
      }
      return (sets: beginner ? 2 : 3, repsMin: 10, repsMax: 15, restSec: 45);
    case SlotRole.main:
    case SlotRole.acc:
      break;
  }
  final main = role == SlotRole.main;
  switch (goal) {
    case Goal.strength:
      return main
          ? (sets: beginner ? 3 : 4, repsMin: beginner ? 6 : 4, repsMax: beginner ? 8 : 6, restSec: 150)
          : (sets: 3, repsMin: 8, repsMax: 10, restSec: 75);
    case Goal.muscle:
      return main ? (sets: beginner ? 3 : 4, repsMin: 8, repsMax: 12, restSec: 90) : (sets: beginner ? 2 : 3, repsMin: 10, repsMax: 15, restSec: 60);
    case Goal.general:
      return main ? (sets: 3, repsMin: 8, repsMax: 12, restSec: 75) : (sets: 2, repsMin: 10, repsMax: 15, restSec: 45);
    case Goal.fatLoss:
    case Goal.lean:
      return main ? (sets: 3, repsMin: 8, repsMax: 10, restSec: 75) : (sets: beginner ? 2 : 3, repsMin: 10, repsMax: 12, restSec: 45);
  }
}

/// Variants that confuse more than they help in a generated plan (still available to pick by hand).
final _oddVariant = RegExp(
  r'exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|wall\)|one leg|single leg platform|twisting|lying femoral|rotary|donkey|self assisted|kneeling jump|pirate|side lying',
  caseSensitive: false,
);

/// Plain gym staples for the isolation patterns.
final _staple = RegExp(
  r'^(machine (lying|seated) leg curl|machine leg extension|machine standing calf raise|dumbbell standing calf raise|bodyweight standing calf raise|machine seated calf raise|dumbbell fly|cable middle fly|machine seated fly|barbell glute bridge|glute bridge two legs on bench|cable standing hip extension|dumbbell incline fly)$',
  caseSensitive: false,
);
final _mainPenalty = RegExp(r'assisted|machine|back extension|hyperextension', caseSensitive: false);
final _pullover = RegExp('pullover', caseSensitive: false);
final _perSide = RegExp(r'single|one-arm|one arm|lunge|split squat|step-?up|side plank|bulgarian|suitcase', caseSensitive: false);

const _targetLevel = {Experience.beginner: 2, Experience.intermediate: 3, Experience.advanced: 4};
const _maxLevel = {Experience.beginner: 3, Experience.intermediate: 4, Experience.advanced: 5};

List<Exercise> _candidatesFor(List<Exercise> lib, MovePattern p, SlotRole role, Experience exp, List<String> equipment) {
  final Unit? wantUnit = role == SlotRole.steady ? Unit.minutes : (role == SlotRole.interval ? Unit.seconds : null);
  final target = _targetLevel[exp]!;
  final maxLevel = _maxLevel[exp]!;
  var list = lib.where((e) => e.pattern == p.value && isAvailable(e, equipment) && (e.level ?? target) <= maxLevel).toList();
  if (wantUnit != null) {
    final exact = list.where((e) => e.defaultUnit == wantUnit).toList();
    if (exact.isNotEmpty) list = exact;
  } else if (role == SlotRole.main || role == SlotRole.acc || role == SlotRole.power) {
    final reps = list.where((e) => e.defaultUnit == Unit.reps).toList();
    if (reps.isNotEmpty) list = reps;
  }
  // main lifts: prefer loaded, proven compound movements (the library's "parent" exercises carry alternates).
  // The 3D dataset fills patterns the curated list lacks; prefer its plain gym staples over odd variants.
  final isMain = role == SlotRole.main;
  double score(Exercise e) =>
      ((e.level ?? target) - target).abs() +
      (isMain && e.isBodyweight == true ? 1.5 : 0) -
      ((isMain || role == SlotRole.acc) && (e.alternates?.isNotEmpty ?? false) ? 1 : 0) +
      (isMain && _mainPenalty.hasMatch(e.name) ? 0.75 : 0) +
      (e.source == 'dataset' ? 1.5 : 0) +
      (_oddVariant.hasMatch(e.name) ? 3 : 0) -
      (_staple.hasMatch(e.name) ? 2 : 0) +
      (isMain && _pullover.hasMatch(e.name) ? 2 : 0);
  final scores = {for (final e in list) e: score(e)};
  return stableSorted<Exercise>(list, (a, b) {
    final d = scores[a]! - scores[b]!;
    return d != 0 ? d : jsLocaleCompare(a.name, b.name);
  });
}

GenProgram generateProgram(GenInput input) {
  final chosen = input.days.toSet().toList()..sort((a, b) => a.index - b.index);
  final n = (chosen.isEmpty ? 3 : chosen.length).clamp(1, 6);
  final split = _splits[input.goal]![n]!;
  final maxSlots = kSlotsForMinutes[input.sessionMin] ?? 6;
  final variant = <String, int>{};
  final usedWeek = <String, int>{};
  final days = <GenDay>[];

  final trainingDays = chosen.take(n).toList();
  for (var i = 0; i < trainingDays.length; i++) {
    final wd = trainingDays[i];
    final t = _t[split[i % split.length]]!;
    final exercises = <GenExercise>[];
    final usedToday = <String>{};
    final slots = t.type == DayType.strength
        ? t.slots.take(maxSlots).toList()
        : t.slots.take(maxSlots - 1 > 3 ? maxSlots - 1 : 3).toList();
    for (final sl in slots) {
      final cands = _candidatesFor(input.library, sl.p, sl.role, input.experience, input.equipment).where((c) => !usedToday.contains(c.id)).toList();
      if (cands.isEmpty) continue;
      final key = '${sl.p.name}:${sl.role.name}';
      final v = variant[key] ?? 0;
      variant[key] = v + 1;
      // prefer exercises not used yet this week for variety (main lifts may repeat across days)
      final fresh = sl.role == SlotRole.main ? cands : cands.where((c) => !usedWeek.containsKey(c.id)).toList();
      final pool = fresh.isNotEmpty ? fresh : cands;
      final pick = pool[v % pool.length];
      usedToday.add(pick.id);
      usedWeek[pick.id] = (usedWeek[pick.id] ?? 0) + 1;
      final pickEq = pick.equipment.join(',');
      Exercise? swap;
      for (final c in cands) {
        if (c.id != pick.id && c.equipment.join(',') != pickEq) {
          swap = c;
          break;
        }
      }
      if (swap == null) {
        for (final c in cands) {
          if (c.id != pick.id) {
            swap = c;
            break;
          }
        }
      }
      final unit = sl.role == SlotRole.steady ? Unit.minutes : (sl.role == SlotRole.interval ? Unit.seconds : pick.defaultUnit);
      final pr = prescription(input.goal, input.experience, sl.role, unit, input.sessionMin);
      exercises.add(GenExercise(
        slot: sl.slot,
        exerciseId: pick.id,
        swapExerciseId: swap?.id,
        supersetGroup: sl.group,
        sets: pr.sets,
        repsMin: pr.repsMin,
        repsMax: pr.repsMax,
        unit: unit,
        perSide: _perSide.hasMatch(pick.name),
        restSec: pr.restSec,
        cue: pick.cue,
      ));
    }
    // superset partners must both exist; otherwise drop the group label
    for (final e in exercises) {
      if (e.supersetGroup != null && exercises.where((x) => x.supersetGroup == e.supersetGroup).length < 2) e.supersetGroup = null;
    }
    days.add(GenDay(weekday: wd, type: t.type, title: t.title, durationMin: input.sessionMin, exercises: exercises));
  }

  // non-training days: rest, with one active-recovery day for fat loss / lean / general
  final free = kWeekdays.where((w) => !days.any((d) => d.weekday == w)).toList();
  final Weekday? recovery = input.goal == Goal.muscle || input.goal == Goal.strength
      ? null
      : (free.contains(Weekday.sun) ? Weekday.sun : (free.isEmpty ? null : free.last));
  for (final w in free) {
    days.add(w == recovery
        ? GenDay(weekday: w, type: DayType.activeRecovery, title: 'Active recovery', notes: '30–45 min brisk walk + 10 min mobility.', exercises: [])
        : GenDay(weekday: w, type: DayType.rest, title: 'Rest', notes: 'Aim for 7,000+ steps.', exercises: []));
  }
  days.sort((a, b) => a.weekday.index - b.weekday.index);
  final g = kGoals.firstWhere((x) => x.id == input.goal);
  return GenProgram(name: '${g.label} · $n day${n > 1 ? 's' : ''}', days: days);
}
