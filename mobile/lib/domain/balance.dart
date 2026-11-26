// Port of src/domain/balance.ts. Plan check: weekly working sets per muscle group, gaps against a
// goal-based minimum, and concrete fixes ("add X to Thursday"). Pure — the UI applies the suggestion.
import 'equipment.dart';
import 'models.dart';

/// Muscle groups (the web app's `Group`); `.wire` is the JSON id.
enum MuscleGroup with Wire {
  chest('chest', 'Chest'),
  back('back', 'Back'),
  shoulders('shoulders', 'Shoulders'),
  biceps('biceps', 'Biceps'),
  triceps('triceps', 'Triceps'),
  quads('quads', 'Quads'),
  hamstrings('hamstrings', 'Hamstrings'),
  glutes('glutes', 'Glutes'),
  calves('calves', 'Calves'),
  core('core', 'Core');

  const MuscleGroup(this.wire, this.label);
  @override
  final String wire;
  final String label;
}

typedef _G = MuscleGroup;

const Map<String, MuscleGroup> _muscleGroup = {
  'chest': _G.chest,
  'lats': _G.back,
  'middle back': _G.back,
  'traps': _G.back,
  'shoulders': _G.shoulders,
  'biceps': _G.biceps,
  'triceps': _G.triceps,
  'quadriceps': _G.quads,
  'hamstrings': _G.hamstrings,
  'glutes': _G.glutes,
  'calves': _G.calves,
  'abdominals': _G.core,
};

/// Helper-muscle credit: stabilisers (calves in squats, abs in presses) don't count as training them.
const Map<MuscleGroup, double> _secondaryWeight = {
  _G.chest: 0.5,
  _G.back: 0.5,
  _G.shoulders: 0.5,
  _G.biceps: 0.5,
  _G.triceps: 0.5,
  _G.quads: 0.5,
  _G.hamstrings: 0.5,
  _G.glutes: 0.5,
  _G.calves: 0,
  _G.core: 0.25,
};

MuscleGroup? groupOfMuscle(String m) => _muscleGroup[m];

/// Minimum weekly working sets that make a group "covered" for the goal (direct = 1, helper = ½).
Map<MuscleGroup, int> targets(Goal? goal) {
  final big = goal == Goal.muscle ? 10 : 6;
  final small = goal == Goal.muscle ? 6 : (goal == Goal.strength ? 3 : 4);
  return {
    _G.chest: big,
    _G.back: big,
    _G.shoulders: small + 1,
    _G.biceps: small,
    _G.triceps: small,
    _G.quads: big,
    _G.hamstrings: big - 1,
    _G.glutes: big - 1,
    _G.calves: small,
    _G.core: 6,
  };
}

class DayLite {
  const DayLite({required this.id, required this.title, required this.weekday, required this.type});
  factory DayLite.of(ProgramDay d) => DayLite(id: d.id, title: d.title, weekday: d.weekday, type: d.type);
  final String id;
  final String title;
  final Weekday weekday;
  final DayType type;
}

/// Weekly sets per group across strength, conditioning and core work (steady cardio doesn't count).
/// Values are rounded to the nearest ½ set.
Map<MuscleGroup, double> weeklySets(List<DayLite> days, List<PlannedExercise> planned, Map<String, Exercise> exMap) {
  final out = {for (final g in MuscleGroup.values) g: 0.0};
  final trainingDays = {
    for (final d in days)
      if (d.type == DayType.strength || d.type == DayType.conditioning || d.type == DayType.cardio) d.id,
  };
  for (final p in planned) {
    if (!trainingDays.contains(p.dayId) || p.unit == Unit.minutes) continue;
    final ex = exMap[p.exerciseId];
    if (ex == null) continue;
    final prim = ex.primaryMuscles.map(groupOfMuscle).whereType<MuscleGroup>().toSet();
    if (ex.category == Category.core && prim.isEmpty) prim.add(_G.core);
    // hip-dominant compounds are real glute work even when the data lists glutes as a helper
    if (ex.pattern == 'hinge' || ex.pattern == 'lunge/single-leg' || ex.pattern == 'glute') prim.add(_G.glutes);
    final sec = (ex.secondaryMuscles ?? const <String>[]).map(groupOfMuscle).whereType<MuscleGroup>().where((g) => !prim.contains(g)).toSet();
    for (final g in prim) {
      out[g] = out[g]! + p.sets;
    }
    for (final g in sec) {
      out[g] = out[g]! + p.sets * _secondaryWeight[g]!;
    }
  }
  // JS Math.round(x * 2) / 2; values are non-negative so Dart's round() (half away from zero) matches.
  for (final g in MuscleGroup.values) {
    out[g] = (out[g]! * 2).round() / 2;
  }
  return out;
}

/// Which movement patterns best fill a gap, in order of preference.
const Map<MuscleGroup, List<String>> _fixPatterns = {
  _G.chest: ['chest fly', 'horizontal push'],
  _G.back: ['horizontal pull', 'vertical pull'],
  _G.shoulders: ['lateral delt', 'vertical push'],
  _G.biceps: ['elbow flexion'],
  _G.triceps: ['elbow extension'],
  _G.quads: ['knee extension', 'squat', 'lunge/single-leg'],
  _G.hamstrings: ['knee flexion', 'hinge'],
  _G.glutes: ['glute', 'hinge', 'lunge/single-leg'],
  _G.calves: ['calves'],
  _G.core: ['core flexion', 'core anti-extension', 'core anti-rotation'],
};

