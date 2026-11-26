// The cards on Today: workout hero, week strip, weekly goal, missed-session re-plan, diet summary,
// coach note and "Life happens" chips. Each is a small widget fed by today_screen.dart.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'today_logic.dart';

/* ------------------------------------------------------------ workout hero */

enum HeroState { active, done, training, rest, empty }

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({
    super.key,
    required this.state,
    this.day,
    this.exerciseCount = 0,
    this.muscles = const [],
    this.movedFrom,
    this.deload = false,
    this.doneMinutes,
    this.activeTitle,
    this.next,
    this.life,
    this.onStart,
    this.onResume,
    this.onOpenTrain,
  });
  final HeroState state;
  final ProgramDay? day;
  final int exerciseCount;
  final List<String> muscles;
  final String? movedFrom;
  final bool deload;
  final int? doneMinutes;
  final String? activeTitle;
  final String? next;
  final LifeStatus? life;
  final VoidCallback? onStart;
  final VoidCallback? onResume;
  final VoidCallback? onOpenTrain;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    switch (state) {
      case HeroState.active:
        return RfCard(
          key: const Key('today-hero-active'),
          padding: const EdgeInsets.all(20),
          border: c.accent,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow(context, 'IN PROGRESS', c.accentInk, CupertinoIcons.timer),
            const SizedBox(height: 6),
            Text(activeTitle ?? 'Workout', style: RfType.title.copyWith(color: c.text)),
            const SizedBox(height: 18),
            RfButton(key: const Key('today-resume'), label: 'Resume workout', icon: CupertinoIcons.play_fill, expand: true, height: Rf.doneBar, onPressed: onResume),
          ]),
        );
      case HeroState.done:
        return RfCard(
          key: const Key('today-hero-done'),
          padding: const EdgeInsets.all(20),
          border: c.done.withValues(alpha: 0.6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow(context, 'DONE TODAY', c.done, CupertinoIcons.checkmark_circle_fill),
            const SizedBox(height: 6),
            Text(day?.title ?? activeTitle ?? 'Workout', style: RfType.title.copyWith(color: c.text)),
            const SizedBox(height: 6),
            Text(
              '${doneMinutes != null ? '$doneMinutes min. ' : ''}Good work. Protein and sleep do the rest tonight.',
              style: RfType.callout.copyWith(color: c.muted),
            ),
          ]),
        );
      case HeroState.training:
        final d = day!;
        return RfCard(
          key: const Key('today-hero-training'),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('TODAY · ${d.type.wire.replaceAll('_', ' ').toUpperCase()}', style: RfType.overline.copyWith(color: c.accentInk)),
              if (movedFrom != null) StatusPill(label: 'Moved from $movedFrom', color: c.text, icon: CupertinoIcons.arrow_right_arrow_left),
              if (deload) StatusPill(label: 'Deload', color: c.text, icon: CupertinoIcons.arrow_down),
            ]),
            const SizedBox(height: 6),
            Text(d.title, style: RfType.title.copyWith(color: c.text, fontSize: 30)),
            const SizedBox(height: 6),
            Row(children: [
              Icon(CupertinoIcons.clock, size: 16, color: c.muted),
              const SizedBox(width: 4),
              Text('${d.durationMin ?? 60} min', style: RfType.callout.copyWith(color: c.muted)),
              const SizedBox(width: 14),
              Text('$exerciseCount exercises', style: RfType.callout.copyWith(color: c.muted)),
            ]),
            if (muscles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in muscles)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.chipRadius)),
                    child: Text(_cap(m), style: RfType.caption.copyWith(color: c.text)),
                  ),
              ]),
            ],
            if (life != null) ...[
              const SizedBox(height: 10),
              Text('${life!.label}: start only if you feel up to it. Skipping today is on plan.', style: RfType.caption.copyWith(color: c.muted)),
            ],
            const SizedBox(height: 18),
            if (exerciseCount > 0)
              RfButton(key: const Key('today-start'), label: 'Start workout', icon: CupertinoIcons.play_fill, expand: true, height: Rf.doneBar, onPressed: onStart)
            else ...[
              Text('No exercises in this session yet.', style: RfType.callout.copyWith(color: c.muted)),
              const SizedBox(height: 8),
              RfButton(label: 'Add exercises in Train', kind: RfButtonKind.secondary, expand: true, onPressed: onOpenTrain),
            ],
          ]),
        );
      case HeroState.rest:
        return RfCard(
          key: const Key('today-hero-rest'),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow(context, day?.type == DayType.activeRecovery ? 'ACTIVE RECOVERY' : 'REST DAY', c.muted, CupertinoIcons.moon),
            const SizedBox(height: 6),
            Text(day?.title.isNotEmpty == true ? day!.title : 'Recover', style: RfType.title.copyWith(color: c.text)),
            const SizedBox(height: 6),
            Text(day?.notes ?? 'Rest builds the muscle. A walk and 7,000 steps are plenty.', style: RfType.callout.copyWith(color: c.muted)),
            if (next != null) ...[const SizedBox(height: 10), Text('Next: $next', style: RfType.bodyStrong.copyWith(color: c.text))],
          ]),
        );
      case HeroState.empty:
        return RfCard(
          key: const Key('today-hero-empty'),
          child: EmptyState(
            icon: Icons.fitness_center,
            title: 'No plan yet',
            body: 'Answer a few questions and your week is ready in a minute.',
            action: RfButton(label: 'Build my plan', onPressed: onOpenTrain),
          ),
        );
    }
  }

  Widget _eyebrow(BuildContext context, String text, Color color, IconData icon) => Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(text, style: RfType.overline.copyWith(color: color)),
      ]);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/* ------------------------------------------------------------ week strip */

