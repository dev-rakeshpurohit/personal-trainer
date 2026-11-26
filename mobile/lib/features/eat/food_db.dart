// Built-in Indian dish table for the local Hinglish parser. Pure Dart (no Flutter imports).
//
// Values are typical home-cooked approximations (IFCT / label data, rounded): good enough to log
// a thali honestly, not medical nutrition. Each dish has one base unit; kcal and protein are per
// base unit at "normal" oil and a medium (M) katori / medium piece. `oilTsp` is the oil already
// counted in that kcal, so the oil chip can scale it (1 tsp oil ≈ 40 kcal).

/// Units a user can type or pick on a chip.
enum FoodUnit {
  piece('piece', 'pc'),
  katori('katori', 'katori'),
  cup('cup', 'cup'),
  glass('glass', 'glass'),
  gm('gm', 'g'),
  scoop('scoop', 'scoop'),
  tsp('tsp', 'tsp'),
  tbsp('tbsp', 'tbsp'),
  handful('handful', 'handful'),
  slice('slice', 'slice');

  const FoodUnit(this.id, this.short);
  final String id;
  final String short;

  bool get isVolume => this == katori || this == cup || this == glass;
  static FoodUnit parse(Object? s) => values.firstWhere((u) => u.id == s, orElse: () => piece);
}

/// S / M / L: katori size or piece size (roti, paratha, dosa…).
enum PortionSize {
  s('S', 'Small'),
  m('M', 'Medium'),
  l('L', 'Large');

  const PortionSize(this.id, this.label);
  final String id;
  final String label;
  static PortionSize parse(Object? s) => values.firstWhere((v) => v.id == s, orElse: () => m);
}

/// Oil chip: kam tel / normal / zyada (dhaba-style).
enum OilLevel {
  light('light', 'Kam tel', 0.5),
  normal('normal', 'Normal oil', 1),
  rich('rich', 'Zyada / dhaba', 2);

  const OilLevel(this.id, this.label, this.factor);
  final String id;
  final String label;
  final double factor;
  static OilLevel parse(Object? s) => values.firstWhere((v) => v.id == s, orElse: () => normal);
}

/// kcal per teaspoon of oil or ghee.
const double kOilKcalPerTsp = 40;

/// Millilitres per volume unit. A katori's size comes from [PortionSize].
const Map<PortionSize, double> kKatoriMl = {PortionSize.s: 100, PortionSize.m: 150, PortionSize.l: 200};
const double kCupMl = 200;
const double kGlassMl = 250;

/// Size multiplier for piece foods (small roti vs large roti).
const Map<PortionSize, double> kPieceSize = {PortionSize.s: 0.75, PortionSize.m: 1, PortionSize.l: 1.3};

/// Diet tags used to filter swaps by diet type and intolerances.
abstract final class FoodTag {
  static const dairy = 'dairy';
  static const lactose = 'lactose';
  static const paneer = 'paneer';
  static const egg = 'egg';
  static const meat = 'meat';
  static const fish = 'fish';
  static const soy = 'soy';
  static const gluten = 'gluten';
  static const nuts = 'nuts';
}

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.aliases,
    required this.unit,
    required this.grams,
    required this.kcal,
    required this.protein,
    this.oilTsp = 0,
    this.tags = const {},
    this.vrat = false,
    this.family,
    this.step,
  });

  final String id;
  final String name;

  /// Lower-case words / phrases that resolve to this dish (Hinglish spellings included).
  final List<String> aliases;
  final FoodUnit unit;

  /// Grams (or ml) in one base unit. For [FoodUnit.gm] dishes the base unit is 100 g.
  final double grams;
  final double kcal;
  final double protein;
  final double oilTsp;
  final Set<String> tags;

  /// Fine during a vrat (fast): sabudana, kuttu, singhara, fruit, dairy…
  final bool vrat;

  /// Variants that can stand in for each other on the unit chip (roti ↔ phulka ↔ paratha).
  final String? family;

  /// Rounding step for quantities in [unit] (defaults: 1 piece, 0.5 katori, 25 g).
  final double? step;

  bool get cooked => oilTsp > 0;
  bool get sized => unit == FoodUnit.piece || unit == FoodUnit.katori;
  double get defaultQty => unit == FoodUnit.gm ? 100 : 1;
  double get qtyStep => step ?? (unit == FoodUnit.gm ? 25 : unit == FoodUnit.piece || unit == FoodUnit.scoop ? 1 : 0.5);
}