/// Where a group's extra work fits best: days already training a related area.
const Map<MuscleGroup, List<MuscleGroup>> _related = {
  _G.chest: [_G.chest, _G.triceps, _G.shoulders],
  _G.back: [_G.back, _G.biceps],
  _G.shoulders: [_G.shoulders, _G.chest],
  _G.biceps: [_G.back, _G.biceps],
  _G.triceps: [_G.chest, _G.triceps],
  _G.quads: [_G.quads, _G.glutes],
  _G.hamstrings: [_G.hamstrings, _G.glutes, _G.quads],
  _G.glutes: [_G.glutes, _G.hamstrings, _G.quads],
  _G.calves: [_G.quads, _G.hamstrings, _G.glutes],
  _G.core: [_G.core],
};

final _odd = RegExp(
  r'exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|one leg|twisting|self assisted|kneeling jump|pirate|side lying|with leg raised|with bicep curl|lunge with|on floor\)',
  caseSensitive: false,
);
final _staple = RegExp(
  r'^(machine (lying|seated) leg curl|machine leg extension|machine standing calf raise|dumbbell standing calf raise|bodyweight standing calf raise|machine seated calf raise|dumbbell fly|cable middle fly|machine seated fly|barbell glute bridge|glute bridge two legs on bench|cable standing hip extension|dumbbell incline fly|machine lateral raise|cable lateral raise|dumbbell lateral raise|dumbbell biceps curl|dumbbell hammer curl|ez-bar curl|rope triceps pushdown|cable pushdown|dumbbell standing triceps extension|seated cable row|chest-supported dumbbell row|cable crunch|crunch)$',
  caseSensitive: false,
);

class Suggestion {
  const Suggestion({
    required this.group,
    required this.have,
    required this.need,
    required this.dayId,
    required this.dayLabel,
    required this.options,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.restSec,
  });
  final MuscleGroup group;
  final double have;
  final int need;
  final String dayId;
  final String dayLabel;
  final List<Exercise> options;
  final int sets;
  final int repsMin;
  final int repsMax;
  final int restSec;
}

class PlanCheckResult {
  const PlanCheckResult({required this.sets, required this.targets, required this.suggestions});
  final Map<MuscleGroup, double> sets;
  final Map<MuscleGroup, int> targets;
  final List<Suggestion> suggestions;
}

PlanCheckResult planCheck({
  required List<DayLite> days,
  required List<PlannedExercise> planned,
  required Map<String, Exercise> exMap,
  required List<Exercise> library,
  required List<String> equipment,
  Goal? goal,
}) {
  final sets = weeklySets(days, planned, exMap);
  final tgt = targets(goal);
  final strengthDays = days.where((d) => d.type == DayType.strength).toList();
  final inPlan = <String>{
    for (final p in planned) ...[p.exerciseId, ?p.swapExerciseId],
  }..remove('');
  final suggestions = <Suggestion>[];
  if (strengthDays.isEmpty) return PlanCheckResult(sets: sets, targets: tgt, suggestions: suggestions);

  // per-day group load, to place the fix next to related work
  final dayLoad = <String, Map<MuscleGroup, double>>{
    for (final d in strengthDays) d.id: weeklySets([d], planned.where((p) => p.dayId == d.id).toList(), exMap),
  };
  int dayCount(String id) => planned.where((p) => p.dayId == id).length;
  final addedTo = <String, int>{};

  for (final g in MuscleGroup.values) {
    final have = sets[g]!;
    final need = tgt[g]!;
    if (have >= need) continue;
    final patterns = _fixPatterns[g]!;
    final scored = [
      for (final e in library)
        if (!inPlan.contains(e.id) &&
            e.defaultUnit != Unit.minutes &&
            (e.category == Category.strength || e.category == Category.core) &&
            isAvailable(e, equipment) &&
            e.pattern != null &&
            e.pattern!.isNotEmpty &&
            patterns.contains(e.pattern) &&
            e.primaryMuscles.any((m) => groupOfMuscle(m) == g || (g == _G.core && e.category == Category.core)))
          (
            e: e,
            score: patterns.indexOf(e.pattern!) * 1.5 +
                (e.source == 'dataset' ? 1 : 0) +
                (_odd.hasMatch(e.name) ? 5 : 0) -
                (_staple.hasMatch(e.name) ? 2 : 0) +
                ((e.level ?? 2) - 2).abs(),
          ),
    ];
    final options = stableSorted(scored, (a, b) {
      final d = a.score - b.score;
      return d != 0 ? d : jsLocaleCompare(a.e.name, b.e.name);
    }).take(3).map((x) => x.e).toList();
    if (options.isEmpty) continue;
    final rel = _related[g]!;
    final day = stableSorted<DayLite>(strengthDays, (a, b) {
      final ra = rel.fold<double>(0, (s, r) => s + dayLoad[a.id]![r]!);
      final rb = rel.fold<double>(0, (s, r) => s + dayLoad[b.id]![r]!);
      final ca = dayCount(a.id) + (addedTo[a.id] ?? 0) * 1.5;
      final cb = dayCount(b.id) + (addedTo[b.id] ?? 0) * 1.5;
      final v = cb - ca + (rb - ra) * 0.4;
      return v != 0 ? v : jsLocaleCompare(a.title, b.title);
    }).first;
    addedTo[day.id] = (addedTo[day.id] ?? 0) + 1;
    final deficit = need - have;
    final small = g == _G.calves || g == _G.biceps || g == _G.triceps || g == _G.core;
    suggestions.add(Suggestion(
      group: g,
      have: have,
      need: need,
      dayId: day.id,
      dayLabel: day.title,
      options: options,
      sets: deficit.ceil().clamp(2, 4),
      repsMin: small ? 12 : 10,
      repsMax: small ? 15 : 12,
      restSec: small ? 45 : 60,
    ));
  }
  return PlanCheckResult(sets: sets, targets: tgt, suggestions: suggestions);
}
