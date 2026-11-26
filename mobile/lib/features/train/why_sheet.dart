// "Why" sheet: the reason behind a planned value, the data it came from, and "Change this".
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/units.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../library/exercise_detail_screen.dart';
import 'train_data.dart';

Future<void> showWhySheet(BuildContext context, {required PlanRow row, required TrainWeek week}) =>
    showRfSheet<void>(context, tall: true, builder: (_) => WhySheet(row: row, week: week, hostContext: context));

class WhySheet extends ConsumerStatefulWidget {
  const WhySheet({super.key, required this.row, required this.week, required this.hostContext});
  final PlanRow row;
  final TrainWeek week;

  /// The page under the sheet (navigation after the sheet closes).
  final BuildContext hostContext;
  @override
  ConsumerState<WhySheet> createState() => _WhySheetState();
}

class _WhySheetState extends ConsumerState<WhySheet> {
  late final Future<History> _history = ref.read(progressionDataProvider).loadHistory(widget.row.pe.exerciseId);

  String _baseReason(PlanRow r) {
    final sg = r.suggestion;
    if (sg != null) {
      return switch (sg.kind) {
        SuggestionKind.first => 'First time on this one: pick a weight you could lift for a couple more reps, and log it as your baseline.',
        SuggestionKind.hold => '${sg.message}. You’re still inside the range, so the weight stays until every set reaches the top.',
        SuggestionKind.timeCap => sg.message,
        _ => sg.message,
      };
    }
    if (r.target.unit == Unit.minutes) return 'Steady work: match last time and keep the pace conversational.';
    return 'Double progression: work inside ${r.target.repsMin}–${r.target.repsMax}. When every set reaches the top, the weight goes up next time.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final r = widget.row;
    final w = widget.week;
    final units = ref.watch(profileProvider).value?.units ?? 'kg';
    final weight = r.weightKg != null && r.weightKg! > 0 ? ' · ${displayWeight(r.weightKg, units)} $units' : '';
    final focus = w.focus;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 24),
      children: [
        Row(children: [
          ExerciseThumb(exercise: r.ex, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: RfType.headline.copyWith(color: c.text)),
              const SizedBox(height: 2),
              Text('${targetText(r.target)}$weight', style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.coach.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(Rf.btnRadius + 2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CoachDot(),
              const SizedBox(width: 8),
              Text(r.changed ? 'WHAT CHANGED THIS WEEK' : 'WHY THIS TARGET', style: RfType.overline.copyWith(color: c.coach)),
            ]),
            const SizedBox(height: 8),
            for (final reason in r.changes)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(reason, style: RfType.body.copyWith(color: c.text))),
            if (!r.changed || r.suggestion?.kind == SuggestionKind.hold || r.suggestion?.kind == SuggestionKind.first)
              Text(_baseReason(r), style: RfType.body.copyWith(color: r.changed ? c.muted : c.text)),
            if (r.target.rir != null) ...[
              const SizedBox(height: 6),
              Text('Stop each set with ${r.target.rir} ${r.target.rir == 1 ? 'rep' : 'reps'} in reserve.', style: RfType.callout.copyWith(color: c.muted)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        if (focus != null || w.deload)
          RfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                w.deload ? 'Week ${w.cycleWeek} · Recovery week — lighter on purpose' : 'Week ${w.cycleWeek} of 8 · ${focus!.focus}',
                style: RfType.bodyStrong.copyWith(color: c.text),
              ),
              if (focus != null && focus.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(focus.note, style: RfType.callout.copyWith(color: c.muted)),
              ],
            ]),
          ),
        const SectionTitle('Based on your last 3 sessions', padding: EdgeInsets.fromLTRB(0, 18, 0, 8)),
        FutureBuilder<History>(
          future: _history,
          builder: (context, snap) {
            final h = snap.data;
            if (h == null) return const SizedBox(height: 40);
            if (h.isEmpty) {
              return Text('No sessions logged yet, so this is the plan’s starting target.', style: RfType.callout.copyWith(color: c.muted));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, sets) in h.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 84,
                      child: Text(i == 0 ? 'Last time' : '$i ${i == 1 ? 'session' : 'sessions'} before', style: RfType.captionStrong.copyWith(color: c.muted)),
                    ),
                    Expanded(
                      child: Text(
                        sets.map((s) => _ws(s, units)).join(' · '),
                        style: RfType.callout.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ]),
                ),
            ]);
          },
        ),
        const SizedBox(height: 18),
        RfButton(
          label: 'Change this',
          kind: RfButtonKind.coach,
          icon: Icons.auto_awesome,
          expand: true,
          onPressed: () {
            final host = widget.hostContext;
            Navigator.of(context).pop();
            // Coach opens; a pre-filled prompt is passed as ?q= for when Coach supports it.
            host.go(Uri(path: '/coach', queryParameters: {'q': 'Change ${r.name} (${targetText(r.target)})'}).toString());
          },
        ),
        const SizedBox(height: 8),
        RfButton(
          label: 'About this exercise',
          kind: RfButtonKind.secondary,
          icon: CupertinoIcons.info_circle,
          expand: true,
          onPressed: () {
            final host = widget.hostContext;
            Navigator.of(context).pop();
            ExerciseDetailScreen.open(host, r.pe.exerciseId);
          },
        ),
      ],
    );
  }
}

String _ws(WorkSet s, String units) {
  if (s.seconds != null) return '${s.seconds}s';
  if (s.meters != null) return '${s.meters!.round()} m';
  final w = s.weightKg != null && s.weightKg! > 0 ? '${displayWeight(s.weightKg, units)}×' : '';
  return '$w${s.reps ?? ''}';
}
