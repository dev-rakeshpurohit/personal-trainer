// Port of src/domain/dietGen.ts. Pure Dart: no Flutter imports.
//
// Diet generator. Targets from Mifflin–St Jeor × activity × goal; protein by g/kg.
// Meals are built from an Indian-friendly food list filtered by diet type and intolerances,
// then portions are scaled so the day hits the protein and calorie targets.
// Values are typical label/IFCT approximations; good enough for planning, not medical nutrition.
import 'models.dart';

/// Food restriction tags (wire values match the TS `Tag` union).
enum DietTag { lactose, paneer, egg, meat, fish, soy, gluten, nuts, dairy }

enum _Role { protein, carb, fixed }

class _Food {
  const _Food({
    required this.id,
    required this.label,
    required this.kcal,
    required this.protein,
    required this.qty,
    required this.step,
    required this.min,
    required this.max,
    required this.role,
    this.tags = const [],
  });
  final String id;
  final String Function(num q) label;
  final double kcal; // per unit
  final double protein; // per unit
  final double qty; // default quantity
  final double step; // rounding step
  final double min;
  final double max;
  final _Role role;
  final List<DietTag> tags;
}

/// JS `Math.round`: halves round toward +∞.
double _jsRound(double x) {
  final f = x.floorToDouble();
  return x - f >= 0.5 ? f + 1 : f;
}

