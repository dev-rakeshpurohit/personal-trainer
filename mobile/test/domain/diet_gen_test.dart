import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/diet_gen.dart';
import 'package:repmate/domain/models.dart';

/// Same as plannedTotals in src/domain/diet.ts: non-optional meals only.
({num kcal, num proteinG}) _plannedTotals(List<GenMeal> meals) {
  num kcal = 0, protein = 0;
  for (final m in meals.where((m) => m.optional != true)) {
    kcal += m.kcal;
    protein += m.proteinG;
  }
  return (kcal: kcal, proteinG: protein);
}

({int kcal, int proteinG}) _targets({
  Sex sex = Sex.male,
  num age = 37,
  num heightCm = 178,
  num weightKg = 79,
  num goalWeightKg = 73,
  int trainingDays = 5,
  required Goal goal,
}) =>
    dietTargets(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg, goalWeightKg: goalWeightKg, goal: goal, trainingDays: trainingDays);

void main() {
  group('diet targets', () {
    test('fat loss for the reference user lands near the hand-made plan (≈2,000–2,300 kcal, ~150 g)', () {
      final t = _targets(goal: Goal.fatLoss);
      expect(t.kcal, greaterThanOrEqualTo(1950));
      expect(t.kcal, lessThanOrEqualTo(2350));
      expect(t.proteinG, greaterThanOrEqualTo(140));
      expect(t.proteinG, lessThanOrEqualTo(160));
    });
    test('muscle gain is a surplus; floors are respected', () {
      expect(_targets(goal: Goal.muscle).kcal, greaterThan(_targets(goal: Goal.general).kcal));
      final tiny = _targets(sex: Sex.female, weightKg: 45, goalWeightKg: 42, heightCm: 150, age: 60, trainingDays: 2, goal: Goal.fatLoss);
      expect(tiny.kcal, kcalFloorFor(Sex.female));
    });
  });

  const diets = [DietType.veg, DietType.vegEgg, DietType.nonveg, DietType.vegan];
  const goals = [Goal.fatLoss, Goal.lean, Goal.muscle, Goal.strength, Goal.general];
  const intol = [
    <String>[],
    ['lactose'],
    ['lactose', 'paneer'],
    ['gluten'],
    ['soy', 'nuts'],
  ];

  group('diet generator', () {
    for (final d in diets) {
      for (final g in goals) {
        for (final x in intol) {
          test('${d.wire} · ${g.wire} · [${x.join(',')}] hits targets and respects restrictions', () {
            final r = generateDiet(DietInput(
              sex: Sex.male,
              age: 37,
              heightCm: 178,
              weightKg: 79,
              goalWeightKg: 73,
              trainingDays: 5,
              goal: g,
              dietType: d,
              intolerances: x,
            ));
            final t = _plannedTotals(r.meals);
            expect((t.kcal - r.kcalTarget).abs() / r.kcalTarget, lessThan(0.12));
            expect(t.proteinG, greaterThanOrEqualTo(r.proteinTargetG * (d == DietType.vegan && x.contains('soy') ? 0.7 : 0.85)));
            final text = r.meals.expand((m) => [...m.items, ...?m.rotate]).join(' ').toLowerCase();
            Matcher hasNo(String re) => isNot(matches(RegExp(re)));
            if (d != DietType.nonveg) expect(text, hasNo(r'chicken|fish'));
            if (d == DietType.veg || d == DietType.vegan) expect(text, hasNo(r'\beggs?\b|egg white'));
            if (d == DietType.vegan) expect(text, hasNo(r'whey|toned milk|curd|yogurt|paneer'));
            if (x.contains('lactose')) expect(text, hasNo(r'toned milk|curd|yogurt|paneer'));
            if (x.contains('gluten')) expect(text, hasNo(r'oats|medium roti|toast'));
            if (x.contains('soy')) expect(text, hasNo(r'soya|tofu|soy milk|edamame'));
            if (x.contains('nuts')) expect(text, hasNo(r'almond'));
            expect(r.meals.where((m) => m.meal == 'Pre-workout').firstOrNull?.skipOnRestDay, true);
          });
        }
      }
    }
  });
}
