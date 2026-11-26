// Local Hinglish food parser + the review-tray plate model. Pure Dart.
//
// "2 roti aur dal, thoda ghee" → Roti ×2 · Dal 1 katori · Ghee ½ tsp.
// No network: everything resolves against the built-in dish table (food_db.dart) and the user's
// own saved versions of dishes ("My dal").
import 'dart:math' as math;

import 'food_db.dart';

/// The user's saved version of a dish (meta 'myDishes'), applied on every later parse.
class MyDish {
  const MyDish({required this.dishId, this.kcal, this.protein, this.oil, this.size});
  final String dishId;

  /// Per base unit, replacing the table values.
  final double? kcal;
  final double? protein;
  final OilLevel? oil;
  final PortionSize? size;

  factory MyDish.fromJson(Map<String, Object?> j) => MyDish(
        dishId: j['dishId'] as String,
        kcal: (j['kcal'] as num?)?.toDouble(),
        protein: (j['protein'] as num?)?.toDouble(),
        oil: j['oil'] == null ? null : OilLevel.parse(j['oil']),
        size: j['size'] == null ? null : PortionSize.parse(j['size']),
      );

  Map<String, Object?> toJson() => {
        'dishId': dishId,
        if (kcal != null) 'kcal': kcal,
        if (protein != null) 'protein': protein,
        if (oil != null) 'oil': oil!.id,
        if (size != null) 'size': size!.id,
      };

  /// Decodes the meta value (a map of dishId → json); tolerant of junk.
  static Map<String, MyDish> decodeAll(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, MyDish>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is Map) {
        try {
          out['${e.key}'] = MyDish.fromJson(Map<String, Object?>.from(v));
        } catch (_) {}
      }
    }
    return out;
  }
}

/// One row on the review tray.
class PlateItem {
  const PlateItem({required this.dish, required this.qty, required this.unit, this.size, this.oil, this.mine, this.edited = false});
  final Dish dish;
  final double qty;
  final FoodUnit unit;

  /// Null = default (the user's katori calibration, or medium).
  final PortionSize? size;

  /// Null = auto (my dish → bahar ka → normal).
  final OilLevel? oil;
  final MyDish? mine;

  /// The user changed this row on the tray (size, oil or numbers): remember it as "My …".
  final bool edited;

  String get displayName => mine != null ? 'My ${dish.name.toLowerCase()}' : dish.name;

  PlateItem copyWith({Dish? dish, double? qty, FoodUnit? unit, PortionSize? size, OilLevel? oil, MyDish? mine, bool? edited, bool clearMine = false}) => PlateItem(
        dish: dish ?? this.dish,
        qty: qty ?? this.qty,
        unit: unit ?? this.unit,
        size: size ?? this.size,
        oil: oil ?? this.oil,
        mine: clearMine ? null : (mine ?? this.mine),
        edited: edited ?? this.edited,
      );

  @override
  String toString() => 'PlateItem(${dish.id} × ${fmtQty(qty)} ${unit.id}${size != null ? ' ${size!.id}' : ''}${oil != null ? ' ${oil!.id}' : ''})';
}

class ParseResult {
  const ParseResult({required this.items, required this.unknown, this.bahar});
  final List<PlateItem> items;

  /// Segments nothing matched ("Not in the list yet").
  final List<String> unknown;

  /// True for "bahar ka / restaurant / dhaba", false for "ghar ka", null if not said.
  final bool? bahar;
}

/* ------------------------------------------------------------------ vocabulary */

const Map<String, double> _numberWords = {
  'a': 1, 'an': 1, 'ek': 1, 'one': 1, 'do': 2, 'two': 2, 'teen': 3, 'three': 3, 'char': 4, 'chaar': 4, 'four': 4, //
  'paanch': 5, 'panch': 5, 'five': 5, 'chhe': 6, 'six': 6, 'saat': 7, 'seven': 7, 'aath': 8, 'eight': 8, //
  'half': 0.5, 'aadha': 0.5, 'adha': 0.5, 'aadhi': 0.5, 'adhi': 0.5, 'dedh': 1.5, 'dhai': 2.5, 'dhaai': 2.5,
};

