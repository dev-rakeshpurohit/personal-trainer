import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/coach.dart';
import 'package:repmate/domain/diet.dart';
import 'package:repmate/domain/models.dart';

/// The seed lives at the repo root; `flutter test` runs from mobile/.
List<PlannedMeal> loadSeedMeals() {
  final seed = jsonDecode(File('../seed/diet.lean-veg-egg-2000.json').readAsStringSync()) as Map<String, Object?>;
  final day = (seed['trainingDay'] as List).cast<Map<String, Object?>>();
  return [
    for (var i = 0; i < day.length; i++)
      PlannedMeal.fromJson({...day[i], 'id': 'm$i', 'dietPlanId': 'seed', 'order': i, 'optional': day[i]['optional'] ?? false}),
  ];
}

PlannedMeal meal(String id, {bool? optional}) =>
    PlannedMeal(id: id, dietPlanId: 'd', order: 0, time: '12:00', meal: id, items: const [], proteinG: 0, kcal: 0, optional: optional);

MealLog log(String state, {String? plannedMealId, double proteinG = 0, double kcal = 0}) => MealLog(
    id: 'l', dayKey: '2026-12-20', plannedMealId: plannedMealId, state: state, proteinG: proteinG, kcal: kcal, loggedAt: '');

PlannedMeal withChange(PlannedMeal m, MealChange c) => PlannedMeal(
      id: m.id,
      dietPlanId: m.dietPlanId,
      order: m.order,
      time: m.time,
      meal: m.meal,
      items: c.items,
      rotate: m.rotate,
      proteinG: m.proteinG,
      kcal: c.kcal,
      optional: m.optional,
      skipOnRestDay: m.skipOnRestDay,
    );

