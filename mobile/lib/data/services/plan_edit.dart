// Port of src/data/plan-edit.ts: small, shared edits to the active plan
// (used by the day editor, library, Plan check and the AI coach).
import 'dart:math' as math;

import '../../domain/models.dart';
import '../db/store.dart';
import 'common.dart';

final _perSide = RegExp(r'single|one-arm|one arm|lunge|split squat|step-?up|side plank|bulgarian|suitcase|one leg', caseSensitive: false);

class PlanEdit {
  PlanEdit(this.s, {IdGen? newId}) : newId = newId ?? defaultIdGen;
  final Stores s;
  final IdGen newId;

  /// Append an exercise to a day with sensible defaults for its unit. A rest / active-recovery day
  /// becomes a strength day.
  Future<PlannedExercise> addExerciseToDay(
    String dayId,
    String exerciseId, {
    int? sets,
    int? repsMin,
    int? repsMax,
    int? restSec,
    bool? perSide,
  }) async {
    final ex = await s.exercises.get(exerciseId);
    final day = await s.programDays.get(dayId);
    final planned = await s.plannedExercises.whereK1(dayId);
    final unit = ex?.defaultUnit ?? Unit.reps;
    final pe = PlannedExercise(
      id: newId(),
      dayId: dayId,
      order: planned.isEmpty ? 0 : planned.map((p) => p.order).reduce(math.max) + 1,
      slot: '${planned.length + 1}',
      exerciseId: exerciseId,
      sets: sets ?? 3,
      repsMin: repsMin ?? (unit == Unit.reps ? 8 : unit == Unit.seconds ? 30 : unit == Unit.minutes ? 20 : 30),
      repsMax: repsMax ?? (unit == Unit.reps ? 12 : unit == Unit.seconds ? 45 : unit == Unit.minutes ? 20 : 30),
      unit: unit,
      perSide: perSide ?? _perSide.hasMatch(ex?.name ?? ''),
      restSec: restSec ?? (unit == Unit.minutes ? 0 : 75),
    );
    await s.transaction(() async {
      await s.plannedExercises.put(pe);
      if (day != null && (day.type == DayType.rest || day.type == DayType.activeRecovery)) {
        await s.programDays.put(day.copyWith(type: DayType.strength));
      }
    });
    return pe;
  }

  /// Days of the active program, in week order.
  Future<List<ProgramDay>> activeDays() async {
    final program = await s.activeProgram();
    if (program == null) return [];
    return (await s.programDays.whereK1(program.id))..sort((a, b) => a.order - b.order);
  }
}