/// thoda = ½, normal = 1, zyada = 1½ (of the dish's usual portion).
const Map<String, double> _amountWords = {
  'thoda': 0.5, 'thodi': 0.5, 'thode': 0.5, 'thora': 0.5, 'thori': 0.5, 'little': 0.5, 'bit': 0.5, //
  'normal': 1, 'regular': 1, 'usual': 1, //
  'zyada': 1.5, 'jyada': 1.5, 'zyaada': 1.5, 'jada': 1.5, 'zada': 1.5, 'ziada': 1.5, 'extra': 1.5, 'bahut': 1.5, 'more': 1.5, 'lots': 1.5, //
  'double': 2,
};

const Map<String, FoodUnit> _unitWords = {
  'katori': FoodUnit.katori, 'katoris': FoodUnit.katori, 'katora': FoodUnit.katori, 'katori-bhar': FoodUnit.katori, 'bowl': FoodUnit.katori, 'bowls': FoodUnit.katori, 'plate': FoodUnit.katori, 'plates': FoodUnit.katori, //
  'cup': FoodUnit.cup, 'cups': FoodUnit.cup, 'pyala': FoodUnit.cup, 'pyaali': FoodUnit.cup, 'mug': FoodUnit.cup, //
  'glass': FoodUnit.glass, 'glasses': FoodUnit.glass, 'gilas': FoodUnit.glass, //
  'g': FoodUnit.gm, 'gm': FoodUnit.gm, 'gms': FoodUnit.gm, 'gram': FoodUnit.gm, 'grams': FoodUnit.gm, 'ml': FoodUnit.gm, //
  'scoop': FoodUnit.scoop, 'scoops': FoodUnit.scoop, //
  'tsp': FoodUnit.tsp, 'teaspoon': FoodUnit.tsp, 'teaspoons': FoodUnit.tsp, 'chammach': FoodUnit.tsp, 'chamach': FoodUnit.tsp, 'chamcha': FoodUnit.tsp, 'spoon': FoodUnit.tsp, 'spoons': FoodUnit.tsp, //
  'tbsp': FoodUnit.tbsp, 'tablespoon': FoodUnit.tbsp, 'tablespoons': FoodUnit.tbsp, //
  'piece': FoodUnit.piece, 'pieces': FoodUnit.piece, 'pc': FoodUnit.piece, 'pcs': FoodUnit.piece, 'nos': FoodUnit.piece, //
  'slice': FoodUnit.slice, 'slices': FoodUnit.slice, //
  'handful': FoodUnit.handful, 'mutthi': FoodUnit.handful, 'muthi': FoodUnit.handful, 'mutthi-bhar': FoodUnit.handful,
};

const Map<String, PortionSize> _sizeWords = {
  'small': PortionSize.s, 'chhota': PortionSize.s, 'chota': PortionSize.s, 'choti': PortionSize.s, 'chhoti': PortionSize.s, 'chote': PortionSize.s, //
  'medium': PortionSize.m, //
  'big': PortionSize.l, 'large': PortionSize.l, 'bada': PortionSize.l, 'badi': PortionSize.l, 'bade': PortionSize.l,
};

const Set<String> _filler = {
  'ka', 'ki', 'ke', 'khaya', 'khayi', 'khaye', 'khaaya', 'khaai', 'liya', 'li', 'ate', 'had', 'have', 'eaten', 'some', 'of', 'the', //
  'mein', 'me', 'bhi', 'x', 'times', 'cooked', 'homemade', 'today', 'aaj', 'for', 'in', 'on', 'my', 'mera', 'meri', 'wala', 'wali', 'waala', 'hi',
};

const List<List<String>> _lightOil = [['kam', 'tel'], ['less', 'oil'], ['low', 'oil'], ['no', 'oil'], ['without', 'oil'], ['bina', 'tel'], ['light']];
const List<List<String>> _richOil = [['zyada', 'tel'], ['jyada', 'tel'], ['extra', 'oil'], ['oily'], ['dhaba', 'style'], ['rich']];
const List<List<String>> _baharWords = [['bahar', 'ka'], ['bahar', 'se'], ['bahar'], ['outside'], ['restaurant'], ['hotel'], ['dhaba'], ['ordered'], ['order'], ['swiggy'], ['zomato'], ['canteen']];
const List<List<String>> _gharWords = [['ghar', 'ka'], ['ghar'], ['home']];

