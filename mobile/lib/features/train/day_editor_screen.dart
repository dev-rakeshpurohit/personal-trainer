// Day editor: reorder, adjust sets/reps/rest with steppers, swap via alternates, remove (Undo),
// add from the exercise picker. Every change is written straight away and can be undone.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../library/exercise_picker_screen.dart';
import 'alternates_sheet.dart';
import 'plan_check.dart' show kWeekdayFull;
import 'train_data.dart';

const _types = [
  (DayType.strength, 'Strength'),
  (DayType.cardio, 'Cardio'),
  (DayType.conditioning, 'Conditioning'),
  (DayType.activeRecovery, 'Recovery'),
  (DayType.rest, 'Rest'),
];

String _unitShort(Unit u) => switch (u) { Unit.reps => 'reps', Unit.seconds => 's', Unit.minutes => 'min', Unit.meters => 'm' };

String plannedSummary(PlannedExercise p) {
  final reps = p.repsMin == p.repsMax ? '${p.repsMax}' : '${p.repsMin}–${p.repsMax}';
  final unit = p.unit == Unit.reps ? '' : ' ${_unitShort(p.unit)}';
  return '${p.sets} × $reps$unit${p.perSide ? ' / side' : ''} · rest ${p.restSec}s';
}

class DayEditorScreen extends ConsumerStatefulWidget {
  const DayEditorScreen({super.key, required this.dayId});
  final String dayId;

  static Future<void> open(BuildContext context, String dayId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DayEditorScreen(dayId: dayId)));

  @override
  ConsumerState<DayEditorScreen> createState() => _DayEditorScreenState();
}

class _DayEditorScreenState extends ConsumerState<DayEditorScreen> {
  List<PlannedExercise>? _optimistic;

  Future<void> _add(ProgramDay day) async {
    final id = await ExercisePickerScreen.pick(context);
    if (id == null || !mounted) return;
    final pe = await ref.read(planEditProvider).addExerciseToDay(day.id, id);
    Haptics.setDone();
    if (!mounted) return;
    final name = ref.read(exerciseMapProvider).value?[id]?.name ?? 'Exercise';
    final ops = ref.read(planOpsProvider);
    showRfToast(context, '$name added · ${plannedSummary(pe)}', icon: CupertinoIcons.checkmark_alt, onUndo: () async {
      await ops.remove(pe.id);
      if (!day.type.isTraining) await ops.updateDay(day);
    });
  }

  Future<void> _reorder(List<PlannedExercise> list, int from, int to) async {
    final next = [...list];
    next.insert(to, next.removeAt(from));
    setState(() => _optimistic = next);
    Haptics.tick();
    await ref.read(planOpsProvider).reorder(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final bundle = ref.watch(programBundleProvider).value;
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    final day = bundle?.days.where((d) => d.id == widget.dayId).firstOrNull;
    if (bundle == null || day == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: CupertinoIcons.calendar, title: 'This day is no longer in your plan'));
    }
    final stored = bundle.plannedFor(day.id);
    // drop the optimistic order once the stored order matches it
    if (_optimistic != null && _optimistic!.map((p) => p.id).join() == stored.map((p) => p.id).join()) _optimistic = null;
    final list = _optimistic != null && _optimistic!.length == stored.length ? _optimistic! : stored;

