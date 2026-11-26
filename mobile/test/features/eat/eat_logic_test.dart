// Eat-tab logic: slots, extras, swaps by diet type, vrat menus and protein-hit days.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/eat/eat_logic.dart';
import 'package:repmate/features/eat/food_db.dart';

PlannedMeal _meal(String name, String time, List<String> items, double p, double k, {List<String>? rotate}) =>
    PlannedMeal(id: name, dietPlanId: 'd', order: 0, time: time, meal: name, items: items, proteinG: p, kcal: k, rotate: rotate);

MealLog _log(String day, double p, {String state = 'eaten'}) =>
    MealLog(id: '$day-$p', dayKey: day, plannedMealId: 'm', state: state, proteinG: p, kcal: 100, loggedAt: '');

void main() {
  test('slots: by meal name, then time', () {
    expect(slotOf(_meal('Pre-gym', '08:30', const [], 0, 0)), MealSlot.breakfast);
    expect(slotOf(_meal('Lunch', '12:30', const [], 0, 0)), MealSlot.lunch);
    expect(slotOf(_meal('Evening', '18:00', const [], 0, 0)), MealSlot.snacks);
    expect(slotOf(_meal('Meal 4', '21:00', const [], 0, 0)), MealSlot.dinner);
    expect(slotForTime('13:00'), MealSlot.lunch);
  });

  test('extras carry their slot in the planned-meal id', () {
    final m = extraMeal('abc', MealSlot.dinner, proteinG: 20, kcal: 400);
    expect(m.id, 'extra:dinner:abc');
    final l = MealLog(id: '1', dayKey: 'd', plannedMealId: m.id, state: 'eaten', proteinG: 20, kcal: 400, loggedAt: '');
    expect(isExtraLog(l), isTrue);
    expect(slotOfExtra(l), MealSlot.dinner);
  });

  test('swaps: rotations first, then three equal-protein options that fit the diet', () {
    final lunch = _meal('Lunch', '12:30', ['50 g dry soya chunks (curry/sabzi)', '200 g cooked thick moong dal', '100 g cooked rice'], 46, 680, rotate: ['Rajma chawal']);
    final veg = swapOptionsFor(lunch, dietType: DietType.veg);
    expect(veg.first.rotation, 'Rajma chawal');
    final eq = veg.where((o) => o.rotation == null).toList();
    expect(eq, hasLength(3));
    expect(eq.map((o) => o.dishId), isNot(contains('soya')), reason: 'not the dish being replaced (soya family)');
    expect(eq.map((o) => o.dishId), contains('paneer'));
    expect(eq.map((o) => o.dishId), contains('tofu'));
    for (final o in eq) {
      expect(o.detail, 'Instead of soya chunks (dry weight)');
      expect((o.proteinG - lunch.proteinG).abs(), lessThan(8), reason: '${o.label} ≈ same protein');
      final d = kDishes[o.dishId]!;
      expect(dishAllowed(d, DietType.veg, const []), isTrue);
    }
    final noPaneer = swapOptionsFor(lunch, dietType: DietType.veg, intolerances: const ['paneer']);
    expect(noPaneer.map((o) => o.dishId), isNot(contains('paneer')));
    final vegan = swapOptionsFor(lunch, dietType: DietType.vegan);
    for (final o in vegan.where((o) => o.dishId != null)) {
      expect(kDishes[o.dishId]!.tags.intersection({FoodTag.dairy, FoodTag.egg, FoodTag.meat, FoodTag.fish}), isEmpty);
    }
    final nonveg = swapOptionsFor(_meal('Dinner', '20:30', ['150 g paneer'], 30, 450), dietType: DietType.nonveg);
    expect(nonveg.map((o) => o.dishId), contains('chicken_breast'));
  });

  test('vrat: fasting menus only use vrat-friendly dishes; targets ease', () {
    for (final slot in MealSlot.values) {
      for (final dairy in [true, false]) {
        for (final m in vratOptions(slot, dairyOk: dairy)) {
          for (final it in m.items) {
            expect(it.dish.vrat, isTrue, reason: '${it.dish.id} in $slot');
            if (!dairy) expect(it.dish.tags, isNot(contains(FoodTag.dairy)));
          }
          expect(m.totals.kcal, greaterThan(0));
        }
      }
    }
    final t = targetsFor(protein: 150, kcal: 2000, vrat: true);
    expect(t.protein, 113);
    expect(t.kcal, 1700);
    expect(targetsFor(protein: 150, kcal: 2000).protein, 150);
  });

  test('protein-hit days count days at ≥90% of target, vrat days against the eased target', () {
    final logs = [
      _log('2026-11-30', 140), // Mon: hit (≥135)
      _log('2026-12-01', 120), // Tue: not hit
      _log('2026-12-02', 105), _log('2026-12-02', 30, state: 'skipped'), // Wed vrat: 105 ≥ 113×0.9
      _log('2026-12-04', 200), // Fri: future, not counted
    ];
    final r = proteinHitDays(today: DateTime(2026, 12, 3, 13), weekLogs: logs, proteinTarget: 150, kcalTarget: 2000, vratDays: {'2026-12-02'});
    expect(r.hit, 2);
    expect(r.days, 7);
  });

  test('go-tos prefer the current slot', () {
    final recent = [const RecentLog('poha + chai', MealSlot.breakfast), const RecentLog('2 roti dal', MealSlot.lunch), const RecentLog('poha + chai', MealSlot.lunch)];
    expect(goTosFor(recent, MealSlot.lunch), ['2 roti dal', 'poha + chai']);
  });
}