class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.days, required this.onTap});
  final List<StripDay> days;
  final ValueChanged<StripDay> onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Row(children: [
      for (final d in days)
        Expanded(
          child: Semantics(
            button: !d.isToday,
            label: d.semantic,
            excludeSemantics: true,
            child: GestureDetector(
              key: Key('strip-${d.date.weekday}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(d),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: d.isToday ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: d.isToday ? Border.all(color: c.accent, width: 1.4) : null,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat('E').format(d.date).substring(0, 1), style: RfType.captionStrong.copyWith(color: d.isToday ? c.accentInk : c.muted)),
                    const SizedBox(height: 2),
                    Text('${d.date.day}', style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(height: 4),
                    SizedBox(height: 18, child: _mark(c, d)),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _mark(RfColors c, StripDay d) => switch (d.mark) {
        DayMark.done => Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: c.done),
        DayMark.today => d.day != null && d.day!.type.isTraining
            ? Icon(Icons.fitness_center, size: 15, color: c.accentInk)
            : Icon(CupertinoIcons.moon, size: 15, color: c.muted),
        DayMark.planned => Icon(Icons.fitness_center, size: 14, color: c.muted),
        DayMark.missed => Icon(CupertinoIcons.circle, size: 15, color: c.muted),
        DayMark.rest => Text('–', style: RfType.caption.copyWith(color: c.line)),
      };
}

/// Read-only preview of another day (only today's session can be started; see DECISIONS).
class DayPreviewSheet extends StatelessWidget {
  const DayPreviewSheet({super.key, required this.day, required this.planned, required this.exMap, required this.isPast, required this.done});
  final StripDay day;
  final List<PlannedExercise> planned;
  final Map<String, Exercise> exMap;
  final bool isPast;
  final bool done;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final d = day.day;
    final when = DateFormat('EEEE d MMM').format(day.date);
    final training = d != null && d.type.isTraining;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Rf.gutter, 20, Rf.gutter, 24), children: [
      Text(when.toUpperCase(), style: RfType.overline.copyWith(color: c.muted)),
      const SizedBox(height: 4),
      Text(training ? d.title : (d?.title.isNotEmpty == true ? d!.title : 'Rest day'), style: RfType.headline.copyWith(color: c.text)),
      const SizedBox(height: 6),
      Row(children: [
        Icon(CupertinoIcons.eye, size: 16, color: c.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            done
                ? 'Done'
                : !training
                    ? 'Nothing to train'
                    : isPast
                        ? 'Preview · this day has passed'
                        : 'Preview · starts on ${DateFormat('EEEE').format(day.date)}',
            style: RfType.callout.copyWith(color: c.muted),
          ),
        ),
      ]),
      if (training) ...[
        const SizedBox(height: 14),
        for (final p in planned)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(child: Text(exMap[p.exerciseId]?.name ?? p.exerciseId, style: RfType.body.copyWith(color: c.text))),
              Text(
                '${p.sets} × ${p.repsMin == p.repsMax ? p.repsMin : '${p.repsMin}–${p.repsMax}'}${p.unit == Unit.reps ? '' : ' ${p.unit.wire}'}',
                style: RfType.callout.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
          ),
      ],
    ]);
  }
}

/* ------------------------------------------------------------ weekly goal */

class WeeklyGoalCard extends StatelessWidget {
  const WeeklyGoalCard({super.key, required this.done, required this.planned, this.paused});
  final int done;
  final int planned;
  final LifeStatus? paused;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final hit = planned > 0 && done >= planned;
    return RfCard(
      child: Row(children: [
        ProgressRing(
          value: planned == 0 ? 0 : done / planned,
          size: 64,
          stroke: 7,
          color: hit ? c.done : c.accent,
          semanticLabel: '$done of $planned sessions this week',
          child: Text('$done/$planned', style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$done of $planned sessions', style: RfType.bodyStrong.copyWith(color: c.text)),
            const SizedBox(height: 2),
            Text(
              paused != null ? 'Paused while you\'re ${paused!.label.toLowerCase()}. Nothing is lost.' : weeklyGoalWords(done, planned),
              style: RfType.callout.copyWith(color: c.muted),
            ),
          ]),
        ),
        if (hit) Icon(CupertinoIcons.star_fill, color: c.pr, semanticLabel: 'Goal hit'),
      ]),
    );
  }
}