/// Alias token lists, longest first, for greedy longest-match.
final List<(List<String>, Dish)> _aliasIndex = () {
  final out = <(List<String>, Dish)>[];
  for (final d in allDishes) {
    for (final a in d.aliases) {
      out.add((a.split(' '), d));
    }
  }
  out.sort((a, b) => b.$1.length - a.$1.length);
  return out;
}();

final _segmentSplit = RegExp(r'[,;+&\n]|\b(?:aur|and|with|n|plus|saath|sath|then|also|phir)\b');

String _normalise(String text) {
  var t = text.toLowerCase();
  t = t.replaceAll('½', ' 0.5 ').replaceAll('¼', ' 0.25 ').replaceAll('¾', ' 0.75 ').replaceAll('×', ' x ');
  t = t.replaceAllMapped(RegExp(r'(\d+)\s*/\s*(\d+)'), (m) {
    final a = int.parse(m[1]!);
    final b = int.parse(m[2]!);
    return b == 0 ? m[0]! : ' ${a / b} ';
  });
  t = t.replaceAllMapped(RegExp(r'(\d)(g|gm|gms|grams?|ml)\b'), (m) => '${m[1]} ${m[2]}');
  t = t.replaceAllMapped(RegExp(r'\bx\s*(\d)'), (m) => ' ${m[1]}');
  t = t.replaceAllMapped(RegExp(r'(\d)\s*x\b'), (m) => '${m[1]} ');
  t = t.replaceAll(RegExp(r'[()\[\]:!?"]'), ' ');
  return t;
}

bool _match(List<String> toks, int i, List<String> phrase) {
  if (i + phrase.length > toks.length) return false;
  for (var k = 0; k < phrase.length; k++) {
    if (toks[i + k] != phrase[k]) return false;
  }
  return true;
}

int _matchAny(List<String> toks, int i, List<List<String>> phrases) {
  for (final p in phrases) {
    if (_match(toks, i, p)) return p.length;
  }
  return 0;
}

/// Longest dish alias at [i]; tries plural-stripped tokens too ("idlis" → "idli").
(Dish, int)? _dishAt(List<String> toks, int i) {
  for (final (alias, dish) in _aliasIndex) {
    if (i + alias.length > toks.length) continue;
    var ok = true;
    for (var k = 0; k < alias.length; k++) {
      final t = toks[i + k];
      if (t != alias[k] && !(t.endsWith('s') && t.substring(0, t.length - 1) == alias[k])) {
        ok = false;
        break;
      }
    }
    if (ok) return (dish, alias.length);
  }
  return null;
}

