// Port of src/domain/coach.ts. Pure Dart.
import 'diet.dart';
import 'models.dart';

enum DietCardKind with Wire {
  onTrack('on_track'),
  keepGoing('keep_going'),
  stalled('stalled'),
  adherence('adherence'),
  eatMore('eat_more');

  const DietCardKind(this.wire);
  @override
  final String wire;
  static DietCardKind parse(Object? s) => parseWire(values, s, DietCardKind.keepGoing);

  /// The meal edit this card can apply, if any (stalled / eat_more).
  MealChangeKind? get mealChangeKind => switch (this) {
        DietCardKind.stalled => MealChangeKind.stalled,
        DietCardKind.eatMore => MealChangeKind.eatMore,
        _ => null,
      };
}

class DietCard {
  const DietCard({
    required this.kind,
    required this.title,
    required this.body,
    required this.kcalDelta,
    required this.applicable,
    this.floorWarning,
  });
  final DietCardKind kind;
  final String title;
  final String body;
  final int kcalDelta;
  final bool applicable;
  final bool? floorWarning;

  @override
  String toString() => 'DietCard(${kind.wire}, $title, kcalDelta: $kcalDelta)';
}

/// Diet adjustment coach (doc 06 §6). [checks] are weekly-loss values (kg/week, oldest first),
/// computed from consecutive valid weekly averages. Needs ≥ 14 days of data.
/// [rate] defaults to the last check; [adherence] (0–100, as from adherencePct) defaults to 0.
DietCard? dietAdjustment({
  required int daysOfData,
  required List<double> checks,
  double? rate,
  int? adherence,
  required int liftsDown,
  required Sex sex,
  required num kcalTarget,
  required bool riceReduced,
}) {
  final adh = adherence ?? 0;
  if (daysOfData < 14) return null;
  final r = rate ?? (checks.isEmpty ? null : checks.last);
  if (r == null) return null;

  if (r > 1.0 || liftsDown >= 2) {
    return DietCard(
      kind: DietCardKind.eatMore,
      title: 'Eat a bit more',
      body: riceReduced
          ? 'You are losing fast or strength is slipping. Put lunch rice back to 100 g (≈ +65 kcal).'
          : 'You are losing fast or strength is slipping. Add 1 slice of multigrain toast at breakfast (≈ +70 kcal).',
      kcalDelta: riceReduced ? 65 : 70,
      applicable: true,
    );
  }
  final last2 = checks.length <= 2 ? checks : checks.sublist(checks.length - 2);
  final stalled2 = last2.length == 2 && last2.every((c) => c < 0.3);
  if (r < 0.3 && adh < 80) {
    return DietCard(
      kind: DietCardKind.adherence,
      title: 'Adherence first',
      body: 'You hit $adh% of meals. Get that to 80%+ before cutting anything.',
      kcalDelta: 0,
      applicable: false,
    );
  }
  if (stalled2 && adh >= 80) {
    final next = kcalTarget - 65;
    return DietCard(
      kind: DietCardKind.stalled,
      title: 'Progress has stalled',
      body: riceReduced
          ? 'Add 2,000 steps/day. Rice is already at 50 g, so keep steps up before cutting further.'
          : 'Add 2,000 steps/day first. If still stuck next check: lunch rice → 50 g (≈ −65 kcal).',
      kcalDelta: riceReduced ? 0 : -65,
      applicable: !riceReduced,
      floorWarning: next < kcalFloor(sex),
    );
  }
  if (r >= 0.5 && r <= 0.75) {
    return const DietCard(
      kind: DietCardKind.onTrack,
      title: 'On track ✅',
      body: 'Weekly average loss is in the sweet spot. No change.',
      kcalDelta: 0,
      applicable: false,
    );
  }
  return DietCard(
    kind: DietCardKind.keepGoing,
    title: 'Keep going',
    body: 'Losing ${r.toStringAsFixed(2)} kg/week. Stay consistent and check again in 2 weeks.',
    kcalDelta: 0,
    applicable: false,
  );
}
