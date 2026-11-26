// Pure diff / impact / adjust logic behind the proposal card.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/ai_plan.dart';
import 'package:repmate/domain/balance.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/coach/coach_models.dart';
import 'package:repmate/features/coach/coach_safety.dart';
import 'package:repmate/features/coach/proposal_diff.dart';

const _ex = {
  'squat': Exercise(id: 'squat', name: 'Barbell squat', primaryMuscles: ['quadriceps'], pattern: 'squat'),
  'goblet': Exercise(id: 'goblet', name: 'DB goblet squat', primaryMuscles: ['quadriceps'], pattern: 'squat'),
  'rdl': Exercise(id: 'rdl', name: 'Romanian deadlift', primaryMuscles: ['hamstrings'], pattern: 'hinge'),
  'bench': Exercise(id: 'bench', name: 'Bench press', primaryMuscles: ['chest'], pattern: 'horizontal push'),
  'row': Exercise(id: 'row', name: 'Cable row', primaryMuscles: ['middle back'], pattern: 'horizontal pull'),
  'curl': Exercise(id: 'curl', name: 'Biceps curl', primaryMuscles: ['biceps'], pattern: 'elbow flexion'),
};

NormExercise ex(String id, int sets, int lo, [int? hi]) =>
    NormExercise(slot: 'A', exerciseId: id, sets: sets, repsMin: lo, repsMax: hi ?? lo, unit: Unit.reps, perSide: false, restSec: 90);

NormDay day(Weekday w, String title, List<NormExercise> list) =>
    NormDay(weekday: w, type: list.isEmpty ? DayType.rest : DayType.strength, title: list.isEmpty ? 'Rest' : title, exercises: list);

NormWorkout week(Map<Weekday, NormDay> days) =>
    NormWorkout(name: 'W', days: [for (final w in Weekday.values) days[w] ?? day(w, 'Rest', const [])]);