/* ------------------------------------------------------------ missed session re-plan */

class ReplanCard extends StatelessWidget {
  const ReplanCard({
    super.key,
    required this.week,
    required this.today,
    required this.choice,
    required this.onShift,
    required this.onSkip,
    required this.onAskCoach,
    required this.onChange,
  });
  final LiveWeekPlan week;
  final String today;
  final String? choice;
  final VoidCallback onShift;
  final VoidCallback onSkip;
  final VoidCallback onAskCoach;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    if (choice != null) {
      final text = choice == 'skip'
          ? 'Keeping the original week. ${missedWords(week)} is skipped, no catch-up needed.'
          : 'Week re-planned. ${week.byDate[today]?.title != null ? 'Today: ${week.byDate[today]!.title}.' : 'Missed sessions move to your next training days.'}'
              '${week.dropped.isNotEmpty ? ' Dropped this week: ${week.dropped.map((d) => shortTitle(d.title)).join(', ')}.' : ''}';
      return RfCard(
        key: const Key('today-replan-done'),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(children: [
          Icon(CupertinoIcons.calendar, size: 20, color: c.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: RfType.callout.copyWith(color: c.text))),
          TextButton(onPressed: onChange, child: Text('Change', style: RfType.callout.copyWith(color: c.accentInk, fontWeight: FontWeight.w600))),
        ]),
      );
    }
    final todayPlan = week.adjusted && !week.off ? week.byDate[today] : null;
    return RfCard(
      key: const Key('today-replan'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(CupertinoIcons.calendar_badge_plus, size: 22, color: c.accentInk),
          const SizedBox(width: 10),
          Expanded(child: Text('${missedWords(week)}. No problem. Pick one:', style: RfType.bodyStrong.copyWith(color: c.text))),
        ]),
        const SizedBox(height: 12),
        _Option(
          key: const Key('replan-shift'),
          icon: CupertinoIcons.arrow_right_circle,
          title: 'Do it today, shift the week',
          sub: todayPlan != null ? 'Today becomes ${todayPlan.title}; the rest moves along.' : 'Missed sessions move to your next training days.',
          onTap: onShift,
        ),
        _Option(
          key: const Key('replan-merge'),
          icon: Icons.auto_awesome,
          title: 'Merge key lifts into another day',
          sub: 'Ask the coach for a proposal you can approve.',
          onTap: onAskCoach,
          coach: true,
        ),
        _Option(
          key: const Key('replan-skip'),
          icon: CupertinoIcons.forward,
          title: 'Skip it, keep the week',
          sub: 'The rest of the week stays as planned.',
          onTap: onSkip,
        ),
        if (week.missed.length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('A busy week? Set a "Life happens" status below and the weekly goal pauses.', style: RfType.caption.copyWith(color: c.muted)),
          ),
      ]),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.icon, required this.title, required this.sub, required this.onTap, this.coach = false});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool coach;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final tone = coach ? c.coach : c.accentInk;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $sub',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(minHeight: Rf.tap + 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
        child: Row(children: [
          Icon(icon, size: 22, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: RfType.bodyStrong.copyWith(color: c.text)),
              Text(sub, style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
          Icon(CupertinoIcons.chevron_forward, size: 16, color: c.muted),
        ]),
      ),
    );
  }
}

