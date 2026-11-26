// Plan check: weekly hard sets per muscle against a goal range, as a body map + words,
// with one-tap fixes ("Add to Tuesday") that can be undone.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/balance.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'body_map.dart';
import 'train_data.dart';

const kWeekdayFull = {
  Weekday.mon: 'Monday',
  Weekday.tue: 'Tuesday',
  Weekday.wed: 'Wednesday',
  Weekday.thu: 'Thursday',
  Weekday.fri: 'Friday',
  Weekday.sat: 'Saturday',
  Weekday.sun: 'Sunday',
};

Map<MuscleGroup, VolumeState> _states(PlanCheckView v) => {for (final g in MuscleGroup.values) g: v.stateOf(g)};

IconData stateIcon(VolumeState s) => switch (s) {
      VolumeState.below => CupertinoIcons.arrow_down_circle,
      VolumeState.inRange => CupertinoIcons.checkmark_circle_fill,
      VolumeState.above => CupertinoIcons.arrow_up_circle,
    };

String stateLabel(VolumeState s) => switch (s) {
      VolumeState.below => 'Below',
      VolumeState.inRange => 'In range',
      VolumeState.above => 'Above',
    };

Color stateColor(BuildContext context, VolumeState s) => switch (s) {
      VolumeState.below => context.rf.muted,
      VolumeState.inRange => context.rf.accentInk,
      VolumeState.above => context.rf.caution,
    };

/// Compact Plan check at the top of the week (Train tab).
class PlanCheckCard extends ConsumerWidget {
  const PlanCheckCard({super.key});

  void _open(BuildContext context, [MuscleGroup? g]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlanCheckScreen(initial: g)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final view = ref.watch(planCheckProvider).value;
    if (view == null) return const SizedBox.shrink();
    final gaps = view.result.suggestions;
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(CupertinoIcons.scope, size: 18, color: c.muted),
          const SizedBox(width: 6),
          Expanded(child: Semantics(header: true, child: Text('PLAN CHECK', style: RfType.overline.copyWith(color: c.muted)))),
          TextButton(onPressed: () => _open(context), child: Text('Details', style: RfType.callout.copyWith(color: c.accentInk, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 4),
        Text(view.summary, style: RfType.bodyStrong.copyWith(color: c.text)),
        const SizedBox(height: 12),
        BodyMap(states: _states(view), height: 168, onSelect: (g) => _open(context, g)),
        const SizedBox(height: 10),
        const BodyMapLegend(),
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 14),
          FixCard(key: ValueKey('fix-${gaps.first.group.wire}'), s: gaps.first, view: view, compact: true),
          if (gaps.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: RfButton(
                label: '${gaps.length - 1} more ${gaps.length == 2 ? 'fix' : 'fixes'}',
                kind: RfButtonKind.ghost,
                icon: CupertinoIcons.chevron_right,
                onPressed: () => _open(context),
              ),
            ),
        ],
      ]),
    );
  }
}

/// A gap with its suggested exercises and a one-tap "Add to (day)".
class FixCard extends ConsumerStatefulWidget {
  const FixCard({super.key, required this.s, required this.view, this.compact = false});
  final Suggestion s;
  final PlanCheckView view;
  final bool compact;
  @override
  ConsumerState<FixCard> createState() => _FixCardState();
}

class _FixCardState extends ConsumerState<FixCard> {
  late String _pick = widget.s.options.first.id;
  bool _busy = false;

  String get _dayName {
    final d = widget.view.dayOf(widget.s.dayId);
    return d == null ? widget.s.dayLabel.split(' – ').first : kWeekdayFull[d.weekday]!;
  }

