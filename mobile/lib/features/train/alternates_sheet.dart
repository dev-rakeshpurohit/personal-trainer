// Alternates for a planned exercise: its plan swap and research alternates that fit the gym,
// then more of the same movement pattern from the library. Resolves to the chosen exercise id.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/equipment.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../library/library_data.dart' show availableEquipmentProvider;

final _odd = RegExp(r'exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|self assisted|pirate', caseSensitive: false);

/// Candidate list (pure): listed alternates that fit, then same-pattern exercises ranked by fit.
({List<Exercise> listed, List<Exercise> more}) alternatesFor(PlannedExercise pe, Map<String, Exercise> exMap, List<String> eq) {
  final orig = exMap[pe.exerciseId];
  final ids = <String>{pe.exerciseId, ?pe.swapExerciseId, ...?orig?.alternates};
  final listed = [
    for (final id in ids)
      if (exMap[id] case final e? when e.id == pe.exerciseId || isAvailable(e, eq)) e,
  ];
  final seen = listed.map((e) => e.id).toSet();
  final target = orig?.level ?? 2;
  final more = orig?.pattern == null
      ? <Exercise>[]
      : (exMap.values.where((e) => e.pattern == orig!.pattern && !seen.contains(e.id) && isAvailable(e, eq)).map((e) => (
            e: e,
            score: (e.source == 'dataset' ? 1 : 0) + (_odd.hasMatch(e.name) ? 4 : 0) + ((e.level ?? target) - target).abs() + (e.defaultUnit == orig!.defaultUnit ? 0 : 3),
          )).toList()
            ..sort((a, b) => a.score != b.score ? a.score.compareTo(b.score) : a.e.name.compareTo(b.e.name)))
          .map((x) => x.e)
          .toList();
  return (listed: listed, more: more);
}

Future<String?> showAlternatesSheet(BuildContext context, PlannedExercise pe) =>
    showRfSheet<String>(context, tall: true, builder: (_) => _AlternatesSheet(pe: pe));

class _AlternatesSheet extends ConsumerStatefulWidget {
  const _AlternatesSheet({required this.pe});
  final PlannedExercise pe;
  @override
  ConsumerState<_AlternatesSheet> createState() => _AlternatesSheetState();
}

class _AlternatesSheetState extends ConsumerState<_AlternatesSheet> {
  int _more = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final exMap = ref.watch(exerciseMapProvider).value ?? const {};
    final eq = ref.watch(availableEquipmentProvider);
    final alts = alternatesFor(widget.pe, exMap, eq);

    Widget row(Exercise e) {
      final current = e.id == widget.pe.exerciseId;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RfCard(
          padding: const EdgeInsets.all(8),
          border: current ? c.accent : null,
          onTap: current ? null : () => Navigator.of(context).pop(e.id),
          semanticLabel: '${e.name}${current ? ', current' : ''}',
          child: Row(children: [
            ExerciseThumb(exercise: e, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: RfType.bodyStrong.copyWith(color: c.text)),
                Text(
                  [if (e.level != null) 'Difficulty ${e.level}/5', if (e.id == widget.pe.swapExerciseId) 'Plan swap', if (current) 'Current'].join(' · '),
                  style: RfType.caption.copyWith(color: c.muted),
                ),
              ]),
            ),
            if (!current) Icon(CupertinoIcons.arrow_right_arrow_left, size: 18, color: c.muted),
          ]),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 24),
      children: [
        Text('Replace with', style: RfType.headline.copyWith(color: c.text)),
        const SizedBox(height: 4),
        Text('Same movement, different equipment or difficulty. Each keeps its own history.', style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 12),
        ...alts.listed.map(row),
        if (alts.more.isNotEmpty) ...[
          SectionTitle('More from the library · ${alts.more.length}', padding: const EdgeInsets.fromLTRB(0, 14, 0, 8)),
          ...alts.more.take(_more).map(row),
          if (alts.more.length > _more) RfButton(label: 'Show more', kind: RfButtonKind.ghost, onPressed: () => setState(() => _more += 12)),
        ],
      ],
    );
  }
}