void main() {
  final before = week({
    Weekday.wed: day(Weekday.wed, 'Upper', [ex('bench', 3, 8, 12), ex('row', 3, 8, 12)]),
    Weekday.sat: day(Weekday.sat, 'Legs', [ex('squat', 4, 6), ex('rdl', 3, 8)]),
  });

  test('moved day, swap, changed dose and added exercise', () {
    final after = week({
      Weekday.wed: day(Weekday.wed, 'Legs', [ex('goblet', 4, 10), ex('rdl', 3, 8)]),
      Weekday.sat: day(Weekday.sat, 'Upper', [ex('bench', 4, 6), ex('row', 3, 8, 12), ex('curl', 2, 12)]),
    });
    final d = diffWorkouts(before, after, _ex);
    final legs = d.days.firstWhere((x) => x.title == 'Legs');
    expect(legs.weekday, Weekday.wed);
    expect(legs.movedFrom, Weekday.sat);
    expect(legs.lines.single.kind, DiffKind.replaced);
    expect(legs.lines.single.from!.exerciseId, 'squat');
    expect(doseOf(legs.lines.single.from!), '4×6');
    expect(doseOf(legs.lines.single.to!), '4×10');
    final upper = d.days.firstWhere((x) => x.title == 'Upper');
    expect(upper.movedFrom, Weekday.wed);
    expect(upper.lines.map((l) => l.kind), [DiffKind.changed, DiffKind.added]);
    expect(upper.unchanged, 1);
  });

  test('impact: weekly sets before → after, gaps and session time', () {
    final after = week({
      Weekday.wed: day(Weekday.wed, 'Upper', [ex('bench', 3, 8, 12), ex('row', 3, 8, 12)]),
      Weekday.sat: day(Weekday.sat, 'Legs', [ex('goblet', 3, 10), ex('rdl', 3, 8)]),
    });
    final i = impactOf(before, after, _ex, Goal.lean);
    final quads = i.groups.firstWhere((g) => g.group == MuscleGroup.quads);
    expect(quads.before, 4);
    expect(quads.after, 3);
    expect(i.highlights.first.group, MuscleGroup.quads);
    expect(i.gapsAfter, contains(MuscleGroup.quads));
    expect(i.minutesAfter, isNotNull);
    expect(i.minutesAfter! <= i.minutesBefore!, isTrue);
  });

  test('adjust: edit dose and revert lines', () {
    final after = week({
      Weekday.wed: day(Weekday.wed, 'Upper', [ex('bench', 4, 6), ex('row', 3, 8, 12), ex('curl', 2, 12)]),
      Weekday.sat: day(Weekday.sat, 'Legs', [ex('goblet', 4, 10)]),
    });
    var plan = NormPlan(summary: 's', workout: after, warnings: const []);
    plan = setDose(plan, Weekday.wed, 'bench', sets: 5, repsMin: 5, repsMax: 5);
    expect(plan.workout!.days[Weekday.wed.index].exercises.first.sets, 5);

    var d = diffWorkouts(before, plan.workout, _ex);
    final upper = d.days.firstWhere((x) => x.weekday == Weekday.wed);
    final added = upper.lines.firstWhere((l) => l.kind == DiffKind.added);
    plan = revertLine(plan, added, before);
    expect(plan.workout!.days[Weekday.wed.index].exercises.map((e) => e.exerciseId), ['bench', 'row']);
    expect(plan.workout!.days[Weekday.wed.index].exercises.map((e) => e.slot), ['A', 'B']);

    d = diffWorkouts(before, plan.workout, _ex);
    final legs = d.days.firstWhere((x) => x.weekday == Weekday.sat);
    final removed = legs.lines.firstWhere((l) => l.kind == DiffKind.removed);
    plan = revertLine(plan, removed, before);
    final replaced = diffWorkouts(before, plan.workout, _ex).days.firstWhere((x) => x.weekday == Weekday.sat).lines.single;
    expect(replaced.kind, DiffKind.replaced);
    plan = revertLine(plan, replaced, before);
    final changed = diffWorkouts(before, plan.workout, _ex).days.firstWhere((x) => x.weekday == Weekday.wed).lines.single;
    plan = revertLine(plan, changed, before);
    expect(diffWorkouts(before, plan.workout, _ex).isEmpty, isTrue);
  });

  test('diet diff: targets and meals', () {
    const b = AiDiet(kcalTarget: 2000, proteinTargetG: 110, meals: [
      AiMeal(time: '8:00', meal: 'Breakfast', items: ['Poha'], kcal: 400, proteinG: 12),
      AiMeal(time: '13:00', meal: 'Lunch', items: ['Dal', 'Roti'], kcal: 600, proteinG: 25),
    ]);
    const a = AiDiet(kcalTarget: 1800, proteinTargetG: 110, meals: [
      AiMeal(time: '8:00', meal: 'Breakfast', items: ['Sabudana khichdi'], kcal: 450, proteinG: 10),
      AiMeal(time: '13:00', meal: 'Lunch', items: ['Dal', 'Roti'], kcal: 600, proteinG: 25),
      AiMeal(time: '17:00', meal: 'Snack', items: ['Fruit', 'Curd'], kcal: 200, proteinG: 8),
    ]);
    final d = diffDiets(b, a)!;
    expect(d.kcalBefore, 2000);
    expect(d.kcalAfter, 1800);
    expect(d.meals.map((m) => m.kind), [MealChange.changed, MealChange.added]);
    expect(d.unchangedMeals, 1);
  });

  test('NormPlan JSON round trip and safety routing', () {
    final p = NormPlan(summary: 'x', workout: before, warnings: const ['w']);
    final back = normPlanFromJson(p.toJson());
    expect(back.toJson(), p.toJson());
    expect(CoachSafety.of('my knee hurts').pain, isTrue);
    expect(CoachSafety.of('ghutne mein dard hai').pain, isTrue);
    expect(CoachSafety.of('I have PCOS').medical, isTrue);
    expect(CoachSafety.of('on Ozempic now').medical, isTrue);
    expect(CoachSafety.of('make it harder').any, isFalse);
  });
}
