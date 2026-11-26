// Port of src/domain/equipment.ts. Gym equipment model: what each exercise needs, what's
// available, and plan substitution. Pure Dart.
import 'models.dart';

/// Equipment ids (wire values, same strings as the web app's `EquipmentId`).
abstract final class Equip {
  static const dumbbells = 'dumbbells';
  static const barbell = 'barbell';
  static const trapBar = 'trap_bar';
  static const kettlebells = 'kettlebells';
  static const cable = 'cable';
  static const machines = 'machines';
  static const bench = 'bench';
  static const pullupBar = 'pullup_bar';
  static const bands = 'bands';
  static const medicineBall = 'medicine_ball';
  static const box = 'box';
  static const cardioMachines = 'cardio_machines';
  static const stabilityBall = 'stability_ball';
  static const sled = 'sled';
}

class EquipmentOption {
  const EquipmentOption(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;
}

const List<EquipmentOption> kEquipment = [
  EquipmentOption('dumbbells', 'Dumbbells', 'A rack of fixed or adjustable dumbbells'),
  EquipmentOption('bench', 'Adjustable bench', 'Flat / incline'),
  EquipmentOption('barbell', 'Barbell + plates', 'Includes EZ bar, squat rack'),
  EquipmentOption('trap_bar', 'Trap / hex bar', ''),
  EquipmentOption('kettlebells', 'Kettlebells', ''),
  EquipmentOption('cable', 'Cable station', 'Pulley with handles / rope'),
  EquipmentOption('machines', 'Machines', 'Leg press, lat pulldown, rows…'),
  EquipmentOption('pullup_bar', 'Pull-up bar', 'Or captain’s chair'),
  EquipmentOption('bands', 'Resistance bands', ''),
  EquipmentOption('medicine_ball', 'Medicine ball', ''),
  EquipmentOption('box', 'Plyo box / step', ''),
  EquipmentOption('cardio_machines', 'Cardio machines', 'Bike, treadmill, rower, cross-trainer'),
  EquipmentOption('stability_ball', 'Stability ball', ''),
  EquipmentOption('sled', 'Sled', ''),
];

/// Equipment presets, keyed `full_gym` | `dumbbells_only` | `home`.
const Map<String, List<String>> kPresets = {
  'full_gym': [
    'dumbbells', 'bench', 'barbell', 'trap_bar', 'kettlebells', 'cable', 'machines', 'pullup_bar', //
    'bands', 'medicine_ball', 'box', 'cardio_machines', 'stability_ball',
  ],
  'dumbbells_only': ['dumbbells', 'bench', 'bands'],
  'home': ['bands'],
};

RegExp _re(String p) => RegExp(p);

final _cardioName = _re(r'bike|cycling|bicycl|treadmill|rower|rowing machine|rowing,|elliptical|cross-?trainer|stair|stepmill|ergometer|assault|airdyne|ski erg');
final _reDumbbell = _re('dumbbell');
final _reBarbell = _re('barbell|e-z|ez bar');
final _reCable = _re('cable');
final _reMachine = _re('machine');
final _reKettlebell = _re('kettlebell');
final _reBand = _re('band');
final _reMedBall = _re('medicine ball');
final _reStability = _re('exercise ball|stability');
final _reTrapBar = _re(r'trap.?bar|hex bar');
final _reOutdoor = _re('walk|outdoor|band');
final _reMachineName =
    _re(r'leg press|hack squat|pulldown|pull-?down|smith|pec deck|leg curl|leg extension|assisted pull-?up machine|chest press machine|glute-ham|calf press');
final _reCableName = _re('cable|woodchop|pallof');
final _reBar = _re(r'pull-?up|chin-?up|hanging|toes to bar');
final _reBarExcept = _re('machine|band-assisted pulldown');
final _reBenchName = _re(r'bench|incline|decline|step-?up|bulgarian|box squat|hip thrust');
final _reBenchSelf = _re(r'bench|step-?up|bulgarian');
final _reBox = _re('box jump|depth jump');
final _reSled = _re('sled|yoke|prowler');
final _reCarry = _re('farmer|suitcase carry');
final _reSlam = _re(r'medicine.?ball|slam');
final _reWordBand = _re(r'\bband');

// Exercise is immutable, so the derived list is cached per instance (the generator calls this a lot).
final _requiredCache = Expando<List<String>>('requiredEquipment');

/// Equipment an exercise needs (empty = bodyweight). Order matches the JS `Set` insertion order.
List<String> requiredEquipment(Exercise ex) => List.of(_requiredCache[ex] ??= List.unmodifiable(_requiredEquipment(ex)));

List<String> _requiredEquipment(Exercise ex) {
  final name = ex.name.toLowerCase();
  final eq = ex.equipment.map((e) => e.toLowerCase());
  final out = <String>{}; // LinkedHashSet: insertion-ordered like JS Set
  for (final e in eq) {
    if (_reDumbbell.hasMatch(e)) {
      out.add(Equip.dumbbells);
    } else if (_reBarbell.hasMatch(e)) {
      out.add(Equip.barbell);
    } else if (_reCable.hasMatch(e)) {
      out.add(Equip.cable);
    } else if (_reMachine.hasMatch(e)) {
      out.add(_cardioName.hasMatch(name) ? Equip.cardioMachines : Equip.machines);
    } else if (_reKettlebell.hasMatch(e)) {
      out.add(Equip.kettlebells);
    } else if (_reBand.hasMatch(e)) {
      out.add(Equip.bands);
    } else if (_reMedBall.hasMatch(e)) {
      out.add(Equip.medicineBall);
    } else if (_reStability.hasMatch(e)) {
      out.add(Equip.stabilityBall);
    }
  }
  if (_reTrapBar.hasMatch(name)) {
    out.remove(Equip.barbell);
    out.add(Equip.trapBar);
  }
  if (_cardioName.hasMatch(name) && !_reOutdoor.hasMatch(name)) {
    out.remove(Equip.machines);
    out.add(Equip.cardioMachines);
  }
  if (_reMachineName.hasMatch(name)) out.add(Equip.machines);
  if (_reCableName.hasMatch(name) && !out.contains(Equip.bands) && !_reBand.hasMatch(name)) out.add(Equip.cable);
  if (_reBar.hasMatch(name) && !_reBarExcept.hasMatch(name)) out.add(Equip.pullupBar);
  if (_reBenchName.hasMatch(name) &&
      (out.contains(Equip.dumbbells) || out.contains(Equip.barbell) || _reBenchSelf.hasMatch(name))) {
    out.add(Equip.bench);
  }
  if (_reBox.hasMatch(name)) out.add(Equip.box);
  if (_reSled.hasMatch(name)) out.add(Equip.sled);
  if (_reCarry.hasMatch(name) && out.isEmpty) out.add(Equip.dumbbells);
  if (_reSlam.hasMatch(name) && out.isEmpty) out.add(Equip.medicineBall);
  if (_reKettlebell.hasMatch(name)) out.add(Equip.kettlebells);
  if (_reDumbbell.hasMatch(name)) out.add(Equip.dumbbells);
  if (_reWordBand.hasMatch(name)) {
    out.remove(Equip.cable);
    out.add(Equip.bands);
  }
  return out.toList();
}

bool isAvailable(Exercise ex, List<String> available) =>
    (_requiredCache[ex] ??= List.unmodifiable(_requiredEquipment(ex))).every(available.contains);

/// Best available replacement: plan swap first, then alternates closest in difficulty and with the same unit.
Exercise? bestReplacement(Exercise original, List<Exercise?> candidates, List<String> available, {List<String> exclude = const []}) {
  final target = original.level ?? 3;
  final ok = [
    for (final c in candidates)
      if (c != null && c.id != original.id && !exclude.contains(c.id) && isAvailable(c, available)) c,
  ];
  Exercise? best;
  double bestScore = double.infinity;
  for (var i = 0; i < ok.length; i++) {
    final c = ok[i];
    final score = ((c.level ?? target) - target).abs() * 2 + (c.defaultUnit == original.defaultUnit ? 0 : 3) + i * 0.01;
    // strict < keeps the earliest on ties, like the stable JS sort + [0]
    if (score < bestScore) {
      best = c;
      bestScore = score;
    }
  }
  return best;
}

enum PlanChangeKind with Wire {
  replaced('replaced'),
  removed('removed'),
  swapReplaced('swap_replaced'),
  swapRemoved('swap_removed');