/// Parses free text ("2 roti aur dal, thoda ghee") into tray rows. [mine] are the user's saved dishes.
ParseResult parseFood(String text, {Map<String, MyDish> mine = const {}}) {
  final items = <PlateItem>[];
  final unknown = <String>[];
  bool? bahar;

  for (final rawSeg in _normalise(text).split(_segmentSplit)) {
    final toks = rawSeg.split(RegExp(r'\s+')).map((t) => t.replaceAll(RegExp(r'[^a-z0-9.\-]'), '')).where((t) => t.isNotEmpty).toList();
    if (toks.isEmpty) continue;

    double? num;
    double? amount;
    FoodUnit? unit;
    PortionSize? size;
    OilLevel? oil;
    final segStart = items.length;
    var lastExplicit = true;
    var leftovers = false;

    void reset() {
      num = null;
      amount = null;
      unit = null;
      size = null;
    }

    bool pending() => num != null || amount != null || unit != null || size != null;

    var i = 0;
    while (i < toks.length) {
      final t = toks[i];
      var n = _matchAny(toks, i, _lightOil);
      if (n > 0) {
        oil = OilLevel.light;
        i += n;
        continue;
      }
      n = _matchAny(toks, i, _richOil);
      if (n > 0) {
        oil = OilLevel.rich;
        i += n;
        continue;
      }
      n = _matchAny(toks, i, _baharWords);
      if (n > 0) {
        bahar = true;
        i += n;
        continue;
      }
      n = _matchAny(toks, i, _gharWords);
      if (n > 0) {
        bahar = false;
        i += n;
        continue;
      }
      final hit = _dishAt(toks, i);
      if (hit != null) {
        final (dish, len) = hit;
        final explicit = pending();
        items.add(_build(dish, num, amount, unit, size, mine[dish.id]));
        lastExplicit = explicit;
        reset();
        i += len;
        continue;
      }
      final d = double.tryParse(t);
      if (d != null) {
        num = (num ?? 1) * d;
      } else if (_numberWords.containsKey(t)) {
        num = (num ?? 1) * _numberWords[t]!;
      } else if (_amountWords.containsKey(t)) {
        amount = _amountWords[t];
      } else if (_unitWords.containsKey(t)) {
        unit = _unitWords[t];
        if (t.startsWith('plate')) size = PortionSize.l;
      } else if (_sizeWords.containsKey(t)) {
        size = _sizeWords[t];
      } else if (!_filler.contains(t)) {
        leftovers = true;
      }
      i++;
    }

    final segItems = items.length - segStart;
    // Trailing quantity ("roti 2", "chawal 1 katori") belongs to the last dish if it had none.
    if (pending() && segItems > 0 && !lastExplicit) {
      final last = items.removeLast();
      items.add(_build(last.dish, num, amount, unit, size, last.mine));
    }
    if (oil != null) {
      final from = segItems > 0 ? segStart : math.max(0, items.length - 1);
      for (var k = from; k < items.length; k++) {
        if (items[k].dish.cooked) items[k] = items[k].copyWith(oil: oil);
      }
    }
    if (segItems == 0 && leftovers) unknown.add(rawSeg.trim());
  }
  return ParseResult(items: items, unknown: unknown, bahar: bahar);
}

PlateItem _build(Dish dish, double? num, double? amount, FoodUnit? unit, PortionSize? size, MyDish? mine) {
  FoodUnit u;
  double qty;
  if (unit == null) {
    u = dish.unit;
    final n = num ?? 1;
    // "150 paneer" means grams; "2 paneer" means two 100 g portions.
    qty = dish.unit == FoodUnit.gm ? (n >= 20 ? n : n * 100) : n;
  } else if (unit == FoodUnit.gm && num == null) {
    u = dish.unit;
    qty = dish.defaultQty;
  } else {
    u = unit;
    qty = num ?? 1;
  }
  qty *= amount ?? 1;
  // A volume unit on a piece food ("1 katori idli") just counts pieces.
  if (u.isVolume && !dish.unit.isVolume && dish.unit != FoodUnit.gm) u = dish.unit;
  return PlateItem(dish: dish, qty: qty, unit: u, size: size, mine: mine);
}

/* ------------------------------------------------------------------ nutrition */

/// How many of the dish's base units a row amounts to.
double baseUnits(PlateItem it, {PortionSize katori = PortionSize.m}) {
  final d = it.dish;
  final size = it.size ?? it.mine?.size ?? (d.unit == FoodUnit.katori ? katori : PortionSize.m);
  switch (it.unit) {
    case FoodUnit.gm:
      return it.qty / d.grams;
    case FoodUnit.katori:
    case FoodUnit.cup:
    case FoodUnit.glass:
      if (!d.unit.isVolume && d.unit != FoodUnit.gm) return it.qty;
      final ml = it.unit == FoodUnit.katori ? kKatoriMl[size]! : it.unit == FoodUnit.cup ? kCupMl : kGlassMl;
      return it.qty * ml / d.grams;
    case FoodUnit.tsp:
    case FoodUnit.tbsp:
      if (it.unit == d.unit) return it.qty;
      return it.qty * (it.unit == FoodUnit.tsp ? 5 : 15) / d.grams;
    case FoodUnit.piece:
      if (d.unit == FoodUnit.piece) return it.qty * kPieceSize[size]!;
      return it.qty;
    case FoodUnit.scoop:
    case FoodUnit.handful:
    case FoodUnit.slice:
      return it.qty;
  }
}

/// The oil level actually applied to a row.
OilLevel effectiveOil(PlateItem it, {bool bahar = false}) => it.oil ?? (bahar ? OilLevel.rich : (it.mine?.oil ?? OilLevel.normal));

