// Pure helpers for the gym-floor logger: target lines, plate maths, steps, effort → RIR,
// swap ranking and the narrated summary. No Flutter imports, so all of it is unit-testable.
import '../../data/services/session_service.dart' show SetValues;
import '../../domain/equipment.dart' as eq;
import '../../domain/models.dart';
import '../../domain/progression.dart' as prog;
import '../../domain/units.dart';

/* ------------------------------------------------------------------ targets */

String _range(int a, int b) => a == b ? '$b' : '$a–$b';

/// "8–10", "30–45 s", "20 min", "500 m", with "/ side".
String repsLabel(SessionExercise se) {
  final suffix = switch (se.unit) {
    Unit.reps => '',
    Unit.seconds => ' s',
    Unit.minutes => ' min',
    Unit.meters => ' m',
  };
  return '${_range(se.repsMin, se.repsMax)}$suffix${se.perSide ? ' / side' : ''}';
}

/// "4 × 8–10 @ 2 left" (sets × range, then the target reps-in-reserve when the plan has one).
String targetLine(SessionExercise se, int totalSets) {
  final rir = se.rir == null || se.unit != Unit.reps ? '' : (se.rir == 0 ? ' · to the limit' : ' @ ${se.rir} left');
  return '$totalSets × ${repsLabel(se)}$rir';
}

/// Copy for an exercise with no history (calibration set).
String calibrationCopy(SessionExercise se) {
  if (se.unit != Unit.reps) return 'First time: start easy and note what felt right.';
  final stop = se.repsMax;
  return 'Find a weight you could do ${stop + 2} times; stop at $stop.';
}

/* ------------------------------------------------------------------ values */

String _w(double kg, String units) => '${displayWeight(kg, units)} $units';

/// One set's values as shown in rows and toasts: "80 kg × 8", "45 s", "45 s · 10 kg", "12 reps".
String setText(SetValues v, Unit unit, String units, {bool bodyweight = false}) {
  final w = !bodyweight && v.weightKg != null && v.weightKg! > 0 ? v.weightKg : null;
  switch (unit) {
    case Unit.reps:
      final r = v.reps ?? 0;
      return w == null ? '$r reps' : '${_w(w, units)} × $r';
    case Unit.seconds:
      final s = '${v.seconds ?? 0} s';
      return w == null ? s : '$s · ${_w(w, units)}';
    case Unit.minutes:
      final m = '${((v.seconds ?? 0) / 60).round()} min';
      return w == null ? m : '$m · ${_w(w, units)}';
    case Unit.meters:
      final m = '${jsNumLike(v.meters ?? 0)} m';
      return w == null ? m : '$m · ${_w(w, units)}';
  }
}

/// Short form for "Next: 80 × 8" (no unit on the weight).
String shortSetText(SetValues v, Unit unit, String units, {bool bodyweight = false}) {
  final w = !bodyweight && v.weightKg != null && v.weightKg! > 0 ? displayWeight(v.weightKg, units) : null;
  return switch (unit) {
    Unit.reps => w == null ? '${v.reps ?? 0} reps' : '$w × ${v.reps ?? 0}',
    Unit.seconds => '${v.seconds ?? 0} s',
    Unit.minutes => '${((v.seconds ?? 0) / 60).round()} min',
    Unit.meters => '${jsNumLike(v.meters ?? 0)} m',
  };
}

