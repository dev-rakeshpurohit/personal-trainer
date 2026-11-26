import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/coach.dart';
import 'package:repmate/domain/diet.dart';
import 'package:repmate/domain/models.dart';

// coach.ts has no TS test of its own (its cases live in diet.test.ts and are ported in
// diet_test.dart). These cover each rule of dietAdjustment (doc 06 §6) and its precedence.
DietCard? adj({
  int daysOfData = 21,
  List<double> checks = const [],
  double? rate,
  int? adherence = 90,
  int liftsDown = 0,
  Sex sex = Sex.male,
  num kcalTarget = 2000,
  bool riceReduced = false,
}) =>
    dietAdjustment(
      daysOfData: daysOfData,
      checks: checks,
      rate: rate,
      adherence: adherence,
      liftsDown: liftsDown,
      sex: sex,
      kcalTarget: kcalTarget,
      riceReduced: riceReduced,
    );

void main() {
  group('data requirements', () {
    test('needs at least 14 days of data', () {
      expect(adj(daysOfData: 13, checks: [0.6]), isNull);
      expect(adj(daysOfData: 14, checks: [0.6])?.kind, DietCardKind.onTrack);
    });
    test('no checks and no rate → null', () => expect(adj(), isNull));
    test('explicit rate overrides the last check', () {
      expect(adj(checks: [0.1], rate: 0.6)?.kind, DietCardKind.onTrack);
      expect(adj(rate: 0.6)?.kind, DietCardKind.onTrack);
    });
  });

  group('eat more', () {
    test('rate > 1.0 kg/week, toast when rice is not reduced', () {
      final c = adj(checks: [1.01])!;
      expect(c.kind, DietCardKind.eatMore);
      expect(c.kcalDelta, 70);
      expect(c.applicable, isTrue);
      expect(c.body, contains('multigrain toast'));
      expect(c.floorWarning, isNull);
    });
    test('exactly 1.0 kg/week is not too fast', () => expect(adj(checks: [1.0])?.kind, DietCardKind.keepGoing));
    test('rice back to 100 g when rice is reduced', () {
      final c = adj(checks: [1.2], riceReduced: true)!;
      expect(c.kcalDelta, 65);
      expect(c.body, contains('rice back to 100 g'));
    });
    test('2+ lifts down beats everything, even poor adherence and a stall', () {
      expect(adj(checks: [0.1, 0.1], adherence: 10, liftsDown: 2)?.kind, DietCardKind.eatMore);
      expect(adj(checks: [0.6], liftsDown: 1)?.kind, DietCardKind.onTrack);
    });
  });

  group('adherence first', () {
    test('slow loss with < 80% adherence', () {
      final c = adj(checks: [0.29], adherence: 79)!;
      expect(c.kind, DietCardKind.adherence);
      expect(c.body, 'You hit 79% of meals. Get that to 80%+ before cutting anything.');
      expect(c.kcalDelta, 0);
      expect(c.applicable, isFalse);
    });
    test('missing adherence counts as 0%', () {
      expect(adj(checks: [0.1], adherence: null)?.body, startsWith('You hit 0% of meals.'));
    });
    test('not shown when losing ≥ 0.3', () => expect(adj(checks: [0.3], adherence: 10)?.kind, DietCardKind.keepGoing));
  });

  group('stalled', () {
    test('needs two consecutive checks < 0.3 and ≥ 80% adherence', () {
      final c = adj(checks: [0.6, 0.2, 0.1], adherence: 80)!;
      expect(c.kind, DietCardKind.stalled);
      expect(c.kcalDelta, -65);
      expect(c.applicable, isTrue);
      expect(c.floorWarning, isFalse);
      expect(adj(checks: [0.1], adherence: 90)?.kind, DietCardKind.keepGoing);
      expect(adj(checks: [0.3, 0.1], adherence: 90)?.kind, DietCardKind.keepGoing);
    });
    test('rice already reduced → steps only, not applicable', () {
      final c = adj(checks: [0.2, 0.1], riceReduced: true)!;
      expect(c.kind, DietCardKind.stalled);
      expect(c.kcalDelta, 0);
      expect(c.applicable, isFalse);
      expect(c.body, contains('Rice is already at 50 g'));
    });
    test('floor warning uses the sex-specific floor', () {
      expect(adj(checks: [0.1, 0.1], kcalTarget: 1764)?.floorWarning, isTrue);
      expect(adj(checks: [0.1, 0.1], kcalTarget: 1765)?.floorWarning, isFalse);
      expect(adj(checks: [0.1, 0.1], kcalTarget: 1450, sex: Sex.female)?.floorWarning, isTrue);
      expect(adj(checks: [0.1, 0.1], kcalTarget: 1465, sex: Sex.female)?.floorWarning, isFalse);
    });
  });

  group('on track / keep going', () {
    test('0.5–0.75 kg/week inclusive is on track', () {
      expect(adj(checks: [0.5])?.kind, DietCardKind.onTrack);
      expect(adj(checks: [0.75])?.kind, DietCardKind.onTrack);
      expect(adj(checks: [0.6])?.title, 'On track ✅');
    });
    test('otherwise keep going, with the rate to 2 decimals', () {
      final c = adj(checks: [0.4])!;
      expect(c.kind, DietCardKind.keepGoing);
      expect(c.body, 'Losing 0.40 kg/week. Stay consistent and check again in 2 weeks.');
      expect(adj(checks: [0.8])?.body, startsWith('Losing 0.80 kg/week.'));
      expect(adj(checks: [-0.25])?.body, startsWith('Losing -0.25 kg/week.'));
    });
  });

  group('kinds', () {
    test('wire values match the web app', () {
      expect(DietCardKind.values.map((k) => k.wire).toList(), ['on_track', 'keep_going', 'stalled', 'adherence', 'eat_more']);
      expect(DietCardKind.parse('eat_more'), DietCardKind.eatMore);
    });
    test('maps to the meal change kind', () {
      expect(DietCardKind.stalled.mealChangeKind, MealChangeKind.stalled);
      expect(DietCardKind.eatMore.mealChangeKind, MealChangeKind.eatMore);
      expect(DietCardKind.onTrack.mealChangeKind, isNull);
    });
  });
}