  Future<void> _add() async {
    final s = widget.s;
    setState(() => _busy = true);
    final pe = await ref.read(planEditProvider).addExerciseToDay(s.dayId, _pick, sets: s.sets, repsMin: s.repsMin, repsMax: s.repsMax, restSec: s.restSec);
    Haptics.setDone();
    if (!mounted) return;
    final name = s.options.firstWhere((o) => o.id == _pick).name;
    final ops = ref.read(planOpsProvider);
    showRfToast(context, 'Added $name to $_dayName · ${s.sets} × ${s.repsMin}–${s.repsMax}',
        icon: CupertinoIcons.checkmark_alt, onUndo: () => ops.remove(pe.id));
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final s = widget.s;
    final options = widget.compact ? s.options.take(1).toList() : s.options;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius + 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(stateIcon(VolumeState.below), size: 18, color: c.text),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.view.line(s.group), style: RfType.bodyStrong.copyWith(color: c.text))),
        ]),
        const SizedBox(height: 2),
        Text('Add ${s.sets} × ${s.repsMin}–${s.repsMax} on $_dayName, next to related work.', style: RfType.caption.copyWith(color: c.muted)),
        const SizedBox(height: 8),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(
              selected: _pick == o.id,
              button: true,
              label: o.name,
              excludeSemantics: true,
              child: Pressable(
                onTap: options.length > 1 ? () => setState(() => _pick = o.id) : null,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Rf.btnRadius),
                    border: Border.all(color: _pick == o.id && options.length > 1 ? c.accent : c.line, width: _pick == o.id && options.length > 1 ? 1.4 : 0.6),
                  ),
                  child: Row(children: [
                    ExerciseThumb(exercise: o, size: 44),
                    const SizedBox(width: 10),
                    Expanded(child: Text(o.name, style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600))),
                    if (_pick == o.id && options.length > 1) Icon(CupertinoIcons.checkmark_alt, size: 18, color: c.accentInk),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        RfButton(label: 'Add to $_dayName', icon: CupertinoIcons.add, expand: true, busy: _busy, onPressed: _add),
      ]),
    );
  }
}

/// Full Plan check: big map, selected muscle, all fixes, every muscle as a list.
class PlanCheckScreen extends ConsumerStatefulWidget {
  const PlanCheckScreen({super.key, this.initial});
  final MuscleGroup? initial;
  @override
  ConsumerState<PlanCheckScreen> createState() => _PlanCheckScreenState();
}

class _PlanCheckScreenState extends ConsumerState<PlanCheckScreen> {
  late MuscleGroup? _sel = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final view = ref.watch(planCheckProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan check')),
      body: view == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, MediaQuery.paddingOf(context).bottom + 16),
              children: [
                Text(view.summary, style: RfType.headline.copyWith(color: c.text)),
                const SizedBox(height: 4),
                Text('Hard sets per muscle each week. Helper muscles count half. Ranges come from your goal.',
                    style: RfType.callout.copyWith(color: c.muted)),
                const SizedBox(height: 16),
                BodyMap(states: _states(view), height: 260, selected: _sel, onSelect: (g) => setState(() => _sel = g)),
                const SizedBox(height: 10),
                const BodyMapLegend(),
                if (_sel != null) ...[const SizedBox(height: 16), _Selected(view: view, g: _sel!)],
                if (view.result.suggestions.isNotEmpty) ...[
                  const SectionTitle('Fixes', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
                  for (final s in view.result.suggestions)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: FixCard(key: ValueKey('fixall-${s.group.wire}'), s: s, view: view)),
                ],
                const SectionTitle('Every muscle', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
                RfCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    for (final g in MuscleGroup.values)
                      MuscleRow(view: view, g: g, selected: g == _sel, onTap: () => setState(() => _sel = g)),
                  ]),
                ),
              ],
            ),
    );
  }
}

class _Selected extends StatelessWidget {
  const _Selected({required this.view, required this.g});
  final PlanCheckView view;
  final MuscleGroup g;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final st = view.stateOf(g);
    final fix = view.fixFor(g);
    final text = switch (st) {
      VolumeState.below => fix != null ? 'Not enough yet. One extra exercise closes the gap — see the fix below.' : 'Not enough yet, and nothing in your gym fits as a quick add. Ask the coach for options.',
      VolumeState.inRange => 'Right where it should be for your goal.',
      VolumeState.above => 'More than you need. Fine for a block if you recover well; trim a set if it lingers.',
    };
    return RfCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(stateIcon(st), color: stateColor(context, st)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(view.line(g), style: RfType.bodyStrong.copyWith(color: c.text)),
            const SizedBox(height: 2),
            Text(text, style: RfType.callout.copyWith(color: c.muted)),
          ]),
        ),
      ]),
    );
  }
}

/// "Hamstrings 4 sets — aim 9–14   ↓ Below".
class MuscleRow extends StatelessWidget {
  const MuscleRow({super.key, required this.view, required this.g, this.selected = false, this.onTap});
  final PlanCheckView view;
  final MuscleGroup g;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final st = view.stateOf(g);
    final col = stateColor(context, st);
    return Semantics(
      button: true,
      selected: selected,
      label: '${view.line(g)}, ${stateLabel(st)}',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Rf.tap),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.5), width: 0.5))),
          child: Row(children: [
            Expanded(
              child: Text(view.line(g),
                  style: RfType.callout.copyWith(color: c.text, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ),
            Icon(stateIcon(st), size: 16, color: col),
            const SizedBox(width: 4),
            Text(stateLabel(st), style: RfType.captionStrong.copyWith(color: col)),
          ]),
        ),
      ),
    );
  }
}