String jsNumLike(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

SetValues valuesOf(SetLog s) => SetValues(weightKg: s.weightKg, reps: s.reps, seconds: s.seconds, meters: s.meters, rir: s.rir);

/* ------------------------------------------------------------------ implements & plates */

enum Implement { barbell, dumbbells, singleDumbbell, other }

final _single = RegExp(r'goblet|single|one[- ]arm|1[- ]arm|one[- ]hand|suitcase', caseSensitive: false);
final _barName = RegExp(r'barbell|e-z|ez bar', caseSensitive: false);

/// What the logged weight is loaded on: a 20 kg barbell (per-side plates), one or two dumbbells.
Implement implementOf(Exercise? ex) {
  if (ex == null || ex.isBodyweight == true) return Implement.other;
  final req = eq.requiredEquipment(ex);
  if (req.contains(eq.Equip.trapBar)) return Implement.other;
  if (req.contains(eq.Equip.barbell) || _barName.hasMatch(ex.name)) return Implement.barbell;
  if (req.contains(eq.Equip.dumbbells)) return _single.hasMatch(ex.name) ? Implement.singleDumbbell : Implement.dumbbells;
  return Implement.other;
}

const kKgPlates = [20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const kLbPlates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];
const kBarKg = 20.0;
const kBarLb = 45.0;

/// Plates per side (greedy, largest first) for [total] on a [bar]. Null when below the bar.
/// [exact] is false when the plates can't make the weight exactly.
({List<double> plates, bool exact})? platesPerSide(double total, {double bar = kBarKg, List<double> plates = kKgPlates}) {
  if (total + 1e-9 < bar) return null;
  var side = (total - bar) / 2;
  final out = <double>[];
  for (final p in plates) {
    while (side + 1e-9 >= p) {
      out.add(p);
      side -= p;
    }
  }
  return (plates: out, exact: side.abs() < 0.01);
}

/// "Per side: 20 + 5 + 2.5" (kg plates on a 20 kg bar; lb plates on a 45 lb bar), "Just the bar".
String? plateLine(double? weightKg, String units) {
  if (weightKg == null || weightKg <= 0) return null;
  final lb = units == 'lb';
  final total = lb ? toUserUnits(weightKg, 'lb') : weightKg;
  final r = platesPerSide(total, bar: lb ? kBarLb : kBarKg, plates: lb ? kLbPlates : kKgPlates);
  if (r == null) return 'Lighter than the ${lb ? '45 lb' : '20 kg'} bar';
  if (r.plates.isEmpty) return 'Just the bar';
  return 'Per side: ${r.plates.map(jsNumLike).join(' + ')}${r.exact ? '' : ' (closest)'}';
}

/// "2 × 20 kg" / "1 × 16 kg" for dumbbell work (weight is logged per dumbbell).
String? implementLine(Exercise? ex, double? weightKg, String units) => switch (implementOf(ex)) {
      Implement.barbell => plateLine(weightKg, units),
      Implement.dumbbells => weightKg == null || weightKg <= 0 ? null : '2 × ${_w(weightKg, units)} dumbbells',
      Implement.singleDumbbell => weightKg == null || weightKg <= 0 ? null : '1 × ${_w(weightKg, units)} dumbbell',
      Implement.other => null,
    };

/// Stepper step in the user's units: the profile's step for the equipment bucket
/// (barbell steps are half the increment, i.e. the smallest plate pair).
double weightStep(Exercise? ex, StepKg step, String units) {
  final bucket = ex == null ? prog.Equip.dumbbell : prog.equipmentBucket(ex);
  if (units == 'lb') return bucket == prog.Equip.barbell ? 5 : stepFor(ex == null ? step.dumbbell : prog.incrementFor(ex, step), 'lb');
  return switch (bucket) {
    prog.Equip.barbell => step.barbell / 2,
    prog.Equip.machine => step.machine,
    prog.Equip.dumbbell => step.dumbbell,
  };
}

/// Weight increment (kg) used for calibration nudges.
double incrementKg(Exercise? ex, StepKg step) => ex == null ? step.dumbbell : prog.incrementFor(ex, step);

/* ------------------------------------------------------------------ effort */

/// The four-word effort question asked during rest, stored as reps in reserve.
enum Effort {
  easy('Easy', 4),
  twoLeft('2 left', 2),
  oneLeft('1 left', 1),
  max('Max', 0);

  const Effort(this.label, this.rir);
  final String label;
  final int rir;

  static Effort? ofRir(int? rir) {
    if (rir == null) return null;
    if (rir >= 3) return Effort.easy;
    if (rir == 2) return Effort.twoLeft;
    if (rir == 1) return Effort.oneLeft;
    return Effort.max;
  }
}

/// Calibration nudge for the next set after an effort answer: +increment when easy, −increment at max.
double? calibratedWeight(Effort e, double? weightKg, double incrementKg) {
  if (weightKg == null || weightKg <= 0) return null;
  return switch (e) {
    Effort.easy => weightKg + incrementKg,
    Effort.max => (weightKg - incrementKg).clamp(0, double.infinity).toDouble(),
    _ => null,
  };
}

/* ------------------------------------------------------------------ swap */

enum SwapReason {
  busy('Busy'),
  notInGym('Not in my gym'),
  hurts('Hurts'),
  change('Want a change');

  const SwapReason(this.label);
  final String label;
}

class SwapOption {
  const SwapOption({required this.exercise, required this.reason});
  final Exercise exercise;

  /// One plain-English line explaining why this alternative fits.
  final String reason;
}

final _odd = RegExp(r'exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|self assisted|pirate', caseSensitive: false);
final _steady = RegExp(r'machine|cable|smith|supported|seated|chest-supported', caseSensitive: false);

String _equipLabel(List<String> ids) {
  if (ids.isEmpty) return 'no equipment';
  final names = [
    for (final id in ids)
      (eq.kEquipment.where((o) => o.id == id).map((o) => o.label).firstOrNull ?? id.replaceAll('_', ' ')).toLowerCase().replaceAll('adjustable ', ''),
  ];
  return names.join(' + ');
}

/// Three ranked alternatives for the exercise in a slot: the plan's backup, the exercise's researched
/// alternates and same-pattern library exercises, filtered by the user's equipment and scored for
/// the reason the lifter gave.
List<SwapOption> rankAlternatives({
  required Exercise original,
  required String currentId,
  required Map<String, Exercise> library,
  required List<String> equipment,
  required SwapReason reason,
  String? planSwapId,
  Set<String> exclude = const {},
  int limit = 3,
}) {
  final target = original.level ?? 2;
  final current = library[currentId] ?? original;
  final currentReq = eq.requiredEquipment(current).toSet();
  final scored = <String, ({Exercise e, double score, String? tag})>{};

  void consider(Exercise? e, double base, {String? tag}) {
    if (e == null || e.id == currentId || exclude.contains(e.id) || scored.containsKey(e.id)) return;
    if (!eq.isAvailable(e, equipment)) return;
    final req = eq.requiredEquipment(e).toSet();
    final dl = (e.level ?? target) - target;
    var s = base + (e.defaultUnit == original.defaultUnit ? 0 : 3) + (_odd.hasMatch(e.name) ? 4 : 0);
    final sameKit = req.isNotEmpty && req.length == currentReq.length && req.containsAll(currentReq);
    switch (reason) {
      case SwapReason.busy:
      case SwapReason.notInGym:
        s += dl.abs() + (sameKit ? 3 : 0) + (req.isEmpty ? -0.5 : 0);
      case SwapReason.hurts:
        s += dl > 0 ? dl * 3 : dl.abs() * 0.5;
        if (_steady.hasMatch(e.name) || req.contains(eq.Equip.machines) || req.contains(eq.Equip.cable)) s -= 1;
      case SwapReason.change:
        s += dl.abs() + (sameKit ? 1 : 0);
    }
    scored[e.id] = (e: e, score: s, tag: tag);
  }

  if (currentId != original.id) consider(original, -5, tag: 'Back to your planned exercise');
  if (planSwapId != null) consider(library[planSwapId], reason == SwapReason.change ? 0 : -2, tag: "Your plan's backup for this slot");
  final alts = original.alternates ?? const <String>[];
  for (var i = 0; i < alts.length; i++) {
    consider(library[alts[i]], i * 0.3);
  }
  if (original.pattern != null) {
    for (final e in library.values) {
      if (e.pattern == original.pattern) consider(e, 2 + (e.source == 'dataset' ? 1 : 0));
    }
  }
  final ranked = scored.values.toList()
    ..sort((a, b) {
      final c = a.score.compareTo(b.score);
      return c != 0 ? c : eq.jsLocaleCompare(a.e.name, b.e.name);
    });
  return [
    for (final r in ranked.take(limit)) SwapOption(exercise: r.e, reason: _swapReason(r.e, current, target, reason, r.tag)),
  ];
}

String _swapReason(Exercise e, Exercise current, int target, SwapReason why, String? tag) {
  final req = eq.requiredEquipment(e);
  final curReq = eq.requiredEquipment(current).toSet();
  final parts = <String>[];
  if (tag != null) parts.add(tag);
  if (req.isEmpty) {
    parts.add(why == SwapReason.busy ? 'no kit to wait for' : 'no equipment needed');
  } else if (!(req.length == curReq.length && curReq.containsAll(req))) {
    parts.add('uses ${_equipLabel(req)}');
  } else {
    parts.add('same equipment');
  }
  final dl = (e.level ?? target) - target;
  if (why == SwapReason.hurts && dl <= 0) {
    parts.add(_steady.hasMatch(e.name) ? 'steadier, easier on joints' : 'gentler on joints');
  } else if (dl < 0) {
    parts.add('a step easier');
  } else if (dl > 0) {
    parts.add('a step harder');
  } else {
    parts.add('same difficulty');
  }
  final s = parts.join(' · ');
  return s[0].toUpperCase() + s.substring(1);
}

/* ------------------------------------------------------------------ summary narration */

/// Best set of an exercise: heaviest, then most reps (or longest / furthest for timed work).
SetLog? topSet(List<SetLog> sets) {
  SetLog? best;
  for (final s in sets) {
    if (best == null) {
      best = s;
      continue;
    }
    final bw = best.weightKg ?? 0, sw = s.weightKg ?? 0;
    final bv = (best.reps ?? 0) + (best.seconds ?? 0) + (best.meters ?? 0);
    final sv = (s.reps ?? 0) + (s.seconds ?? 0) + (s.meters ?? 0);
    if (sw > bw || (sw == bw && sv > bv)) best = s;
  }
  return best;
}

/// "Bench press 40 kg × 10 — next time 42.5." The short plain-English line per exercise.
String narrateExercise({
  required String name,
  required SetLog top,
  required Unit unit,
  required String units,
  bool bodyweight = false,
  prog.Suggestion? next,
}) {
  final did = '$name ${setText(valuesOf(top), unit, units, bodyweight: bodyweight)}';
  if (next == null) return '$did.';
  switch (next.kind) {
    case prog.SuggestionKind.increase:
      return '$did — next time ${displayWeight(next.weightKg, units)}.';
    case prog.SuggestionKind.timeIncrease:
      final s = next.prefill.isEmpty ? null : next.prefill.first.seconds;
      return s == null ? '$did — hold a little longer next time.' : '$did — next time hold $s s.';
    case prog.SuggestionKind.decrease:
      return '$did — next time ease to ${displayWeight(next.weightKg, units)} and own the reps.';
    case prog.SuggestionKind.hold:
    case prog.SuggestionKind.timeCap:
    case prog.SuggestionKind.first:
      return '$did — same again next time, chase one more rep.';
  }
}

/// Closing line of the narrated summary.
String closingLine({required int ordinal, required int prCount, required bool allDone}) {
  if (ordinal == 1) return 'Great start!';
  if (prCount > 0) return 'Strong session: new bests today.';
  if (!allDone) return 'Some is always better than none. Well done.';
  return 'Solid work. Consistency builds results.';
}

/// "1st", "2nd", "3rd", "11th" …
String ordinalSuffix(int n) {
  final t = n % 100;
  if (t >= 11 && t <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

/* ------------------------------------------------------------------ form cues */

final _sentence = RegExp(r'(?<=[.!?])\s+');

/// Two or three short form cues: the plan's cue first (trainer/coach), then the exercise's own
/// cue and instructions, split into sentences and de-duplicated.
List<String> formCues(SessionExercise se, Exercise? ex, {int max = 3}) {
  final out = <String>[];
  for (final src in [se.cue, ex?.cue, ...?ex?.instructions]) {
    if (src == null) continue;
    for (final raw in src.split(_sentence)) {
      final t = raw.trim();
      if (t.length < 4 || t.length > 120) continue;
      if (out.any((o) => o.toLowerCase() == t.toLowerCase())) continue;
      out.add(t);
      if (out.length >= max) return out;
    }
  }
  return out;
}
