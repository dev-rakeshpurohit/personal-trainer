// Library: browse filters (body area, equipment, fits my gym), search, and per-exercise history.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/common.dart' show equipmentOf;
import '../../domain/equipment.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart' show e1rm;
import '../../state/providers.dart';

class BodyArea {
  const BodyArea(this.id, this.label, this.test);
  final String id;
  final String label;
  final bool Function(Exercise e) test;
}

bool _any(Exercise e, Set<String> m) => e.primaryMuscles.any(m.contains);

/// Body areas for browsing (maps the library's muscle vocabulary).
final List<BodyArea> kBodyAreas = [
  BodyArea('chest', 'Chest', (e) => e.primaryMuscles.contains('chest')),
  BodyArea('back', 'Back', (e) => _any(e, {'lats', 'middle back', 'traps', 'lower back'})),
  BodyArea('shoulders', 'Shoulders', (e) => e.primaryMuscles.contains('shoulders')),
  BodyArea('arms', 'Arms', (e) => _any(e, {'biceps', 'triceps', 'forearms'})),
  BodyArea('legs', 'Legs', (e) => _any(e, {'quadriceps', 'hamstrings', 'adductors', 'abductors'})),
  BodyArea('glutes', 'Glutes', (e) => e.primaryMuscles.contains('glutes')),
  BodyArea('calves', 'Calves', (e) => e.primaryMuscles.contains('calves')),
  BodyArea('core', 'Core', (e) => e.category == Category.core || e.primaryMuscles.contains('abdominals')),
  BodyArea('cardio', 'Cardio & power', (e) => e.category == Category.cardio || e.category == Category.power),
  BodyArea('mobility', 'Mobility', (e) => e.category == Category.mobility),
];

/// Equipment filter value for "no equipment".
const kBodyweight = 'none';

class LibraryFilter {
  const LibraryFilter({this.query = '', this.area, this.equipment, this.fitsGym = true});
  final String query;
  final String? area;
  final String? equipment;
  final bool fitsGym;

  LibraryFilter copyWith({String? query, String? Function()? area, String? Function()? equipment, bool? fitsGym}) => LibraryFilter(
        query: query ?? this.query,
        area: area != null ? area() : this.area,
        equipment: equipment != null ? equipment() : this.equipment,
        fitsGym: fitsGym ?? this.fitsGym,
      );
}

/// Filter [all] (already sorted) with [f] against the user's [available] equipment.
List<Exercise> filterExercises(List<Exercise> all, LibraryFilter f, List<String> available) {
  final words = f.query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final area = f.area == null ? null : kBodyAreas.firstWhere((a) => a.id == f.area);
  return [
    for (final e in all)
      if (_matches(e, f, area, words, available)) e,
  ];
}

bool _matches(Exercise e, LibraryFilter f, BodyArea? area, List<String> words, List<String> available) {
  if (f.fitsGym && !isAvailable(e, available)) return false;
  if (area != null && !area.test(e)) return false;
  if (f.equipment != null) {
    final need = requiredEquipment(e);
    if (f.equipment == kBodyweight ? need.isNotEmpty : !need.contains(f.equipment)) return false;
  }
  if (words.isNotEmpty) {
    final hay = '${e.name} ${e.primaryMuscles.join(' ')} ${e.pattern ?? ''}'.toLowerCase();
    if (!words.every(hay.contains)) return false;
  }
  return true;
}

/// Every exercise sorted by name.
final sortedExercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final map = await ref.watch(exerciseMapProvider.future);
  return map.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// The user's gym equipment (full gym before onboarding).
final availableEquipmentProvider = Provider<List<String>>((ref) {
  final p = ref.watch(profileProvider).value;
  return p == null ? kPresets['full_gym']! : equipmentOf(p);
});

/// Ids of exercises in the active plan ("In plan" badge).
final inPlanIdsProvider = Provider<Set<String>>((ref) {
  final b = ref.watch(programBundleProvider).value;
  return {for (final p in b?.planned ?? const <PlannedExercise>[]) p.exerciseId};
});

/* ------------------------------------------------------------------ history for one lift */

class LiftSession {
  const LiftSession({required this.session, required this.sets});
  final Session session;
  final List<SetLog> sets;

  /// Best Epley e1RM of the session (null for bodyweight / timed work).
  double? get bestE1rm {
    double? best;
    for (final s in sets) {
      final v = e1rm(s.weightKg, s.reps);
      if (v != null) best = best == null ? v : math.max(best, v);
    }
    return best;
  }

  int get bestReps => sets.fold(0, (m, s) => math.max(m, s.reps ?? 0));
  int get bestSeconds => sets.fold(0, (m, s) => math.max(m, s.seconds ?? 0));
}

/// Completed sessions with working sets of an exercise, oldest first.
final liftHistoryProvider = StreamProvider.family<List<LiftSession>, String>((ref, exerciseId) {
  final s = ref.watch(storesProvider);
  return s.live({'sets', 'sessions'}, () async {
    final sets = (await s.sets.whereK2(exerciseId)).where((x) => !x.isWarmup).toList();
    if (sets.isEmpty) return const <LiftSession>[];
    final sessions = (await s.sessions.bulkGet({for (final x in sets) x.sessionId})).whereType<Session>().where((x) => x.status != 'abandoned').toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return [
      for (final ss in sessions)
        LiftSession(session: ss, sets: [for (final x in sets) if (x.sessionId == ss.id) x]..sort((a, b) => a.setIndex - b.setIndex)),
    ];
  });
});

/// Indexes of sessions whose e1RM beat every earlier one (the first one counts as the baseline, not a PR).
List<int> prIndexes(List<double> values) {
  final out = <int>[];
  var best = double.negativeInfinity;
  for (var i = 0; i < values.length; i++) {
    if (values[i] > best + 1e-9) {
      if (i > 0) out.add(i);
      best = values[i];
    }
  }
  return out;
}