const _dishes = <Dish>[
  // ---------------------------------------------------------------- breads
  Dish(id: 'roti', name: 'Roti', aliases: ['roti', 'rotis', 'chapati', 'chapatis', 'chapathi', 'chapatti', 'rotli', 'fulka roti'], unit: FoodUnit.piece, grams: 40, kcal: 105, protein: 3.1, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'phulka', name: 'Phulka', aliases: ['phulka', 'phulkas', 'fulka', 'fulkas'], unit: FoodUnit.piece, grams: 30, kcal: 80, protein: 2.5, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'paratha', name: 'Paratha', aliases: ['paratha', 'parathas', 'parantha', 'parontha', 'plain paratha'], unit: FoodUnit.piece, grams: 60, kcal: 200, protein: 4.5, oilTsp: 1.5, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'aloo_paratha', name: 'Aloo paratha', aliases: ['aloo paratha', 'aloo parantha', 'alu paratha'], unit: FoodUnit.piece, grams: 110, kcal: 290, protein: 6, oilTsp: 2, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'paneer_paratha', name: 'Paneer paratha', aliases: ['paneer paratha', 'paneer parantha'], unit: FoodUnit.piece, grams: 120, kcal: 320, protein: 12, oilTsp: 2, tags: {FoodTag.gluten, FoodTag.paneer, FoodTag.dairy, FoodTag.lactose}, family: 'bread'),
  Dish(id: 'thepla', name: 'Thepla', aliases: ['thepla', 'theplas'], unit: FoodUnit.piece, grams: 40, kcal: 120, protein: 3, oilTsp: 1, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'bhakri', name: 'Jowar / bajra roti', aliases: ['bhakri', 'jowar roti', 'bajra roti', 'jowar', 'bajra', 'makki roti', 'makki ki roti'], unit: FoodUnit.piece, grams: 45, kcal: 110, protein: 3.5, family: 'bread'),
  Dish(id: 'puri', name: 'Puri', aliases: ['puri', 'puris', 'poori', 'pooris'], unit: FoodUnit.piece, grams: 25, kcal: 100, protein: 2, oilTsp: 1, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'bhatura', name: 'Bhatura', aliases: ['bhatura', 'bhature', 'bhaturas'], unit: FoodUnit.piece, grams: 70, kcal: 300, protein: 6, oilTsp: 2.5, tags: {FoodTag.gluten}, family: 'bread'),
  Dish(id: 'naan', name: 'Naan', aliases: ['naan', 'nan', 'butter naan', 'kulcha'], unit: FoodUnit.piece, grams: 90, kcal: 260, protein: 8, oilTsp: 0.5, tags: {FoodTag.gluten, FoodTag.dairy}, family: 'bread'),
  Dish(id: 'bread', name: 'Bread / toast', aliases: ['bread', 'toast', 'brown bread', 'multigrain toast', 'slice bread'], unit: FoodUnit.slice, grams: 28, kcal: 70, protein: 2.5, tags: {FoodTag.gluten}, step: 1),
  Dish(id: 'kuttu_roti', name: 'Kuttu roti', aliases: ['kuttu roti', 'kuttu', 'kuttu puri', 'kuttu ki roti', 'buckwheat roti'], unit: FoodUnit.piece, grams: 40, kcal: 120, protein: 3, oilTsp: 0.5, vrat: true, family: 'bread'),
  Dish(id: 'singhara_roti', name: 'Singhara roti', aliases: ['singhara roti', 'singhara', 'singhare ki roti', 'singhara atta'], unit: FoodUnit.piece, grams: 40, kcal: 110, protein: 1.5, oilTsp: 0.5, vrat: true, family: 'bread'),
  // ---------------------------------------------------------------- rice
  Dish(id: 'rice', name: 'Rice', aliases: ['rice', 'chawal', 'chaawal', 'bhaat', 'bhat', 'plain rice', 'steamed rice', 'cooked rice'], unit: FoodUnit.katori, grams: 150, kcal: 195, protein: 4, family: 'rice'),
  Dish(id: 'jeera_rice', name: 'Jeera rice', aliases: ['jeera rice', 'zeera rice'], unit: FoodUnit.katori, grams: 150, kcal: 230, protein: 4, oilTsp: 1, family: 'rice'),
  Dish(id: 'pulao', name: 'Veg pulao', aliases: ['pulao', 'pulav', 'veg pulao', 'tehri'], unit: FoodUnit.katori, grams: 150, kcal: 250, protein: 5, oilTsp: 1.5, family: 'rice'),
  Dish(id: 'veg_biryani', name: 'Veg biryani', aliases: ['biryani', 'veg biryani', 'biriyani'], unit: FoodUnit.katori, grams: 170, kcal: 300, protein: 7, oilTsp: 2, family: 'rice'),
  Dish(id: 'chicken_biryani', name: 'Chicken biryani', aliases: ['chicken biryani', 'chicken biriyani', 'mutton biryani'], unit: FoodUnit.katori, grams: 180, kcal: 350, protein: 18, oilTsp: 2, tags: {FoodTag.meat}, family: 'rice'),
  Dish(id: 'khichdi', name: 'Khichdi', aliases: ['khichdi', 'khichri', 'khichadi', 'dal khichdi'], unit: FoodUnit.katori, grams: 170, kcal: 200, protein: 7, oilTsp: 1, family: 'rice'),
  Dish(id: 'curd_rice', name: 'Curd rice', aliases: ['curd rice', 'dahi chawal', 'thayir sadam'], unit: FoodUnit.katori, grams: 170, kcal: 220, protein: 6, oilTsp: 0.5, tags: {FoodTag.dairy, FoodTag.lactose}, family: 'rice'),
  Dish(id: 'samak_rice', name: 'Samak rice', aliases: ['samak', 'sama rice', 'samak rice', 'samvat', 'vrat ke chawal', 'barnyard millet'], unit: FoodUnit.katori, grams: 150, kcal: 170, protein: 3, oilTsp: 0.5, vrat: true, family: 'rice'),
  // ---------------------------------------------------------------- dal & curries
  Dish(id: 'dal', name: 'Dal', aliases: ['dal', 'daal', 'dhal', 'dal tadka', 'tadka dal', 'yellow dal', 'moong dal', 'toor dal', 'arhar dal', 'masoor dal', 'chana dal', 'dal fry', 'thick dal', 'thick moong dal'], unit: FoodUnit.katori, grams: 150, kcal: 150, protein: 9, oilTsp: 1, family: 'dal'),
  Dish(id: 'dal_makhani', name: 'Dal makhani', aliases: ['dal makhani', 'maa ki dal', 'kali dal'], unit: FoodUnit.katori, grams: 150, kcal: 260, protein: 10, oilTsp: 2, tags: {FoodTag.dairy}, family: 'dal'),
  Dish(id: 'rajma', name: 'Rajma', aliases: ['rajma', 'rajmah', 'kidney beans'], unit: FoodUnit.katori, grams: 150, kcal: 210, protein: 11, oilTsp: 1, family: 'dal'),
  Dish(id: 'chole', name: 'Chole', aliases: ['chole', 'chhole', 'chana masala', 'chana', 'channa', 'kabuli chana', 'chickpeas'], unit: FoodUnit.katori, grams: 150, kcal: 240, protein: 11, oilTsp: 1.5, family: 'dal'),
  Dish(id: 'kadhi', name: 'Kadhi', aliases: ['kadhi', 'kadi', 'kadhi pakora'], unit: FoodUnit.katori, grams: 150, kcal: 160, protein: 6, oilTsp: 1, tags: {FoodTag.dairy, FoodTag.lactose}, family: 'dal'),
  Dish(id: 'sambhar', name: 'Sambhar', aliases: ['sambhar', 'sambar'], unit: FoodUnit.katori, grams: 150, kcal: 130, protein: 6, oilTsp: 1, family: 'dal'),
  Dish(id: 'rasam', name: 'Rasam', aliases: ['rasam'], unit: FoodUnit.katori, grams: 150, kcal: 60, protein: 2, oilTsp: 0.5, family: 'dal'),
  Dish(id: 'sabzi', name: 'Sabzi', aliases: ['sabzi', 'sabji', 'subzi', 'veg', 'mix veg', 'mixed veg', 'bhindi', 'gobi', 'aloo gobi', 'lauki', 'tinda', 'baingan', 'beans', 'cabbage', 'capsicum', 'palak', 'methi', 'bhaji', 'non-starchy sabzi', 'vegetable'], unit: FoodUnit.katori, grams: 150, kcal: 120, protein: 3, oilTsp: 1.5, family: 'sabzi'),
  Dish(id: 'aloo_sabzi', name: 'Aloo sabzi', aliases: ['aloo', 'aloo sabzi', 'alu', 'potato', 'aloo matar', 'jeera aloo', 'vrat aloo'], unit: FoodUnit.katori, grams: 150, kcal: 180, protein: 3, oilTsp: 1.5, vrat: true, family: 'sabzi'),
  Dish(id: 'palak_paneer', name: 'Palak paneer', aliases: ['palak paneer', 'saag paneer'], unit: FoodUnit.katori, grams: 150, kcal: 260, protein: 13, oilTsp: 2, tags: {FoodTag.paneer, FoodTag.dairy, FoodTag.lactose}, family: 'paneer'),
  Dish(id: 'paneer_curry', name: 'Paneer butter masala', aliases: ['paneer butter masala', 'paneer makhani', 'shahi paneer', 'kadai paneer', 'paneer curry', 'paneer masala', 'paneer sabzi'], unit: FoodUnit.katori, grams: 150, kcal: 340, protein: 14, oilTsp: 3, tags: {FoodTag.paneer, FoodTag.dairy, FoodTag.lactose}, family: 'paneer'),
  Dish(id: 'matar_paneer', name: 'Matar paneer', aliases: ['matar paneer', 'mutter paneer'], unit: FoodUnit.katori, grams: 150, kcal: 250, protein: 12, oilTsp: 2, tags: {FoodTag.paneer, FoodTag.dairy, FoodTag.lactose}, family: 'paneer'),
  Dish(id: 'paneer_bhurji', name: 'Paneer bhurji', aliases: ['paneer bhurji', 'paneer tikka'], unit: FoodUnit.katori, grams: 120, kcal: 280, protein: 18, oilTsp: 1.5, tags: {FoodTag.paneer, FoodTag.dairy, FoodTag.lactose}, family: 'paneer'),
  Dish(id: 'paneer', name: 'Paneer', aliases: ['paneer', 'cottage cheese'], unit: FoodUnit.gm, grams: 100, kcal: 265, protein: 18, tags: {FoodTag.paneer, FoodTag.dairy, FoodTag.lactose}, vrat: true, family: 'paneer'),
  Dish(id: 'tofu', name: 'Tofu', aliases: ['tofu', 'tofu bhurji', 'tofu sabzi', 'tofu tikka', 'firm tofu'], unit: FoodUnit.gm, grams: 100, kcal: 145, protein: 15, oilTsp: 0.5, tags: {FoodTag.soy}),
  Dish(id: 'soya', name: 'Soya chunks curry', aliases: ['soya', 'soya chunks', 'soya chunk', 'soy chunks', 'nutrela', 'soya curry', 'soya chunks curry'], unit: FoodUnit.katori, grams: 150, kcal: 220, protein: 25, oilTsp: 1.5, tags: {FoodTag.soy}, family: 'soya'),
  Dish(id: 'soya_dry', name: 'Soya chunks (dry weight)', aliases: ['dry soya chunks', 'dry soya', 'soya chunks dry', 'dry soy chunks'], unit: FoodUnit.gm, grams: 100, kcal: 345, protein: 52, tags: {FoodTag.soy}, family: 'soya'),
  Dish(id: 'sprouts', name: 'Sprouts', aliases: ['sprouts', 'moong sprouts', 'sprouts chaat', 'ankurit moong'], unit: FoodUnit.katori, grams: 120, kcal: 110, protein: 8, family: 'dal'),
  Dish(id: 'edamame', name: 'Edamame', aliases: ['edamame'], unit: FoodUnit.gm, grams: 100, kcal: 120, protein: 11, tags: {FoodTag.soy}),
  // ---------------------------------------------------------------- eggs, chicken, fish
  Dish(id: 'egg', name: 'Boiled egg', aliases: ['egg', 'eggs', 'anda', 'ande', 'anday', 'boiled egg', 'boiled eggs', 'whole egg', 'whole eggs'], unit: FoodUnit.piece, grams: 50, kcal: 72, protein: 6.3, tags: {FoodTag.egg}),
  Dish(id: 'egg_white', name: 'Egg white', aliases: ['egg white', 'egg whites', 'whites'], unit: FoodUnit.piece, grams: 33, kcal: 17, protein: 3.6, tags: {FoodTag.egg}),
  Dish(id: 'omelette', name: 'Omelette (2 eggs)', aliases: ['omelette', 'omelet', 'omlet', 'amlet', 'masala omelette'], unit: FoodUnit.piece, grams: 110, kcal: 190, protein: 13, oilTsp: 1, tags: {FoodTag.egg}),
  Dish(id: 'egg_bhurji', name: 'Egg bhurji (2 eggs)', aliases: ['egg bhurji', 'anda bhurji', 'scrambled eggs', 'bhurji'], unit: FoodUnit.katori, grams: 120, kcal: 200, protein: 13, oilTsp: 1, tags: {FoodTag.egg}),
  Dish(id: 'egg_curry', name: 'Egg curry (2 eggs)', aliases: ['egg curry', 'anda curry'], unit: FoodUnit.katori, grams: 180, kcal: 240, protein: 13, oilTsp: 1.5, tags: {FoodTag.egg}),
  Dish(id: 'chicken_curry', name: 'Chicken curry', aliases: ['chicken curry', 'chicken', 'butter chicken', 'kadai chicken', 'chicken masala'], unit: FoodUnit.katori, grams: 150, kcal: 280, protein: 25, oilTsp: 2, tags: {FoodTag.meat}),
  Dish(id: 'chicken_breast', name: 'Chicken breast', aliases: ['chicken breast', 'grilled chicken', 'boiled chicken', 'tandoori chicken'], unit: FoodUnit.gm, grams: 100, kcal: 165, protein: 31, tags: {FoodTag.meat}),
  Dish(id: 'chicken_tikka', name: 'Chicken tikka', aliases: ['chicken tikka', 'tikka'], unit: FoodUnit.piece, grams: 30, kcal: 50, protein: 7, tags: {FoodTag.meat}),
  Dish(id: 'mutton_curry', name: 'Mutton curry', aliases: ['mutton', 'mutton curry', 'gosht', 'keema'], unit: FoodUnit.katori, grams: 150, kcal: 340, protein: 24, oilTsp: 2.5, tags: {FoodTag.meat}),
  Dish(id: 'fish_curry', name: 'Fish curry', aliases: ['fish curry', 'fish', 'machhi', 'machli', 'meen curry'], unit: FoodUnit.katori, grams: 150, kcal: 220, protein: 22, oilTsp: 1.5, tags: {FoodTag.fish}),
  Dish(id: 'fish_fry', name: 'Fish fry', aliases: ['fish fry', 'fried fish', 'grilled fish'], unit: FoodUnit.piece, grams: 100, kcal: 230, protein: 20, oilTsp: 2, tags: {FoodTag.fish}),
  // ---------------------------------------------------------------- breakfast & tiffin
  Dish(id: 'poha', name: 'Poha', aliases: ['poha', 'pohe', 'aval'], unit: FoodUnit.katori, grams: 150, kcal: 180, protein: 3.5, oilTsp: 1),
  Dish(id: 'upma', name: 'Upma', aliases: ['upma', 'uppittu', 'rava upma'], unit: FoodUnit.katori, grams: 150, kcal: 190, protein: 4.5, oilTsp: 1, tags: {FoodTag.gluten}),
  Dish(id: 'idli', name: 'Idli', aliases: ['idli', 'idlis', 'idly', 'idlies'], unit: FoodUnit.piece, grams: 40, kcal: 58, protein: 2),
  Dish(id: 'dosa', name: 'Dosa', aliases: ['dosa', 'dosas', 'plain dosa', 'dosai'], unit: FoodUnit.piece, grams: 80, kcal: 170, protein: 4, oilTsp: 1, family: 'dosa'),
  Dish(id: 'masala_dosa', name: 'Masala dosa', aliases: ['masala dosa'], unit: FoodUnit.piece, grams: 160, kcal: 300, protein: 6, oilTsp: 2, family: 'dosa'),
  Dish(id: 'uttapam', name: 'Uttapam', aliases: ['uttapam', 'uthappam', 'utappa'], unit: FoodUnit.piece, grams: 100, kcal: 200, protein: 5, oilTsp: 1, family: 'dosa'),
  Dish(id: 'vada', name: 'Medu vada', aliases: ['vada', 'vadas', 'medu vada', 'wada'], unit: FoodUnit.piece, grams: 40, kcal: 130, protein: 4, oilTsp: 1),
  Dish(id: 'chilla', name: 'Besan chilla', aliases: ['chilla', 'cheela', 'besan chilla', 'besan cheela', 'moong chilla', 'moong dal chilla'], unit: FoodUnit.piece, grams: 70, kcal: 140, protein: 7, oilTsp: 1),
  Dish(id: 'oats', name: 'Oats', aliases: ['oats', 'oatmeal', 'masala oats', 'daliya', 'dalia'], unit: FoodUnit.katori, grams: 150, kcal: 150, protein: 5, tags: {FoodTag.gluten}),
  Dish(id: 'dhokla', name: 'Dhokla', aliases: ['dhokla', 'khaman'], unit: FoodUnit.piece, grams: 30, kcal: 50, protein: 2),
  Dish(id: 'sabudana', name: 'Sabudana khichdi', aliases: ['sabudana', 'sabudana khichdi', 'sago', 'sabudana vada'], unit: FoodUnit.katori, grams: 150, kcal: 300, protein: 3, oilTsp: 2, tags: {FoodTag.nuts}, vrat: true),
  // ---------------------------------------------------------------- dairy & drinks
  Dish(id: 'curd', name: 'Curd', aliases: ['curd', 'dahi', 'yogurt', 'yoghurt', 'plain curd'], unit: FoodUnit.katori, grams: 150, kcal: 90, protein: 5, tags: {FoodTag.dairy, FoodTag.lactose}, vrat: true),
  Dish(id: 'hung_curd', name: 'Hung curd', aliases: ['hung curd', 'greek yogurt', 'greek yoghurt', 'skyr'], unit: FoodUnit.katori, grams: 150, kcal: 145, protein: 14, tags: {FoodTag.dairy}, vrat: true),
  Dish(id: 'raita', name: 'Raita', aliases: ['raita', 'boondi raita'], unit: FoodUnit.katori, grams: 120, kcal: 100, protein: 4, tags: {FoodTag.dairy, FoodTag.lactose}, vrat: true),
  Dish(id: 'milk', name: 'Milk', aliases: ['milk', 'doodh', 'toned milk', 'haldi doodh'], unit: FoodUnit.glass, grams: 250, kcal: 150, protein: 8, tags: {FoodTag.dairy, FoodTag.lactose}, vrat: true),
  Dish(id: 'soy_milk', name: 'Soy milk', aliases: ['soy milk', 'soya milk', 'unsweetened soy milk'], unit: FoodUnit.glass, grams: 250, kcal: 80, protein: 8, tags: {FoodTag.soy}),
  Dish(id: 'chai', name: 'Chai', aliases: ['chai', 'tea', 'cha', 'masala chai', 'adrak chai'], unit: FoodUnit.cup, grams: 150, kcal: 90, protein: 2, tags: {FoodTag.dairy, FoodTag.lactose}, vrat: true),
  Dish(id: 'coffee', name: 'Coffee', aliases: ['coffee', 'filter coffee', 'cold coffee'], unit: FoodUnit.cup, grams: 150, kcal: 100, protein: 3, tags: {FoodTag.dairy, FoodTag.lactose}),
  Dish(id: 'black_coffee', name: 'Black coffee / tea', aliases: ['black coffee', 'black tea', 'green tea', 'americano'], unit: FoodUnit.cup, grams: 150, kcal: 5, protein: 0, vrat: true),
  Dish(id: 'lassi', name: 'Lassi', aliases: ['lassi', 'sweet lassi'], unit: FoodUnit.glass, grams: 250, kcal: 220, protein: 7, tags: {FoodTag.dairy, FoodTag.lactose}, vrat: true),
  Dish(id: 'chaas', name: 'Chaas', aliases: ['chaas', 'chhaas', 'chhach', 'buttermilk', 'mattha'], unit: FoodUnit.glass, grams: 250, kcal: 45, protein: 2, tags: {FoodTag.dairy}, vrat: true),
  Dish(id: 'whey', name: 'Whey protein', aliases: ['whey', 'protein shake', 'protein', 'shake', 'whey isolate', 'whey protein'], unit: FoodUnit.scoop, grams: 30, kcal: 120, protein: 24, tags: {FoodTag.dairy}),
  Dish(id: 'plant_protein', name: 'Plant protein', aliases: ['plant protein', 'pea protein', 'vegan protein'], unit: FoodUnit.scoop, grams: 32, kcal: 120, protein: 24),
  // ---------------------------------------------------------------- snacks
  Dish(id: 'roasted_chana', name: 'Roasted chana', aliases: ['roasted chana', 'bhuna chana', 'bhune chane', 'chana roasted'], unit: FoodUnit.handful, grams: 30, kcal: 110, protein: 6),
  Dish(id: 'peanuts', name: 'Peanuts', aliases: ['peanuts', 'peanut', 'moongphali', 'mungfali', 'shengdana'], unit: FoodUnit.handful, grams: 30, kcal: 170, protein: 7, tags: {FoodTag.nuts}, vrat: true),
  Dish(id: 'makhana', name: 'Makhana', aliases: ['makhana', 'makhane', 'fox nuts', 'phool makhana'], unit: FoodUnit.katori, grams: 25, kcal: 90, protein: 2.5, oilTsp: 0.5, vrat: true),
  Dish(id: 'almonds', name: 'Almonds', aliases: ['almonds', 'almond', 'badam', 'badaam'], unit: FoodUnit.piece, grams: 1.2, kcal: 7, protein: 0.25, tags: {FoodTag.nuts}, vrat: true),
  Dish(id: 'samosa', name: 'Samosa', aliases: ['samosa', 'samosas', 'samose'], unit: FoodUnit.piece, grams: 80, kcal: 260, protein: 4, oilTsp: 2, tags: {FoodTag.gluten}),
  Dish(id: 'pakora', name: 'Pakora', aliases: ['pakora', 'pakoras', 'pakode', 'pakoda', 'bhajiya'], unit: FoodUnit.piece, grams: 20, kcal: 75, protein: 2, oilTsp: 0.7),
  Dish(id: 'biscuit', name: 'Biscuit', aliases: ['biscuit', 'biscuits', 'cookie', 'cookies', 'rusk', 'toast rusk'], unit: FoodUnit.piece, grams: 10, kcal: 45, protein: 0.6, tags: {FoodTag.gluten}),
  Dish(id: 'peanut_butter', name: 'Peanut butter', aliases: ['peanut butter', 'pb'], unit: FoodUnit.tbsp, grams: 16, kcal: 95, protein: 4, tags: {FoodTag.nuts}, step: 0.5),
  Dish(id: 'ghee', name: 'Ghee', aliases: ['ghee', 'ghi', 'desi ghee'], unit: FoodUnit.tsp, grams: 5, kcal: 45, protein: 0, tags: {FoodTag.dairy}, vrat: true, step: 0.5),
  Dish(id: 'oil', name: 'Oil', aliases: ['oil', 'tel', 'butter', 'makhan'], unit: FoodUnit.tsp, grams: 5, kcal: 40, protein: 0, step: 0.5),
  Dish(id: 'sweet', name: 'Mithai', aliases: ['mithai', 'sweet', 'laddoo', 'ladoo', 'gulab jamun', 'barfi', 'halwa', 'kheer'], unit: FoodUnit.piece, grams: 40, kcal: 170, protein: 2.5, tags: {FoodTag.dairy}),
  // ---------------------------------------------------------------- fruit & veg
  Dish(id: 'banana', name: 'Banana', aliases: ['banana', 'bananas', 'kela', 'kele'], unit: FoodUnit.piece, grams: 120, kcal: 105, protein: 1.3, vrat: true, family: 'fruit'),
  Dish(id: 'apple', name: 'Apple', aliases: ['apple', 'apples', 'seb'], unit: FoodUnit.piece, grams: 180, kcal: 95, protein: 0.5, vrat: true, family: 'fruit'),
  Dish(id: 'fruit', name: 'Fruit', aliases: ['fruit', 'fruits', 'phal', 'guava', 'amrood', 'orange', 'santra', 'pear', 'mango', 'aam', 'chikoo', 'fruit bowl'], unit: FoodUnit.piece, grams: 150, kcal: 80, protein: 1, vrat: true, family: 'fruit'),
  Dish(id: 'papaya', name: 'Papaya', aliases: ['papaya', 'papita', 'watermelon', 'tarbooz', 'melon'], unit: FoodUnit.katori, grams: 150, kcal: 60, protein: 0.7, vrat: true, family: 'fruit'),
  Dish(id: 'dates', name: 'Dates', aliases: ['dates', 'date', 'khajoor', 'khajur'], unit: FoodUnit.piece, grams: 8, kcal: 23, protein: 0.2, vrat: true),
  Dish(id: 'shakarkandi', name: 'Sweet potato', aliases: ['shakarkandi', 'sweet potato', 'shakarkand'], unit: FoodUnit.piece, grams: 130, kcal: 115, protein: 2, vrat: true),
  Dish(id: 'salad', name: 'Salad', aliases: ['salad', 'kachumber', 'cucumber', 'kheera'], unit: FoodUnit.katori, grams: 100, kcal: 30, protein: 1, vrat: true),
  Dish(id: 'rajgira', name: 'Rajgira ladoo', aliases: ['rajgira', 'rajgira ladoo', 'amaranth', 'ramdana'], unit: FoodUnit.piece, grams: 30, kcal: 110, protein: 2.5, vrat: true),
];

/// Every built-in dish by id.
final Map<String, Dish> kDishes = {for (final d in _dishes) d.id: d};

/// All dishes in table order.
List<Dish> get allDishes => _dishes;

/// Dishes in the same family (for the variant chip).
List<Dish> familyOf(Dish d) => d.family == null ? [d] : _dishes.where((x) => x.family == d.family).toList();