  const PlanChangeKind(this.wire);
  @override
  final String wire;
}

class PlanChange {
  const PlanChange({required this.plannedExerciseId, required this.from, this.to, required this.kind});
  final String plannedExerciseId;
  final String from;
  final String? to;
  final PlanChangeKind kind;

  @override
  bool operator ==(Object other) =>
      other is PlanChange && other.plannedExerciseId == plannedExerciseId && other.from == from && other.to == to && other.kind == kind;
  @override
  int get hashCode => Object.hash(plannedExerciseId, from, to, kind);
  @override
  String toString() => 'PlanChange($plannedExerciseId, $from → $to, ${kind.wire})';
}

Exercise? _lookup(Map<String, Exercise> exMap, String? id) => (id == null || id.isEmpty) ? null : exMap[id];

/// Make a day's planned exercises fit the available equipment. Returns the edits to apply.
List<PlanChange> adaptToEquipment(List<PlannedExercise> planned, Map<String, Exercise> exMap, List<String> available) {
  final changes = <PlanChange>[];
  for (final pe in planned) {
    final ex = exMap[pe.exerciseId];
    if (ex == null) continue;
    final used = [for (final p in planned) if (p.id != pe.id) p.exerciseId];
    if (!isAvailable(ex, available)) {
      final candidates = [pe.swapExerciseId, ...?ex.alternates].map((id) => _lookup(exMap, id)).toList();
      final rep = bestReplacement(ex, candidates, available, exclude: used);
      changes.add(rep != null
          ? PlanChange(plannedExerciseId: pe.id, from: ex.id, to: rep.id, kind: PlanChangeKind.replaced)
          : PlanChange(plannedExerciseId: pe.id, from: ex.id, kind: PlanChangeKind.removed));
    }
    final swap = _lookup(exMap, pe.swapExerciseId);
    if (swap != null && !isAvailable(swap, available)) {
      String? mainTo;
      for (final c in changes) {
        if (c.plannedExerciseId == pe.id) {
          mainTo = c.to;
          break;
        }
      }
      final main = mainTo ?? pe.exerciseId;
      final rep = bestReplacement(swap, [for (final id in ex.alternates ?? const <String>[]) exMap[id]], available, exclude: [main, ...used]);
      changes.add(rep != null
          ? PlanChange(plannedExerciseId: pe.id, from: swap.id, to: rep.id, kind: PlanChangeKind.swapReplaced)
          : PlanChange(plannedExerciseId: pe.id, from: swap.id, kind: PlanChangeKind.swapRemoved));
    }
  }
  return changes;
}

/* ------------------------------------------------ JS sort semantics (shared by generator & balance) */

/// Stable sort (JS `Array.prototype.sort` is stable; Dart's `List.sort` is not guaranteed to be).
/// The comparator may return any num, like a JS comparator; only its sign is used.
List<T> stableSorted<T>(Iterable<T> items, num Function(T a, T b) compare) {
  final indexed = items.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final c = compare(a.value, b.value);
    if (c < 0) return -1;
    if (c > 0) return 1;
    return a.key - b.key;
  });
  return [for (final e in indexed) e.value];
}

