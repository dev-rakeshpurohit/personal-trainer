// One day of the week: what's planned (sets × reps × target, superset letters), violet dots on
// values the coach changed, and the one thing you can do with it (start today / preview).
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../domain/units.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../workout/start.dart';
import 'day_editor_screen.dart';
import 'train_data.dart';
import 'why_sheet.dart';

IconData dayIcon(DayType t) => switch (t) {
      DayType.strength => Icons.fitness_center,
      DayType.cardio => CupertinoIcons.heart,
      DayType.conditioning => CupertinoIcons.bolt,
      DayType.rest => CupertinoIcons.moon,
      DayType.activeRecovery => CupertinoIcons.leaf_arrow_circlepath,
    };

class DayCard extends ConsumerWidget {
  const DayCard({super.key, required this.day, required this.week});
  final TrainDay day;
  final TrainWeek week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final pd = day.day;
    final dateLabel = DateFormat('EEE d').format(day.date);
    final units = ref.watch(profileProvider).value?.units ?? 'kg';

    if (pd == null || !pd.type.isTraining) {
      final rest = pd?.type == DayType.activeRecovery;
      return RfCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        border: day.isToday ? c.accent.withValues(alpha: 0.6) : null,
        child: Row(children: [
          _DayIcon(type: pd?.type ?? DayType.rest),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$dateLabel${day.isToday ? ' · Today' : ''}', style: RfType.captionStrong.copyWith(color: c.muted)),
              Text(pd?.title ?? 'Rest', style: RfType.bodyStrong.copyWith(color: c.text)),
              Text(rest ? 'Easy movement: walk, stretch, breathe.' : 'Recovery is when you get stronger.', style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
          if (pd != null) _EditButton(dayId: pd.id, title: pd.title),
        ]),
      );
    }

    final changed = day.rows.where((r) => r.changed).length;
    return RfCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
      border: day.isToday ? c.accent.withValues(alpha: 0.7) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _DayIcon(type: pd.type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('$dateLabel${day.isToday ? ' · Today' : ''}', style: RfType.captionStrong.copyWith(color: day.isToday ? c.accentInk : c.muted)),
                if (day.done) StatusPill(label: 'Done', color: c.done, icon: CupertinoIcons.checkmark_alt),
                if (day.moved) StatusPill(label: 'Moved here', color: c.muted, icon: CupertinoIcons.arrow_turn_down_right),
              ]),
              Text(pd.title, style: RfType.bodyStrong.copyWith(color: c.text)),
              Text(
                '${day.rows.length} exercises · ${pd.durationMin ?? 60} min${changed > 0 ? ' · $changed changed' : ''}',
                style: RfType.caption.copyWith(color: c.muted),
              ),
            ]),
          ),
          _EditButton(dayId: pd.id, title: pd.title),
        ]),
        if (day.rows.isNotEmpty) const SizedBox(height: 6),
        for (final r in day.rows) _ExerciseLine(row: r, week: week, units: units),
        if (day.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Text('Nothing planned yet. Tap the pencil to add exercises.', style: RfType.callout.copyWith(color: c.muted)),
          ),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(right: 8), child: _Footer(day: day)),
      ]),
    );
  }
}

class _DayIcon extends StatelessWidget {
  const _DayIcon({required this.type});
  final DayType type;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Icon(dayIcon(type), size: 20, color: type.isTraining ? c.text : c.muted),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.dayId, required this.title});
  final String dayId;
  final String title;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Edit $title',
        constraints: const BoxConstraints(minWidth: Rf.tap, minHeight: Rf.tap),
        icon: Icon(CupertinoIcons.pencil, color: context.rf.muted),
        onPressed: () => DayEditorScreen.open(context, dayId),
      );
}

class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.row, required this.week, required this.units});
  final PlanRow row;
  final TrainWeek week;
  final String units;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final w = row.weightKg != null && row.weightKg! > 0 ? ' · ${displayWeight(row.weightKg, units)} $units' : '';
    final superset = row.pe.supersetGroup != null && row.pe.supersetGroup!.isNotEmpty;
    return Pressable(
      onTap: () => showWhySheet(context, row: row, week: week),
      semanticLabel: '${row.pe.slot} ${row.name}, ${targetText(row.target)}$w${row.changed ? ', changed by coach' : ''}. Why this target',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.only(top: 6, bottom: 6, right: 8),
        child: Row(children: [
          ExerciseThumb(exercise: row.ex, size: 44),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              row.pe.slot,
              style: RfType.captionStrong.copyWith(color: superset ? c.accentInk : c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600)),
              Row(children: [
                Flexible(
                  child: Text(
                    '${targetText(row.target)}$w',
                    style: RfType.caption.copyWith(color: row.changed ? c.coach : c.muted, fontWeight: row.changed ? FontWeight.w600 : null, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                if (row.changed) ...[const SizedBox(width: 6), const CoachDot()],
              ]),
            ]),
          ),
          Icon(CupertinoIcons.question_circle, size: 18, color: row.changed ? c.coach : c.line),
        ]),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.day});
  final TrainDay day;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final pd = day.day!;
    if (day.done) {
      return Row(children: [
        Icon(CupertinoIcons.checkmark_seal_fill, size: 18, color: c.done),
        const SizedBox(width: 6),
        Text(day.isToday ? 'Done today. Nice work.' : 'Done', style: RfType.callout.copyWith(color: c.done, fontWeight: FontWeight.w600)),
      ]);
    }
    if (day.startable) {
      final active = ref.watch(activeSessionProvider).value;
      return RfButton(
        label: active != null ? 'Resume session' : 'Start session',
        icon: CupertinoIcons.play_fill,
        expand: true,
        height: Rf.gymTap,
        onPressed: () => active != null ? resumeWorkout(context) : startWorkout(ref, context, dayId: pd.id),
      );
    }
    final now = ref.watch(clockProvider)();
    final past = day.date.isBefore(DateTime(now.year, now.month, now.day));
    final when = DateFormat('EEEE d MMM').format(day.date);
    return Row(children: [
      Icon(CupertinoIcons.lock, size: 15, color: c.muted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(past ? 'Was planned for $when · preview only' : 'Starts on $when', style: RfType.callout.copyWith(color: c.muted)),
      ),
    ]);
  }
}
