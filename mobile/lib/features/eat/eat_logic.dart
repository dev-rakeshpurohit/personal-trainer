// Eat-tab logic: meal slots, extra logs, vrat menus, protein-equivalent swaps, protein-hit days.
// Pure Dart over the domain models (no Flutter imports).
import 'dart:math' as math;

import '../../domain/models.dart';
import '../../domain/schedule.dart';
import 'food_db.dart';
import 'food_parser.dart';

/* ------------------------------------------------------------------ meta keys */

/// List of yyyy-MM-dd days marked as vrat (fast) days.
const kVratDaysKey = 'eat.vratDays';

/// Map dishId → MyDish json: the user's own version of a dish.
const kMyDishesKey = 'eat.myDishes';

/// The user's katori: 'S' | 'M' | 'L' (one-time calibration on the review tray).
const kKatoriKey = 'eat.katoriSize';

/// Recent free-text logs [{text, slot}], newest first (time-of-day go-tos on the log bar).
const kRecentKey = 'eat.recent';

/* ------------------------------------------------------------------ slots */

enum MealSlot {
  breakfast('breakfast', 'Breakfast'),
  lunch('lunch', 'Lunch'),
  snacks('snacks', 'Snacks'),
  dinner('dinner', 'Dinner');

  const MealSlot(this.id, this.label);
  final String id;
  final String label;
  static MealSlot parse(Object? s) => values.firstWhere((v) => v.id == s, orElse: () => snacks);
}

MealSlot slotForTime(String hhmm) {
  if (hhmm.compareTo('11:30') < 0) return MealSlot.breakfast;
  if (hhmm.compareTo('15:00') < 0) return MealSlot.lunch;
  if (hhmm.compareTo('19:30') < 0) return MealSlot.snacks;
  return MealSlot.dinner;
}

