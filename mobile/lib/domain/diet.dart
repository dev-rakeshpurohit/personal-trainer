// Port of src/domain/diet.ts. Pure Dart.
import 'models.dart';

/// JS Math.round: halves round towards +∞.
int _jsRound(double x) {
  final r = x.roundToDouble();
  return (x - r == 0.5 ? r + 1 : r).toInt();
}

typedef Totals = ({double proteinG, double kcal});

/// Meals shown on a day: rest days hide meals flagged `skipOnRestDay`.
List<PlannedMeal> mealsForDay(List<PlannedMeal> meals, bool restDay) =>
    restDay ? meals.where((m) => m.skipOnRestDay != true).toList() : meals;

/// Planned totals for non-optional meals.
Totals plannedTotals(Iterable<PlannedMeal> meals) =>
    plannedTotalsBy(meals, proteinG: (m) => m.proteinG, kcal: (m) => m.kcal, optional: (m) => m.optional == true);

/// Generic [plannedTotals] for other meal shapes (e.g. generated meals), via accessors.
Totals plannedTotalsBy<T>(
  Iterable<T> meals, {
  required num Function(T m) proteinG,
  required num Function(T m) kcal,
  bool Function(T m)? optional,
}) {
  var p = 0.0;
  var k = 0.0;
  for (final m in meals) {
    if (optional != null && optional(m)) continue;
    p += proteinG(m);
    k += kcal(m);
  }
  return (proteinG: p, kcal: k);
}

/// Day totals from logs: eaten/swapped count their logged values, skipped = 0.
Totals dayTotals(Iterable<MealLog> logs) {
  var p = 0.0;
  var k = 0.0;
  for (final l in logs) {
    if (l.state == 'skipped') continue;
    p += l.proteinG;
    k += l.kcal;
  }
  return (proteinG: p, kcal: k);
}

/// One day's planned meals and its logs, for [adherencePct].
typedef AdherenceDay = ({List<PlannedMeal> meals, List<MealLog> logs});

/// Adherence = eaten-or-swapped non-optional meals / planned non-optional meals (0–100), rounded.
/// Null when nothing was planned.
int? adherencePct(Iterable<AdherenceDay> days) {
  var planned = 0;
  var hit = 0;
  for (final d in days) {
    final req = d.meals.where((m) => m.optional != true);
    for (final m in req) {
      planned++;
      MealLog? l;
      for (final x in d.logs) {
        if (x.plannedMealId == m.id) {
          l = x;
          break;
        }
      }
      if (l != null && l.state != 'skipped') hit++;
    }
  }
  return planned > 0 ? _jsRound(hit / planned * 100) : null;
}

/// The next meal to show on Today: first unlogged non-optional meal at/after [nowHHmm], else first unlogged.
PlannedMeal? nextMeal(List<PlannedMeal> meals, Set<String> loggedIds, String nowHHmm) {
  final open = meals.where((m) => !loggedIds.contains(m.id) && m.optional != true).toList();
  for (final m in open) {
    if (m.time.compareTo(nowHHmm) >= 0) return m;
  }
  return open.isEmpty ? null : open.first;
}

/// Suggested targets (Mifflin-St Jeor, moderate activity, ~20% deficit) for users without a template.
({int kcal, int proteinG}) suggestTargets({
  required Sex sex,
  required num age,
  required num heightCm,
  required num weightKg,
  required num goalWeightKg,
}) {
  final s = sex == Sex.male ? 5 : sex == Sex.female ? -161 : -78;
  final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + s;
  final tdee = bmr * 1.55;
  final floor = kcalFloor(sex);
  final rounded = _jsRound(tdee * 0.8 / 50) * 50;
  final kcal = rounded > floor ? rounded : floor;
  final lower = goalWeightKg > weightKg * 0.85 ? goalWeightKg : weightKg * 0.85;
  final basis = weightKg < lower ? weightKg : lower;
  final proteinG = _jsRound(2 * basis / 5) * 5;
  return (kcal: kcal, proteinG: proteinG);
}

/// Minimum daily kcal suggested for a sex.
int kcalFloor(Sex sex) => sex == Sex.female ? 1400 : 1700;

/// A concrete edit to one planned meal.
class MealChange {
  const MealChange({required this.mealId, required this.items, required this.kcal, required this.proteinG, required this.description});
  final String mealId;
  final List<String> items;
  final double kcal;
  final double proteinG;
  final String description;

  @override
  String toString() => 'MealChange($mealId, $description)';
}

/// The diet-coach card kinds that map to a meal edit (TS: 'stalled' | 'eat_more').
enum MealChangeKind { stalled, eatMore }

final _cookedRice = RegExp('cooked rice', caseSensitive: false);
final _rice50 = RegExp(r'\b50 g\b');
final _breakfast = RegExp('breakfast', caseSensitive: false);
final _toast = RegExp('multigrain toast', caseSensitive: false);

/// Turn a diet-coach card into a concrete meal edit (doc 06 §6). Pure.
MealChange? dietChangeFor(MealChangeKind kind, List<PlannedMeal> meals) {
  PlannedMeal? riceMeal;
  for (final m in meals) {
    if (m.items.any(_cookedRice.hasMatch)) {
      riceMeal = m;
      break;
    }
  }
  String? riceItem;
  if (riceMeal != null) {
    for (final i in riceMeal.items) {
      if (_cookedRice.hasMatch(i)) {
        riceItem = i;
        break;
      }
    }
  }
  final reduced = riceItem != null && _rice50.hasMatch(riceItem);
  if (kind == MealChangeKind.stalled) {
    if (riceMeal == null || riceItem == null || reduced) return null;
    return MealChange(
      mealId: riceMeal.id,
      items: [for (final i in riceMeal.items) i == riceItem ? i.replaceFirst(RegExp(r'\d+\s*g'), '50 g') : i],
      kcal: riceMeal.kcal - 65,
      proteinG: riceMeal.proteinG - 1,
      description: '${riceMeal.meal}: rice → 50 g (−65 kcal)',
    );
  }
  if (riceMeal != null && riceItem != null && reduced) {
    return MealChange(
      mealId: riceMeal.id,
      items: [for (final i in riceMeal.items) i == riceItem ? i.replaceFirst(RegExp(r'50\s*g'), '100 g') : i],
      kcal: riceMeal.kcal + 65,
      proteinG: riceMeal.proteinG + 1,
      description: '${riceMeal.meal}: rice back to 100 g (+65 kcal)',
    );
  }
  PlannedMeal? breakfast;
  for (final m in meals) {
    if (_breakfast.hasMatch(m.meal)) {
      breakfast = m;
      break;
    }
  }
  breakfast ??= meals.isEmpty ? null : meals.first;
  if (breakfast == null || breakfast.items.any(_toast.hasMatch)) return null;
  return MealChange(
    mealId: breakfast.id,
    items: [...breakfast.items, '1 slice multigrain toast'],
    kcal: breakfast.kcal + 70,
    proteinG: breakfast.proteinG + 3,
    description: '${breakfast.meal}: +1 slice multigrain toast (+70 kcal)',
  );
}

/// True when some meal's cooked-rice item is already at 50 g.
bool riceReduced(Iterable<PlannedMeal> meals) =>
    meals.any((m) => m.items.any((i) => _cookedRice.hasMatch(i) && _rice50.hasMatch(i)));
