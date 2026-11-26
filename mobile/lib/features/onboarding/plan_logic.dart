// Pure helpers for "Building your plan", the plan reveal and the first-edit diff.
// Every line shown while building is derived from the real inputs and outputs (no fake loaders).
import '../../domain/ai_plan.dart';
import '../../domain/balance.dart';
import '../../domain/generator.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import 'draft.dart';

String _days(int n) => n == 1 ? '1 day' : '$n days';

/// Why this split: "4 days a week for build muscle → Upper A, Lower A, Upper B, Lower B".
String splitLine(OnboardingDraft d, GenProgram gen) {
  final titles = gen.days.where((x) => x.type.isTraining).map((x) => x.title).toList();
  return '${_days(titles.length)} a week to ${goalLabel(d.goal)} → ${titles.join(', ')}';
}

String sessionLine(OnboardingDraft d) {
  final slots = kSlotsForMinutes[d.sessionMin] ?? 6;
  return '${d.sessionMin} min sessions → up to $slots exercises, supersets where they save time';
}

String equipmentLine(OnboardingDraft d) => d.equipment.isEmpty
    ? 'No equipment → bodyweight moves only'
    : '${d.equipment.length} kinds of equipment → only exercises you can do at your gym';

String? painLine(OnboardingDraft d) {
  final p = d.pain ?? const [];
  if (p.isEmpty) return null;
  return 'Noted: ${p.map(painLabel).join(', ').toLowerCase()}. Tell the coach what hurts and it will swap moves';
}

String dietLine(OnboardingDraft d, int kcal, int protein) =>
    '${dietLabel(d.diet)} meals at about ${_thousands(kcal)} kcal and $protein g protein a day';

String targetsWhy(OnboardingDraft d) =>
    'From your height, weight, age and ${_days(d.days.length)} of training, aimed to ${goalLabel(d.goal)}';

String _thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String thousandsOf(num n) => _thousands(n.round());

/* ------------------------------------------------------------ plan check summary */

class CheckSummary {
  const CheckSummary({required this.covered, required this.total, required this.rows});
  final int covered;
  final int total;
  final List<({MuscleGroup group, double have, int need})> rows;

  String get headline => covered == total
      ? 'Every muscle group gets enough weekly work'
      : '$covered of $total muscle groups get enough weekly work';
}

CheckSummary summariseCheck(PlanCheckResult r) {
  final rows = [for (final g in MuscleGroup.values) (group: g, have: r.sets[g] ?? 0, need: r.targets[g] ?? 0)];
  return CheckSummary(covered: rows.where((x) => x.have >= x.need).length, total: rows.length, rows: rows);
}

PlanCheckResult checkBundle(ProgramBundle b, Map<String, Exercise> exMap, List<Exercise> library, Profile p) => planCheck(
      days: b.days.map(DayLite.of).toList(),
      planned: b.planned,
      exMap: exMap,
      library: library,
      equipment: p.equipment ?? const [],
      goal: p.goal,
    );

/* ------------------------------------------------------------ coach diff */

/// One changed line of a proposal: "Thu · Lower A: − Back squat, + Leg press".
class DiffLine {
  const DiffLine(this.label, this.removed, this.added);
  final String label;
  final List<String> removed;
  final List<String> added;
  bool get isEmpty => removed.isEmpty && added.isEmpty;
}

/// Compare the saved week with a proposed workout, day by day (by weekday), by exercise name.
List<DiffLine> workoutDiff(ProgramBundle current, NormWorkout proposed, Map<String, Exercise> exMap) {
  String name(String id) => exMap[id]?.name ?? id;
  final out = <DiffLine>[];
  for (final wd in Weekday.values) {
    final before = current.days.where((d) => d.weekday == wd).firstOrNull;
    final after = proposed.days.where((d) => d.weekday == wd).firstOrNull;
    final b = before == null ? <String>[] : current.plannedFor(before.id).map((p) => name(p.exerciseId)).toList();
    final a = after == null ? <String>[] : after.exercises.map((e) => name(e.exerciseId)).toList();
    final removed = b.where((x) => !a.contains(x)).toList();
    final added = a.where((x) => !b.contains(x)).toList();
    final beforeTitle = before?.type.isTraining == true ? before!.title : 'Rest';
    final afterTitle = after?.type.isTraining == true ? after!.title : 'Rest';
    final label = beforeTitle == afterTitle ? '${wd.label} · $afterTitle' : '${wd.label} · $beforeTitle → $afterTitle';
    final line = DiffLine(label, removed, added);
    if (!line.isEmpty || beforeTitle != afterTitle) out.add(line);
  }
  return out;
}

/// Diet change as words: "2,100 → 2,250 kcal · 130 → 145 g protein".
String? dietDiff(DietPlan? current, AiDiet? proposed) {
  if (proposed == null) return null;
  final k = proposed.kcalTarget.round();
  final p = proposed.proteinTargetG.round();
  if (current == null) return '${_thousands(k)} kcal · $p g protein';
  final parts = [
    if (current.kcalTarget != k) '${_thousands(current.kcalTarget)} → ${_thousands(k)} kcal',
    if (current.proteinTargetG != p) '${current.proteinTargetG} → $p g protein',
  ];
  return parts.isEmpty ? 'Meals changed, same targets' : parts.join(' · ');
}

/// Does a free-text change mention food? Then the coach is also asked for the diet.
bool mentionsFood(String text) => RegExp(
      r'diet|food|meal|eat|protein|calor|kcal|paneer|egg|chicken|fish|dal|roti|rice|whey|breakfast|lunch|dinner|snack|khana|veg',
      caseSensitive: false,
    ).hasMatch(text);
