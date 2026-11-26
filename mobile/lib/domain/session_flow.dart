// Port of src/domain/sessionFlow.ts. Pure Dart.
// Session sequencing: supersets alternate A1 → A2 → A1 … (doc 02 §3.3).

/// One exercise in the session, as far as sequencing cares.
typedef FlowExercise = ({int sets, String? supersetGroup});

/// One set of one exercise: `ex` is the exercise index, `set` the 0-based set index.
typedef Step = ({int ex, int set});

/// Order every set of the session. Consecutive exercises sharing a superset group
/// alternate set by set; an empty group string counts as "no group" (JS falsy).
List<Step> buildFlow(List<FlowExercise> exs) {
  final steps = <Step>[];
  var i = 0;
  while (i < exs.length) {
    final g = exs[i].supersetGroup;
    var j = i + 1;
    if (g != null && g.isNotEmpty) {
      while (j < exs.length && exs[j].supersetGroup == g) {
        j++;
      }
    }
    final block = [for (var k = i; k < j; k++) (idx: k, sets: exs[k].sets)];
    final maxSets = block.map((b) => b.sets).reduce((a, b) => a > b ? a : b);
    for (var s = 0; s < maxSets; s++) {
      for (final b in block) {
        if (s < b.sets) steps.add((ex: b.idx, set: s));
      }
    }
    i = j;
  }
  return steps;
}

/// Stable string key for a step: `"ex:set"`.
String stepKey(Step s) => '${s.ex}:${s.set}';

/// Next pending step after [from] (wrapping), or null if everything is done.
/// Without [from] (or if it isn't in the flow) the search starts at the first step.
Step? nextStep(List<Step> flow, Set<String> done, {Step? from}) {
  final start = from == null ? -1 : flow.indexWhere((s) => s.ex == from.ex && s.set == from.set);
  for (var k = 1; k <= flow.length; k++) {
    final s = flow[(start + k + flow.length) % flow.length];
    if (!done.contains(stepKey(s))) return s;
  }
  return null;
}