String hhmmOf(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The timeline slot a planned meal sits in (by its name first, then its time).
MealSlot slotOf(PlannedMeal m) {
  final n = m.meal.toLowerCase();
  if (n.contains('breakfast') || n.contains('pre-gym') || n.contains('pre gym') || n.contains('morning') || n.contains('nashta')) return MealSlot.breakfast;
  if (n.contains('lunch')) return MealSlot.lunch;
  if (n.contains('dinner')) return MealSlot.dinner;
  if (n.contains('snack') || n.contains('evening') || n.contains('post')) return MealSlot.snacks;
  return slotForTime(m.time);
}

/* ------------------------------------------------------------------ extra logs */

const _extraPrefix = 'extra:';

/// Food logged from the log bar that isn't a planned meal. Stored as a meal log whose
/// plannedMealId is `extra:<slot>:<id>` so it lands in the right slot and Undo works through Repo.
bool isExtraLog(MealLog l) => l.plannedMealId == null || l.plannedMealId!.startsWith(_extraPrefix);

MealSlot slotOfExtra(MealLog l) {
  final id = l.plannedMealId;
  if (id != null && id.startsWith(_extraPrefix)) return MealSlot.parse(id.split(':')[1]);
  final t = DateTime.tryParse(l.loggedAt)?.toLocal();
  return t == null ? MealSlot.snacks : slotForTime(hhmmOf(t));
}

/// The stand-in planned meal Repo.logMeal needs for an extra log.
PlannedMeal extraMeal(String id, MealSlot slot, {required double proteinG, required double kcal}) =>
    PlannedMeal(id: '$_extraPrefix${slot.id}:$id', dietPlanId: 'extra', order: 99, time: '', meal: slot.label, items: const [], proteinG: proteinG, kcal: kcal);

/* ------------------------------------------------------------------ targets */

typedef DayTargets = ({double protein, double kcal, bool vrat});

/// A vrat day eases targets: fasting food is light on protein, so ask for less.
const double kVratProteinShare = 0.75;
const double kVratKcalShare = 0.85;

DayTargets targetsFor({required num protein, required num kcal, bool vrat = false}) => vrat
    ? (protein: (protein * kVratProteinShare).roundToDouble(), kcal: (kcal * kVratKcalShare / 10).roundToDouble() * 10, vrat: true)
    : (protein: protein.toDouble(), kcal: kcal.toDouble(), vrat: false);

/// A protein-hit day: at least 90% of the day's protein target.
const double kProteinHitShare = 0.9;

bool proteinHit(double eaten, double target) => target > 0 && eaten >= target * kProteinHitShare;

double proteinOf(Iterable<MealLog> logs) => logs.fold(0.0, (a, l) => l.state == 'skipped' ? a : a + l.proteinG);

/// Protein-hit days in the week containing [today] (days after today can't count yet).
({int hit, int days}) proteinHitDays({
  required DateTime today,
  required List<MealLog> weekLogs,
  required num proteinTarget,
  required num kcalTarget,
  Set<String> vratDays = const {},
}) {
  var hit = 0;
  for (final d in weekDates(dateOnly(today))) {
    if (d.isAfter(dateOnly(today))) break;
    final k = dayKey(d);
    final t = targetsFor(protein: proteinTarget, kcal: kcalTarget, vrat: vratDays.contains(k));
    if (proteinHit(proteinOf(weekLogs.where((l) => l.dayKey == k)), t.protein)) hit++;
  }
  return (hit: hit, days: 7);
}

Set<String> decodeDays(Object? raw) => raw is List ? {for (final x in raw) '$x'} : <String>{};

PortionSize decodeKatori(Object? raw) => raw is String ? PortionSize.parse(raw) : PortionSize.m;

/* ------------------------------------------------------------------ diet filters */

/// Whether a dish fits the user's diet type and intolerances (e.g. 'lactose', 'paneer', 'soy').
bool dishAllowed(Dish d, DietType type, List<String> intolerances) {
  final t = d.tags;
  final blocked = switch (type) {
    DietType.veg => t.contains(FoodTag.egg) || t.contains(FoodTag.meat) || t.contains(FoodTag.fish),
    DietType.vegEgg => t.contains(FoodTag.meat) || t.contains(FoodTag.fish),
    DietType.nonveg => false,
    DietType.vegan => t.contains(FoodTag.dairy) || t.contains(FoodTag.egg) || t.contains(FoodTag.meat) || t.contains(FoodTag.fish) || t.contains(FoodTag.paneer),
  };
  if (blocked) return false;
  for (final i in intolerances) {
    final k = i.toLowerCase().trim();
    if (k.isNotEmpty && t.contains(k)) return false;
  }
  return true;
}

/* ------------------------------------------------------------------ swaps */

class SwapOption {
  const SwapOption({required this.label, required this.detail, required this.proteinG, required this.kcal, this.rotation, this.dishId});
  final String label;
  final String detail;
  final double proteinG;
  final double kcal;

  /// Set when the option is one of the planned meal's rotations.
  final String? rotation;
  final String? dishId;
}

/// Protein sources offered as equivalents, in the order they are suggested.
const _proteinSwaps = [
  'paneer', 'tofu', 'soya', 'egg_bhurji', 'chicken_breast', 'chole', 'hung_curd', 'rajma', 'chilla', 'egg', 'fish_curry', 'sprouts', 'whey', 'plant_protein', 'edamame', //
];

/// The meal's biggest protein item, parsed from its planned item lines.
PlateItem? mainProteinItem(PlannedMeal meal, {Map<String, MyDish> mine = const {}}) {
  PlateItem? best;
  var bestP = 0.0;
  for (final line in meal.items) {
    for (final it in parseFood(line, mine: mine).items) {
      final p = itemNutrition(it).protein;
      if (p > bestP) {
        bestP = p;
        best = it;
      }
    }
  }
  return bestP >= 5 ? best : null;
}

/// Rounds a quantity of [d] that gives [protein] g to a sensible portion.
PlateItem portionForProtein(Dish d, double protein) {
  final units = protein / math.max(0.1, d.protein);
  double qty;
  switch (d.unit) {
    case FoodUnit.gm:
      qty = math.max(50, (units * 100 / 25).round() * 25).toDouble();
    case FoodUnit.piece:
    case FoodUnit.slice:
      qty = math.max(1, units.round()).toDouble();
    default:
      qty = math.max(0.5, (units * 2).round() / 2);
  }
  return PlateItem(dish: d, qty: qty, unit: d.unit);
}

/// Swap options for a planned meal: its rotations first, then three equivalent-protein swaps
/// that fit the diet type (paneer ↔ tofu ↔ soya chunks …).
List<SwapOption> swapOptionsFor(PlannedMeal meal, {required DietType dietType, List<String> intolerances = const [], Map<String, MyDish> mine = const {}}) {
  final out = <SwapOption>[
    for (final r in meal.rotate ?? const <String>[]) SwapOption(label: r, detail: 'Plan rotation · same macros', proteinG: meal.proteinG, kcal: meal.kcal, rotation: r),
  ];
  final main = mainProteinItem(meal, mine: mine);
  final mainN = main == null ? null : itemNutrition(main);
  final target = mainN?.protein ?? meal.proteinG;
  if (target < 5) return out;
  final seenFamilies = <String>{if (main?.dish.family != null) main!.dish.family!};
  var added = 0;
  final order = <String>{
    ...switch (dietType) {
      DietType.nonveg => const ['chicken_breast', 'paneer', 'egg_bhurji', 'fish_curry'],
      DietType.vegEgg => const ['paneer', 'egg_bhurji', 'tofu'],
      _ => const <String>[],
    },
    ..._proteinSwaps,
  };
  for (final id in order) {
    if (added >= 3) break;
    final d = kDishes[id]!;
    if (main != null && d.id == main.dish.id) continue;
    if (d.family != null && seenFamilies.contains(d.family)) continue;
    if (!dishAllowed(d, dietType, intolerances)) continue;
    final alt = portionForProtein(d, target);
    final n = itemNutrition(alt);
    final p = mainN == null ? n.protein : meal.proteinG - mainN.protein + n.protein;
    final k = mainN == null ? meal.kcal : meal.kcal - mainN.kcal + n.kcal;
    out.add(SwapOption(
      label: '${d.name} ${qtyLabel(alt)}',
      detail: main == null ? 'Same protein as planned' : 'Instead of ${main.dish.name.toLowerCase()}',
      proteinG: math.max(0, p).roundToDouble(),
      kcal: math.max(0, k).roundToDouble(),
      dishId: d.id,
    ));
    if (d.family != null) seenFamilies.add(d.family!);
    added++;
  }
  return out;
}

/* ------------------------------------------------------------------ vrat */

class VratMeal {
  const VratMeal(this.items);
  final List<PlateItem> items;
  String get label => plateLabel(items);
  Nutrition get totals => plateTotals(items);
}

PlateItem _p(String id, double qty, [FoodUnit? unit]) {
  final d = kDishes[id]!;
  return PlateItem(dish: d, qty: qty, unit: unit ?? d.unit);
}

/// Fasting-friendly meals for a slot (sabudana, kuttu, singhara, samak, fruit, dairy).
List<VratMeal> vratOptions(MealSlot slot, {bool dairyOk = true}) => switch (slot) {
      MealSlot.breakfast => [
          VratMeal([_p('sabudana', 1), dairyOk ? _p('milk', 1) : _p('peanuts', 1)]),
          VratMeal([_p('fruit', 2), dairyOk ? _p('hung_curd', 1) : _p('almonds', 8)]),
        ],
      MealSlot.lunch => [
          VratMeal([_p('kuttu_roti', 2), _p('aloo_sabzi', 1), dairyOk ? _p('curd', 1) : _p('peanuts', 1)]),
          VratMeal([_p('singhara_roti', 2), _p('aloo_sabzi', 1), dairyOk ? _p('paneer', 100) : _p('salad', 1)]),
        ],
      MealSlot.snacks => [
          VratMeal([_p('makhana', 1), dairyOk ? _p('chaas', 1) : _p('almonds', 6)]),
          VratMeal([_p('fruit', 1), dairyOk ? _p('lassi', 1) : _p('peanuts', 1)]),
        ],
      MealSlot.dinner => [
          VratMeal([_p('samak_rice', 1), dairyOk ? _p('paneer', 100) : _p('shakarkandi', 1), _p('salad', 1)]),
          VratMeal([_p('shakarkandi', 1), dairyOk ? _p('curd', 1) : _p('peanuts', 1), _p('fruit', 1)]),
        ],
    };

bool dairyOkFor(DietType type, List<String> intolerances) =>
    type != DietType.vegan && !intolerances.any((i) => i.toLowerCase() == 'lactose' || i.toLowerCase() == 'dairy');

/* ------------------------------------------------------------------ recent go-tos */

class RecentLog {
  const RecentLog(this.text, this.slot);
  final String text;
  final MealSlot slot;
  Map<String, Object?> toJson() => {'text': text, 'slot': slot.id};

  static List<RecentLog> decodeAll(Object? raw) => raw is List
      ? [
          for (final x in raw)
            if (x is Map && x['text'] is String) RecentLog(x['text'] as String, MealSlot.parse(x['slot'])),
        ]
      : const [];
}

/// Up to [n] go-to suggestions for a slot: that slot's recent logs first, then any other.
List<String> goTosFor(List<RecentLog> recent, MealSlot slot, {int n = 3}) {
  final out = <String>[];
  for (final r in [...recent.where((r) => r.slot == slot), ...recent.where((r) => r.slot != slot)]) {
    if (out.length >= n) break;
    if (!out.contains(r.text)) out.add(r.text);
  }
  return out;
}