void main() {
  final meals = loadSeedMeals();

  group('diet totals', () {
    test('training day ≈ 150 g protein / ≈ 2,000 kcal', () {
      final t = plannedTotals(mealsForDay(meals, false));
      expect(t.proteinG, greaterThanOrEqualTo(145));
      expect(t.proteinG, lessThanOrEqualTo(160));
      expect((t.kcal - 2000).abs(), lessThanOrEqualTo(50));
    });

    test('rest day hides pre-gym snack (≈ 1,950 kcal)', () {
      final rest = mealsForDay(meals, true);
      expect(rest.where((m) => m.meal == 'Pre-gym'), isEmpty);
      expect((plannedTotals(rest).kcal - 1950).abs(), lessThanOrEqualTo(50));
    });

    test('skipped meals count zero', () {
      expect(dayTotals([log('eaten', proteinG: 10, kcal: 100), log('skipped', proteinG: 50, kcal: 500)]), (proteinG: 10.0, kcal: 100.0));
    });

    test('adherence ignores optional meals', () {
      final ms = [meal('a'), meal('b'), meal('c', optional: true)];
      expect(
        adherencePct([
          (meals: ms, logs: [log('eaten', plannedMealId: 'a'), log('skipped', plannedMealId: 'b')]),
        ]),
        50,
      );
      expect(adherencePct(const []), isNull);
    });

    test('next meal is the first unlogged one from now', () {
      expect(nextMeal(meals, {'m0'}, '07:00')?.meal, 'Breakfast');
      expect(nextMeal(meals, {}, '13:00')?.meal, 'Snack');
      expect(nextMeal(meals, {}, '23:00')?.meal, 'Pre-gym');
    });

    test('suggests targets with a kcal floor', () {
      final t = suggestTargets(sex: Sex.male, age: 37, heightCm: 178, weightKg: 79, goalWeightKg: 73);
      expect(t.kcal, greaterThanOrEqualTo(1700));
      expect(t.proteinG, greaterThan(120));
    });

    // Extra Dart-side checks (values computed with the TS implementation).
    test('suggested targets: exact numbers and floors', () {
      expect(suggestTargets(sex: Sex.male, age: 37, heightCm: 178, weightKg: 79, goalWeightKg: 73), (kcal: 2150, proteinG: 145));
      expect(suggestTargets(sex: Sex.female, age: 60, heightCm: 150, weightKg: 45, goalWeightKg: 44), (kcal: 1400, proteinG: 90));
      expect(kcalFloor(Sex.other), 1700);
    });

    test('plannedTotalsBy works on other meal shapes', () {
      final t = plannedTotalsBy<({int p, int k, bool opt})>(
        [(p: 10, k: 100, opt: false), (p: 5, k: 50, opt: true)],
        proteinG: (m) => m.p,
        kcal: (m) => m.k,
        optional: (m) => m.opt,
      );
      expect(t, (proteinG: 10.0, kcal: 100.0));
    });
  });

  group('diet adjustment coach', () {
    DietCard? adj({int daysOfData = 21, required List<double> checks, int? adherence, int liftsDown = 0, num kcalTarget = 2000}) =>
        dietAdjustment(
          daysOfData: daysOfData,
          checks: checks,
          adherence: adherence,
          liftsDown: liftsDown,
          sex: Sex.male,
          kcalTarget: kcalTarget,
          riceReduced: false,
        );

    test('needs 14 days', () => expect(adj(daysOfData: 10, checks: [0.6]), isNull));
    test('on track', () => expect(adj(checks: [0.6, 0.6], adherence: 90)?.kind, DietCardKind.onTrack));
    test('stalled 2 checks with good adherence', () {
      final c = adj(checks: [0.2, 0.1], adherence: 85)!;
      expect(c.kind, DietCardKind.stalled);
      expect(c.kcalDelta, -65);
    });
    test('stalled with poor adherence → adherence first',
        () => expect(adj(checks: [0.2, 0.1], adherence: 60)?.kind, DietCardKind.adherence));
    test('losing too fast → eat more', () => expect(adj(checks: [1.2], adherence: 90)?.kind, DietCardKind.eatMore));
    test('lifts down → eat more', () => expect(adj(checks: [0.6], adherence: 90, liftsDown: 2)?.kind, DietCardKind.eatMore));
    test('warns below the kcal floor',
        () => expect(adj(kcalTarget: 1750, checks: [0.1, 0.1], adherence: 90)?.floorWarning, isTrue));
  });

  group('diet changes', () {
    test('stalled → lunch rice 100 g → 50 g, then eat_more puts it back', () {
      final c = dietChangeFor(MealChangeKind.stalled, meals)!;
      expect(c.description, contains('Lunch: rice → 50 g'));
      expect(c.kcal, 680 - 65);
      final after = [for (final m in meals) m.id == c.mealId ? withChange(m, c) : m];
      expect(riceReduced(after), isTrue);
      expect(dietChangeFor(MealChangeKind.stalled, after), isNull);
      final back = dietChangeFor(MealChangeKind.eatMore, after)!;
      expect(back.items.any((i) => i.contains('100 g cooked rice')), isTrue);
    });

    test('eat_more without reduced rice adds toast at breakfast', () {
      final c = dietChangeFor(MealChangeKind.eatMore, meals)!;
      expect(c.description, contains('Breakfast: +1 slice multigrain toast'));
      expect(c.kcal, 390 + 70);
    });

    // Extra Dart-side checks.
    test('no breakfast meal and no rice: toast goes on the first meal; none if toast already there', () {
      final m = PlannedMeal(id: 'x', dietPlanId: 'd', order: 0, time: '09:00', meal: 'Brunch', items: const ['Eggs'], proteinG: 20, kcal: 300);
      final c = dietChangeFor(MealChangeKind.eatMore, [m])!;
      expect(c.mealId, 'x');
      expect(c.items, ['Eggs', '1 slice multigrain toast']);
      expect(c.proteinG, 23);
      expect(dietChangeFor(MealChangeKind.eatMore, [withChange(m, c)]), isNull);
      expect(dietChangeFor(MealChangeKind.stalled, [m]), isNull);
      expect(dietChangeFor(MealChangeKind.eatMore, const []), isNull);
    });
  });
}