    return Scaffold(
      appBar: AppBar(title: Text('Edit ${kWeekdayFull[day.weekday]}')),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, MediaQuery.paddingOf(context).bottom + 16),
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(day.title, style: RfType.headline.copyWith(color: c.text)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (t, label) in _types)
              RfChip(label: label, selected: day.type == t, onTap: () => ref.read(planOpsProvider).updateDay(day.copyWith(type: t))),
          ]),
          SectionTitle(list.isEmpty ? 'Exercises' : 'Exercises · hold ≡ to reorder', padding: const EdgeInsets.fromLTRB(0, 22, 0, 10)),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(day.type.isTraining ? 'Nothing planned yet.' : 'A rest day. Adding an exercise turns it into a workout.',
                  style: RfType.callout.copyWith(color: c.muted)),
            ),
        ]),
        footer: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: RfButton(label: 'Add exercise', icon: CupertinoIcons.add, kind: RfButtonKind.secondary, expand: true, onPressed: () => _add(day)),
        ),
        itemCount: list.length,
        onReorderItem: (from, to) => _reorder(list, from, to),
        itemBuilder: (context, i) {
          final p = list[i];
          final ex = exMap[p.exerciseId];
          return Padding(
            key: ValueKey(p.id),
            padding: const EdgeInsets.only(bottom: 8),
            child: RfCard(
              padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
              child: Row(children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Semantics(
                    label: 'Reorder ${ex?.name ?? p.exerciseId}',
                    child: SizedBox(width: 40, height: Rf.tap, child: Icon(CupertinoIcons.line_horizontal_3, color: c.muted)),
                  ),
                ),
                Expanded(
                  child: Pressable(
                    onTap: () => showPlannedEditSheet(context, p.id),
                    semanticLabel: 'Edit ${ex?.name ?? p.exerciseId}, ${plannedSummary(p)}',
                    child: Row(children: [
                      ExerciseThumb(exercise: ex, size: 48),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${p.slot}  ', style: RfType.captionStrong.copyWith(color: c.accentInk)),
                              TextSpan(text: ex?.name ?? p.exerciseId),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RfType.bodyStrong.copyWith(color: c.text),
                          ),
                          Text(plannedSummary(p), style: RfType.caption.copyWith(color: c.muted)),
                        ]),
                      ),
                      Icon(CupertinoIcons.slider_horizontal_3, size: 18, color: c.muted),
                    ]),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

Future<void> showPlannedEditSheet(BuildContext context, String plannedId) =>
    showRfSheet<void>(context, tall: true, builder: (_) => _PlannedSheet(plannedId: plannedId, hostContext: context));

class _PlannedSheet extends ConsumerWidget {
  const _PlannedSheet({required this.plannedId, required this.hostContext});
  final String plannedId;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final pe = ref.watch(programBundleProvider).value?.planned.where((p) => p.id == plannedId).firstOrNull;
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    if (pe == null) return const SizedBox(height: 120);
    final ex = exMap[pe.exerciseId];
    final ops = ref.read(planOpsProvider);
    final unit = _unitShort(pe.unit);
    final repStep = pe.unit == Unit.seconds || pe.unit == Unit.meters ? 5.0 : 1.0;

    Widget stepper(String label, double value, ValueChanged<double> onChanged, {double step = 1, double min = 1, double max = 600, String? unitLabel}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            SizedBox(width: 92, child: Text(label, style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600))),
            Expanded(child: BigStepper(value: value, onChanged: onChanged, step: step, min: min, max: max, label: label, unit: unitLabel, compact: true)),
          ]),
        );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 24),
      children: [
        Row(children: [
          ExerciseThumb(exercise: ex, size: 52),
          const SizedBox(width: 12),
          Expanded(child: Text(ex?.name ?? pe.exerciseId, style: RfType.headline.copyWith(color: c.text))),
        ]),
        const SizedBox(height: 16),
        stepper('Sets', pe.sets.toDouble(), (v) => ops.update(pe.copyWith(sets: v.round())), max: 10),
        stepper('Min $unit', pe.repsMin.toDouble(), (v) => ops.update(pe.copyWith(repsMin: v.round(), repsMax: v.round() > pe.repsMax ? v.round() : pe.repsMax)), step: repStep),
        stepper('Max $unit', pe.repsMax.toDouble(), (v) => ops.update(pe.copyWith(repsMax: v.round(), repsMin: v.round() < pe.repsMin ? v.round() : pe.repsMin)), step: repStep),
        stepper('Rest', pe.restSec.toDouble(), (v) => ops.update(pe.copyWith(restSec: v.round())), step: 15, min: 0, max: 300, unitLabel: 'seconds'),
        Text('Superset', style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in const ['', 'A', 'B', 'C', 'D'])
            RfChip(
              label: g.isEmpty ? 'None' : g,
              selected: (pe.supersetGroup ?? '') == g,
              onTap: () => ops.update(pe.copyWith(supersetGroup: () => g.isEmpty ? null : g)),
            ),
        ]),
        const SizedBox(height: 20),
        RfButton(
          label: 'Replace with alternate',
          icon: CupertinoIcons.arrow_right_arrow_left,
          kind: RfButtonKind.secondary,
          expand: true,
          onPressed: () async {
            final id = await showAlternatesSheet(context, pe);
            if (id == null) return;
            await ref.read(sessionServiceProvider).makePermanentSwap(pe.id, id);
            Haptics.tick();
            if (!hostContext.mounted) return;
            showRfToast(hostContext, 'Now using ${exMap[id]?.name ?? id}', icon: CupertinoIcons.checkmark_alt, onUndo: () => ops.update(pe));
          },
        ),
        const SizedBox(height: 8),
        RfButton(
          label: 'Remove from this day',
          icon: CupertinoIcons.trash,
          kind: RfButtonKind.destructive,
          expand: true,
          onPressed: () async {
            final removed = await ops.remove(pe.id);
            if (context.mounted) Navigator.of(context).pop();
            if (removed == null || !hostContext.mounted) return;
            showRfToast(hostContext, '${ex?.name ?? 'Exercise'} removed', onUndo: () => ops.restore(removed));
          },
        ),
      ],
    );
  }
}
