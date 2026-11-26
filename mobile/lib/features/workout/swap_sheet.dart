// Swap: reason picker (Busy · Not in my gym · Hurts · Want a change) → three ranked alternatives,
// each with a one-line reason → "Just today" / "From now on".
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../ui/demo_player.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'workout_math.dart';

/// The lifter's pick from the swap sheet.
class SwapChoice {
  const SwapChoice({required this.exerciseId, required this.always, required this.reason});
  final String exerciseId;
  final bool always;
  final SwapReason reason;
}

Future<SwapChoice?> showSwapSheet(
  BuildContext context, {
  required Exercise original,
  required String currentId,
  required Map<String, Exercise> library,
  required List<String> equipment,
  String? planSwapId,
  Set<String> exclude = const {},
  SwapReason? initialReason,
}) =>
    showRfSheet<SwapChoice>(
      context,
      tall: true,
      builder: (_) => _SwapBody(
        original: original,
        currentId: currentId,
        library: library,
        equipment: equipment,
        planSwapId: planSwapId,
        exclude: exclude,
        initialReason: initialReason,
      ),
    );

class _SwapBody extends StatefulWidget {
  const _SwapBody({
    required this.original,
    required this.currentId,
    required this.library,
    required this.equipment,
    required this.planSwapId,
    required this.exclude,
    required this.initialReason,
  });
  final Exercise original;
  final String currentId;
  final Map<String, Exercise> library;
  final List<String> equipment;
  final String? planSwapId;
  final Set<String> exclude;
  final SwapReason? initialReason;
  @override
  State<_SwapBody> createState() => _SwapBodyState();
}

class _SwapBodyState extends State<_SwapBody> {
  late SwapReason? reason = widget.initialReason;
  String? picked;
  List<SwapOption> options = const [];

  @override
  void initState() {
    super.initState();
    if (reason != null) _rank();
  }

  void _rank() {
    options = rankAlternatives(
      original: widget.original,
      currentId: widget.currentId,
      library: widget.library,
      equipment: widget.equipment,
      reason: reason!,
      planSwapId: widget.planSwapId,
      exclude: widget.exclude,
    );
    picked = options.isEmpty ? null : options.first.exercise.id;
  }

  static const _icons = {
    SwapReason.busy: CupertinoIcons.person_2,
    SwapReason.notInGym: CupertinoIcons.xmark_circle,
    SwapReason.hurts: CupertinoIcons.bandage,
    SwapReason.change: CupertinoIcons.shuffle,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final current = widget.library[widget.currentId]?.name ?? widget.original.name;
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 4),
          child: Row(children: [
            if (reason != null)
              Semantics(
                button: true,
                label: 'Back to reasons',
                excludeSemantics: true,
                child: Pressable(
                  onTap: () => setState(() => reason = null),
                  child: SizedBox(width: Rf.tap, height: Rf.tap, child: Icon(CupertinoIcons.chevron_left, color: c.text)),
                ),
              ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(reason == null ? 'Why swap $current?' : 'Pick an alternative', style: RfType.headline.copyWith(color: c.text)),
              ),
            ),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, 12),
            child: reason == null ? _reasons(context) : _options(context),
          ),
        ),
        if (reason != null && options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, 12),
            child: Row(children: [
              Expanded(
                child: RfButton(
                  label: 'Just today',
                  kind: RfButtonKind.secondary,
                  expand: true,
                  height: Rf.gymTap,
                  onPressed: picked == null ? null : () => Navigator.of(context).pop(SwapChoice(exerciseId: picked!, always: false, reason: reason!)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RfButton(
                  label: 'From now on',
                  expand: true,
                  height: Rf.gymTap,
                  onPressed: picked == null ? null : () => Navigator.of(context).pop(SwapChoice(exerciseId: picked!, always: true, reason: reason!)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _reasons(BuildContext context) {
    final c = context.rf;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("Tell me what's up and I'll find the best fit for your gym.", style: RfType.callout.copyWith(color: c.muted)),
      const SizedBox(height: 12),
      for (final r in SwapReason.values) ...[
        RfCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          semanticLabel: r.label,
          onTap: () => setState(() {
            reason = r;
            _rank();
          }),
          child: Row(children: [
            Icon(_icons[r], color: c.text),
            const SizedBox(width: 12),
            Expanded(child: Text(r.label, style: RfType.bodyStrong.copyWith(color: c.text))),
            Icon(CupertinoIcons.chevron_right, size: 18, color: c.muted),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _options(BuildContext context) {
    final c = context.rf;
    if (options.isEmpty) {
      return const EmptyState(
        icon: CupertinoIcons.search,
        title: 'Nothing else fits your equipment',
        body: 'Add equipment in your plan setup to see more alternatives.',
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Ranked for "${reason!.label}". Each keeps its own history.', style: RfType.callout.copyWith(color: c.muted)),
      const SizedBox(height: 12),
      for (final o in options) ...[
        Semantics(
          selected: picked == o.exercise.id,
          button: true,
          label: '${o.exercise.name}. ${o.reason}',
          excludeSemantics: true,
          child: RfCard(
            padding: const EdgeInsets.all(10),
            border: picked == o.exercise.id ? c.accent : null,
            onTap: () => setState(() => picked = o.exercise.id),
            child: Row(children: [
              ExerciseThumb(exercise: o.exercise, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.exercise.name, style: RfType.bodyStrong.copyWith(color: c.text)),
                  const SizedBox(height: 2),
                  Text(o.reason, style: RfType.caption.copyWith(color: c.muted)),
                ]),
              ),
              Icon(
                picked == o.exercise.id ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                color: picked == o.exercise.id ? c.accentInk : c.muted,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