typedef Nutrition = ({double kcal, double protein});

/// kcal and protein of one tray row.
Nutrition itemNutrition(PlateItem it, {bool bahar = false, PortionSize katori = PortionSize.m}) {
  final d = it.dish;
  final units = baseUnits(it, katori: katori);
  final perKcal = it.mine?.kcal ?? d.kcal;
  final perProtein = it.mine?.protein ?? d.protein;
  final oilExtra = d.cooked ? d.oilTsp * (effectiveOil(it, bahar: bahar).factor - 1) * kOilKcalPerTsp : 0.0;
  return (kcal: math.max(0, units * (perKcal + oilExtra)).toDouble(), protein: units * perProtein);
}

/// Sum of a tray.
Nutrition plateTotals(Iterable<PlateItem> items, {bool bahar = false, PortionSize katori = PortionSize.m}) {
  var k = 0.0;
  var p = 0.0;
  for (final it in items) {
    final n = itemNutrition(it, bahar: bahar, katori: katori);
    k += n.kcal;
    p += n.protein;
  }
  return (kcal: k, protein: p);
}

/* ------------------------------------------------------------------ labels */

/// 0.5 → "½", 1.5 → "1½", 2 → "2", 0.33 → "0.3".
String fmtQty(double q) {
  final whole = q.truncate();
  final frac = q - whole;
  String f(double x) => (x - 0.5).abs() < 0.01
      ? '½'
      : (x - 0.25).abs() < 0.01
          ? '¼'
          : (x - 0.75).abs() < 0.01
              ? '¾'
              : '';
  if (frac.abs() < 0.01) return '$whole';
  final sym = f(frac);
  if (sym.isNotEmpty) return whole == 0 ? sym : '$whole$sym';
  return q.toStringAsFixed(1);
}

/// "×2", "1 katori (M)", "½ katori", "150 g", "1 glass".
String qtyLabel(PlateItem it, {PortionSize katori = PortionSize.m}) {
  final q = fmtQty(it.qty);
  switch (it.unit) {
    case FoodUnit.piece:
      final size = it.size ?? it.mine?.size;
      return '×$q${size != null && size != PortionSize.m ? ' · ${size.label.toLowerCase()}' : ''}';
    case FoodUnit.gm:
      return '${it.qty.round()} g';
    case FoodUnit.katori:
      final size = it.size ?? it.mine?.size ?? katori;
      return '$q katori (${size.id})';
    default:
      final plural = it.qty > 1 && it.unit != FoodUnit.tsp && it.unit != FoodUnit.tbsp ? (it.unit == FoodUnit.glass ? 'es' : 's') : '';
      return '$q ${it.unit.short}$plural';
  }
}

/// Short text for a whole tray, used as the meal log label ("Roti ×2 · Dal 1 katori (M) · Ghee ½ tsp").
String plateLabel(Iterable<PlateItem> items, {PortionSize katori = PortionSize.m}) =>
    items.map((it) => '${it.displayName} ${qtyLabel(it, katori: katori)}').join(' · ');

/// Converts a row to another unit, keeping the amount of food the same.
PlateItem convertUnit(PlateItem it, FoodUnit to, {PortionSize katori = PortionSize.m}) {
  if (to == it.unit) return it;
  final units = baseUnits(it, katori: katori);
  final probe = PlateItem(dish: it.dish, qty: 1, unit: to, size: it.size, mine: it.mine);
  final per = baseUnits(probe, katori: katori);
  if (per <= 0) return it;
  var q = units / per;
  final step = to == FoodUnit.gm ? 5.0 : to == it.dish.unit ? it.dish.qtyStep : 0.5;
  q = math.max(step, (q / step).round() * step);
  return it.copyWith(qty: q, unit: to, edited: true);
}

/// Units offered on a row's unit chip.
List<FoodUnit> unitOptions(Dish d) => {
      d.unit,
      if (d.unit.isVolume || d.unit == FoodUnit.gm) FoodUnit.katori,
      if (d.unit != FoodUnit.tsp && d.unit != FoodUnit.tbsp) FoodUnit.gm,
      if (d.unit == FoodUnit.tsp) FoodUnit.tbsp,
    }.toList();
