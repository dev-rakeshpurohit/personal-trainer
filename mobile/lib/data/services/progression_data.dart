// Port of src/features/workout/progressionData.ts: history queries feeding the progression rules.
import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/schedule.dart';
import '../db/store.dart';

/// A progression suggestion for a planned exercise (TS PlannedSuggestion).
class PlannedSuggestion {
  const PlannedSuggestion({required this.suggestion, required this.exerciseId, required this.sets, this.last});
  final Suggestion suggestion;
  final String exerciseId;
  final int sets;

  /// Working sets of the latest completed session (if any).
  final List<WorkSet>? last;

  SuggestionKind get kind => suggestion.kind;
  String get message => suggestion.message;
  double? get weightKg => suggestion.weightKg;
  List<Prefill> get prefill => suggestion.prefill;
}

class ProgressionData {
  ProgressionData(this.s);
  final Stores s;

  /// Past sessions' working sets for an exercise, latest session first (abandoned sessions skipped).
  Future<History> loadHistory(String exerciseId, {String? excludeSessionId, int limit = 3}) async {
    final sets = (await s.sets.whereK2(exerciseId)).where((x) => !x.isWarmup && x.sessionId != excludeSessionId).toList();
    if (sets.isEmpty) return [];
    final sessionIds = {for (final x in sets) x.sessionId};
    final sessions = (await s.sessions.bulkGet(sessionIds)).whereType<Session>().where((x) => x.status != 'abandoned').toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return [
      for (final ss in sessions.take(limit))
        ([for (final x in sets) if (x.sessionId == ss.id) x]..sort((a, b) => a.setIndex - b.setIndex)).map((x) => x.toWorkSet()).toList(),
    ];
  }

  /// Every working set ever logged for an exercise.
  Future<List<SetLog>> allSetsFor(String exerciseId) async => (await s.sets.whereK2(exerciseId)).where((x) => !x.isWarmup).toList();

  Future<PlannedSuggestion> suggestionFor(
    PlannedExercise pe,
    String exerciseId,
    Exercise? ex,
    Profile profile,
    Program program,
    DateTime date, {
    String? excludeSessionId,
  }) async {
    final week = cycleWeek(date, program.startedOn);
    final deload = isDeloadWeek(week, program.progression.cycle);
    final sets = effectiveSets(pe.sets, deload);
    final history = await loadHistory(exerciseId, excludeSessionId: excludeSessionId);
    final sug = suggestNext(
      planned: pe.setTarget,
      sets: sets,
      history: history,
      targetRir: targetRir(week, program.progression.cycle),
      increment: ex != null ? incrementFor(ex, profile.stepKg) : profile.stepKg.dumbbell,
      bodyweight: ex?.isBodyweight ?? false,
    );
    return PlannedSuggestion(suggestion: sug, exerciseId: exerciseId, sets: sets, last: history.isEmpty ? null : history[0]);
  }

  /// Planned exercises (main exercise) ready to go heavier on a day.
  Future<List<({String name, String message})>> goHeavierFor(
    List<PlannedExercise> planned,
    Map<String, Exercise> exMap,
    Profile profile,
    Program program,
    DateTime date,
  ) async {
    final out = <({String name, String message})>[];
    for (final pe in planned) {
      final sg = await suggestionFor(pe, pe.exerciseId, exMap[pe.exerciseId], profile, program, date);
      if (sg.kind == SuggestionKind.increase || sg.kind == SuggestionKind.timeIncrease) {
        out.add((name: exMap[pe.exerciseId]?.name ?? pe.exerciseId, message: sg.message));
      }
    }
    return out;
  }
}