/* ------------------------------------------------------------ diet summary (protein first) */

class DietSummaryCard extends StatelessWidget {
  const DietSummaryCard({
    super.key,
    required this.proteinG,
    required this.proteinTarget,
    required this.kcal,
    required this.kcalTarget,
    this.next,
    this.onAte,
    this.onOpenEat,
  });
  final double proteinG;
  final int proteinTarget;
  final double kcal;
  final int kcalTarget;
  final PlannedMeal? next;
  final VoidCallback? onAte;
  final VoidCallback? onOpenEat;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final p = proteinG.round();
    final hit = proteinTarget > 0 && p >= proteinTarget;
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProgressRing(
            value: proteinTarget == 0 ? 0 : proteinG / proteinTarget,
            size: 72,
            stroke: 8,
            color: hit ? c.done : c.accent,
            semanticLabel: '$p of $proteinTarget grams protein today',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$p', style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
              Text('g', style: RfType.caption.copyWith(color: c.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$p of $proteinTarget g protein', style: RfType.bodyStrong.copyWith(color: c.text)),
              const SizedBox(height: 2),
              Text(
                hit ? 'Protein target hit today.' : '${proteinTarget - p} g to go. Protein first, the rest follows.',
                style: RfType.callout.copyWith(color: c.muted),
              ),
              const SizedBox(height: 2),
              Text('${kcal.round()} of $kcalTarget kcal', style: RfType.caption.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ]),
        if (next != null) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: c.line.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text('NEXT · ${next!.time}', style: RfType.overline.copyWith(color: c.muted)),
          const SizedBox(height: 2),
          Text(next!.meal, style: RfType.bodyStrong.copyWith(color: c.text)),
          Text(next!.items.join(', '), style: RfType.callout.copyWith(color: c.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: RfButton(
                key: const Key('today-ate'),
                label: 'Ate as planned',
                icon: CupertinoIcons.checkmark_alt,
                kind: RfButtonKind.secondary,
                expand: true,
                onPressed: onAte,
              ),
            ),
            const SizedBox(width: 8),
            RfButton(label: 'Eat', kind: RfButtonKind.ghost, onPressed: onOpenEat),
          ]),
        ] else ...[
          const SizedBox(height: 10),
          Text('Every planned meal is logged today.', style: RfType.callout.copyWith(color: c.muted)),
        ],
      ]),
    );
  }
}

/* ------------------------------------------------------------ coach note */

class CoachNoteCard extends StatelessWidget {
  const CoachNoteCard({super.key, required this.title, required this.body, this.onTap});
  final String title;
  final String body;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return RfCard(
      onTap: onTap,
      semanticLabel: 'Coach note: $title. $body',
      border: c.coach.withValues(alpha: 0.35),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 6), child: const CoachDot()),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: RfType.bodyStrong.copyWith(color: c.text)),
            const SizedBox(height: 2),
            Text(body, style: RfType.callout.copyWith(color: c.muted)),
          ]),
        ),
        if (onTap != null) Icon(CupertinoIcons.chevron_forward, size: 16, color: c.muted),
      ]),
    );
  }
}

/* ------------------------------------------------------------ life happens */

class LifeChips extends StatelessWidget {
  const LifeChips({super.key, required this.current, required this.onChanged});
  final LifeStatus? current;
  final ValueChanged<LifeStatus?> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    IconData icon(LifeStatus s) => switch (s) {
          LifeStatus.sick => CupertinoIcons.bandage,
          LifeStatus.travelling => CupertinoIcons.airplane,
          LifeStatus.festival => CupertinoIcons.sparkles,
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in LifeStatus.values)
          RfChip(
            key: Key('life-${s.wire}'),
            label: s.label,
            icon: icon(s),
            selected: current == s,
            onTap: () => onChanged(current == s ? null : s),
          ),
      ]),
      const SizedBox(height: 8),
      Text(current?.note ?? 'Plans bend. Set a status and the week adapts without guilt.', style: RfType.caption.copyWith(color: c.muted)),
    ]);
  }
}
