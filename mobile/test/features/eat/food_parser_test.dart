// The local Hinglish parser and the plate maths behind the review tray.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/features/eat/food_db.dart';
import 'package:repmate/features/eat/food_parser.dart';

void main() {
  List<String> ids(ParseResult r) => r.items.map((i) => i.dish.id).toList();

  test('dish table: about 60+ dishes, unique ids, sane numbers', () {
    expect(allDishes.length, greaterThanOrEqualTo(60));
    expect(kDishes.length, allDishes.length);
    for (final d in allDishes) {
      expect(d.kcal, greaterThanOrEqualTo(0), reason: d.id);
      expect(d.protein, lessThan(60), reason: d.id);
      expect(d.aliases, isNotEmpty, reason: d.id);
    }
  });

  test('"2 roti aur dal, thoda ghee" → roti ×2, dal ×1 katori, ghee ½ tsp', () {
    final r = parseFood('2 roti aur dal, thoda ghee');
    expect(ids(r), ['roti', 'dal', 'ghee']);
    expect(r.items[0].qty, 2);
    expect(r.items[0].unit, FoodUnit.piece);
    expect(r.items[1].qty, 1);
    expect(r.items[1].unit, FoodUnit.katori);
    expect(r.items[2].qty, 0.5);
    expect(r.items[2].unit, FoodUnit.tsp);
    expect(r.unknown, isEmpty);
    final t = plateTotals(r.items);
    // 2 × 105 + 150 + 22.5
    expect(t.kcal, closeTo(382.5, 0.01));
    expect(t.protein, closeTo(15.2, 0.01));
  });

  test('quantity words: thoda = ½, normal = 1, zyada = 1½', () {
    expect(parseFood('thoda chawal').items.single.qty, 0.5);
    expect(parseFood('normal dal').items.single.qty, 1);
    expect(parseFood('zyada rajma').items.single.qty, 1.5);
    expect(parseFood('do anda').items.single.qty, 2);
    expect(parseFood('aadha katori dahi').items.single.qty, 0.5);
  });

  test('units: katori, cup, glass, grams, scoop, trailing quantities', () {
    var r = parseFood('1 katori dal, 100g paneer, 1 scoop whey, 1 glass milk, chai');
    expect(ids(r), ['dal', 'paneer', 'whey', 'milk', 'chai']);
    expect(r.items[1].unit, FoodUnit.gm);
    expect(r.items[1].qty, 100);
    expect(itemNutrition(r.items[1]).protein, closeTo(18, 0.01));
    r = parseFood('roti 3, chawal 1 katori');
    expect(r.items[0].qty, 3);
    expect(r.items[1].qty, 1);
    expect(r.items[1].unit, FoodUnit.katori);
    r = parseFood('roti x2');
    expect(r.items.single.qty, 2);
    r = parseFood('1/2 katori sabzi');
    expect(r.items.single.qty, 0.5);
  });

  test('longest alias wins and plurals resolve', () {
    expect(ids(parseFood('aloo paratha')), ['aloo_paratha']);
    expect(ids(parseFood('paneer butter masala')), ['paneer_curry']);
    expect(ids(parseFood('3 idlis with sambhar')), ['idli', 'sambhar']);
    expect(parseFood('3 idlis with sambhar').items.first.qty, 3);
    expect(ids(parseFood('roasted chana')), ['roasted_chana']);
    expect(ids(parseFood('chicken breast 150g')), ['chicken_breast']);
    expect(parseFood('chicken breast 150g').items.single.qty, 150);
  });

  test('sizes: badi roti is large; katori calibration changes katori maths', () {
    final roti = parseFood('2 badi roti').items.single;
    expect(roti.size, PortionSize.l);
    expect(itemNutrition(roti).kcal, closeTo(2 * 105 * 1.3, 0.01));
    final dal = parseFood('1 katori dal').items.single;
    expect(itemNutrition(dal, katori: PortionSize.s).kcal, closeTo(100, 0.01));
    expect(itemNutrition(dal, katori: PortionSize.l).kcal, closeTo(200, 0.01));
  });

  test('oil: kam tel / dhaba chips and bahar ka raise or lower kcal of cooked dishes only', () {
    final r = parseFood('dal kam tel, 2 roti');
    expect(r.items[0].oil, OilLevel.light);
    expect(r.items[1].oil, isNull, reason: 'roti has no oil');
    expect(itemNutrition(r.items[0]).kcal, closeTo(150 - 20, 0.01));
    final out = parseFood('bahar ka chole bhature');
    expect(out.bahar, isTrue);
    final chole = out.items.firstWhere((i) => i.dish.id == 'chole');
    expect(itemNutrition(chole, bahar: true).kcal, closeTo(240 + 1.5 * 40, 0.01));
    expect(parseFood('ghar ka khana dal').bahar, isFalse);
  });

  test('unknown text is reported, not guessed', () {
    final r = parseFood('2 roti, xyzzy pudding');
    expect(ids(r), ['roti']);
    expect(r.unknown, ['xyzzy pudding']);
  });

  test('"My dal" overrides the table on the next parse', () {
    final mine = {'dal': const MyDish(dishId: 'dal', kcal: 180, protein: 11, oil: OilLevel.light)};
    final dal = parseFood('dal', mine: mine).items.single;
    expect(dal.displayName, 'My dal');
    expect(effectiveOil(dal), OilLevel.light);
    expect(itemNutrition(dal).protein, 11);
    expect(itemNutrition(dal).kcal, closeTo(180 - 20, 0.01));
    final round = MyDish.decodeAll({'dal': mine['dal']!.toJson()});
    expect(round['dal']!.kcal, 180);
    expect(round['dal']!.oil, OilLevel.light);
  });

  test('labels and unit conversion', () {
    final r = parseFood('2 roti aur dal, thoda ghee');
    expect(plateLabel(r.items), 'Roti ×2 · Dal 1 katori (M) · Ghee ½ tsp');
    final g = convertUnit(r.items[1], FoodUnit.gm);
    expect(g.unit, FoodUnit.gm);
    expect(g.qty, 150);
    expect(itemNutrition(g).kcal, closeTo(150, 0.01));
    expect(fmtQty(1.5), '1½');
  });
}