/// JS number → string for whole and simple fractional quantities (60 → "60", 1.5 → "1.5").
String _n(num v) {
  final d = v.toDouble();
  if (d.isFinite && d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

String _scoops(num q) => q == 0.5 ? '½ scoop' : q == 1 ? '1 scoop' : q == 1.5 ? '1½ scoops' : '${_n(q)} scoops';

final Map<String, _Food> _foods = {
  for (final f in <_Food>[
    _Food(id: 'whey', label: (q) => '${_scoops(q)} whey isolate in water', kcal: 115, protein: 26, qty: 1, step: 0.5, min: 0.5, max: 2, role: _Role.protein, tags: [DietTag.dairy]),
    _Food(id: 'pea', label: (q) => '${_scoops(q)} pea/plant protein in water', kcal: 120, protein: 24, qty: 1, step: 0.5, min: 0.5, max: 2, role: _Role.protein),
    _Food(id: 'eggs', label: (q) => '${_n(q)} whole eggs', kcal: 70, protein: 6, qty: 2, step: 1, min: 1, max: 3, role: _Role.fixed, tags: [DietTag.egg]),
    _Food(id: 'whites', label: (q) => '${_n(q)} egg white${q == 1 ? '' : 's'}', kcal: 17, protein: 3.6, qty: 4, step: 1, min: 0, max: 8, role: _Role.protein, tags: [DietTag.egg]),
    _Food(id: 'besan', label: (q) => 'Besan chilla (${_n(q)} g besan) with veggies', kcal: 3.9, protein: 0.22, qty: 60, step: 10, min: 40, max: 100, role: _Role.protein),
    _Food(id: 'tofuB', label: (q) => 'Tofu bhurji (${_n(q)} g firm tofu)', kcal: 1.45, protein: 0.15, qty: 150, step: 25, min: 100, max: 250, role: _Role.protein, tags: [DietTag.soy]),
    _Food(id: 'oats', label: (q) => '${_n(q)} g oats (cooked in water)', kcal: 3.8, protein: 0.13, qty: 40, step: 10, min: 20, max: 80, role: _Role.carb, tags: [DietTag.gluten]),
    _Food(id: 'poha', label: (q) => '${_n(q)} g poha with peas', kcal: 3.6, protein: 0.07, qty: 50, step: 10, min: 30, max: 90, role: _Role.carb),
    _Food(id: 'toast', label: (q) => '${_n(q)} slice${q > 1 ? 's' : ''} multigrain toast', kcal: 70, protein: 3, qty: 1, step: 1, min: 0, max: 3, role: _Role.carb, tags: [DietTag.gluten]),
    _Food(id: 'soya', label: (q) => '${_n(q)} g dry soya chunks (curry)', kcal: 3.45, protein: 0.52, qty: 50, step: 10, min: 30, max: 80, role: _Role.protein, tags: [DietTag.soy]),
    _Food(id: 'chicken', label: (q) => '${_n(q)} g chicken breast (cooked)', kcal: 1.65, protein: 0.31, qty: 150, step: 25, min: 100, max: 250, role: _Role.protein, tags: [DietTag.meat]),
    _Food(id: 'fish', label: (q) => '${_n(q)} g fish (grilled / curry)', kcal: 1.2, protein: 0.21, qty: 150, step: 25, min: 100, max: 250, role: _Role.protein, tags: [DietTag.fish]),
    _Food(id: 'tofu', label: (q) => '${_n(q)} g tofu (sabzi / tikka)', kcal: 1.45, protein: 0.15, qty: 150, step: 25, min: 100, max: 250, role: _Role.protein, tags: [DietTag.soy]),
    _Food(id: 'paneer', label: (q) => '${_n(q)} g paneer', kcal: 2.65, protein: 0.18, qty: 80, step: 10, min: 50, max: 120, role: _Role.protein, tags: [DietTag.paneer, DietTag.lactose, DietTag.dairy]),
    _Food(id: 'dal', label: (q) => '${_n(q)} g cooked thick dal', kcal: 1.05, protein: 0.07, qty: 200, step: 50, min: 150, max: 300, role: _Role.fixed),
    _Food(id: 'chana', label: (q) => '${_n(q)} g cooked chana / rajma', kcal: 1.3, protein: 0.08, qty: 150, step: 25, min: 100, max: 250, role: _Role.protein),
    _Food(id: 'rice', label: (q) => '${_n(q)} g cooked rice', kcal: 1.3, protein: 0.027, qty: 100, step: 25, min: 50, max: 250, role: _Role.carb),
    _Food(id: 'roti', label: (q) => '${_n(q)} medium roti${q > 1 ? 's' : ''}', kcal: 120, protein: 4, qty: 2, step: 1, min: 1, max: 4, role: _Role.carb, tags: [DietTag.gluten]),
    _Food(id: 'jowar', label: (q) => '${_n(q)} jowar/bajra roti${q > 1 ? 's' : ''}', kcal: 110, protein: 3.5, qty: 2, step: 1, min: 1, max: 4, role: _Role.carb),
    _Food(id: 'sabzi', label: (_) => '1 bowl non-starchy sabzi (1 tsp oil)', kcal: 90, protein: 3, qty: 1, step: 1, min: 1, max: 1, role: _Role.fixed),
    _Food(id: 'salad', label: (_) => 'Salad', kcal: 30, protein: 1, qty: 1, step: 1, min: 1, max: 1, role: _Role.fixed),
    _Food(id: 'soymilk', label: (q) => '${_n(q)} ml unsweetened soy milk', kcal: 0.33, protein: 0.033, qty: 250, step: 50, min: 200, max: 400, role: _Role.fixed, tags: [DietTag.soy]),
    _Food(id: 'milk', label: (q) => '${_n(q)} ml toned milk', kcal: 0.58, protein: 0.032, qty: 250, step: 50, min: 200, max: 400, role: _Role.fixed, tags: [DietTag.lactose, DietTag.dairy]),
    _Food(id: 'curd', label: (q) => '${_n(q)} g hung curd / Greek yogurt', kcal: 0.97, protein: 0.09, qty: 150, step: 25, min: 100, max: 250, role: _Role.protein, tags: [DietTag.lactose, DietTag.dairy]),
    _Food(id: 'chanaRoast', label: (q) => '${_n(q)} g roasted chana', kcal: 3.6, protein: 0.2, qty: 30, step: 10, min: 20, max: 60, role: _Role.fixed),
    _Food(id: 'fruit', label: (_) => '1 fruit (guava / apple / orange / papaya)', kcal: 80, protein: 1, qty: 1, step: 1, min: 1, max: 2, role: _Role.fixed),
    _Food(id: 'almonds', label: (q) => '${_n(q)} almonds', kcal: 7, protein: 0.26, qty: 6, step: 2, min: 4, max: 12, role: _Role.fixed, tags: [DietTag.nuts]),
    _Food(id: 'dates', label: (q) => '${_n(q)} dates', kcal: 23, protein: 0.2, qty: 2, step: 1, min: 1, max: 3, role: _Role.fixed),
    _Food(id: 'banana', label: (q) => '${_n(q)} banana${q > 1 ? 's' : ''}', kcal: 105, protein: 1.3, qty: 1, step: 1, min: 1, max: 2, role: _Role.fixed),
    _Food(id: 'pb', label: (q) => '${_n(q)} tbsp peanut butter', kcal: 95, protein: 4, qty: 1, step: 1, min: 1, max: 3, role: _Role.fixed, tags: [DietTag.nuts]),
    _Food(id: 'ghee', label: (q) => '${_n(q)} tsp ghee on rotis/rice', kcal: 45, protein: 0, qty: 1, step: 1, min: 1, max: 3, role: _Role.fixed, tags: [DietTag.dairy]),
    _Food(id: 'seeds', label: (q) => '${_n(q)} tbsp mixed seeds (pumpkin/sunflower)', kcal: 55, protein: 2.5, qty: 1, step: 1, min: 1, max: 3, role: _Role.fixed),
    _Food(id: 'coffee', label: (_) => 'Tea or black coffee', kcal: 10, protein: 0, qty: 1, step: 1, min: 1, max: 1, role: _Role.fixed),
  ])
    f.id: f,
};

class DietInput {
  const DietInput({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.goalWeightKg,
    required this.goal,
    required this.trainingDays,
    required this.dietType,
    this.intolerances = const [],
    this.kcalOverride,
    this.proteinOverride,
  });
  final Sex sex;
  final num age;
  final num heightCm;
  final num weightKg;
  final num goalWeightKg;
  final Goal goal;

  /// Number of training days per week.
  final int trainingDays;
  final DietType dietType;
  final List<String> intolerances;
  final int? kcalOverride;
  final int? proteinOverride;
}

class GenMeal {
  const GenMeal({
    required this.time,
    required this.meal,
    required this.items,
    this.rotate,
    required this.proteinG,
    required this.kcal,
    this.optional,
    this.skipOnRestDay,
  });
  final String time;
  final String meal;
  final List<String> items;
  final List<String>? rotate;
  final int proteinG;
  final int kcal;
  final bool? optional;
  final bool? skipOnRestDay;

  Map<String, Object?> toJson() => {
        'time': time,
        'meal': meal,
        'items': items,
        if (rotate != null) 'rotate': rotate,
        'proteinG': proteinG,
        'kcal': kcal,
        if (optional != null) 'optional': optional,
        if (skipOnRestDay != null) 'skipOnRestDay': skipOnRestDay,
      };
}

class GeneratedDiet {
  const GeneratedDiet({required this.kcalTarget, required this.proteinTargetG, required this.meals});
  final int kcalTarget;
  final int proteinTargetG;
  final List<GenMeal> meals;
}

const Map<Goal, double> _goalFactor = {Goal.fatLoss: 0.8, Goal.lean: 0.88, Goal.muscle: 1.1, Goal.strength: 1.05, Goal.general: 1};
const Map<Goal, double> _proteinPerKg = {Goal.fatLoss: 2.0, Goal.lean: 2.0, Goal.muscle: 1.8, Goal.strength: 1.8, Goal.general: 1.5};

int kcalFloorFor(Sex sex) => sex == Sex.female ? 1400 : sex == Sex.male ? 1700 : 1500;

/// Daily kcal and protein targets (Mifflin–St Jeor × activity × goal; protein g/kg).
({int kcal, int proteinG}) dietTargets({
  required Sex sex,
  required num age,
  required num heightCm,
  required num weightKg,
  required num goalWeightKg,
  required Goal goal,
  required int trainingDays,
}) {
  final s = sex == Sex.male ? 5 : sex == Sex.female ? -161 : -78;
  final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + s;
  final activity = trainingDays <= 2 ? 1.375 : trainingDays <= 4 ? 1.55 : 1.65;
  final rounded = (_jsRound((bmr * activity * _goalFactor[goal]!) / 50) * 50).toInt();
  final floor = kcalFloorFor(sex);
  final kcal = rounded > floor ? rounded : floor;
  // protein: per kg of goal weight when cutting (≈ lean-mass proxy), current weight otherwise; capped for very heavy users
  final double ref;
  if (goal == Goal.fatLoss || goal == Goal.lean) {
    final g = goalWeightKg.toDouble();
    final w85 = weightKg * 0.85;
    final hi = g > w85 ? g : w85;
    ref = weightKg < hi ? weightKg.toDouble() : hi;
  } else {
    ref = weightKg.toDouble();
  }
  final p = (_jsRound((_proteinPerKg[goal]! * ref) / 5) * 5).toInt();
  return (kcal: kcal, proteinG: p < 220 ? p : 220);
}

Set<DietTag> _blocked(DietInput i) {
  final b = <DietTag>{};
  if (i.dietType != DietType.nonveg) b.addAll([DietTag.meat, DietTag.fish]);
  if (i.dietType == DietType.veg || i.dietType == DietType.vegan) b.add(DietTag.egg);
  if (i.dietType == DietType.vegan) b.addAll([DietTag.dairy, DietTag.lactose, DietTag.paneer]);
  for (final x in i.intolerances.map((t) => t.toLowerCase())) {
    if (x.contains('lactose')) b.add(DietTag.lactose);
    if (x.contains('paneer')) b.add(DietTag.paneer);
    if (x.contains('gluten')) b.add(DietTag.gluten);
    if (x.contains('nut')) b.add(DietTag.nuts);
    if (x.contains('soy')) b.add(DietTag.soy);
    if (x.contains('egg')) b.add(DietTag.egg);
    if (x.contains('dairy') || x.contains('milk')) b.addAll([DietTag.dairy, DietTag.lactose, DietTag.paneer]);
  }
  return b;
}

class _Part {
  _Part(this.food, this.q);
  final _Food food;
  double q;
}

class _Meal {
  _Meal(this.time, this.meal, this.parts, {this.rotate, this.skipOnRestDay});
  final String time;
  final String meal;
  final List<_Part> parts;
  final List<String>? rotate;
  final bool? skipOnRestDay;
}

GeneratedDiet generateDiet(DietInput i) {
  final t = dietTargets(
    sex: i.sex,
    age: i.age,
    heightCm: i.heightCm,
    weightKg: i.weightKg,
    goalWeightKg: i.goalWeightKg,
    goal: i.goal,
    trainingDays: i.trainingDays,
  );
  final kcalTarget = i.kcalOverride ?? t.kcal;
  final proteinTargetG = i.proteinOverride ?? t.proteinG;
  final no = _blocked(i);
  bool ok(String id) => !_foods[id]!.tags.any(no.contains);
  String? first(List<String> ids) {
    for (final id in ids) {
      if (ok(id)) return id;
    }
    return null;
  }

  List<_Part> part(String? id, [double? q]) => id == null ? [] : [_Part(_foods[id]!, q ?? _foods[id]!.qty)];

  final shake = first(['whey', 'pea']);
  final shakeOk = shake == 'whey' ? !no.contains(DietTag.dairy) : true;
  final meals = <_Meal>[
    _Meal('08:30', 'Pre-workout', [...part('coffee'), ...part(first(['almonds', 'dates']))], skipOnRestDay: true),
    _Meal('10:30', 'Breakfast', [
      if (shakeOk) ...part(shake),
      ...(ok('eggs') ? [...part('eggs'), ...part('whites')] : part(first(['tofuB', 'besan']))),
      ...part(first(['oats', 'poha'])),
    ]),
    _Meal('13:00', 'Lunch', [
      ...part(first(['chicken', 'fish', 'soya', 'tofu', 'chana'])),
      ...part('dal'),
      ...part('rice'),
      ...part('sabzi'),
      ...part('salad'),
    ]),
    _Meal(
      '16:00',
      'Snack',
      part(first(['soymilk', 'milk']) ?? 'chanaRoast'),
      rotate: [
        if (!no.contains(DietTag.soy)) '100 g edamame',
        '30 g roasted chana',
        '1 cup sprouts chaat',
        if (!no.contains(DietTag.lactose)) '150 g Greek yogurt',
      ],
    ),
    _Meal('18:30', 'Evening', [...part('fruit'), ...(ok('curd') ? part('curd') : part('chanaRoast'))]),
    _Meal('20:30', 'Dinner', [
      ...(i.dietType == DietType.nonveg
          ? part(first(['fish', 'chicken']))
          : ok('eggs')
              ? [...part('eggs'), ...part('whites', 3)]
              : part(first(['paneer', 'tofu', 'chana']))),
      ...part(first(['roti', 'jowar'])),
      ...part('sabzi'),
    ]),
  ];

  // Same accumulation order as the TS reduce calls (float parity).
  double sum(double Function(_Part p) fn) {
    var a = 0.0;
    for (final m in meals) {
      var b = 0.0;
      for (final p in m.parts) {
        b = b + fn(p);
      }
      a = a + b;
    }
    return a;
  }

  double pSum() => sum((p) => p.food.protein * p.q);
  double kSum() => sum((p) => p.food.kcal * p.q);
  double clamp(double v, double lo, double hi) => v > hi ? hi : (v < lo ? lo : v);
  double round(_Part p, double v) {
    final r = _jsRound(v / p.food.step) * p.food.step;
    final lo = r > p.food.min ? r : p.food.min;
    return p.food.max < lo ? p.food.max : lo;
  }

  void scaleRole(_Role role, double factor) {
    for (final m in meals) {
      for (final p in m.parts) {
        if (p.food.role == role) p.q = round(p, p.q * factor);
      }
    }
  }

  // 1) scale protein foods toward the protein target, 2) scale carbs toward the calorie target; iterate a few times
  for (var k = 0; k < 6; k++) {
    final pf = sum((p) => p.food.role == _Role.protein ? p.food.protein * p.q : 0);
    final need = proteinTargetG - (pSum() - pf);
    if (pf > 0) scaleRole(_Role.protein, clamp(need / pf, 0.5, 2));
    final cf = sum((p) => p.food.role == _Role.carb ? p.food.kcal * p.q : 0);
    final kNeed = kcalTarget - (kSum() - cf);
    if (cf > 0) scaleRole(_Role.carb, clamp(kNeed / cf, 0.3, 2.5));
  }

  // High targets (e.g. muscle gain): carbs hit their portion caps, so add energy boosters until within ~5%
  const boosters = <(String, int)>[('banana', 0), ('pb', 0), ('banana', 0), ('seeds', 0), ('pb', 0), ('ghee', 5), ('seeds', 0), ('pb', 0), ('ghee', 5), ('ghee', 5)];
  for (final (id, mealIdx) in boosters) {
    if (kSum() >= kcalTarget * 0.95) break;
    if (!ok(id)) continue;
    final m = meals[mealIdx == 0 ? 3 : mealIdx];
    _Part? existing;
    for (final p in m.parts) {
      if (p.food.id == id) {
        existing = p;
        break;
      }
    }
    if (existing != null) {
      if (existing.q < existing.food.max) existing.q += existing.food.step;
    } else {
      m.parts.add(_Part(_foods[id]!, _foods[id]!.qty));
    }
  }

  final out = <GenMeal>[
    for (final m in meals)
      if (m.parts.isNotEmpty)
        GenMeal(
          time: m.time,
          meal: m.meal,
          items: [for (final p in m.parts) if (p.q > 0) p.food.label(p.q)],
          rotate: (m.rotate?.isNotEmpty ?? false) ? m.rotate : null,
          proteinG: _jsRound(m.parts.fold<double>(0, (a, p) => a + p.food.protein * p.q)).toInt(),
          kcal: (_jsRound(m.parts.fold<double>(0, (a, p) => a + p.food.kcal * p.q) / 5) * 5).toInt(),
          skipOnRestDay: m.skipOnRestDay,
        ),
  ];
  // optional protein top-up
  if (shake != null && shakeOk) {
    out.add(GenMeal(
      time: '22:00',
      meal: 'Only if needed',
      items: ['½ scoop ${shake == 'whey' ? 'whey' : 'plant protein'} in water, only if protein is short'],
      proteinG: 12,
      kcal: 60,
      optional: true,
    ));
  }
  return GeneratedDiet(kcalTarget: kcalTarget, proteinTargetG: proteinTargetG, meals: out);
}