const _punct = "_-‐‑‒–—―,;:!?.…'‘’\"“”()[]{}@*/\\&#%`^";
const _symbols = '+<=>|~\$';

int _primary(int cu) {
  final ch = String.fromCharCode(cu);
  if (ch.trim().isEmpty) return cu; // whitespace first
  final p = _punct.indexOf(ch);
  if (p >= 0) return 100000 + p;
  final s = _symbols.indexOf(ch);
  if (s >= 0) return 200000 + s;
  if (cu >= 0x30 && cu <= 0x39) return 300000 + cu;
  final lower = ch.toLowerCase();
  if (lower != ch.toUpperCase()) return 400000 + lower.codeUnitAt(0); // letters, case-folded
  return 500000 + cu;
}

/// Approximation of JS `a.localeCompare(b)` (ICU root collation) for exercise and day names:
/// whitespace < punctuation < symbols < digits < letters, compared case-insensitively first,
/// then lowercase before uppercase as the tie-break. Plain `compareTo` would put every
/// uppercase letter before every lowercase one and differ from the web app's ordering.
int jsLocaleCompare(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final d = _primary(a.codeUnitAt(i)) - _primary(b.codeUnitAt(i));
    if (d != 0) return d < 0 ? -1 : 1;
  }
  if (a.length != b.length) return a.length < b.length ? -1 : 1;
  for (var i = 0; i < n; i++) {
    final ca = a[i], cb = b[i];
    if (ca == cb) continue;
    final la = ca == ca.toLowerCase(), lb = cb == cb.toLowerCase();
    if (la != lb) return la ? -1 : 1;
  }
  return 0;
}
