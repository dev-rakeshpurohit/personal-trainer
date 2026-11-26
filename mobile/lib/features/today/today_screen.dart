// Today: what to do now (UX spec IA). Phase label, the day's workout with one big Start, the week
// strip, the weekly goal, a missed-session re-plan card, protein-first diet summary, one coach note
// and "Life happens" statuses. Port of the useful parts of src/features/today/Today.tsx.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/diet.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../workout/start.dart';
import 'pending_start.dart';
import 'today_cards.dart';
import 'today_logic.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});
  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePendingStart());
  }

  /// Onboarding's "Start Workout 1 now" lands here; start once the tab is on screen.
  void _maybePendingStart() {
    if (!mounted || _starting || ref.read(pendingStartProvider) == null) return;
    final id = ref.read(pendingStartProvider.notifier).take()!;
    _start(id);
  }

  Future<void> _start(String dayId) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await startWorkout(ref, context, dayId: dayId);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingStartProvider, (_, next) {
      if (next != null) WidgetsBinding.instance.addPostFrameCallback((_) => _maybePendingStart());
    });
    final c = context.rf;
    final now = ref.watch(clockProvider)();
    final today = dateOnly(now);
    final todayKey = dayKey(today);

    final profile = ref.watch(profileProvider).value;
    final bundle = ref.watch(programBundleProvider).value;
    final week = ref.watch(weekPlanProvider(today)).value;
    final active = ref.watch(activeSessionProvider).value;
    final todaySessions = ref.watch(todaySessionsProvider).value ?? const <Session>[];
    final weekSessions = ref.watch(weekSessionsProvider(today)).value ?? const <Session>[];
    final diet = ref.watch(dietProvider).value;
    final mealLogs = ref.watch(mealLogsForDayProvider(todayKey)).value ?? const <MealLog>[];
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    final life = LifeStatus.parse(ref.watch(metaProvider(kLifeStatusMeta)).value);
    final choice = ref.watch(metaProvider(replanChoiceKey(today))).value as String?;

    // The shell uses extendBody, so the bottom inset already includes the translucent tab bar.
    final bottomPad = MediaQuery.paddingOf(context).bottom + 16;
    final name = profile == null || profile.name.trim().isEmpty || profile.name == 'there' ? null : profile.name.trim();

    // ---- the day's workout
    final todayDay = week?.byDate[todayKey];
    final originalDay = week?.original[todayKey];
    final moved = week != null && week.adjusted && !week.off && todayDay != null && todayDay.id != originalDay?.id;
    String? movedFrom;
    if (moved) {
      for (final m in week.missed) {
        if (m.day.id == todayDay.id) movedFrom = DateFormat('EEE').format(fromDayKey(m.date));
      }
    }
    final planned = todayDay == null || bundle == null ? const <PlannedExercise>[] : bundle.plannedFor(todayDay.id);
    final doneToday = todaySessions.where((s) => s.status == 'done').firstOrNull;
    final phase = bundle == null ? null : phaseOf(bundle.program, now);
    final muscles = <String>{for (final p in planned) ...?exMap[p.exerciseId]?.primaryMuscles}.take(4).toList();

    final HeroState heroState;
    if (bundle == null) {
      heroState = HeroState.empty;
    } else if (active != null) {
      heroState = HeroState.active;
    } else if (doneToday != null) {
      heroState = HeroState.done;
    } else if (todayDay != null && todayDay.type.isTraining) {
      heroState = HeroState.training;
    } else {
      heroState = HeroState.rest;
    }

    String? next;
    if (heroState == HeroState.rest && bundle != null) {
      for (var i = 1; i <= 7 && next == null; i++) {
        final d = addDays(today, i);
        final k = dayKey(d);
        final p = (week != null && week.byDate.containsKey(k)) ? week.byDate[k] : bundle.days.where((x) => x.weekday == weekdayOf(d)).firstOrNull;
        if (p != null && p.type.isTraining) next = '${DateFormat('EEE').format(d)} · ${p.title}';
      }
    }

    int? doneMin;
    if (doneToday?.endedAt != null) {
      doneMin = DateTime.parse(doneToday!.endedAt!).difference(DateTime.parse(doneToday.startedAt)).inMinutes;
    }

    // ---- week
    final strip = weekStrip(now, week, weekSessions, days: bundle?.days ?? const []);
    final goal = weeklyGoal(week, weekSessions);
    final showReplan = week != null && week.missed.isNotEmpty;

    // ---- diet
    final restDay = todayDay == null || !todayDay.type.isTraining;
    final meals = diet == null ? const <PlannedMeal>[] : mealsForDay(diet.meals, restDay);
    final totals = dayTotals(mealLogs);
    final logged = {for (final l in mealLogs) ?l.plannedMealId};
    final nextMealPlan = nextMeal(meals, logged, DateFormat('HH:mm').format(now));

    // ---- one coach note
    final (noteTitle, noteBody) = life != null
        ? ('${life.label}: the week bends', life.note)
        : phase != null && phase.deload
        ? ('Deload week', 'Half the sets, same weights. Your body catches up and you come back stronger.')
        : doneToday != null
        ? ('Nice work today', 'Hit your protein and sleep 7+ hours; that is when the session turns into progress.')
        : phase?.note != null && phase!.note!.isNotEmpty
        ? (phase.focus == null ? 'This week' : 'This week: ${phase.focus}', phase.note!)
        : ('Your coach is here', 'Ask for a change in plain words: "no squats today, knee hurts".');

    return Scaffold(
      backgroundColor: c.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context, now, name, phase?.label, phase?.deload ?? false)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, bottomPad),
            // A handful of cards: build them eagerly so cards that change height (re-plan, life status)
            // never upset a lazy list's scroll estimate.
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (life != null) ...[
                    RfCard(
                      key: const Key('today-life-banner'),
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.pause_circle, color: c.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${life.label}. Your weekly goal is paused.', style: RfType.callout.copyWith(color: c.text)),
                          ),
                          TextButton(
                            onPressed: () => _setLife(null),
                            child: Text(
                              'Clear',
                              style: RfType.callout.copyWith(color: c.accentInk, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showReplan) ...[
                    ReplanCard(
                      week: week,
                      today: todayKey,
                      choice: choice,
                      onShift: () => _replan(today, 'shift'),
                      onSkip: () => _replan(today, 'skip'),
                      onAskCoach: () => context.go('/coach'),
                      onChange: () => _replan(today, null),
                    ),
                    const SizedBox(height: 12),
                  ],
                  WorkoutCard(
                    state: heroState,
                    day: heroState == HeroState.done ? (bundle?.days.where((d) => d.id == doneToday?.programDayId).firstOrNull ?? todayDay) : todayDay,
                    exerciseCount: planned.length,
                    muscles: muscles,
                    movedFrom: movedFrom,
                    deload: phase?.deload ?? false,
                    doneMinutes: doneMin,
                    activeTitle: heroState == HeroState.done ? doneToday?.title : active?.session.title,
                    next: next,
                    life: life,
                    onStart: _starting || todayDay == null ? null : () => _start(todayDay.id),
                    onResume: () => resumeWorkout(context),
                    onOpenTrain: () => bundle == null ? context.push('/onboarding?fresh=1') : context.go('/train'),
                  ),
                  if (bundle != null) ...[
                    const SectionTitle('This week', padding: EdgeInsets.fromLTRB(4, 22, 4, 10)),
                    WeekStrip(days: strip, onTap: (d) => _preview(d, bundle, exMap, weekSessions)),
                    const SizedBox(height: 12),
                    WeeklyGoalCard(done: goal.done, planned: goal.planned, paused: life),
                  ],
                  if (diet != null) ...[
                    const SectionTitle('Food today', padding: EdgeInsets.fromLTRB(4, 22, 4, 10)),
                    DietSummaryCard(
                      proteinG: totals.proteinG,
                      proteinTarget: diet.plan.proteinTargetG,
                      kcal: totals.kcal,
                      kcalTarget: diet.plan.kcalTarget,
                      next: nextMealPlan,
                      onAte: nextMealPlan == null ? null : () => _ate(todayKey, nextMealPlan),
                      onOpenEat: () => context.go('/eat'),
                    ),
                  ],
                  const SectionTitle('Coach', padding: EdgeInsets.fromLTRB(4, 22, 4, 10)),
                  CoachNoteCard(title: noteTitle, body: noteBody, onTap: () => context.go('/coach')),
                  const SectionTitle('Life happens', padding: EdgeInsets.fromLTRB(4, 22, 4, 10)),
                  LifeChips(current: life, onChanged: _setLife),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, DateTime now, String? name, String? phase, bool deload) {
    final c = context.rf;
    return Padding(
      padding: EdgeInsets.fromLTRB(Rf.gutter, MediaQuery.paddingOf(context).top + 10, Rf.gutter, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEEE, d MMMM').format(now), style: RfType.callout.copyWith(color: c.muted)),
                Semantics(
                  header: true,
                  child: Text('${greeting(now.hour)}${name == null ? '' : ', $name'}', style: RfType.title.copyWith(color: c.text)),
                ),
                if (phase != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: const Key('today-phase'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.chipRadius)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(deload ? CupertinoIcons.arrow_down_circle : CupertinoIcons.chart_bar_alt_fill, size: 14, color: c.muted),
                        const SizedBox(width: 6),
                        Text(phase, style: RfType.captionStrong.copyWith(color: c.text)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Profile and settings',
            excludeSemantics: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _profileSheet,
              child: SizedBox(
                width: Rf.tap,
                height: Rf.tap,
                child: Center(
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: c.surface2,
                    child: name == null
                        ? Icon(CupertinoIcons.person_fill, color: c.muted, size: 20)
                        : Text(name.characters.first.toUpperCase(), style: RfType.bodyStrong.copyWith(color: c.text)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------ actions */

  void _profileSheet() {
    showRfSheet<void>(
      context,
      builder: (ctx) {
        final c = ctx.rf;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Rf.gutter, 20, Rf.gutter, 20),
          children: [
            Text('You', style: RfType.headline.copyWith(color: c.text)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(CupertinoIcons.arrow_2_circlepath, color: c.accentInk),
              title: const Text('Redo setup'),
              subtitle: const Text('New answers, new plan. Your history is kept.'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/onboarding?fresh=1');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(CupertinoIcons.gear, color: c.muted),
              title: const Text('Settings'),
              subtitle: const Text('Coming in a later beta'),
              enabled: false,
            ),
          ],
        );
      },
    );
  }

  Future<void> _replan(DateTime today, String? choice) async {
    final s = ref.read(storesProvider);
    await s.setMeta(replanChoiceKey(today), choice);
    // "Skip it" keeps the original week; anything else uses the automatic re-plan.
    await s.setMeta(replanOffKey(today), choice == 'skip');
  }

  Future<void> _setLife(LifeStatus? status) async {
    final s = ref.read(storesProvider);
    final now = ref.read(clockProvider)();
    final prev = await s.getMeta<Object?>(kLifeStatusMeta);
    await s.setMeta(kLifeStatusMeta, status == null ? null : {'kind': status.wire, 'since': dayKey(now)});
    if (!mounted) return;
    showRfToast(
      context,
      status == null ? 'Status cleared. Welcome back.' : '${status.label} status on. Your weekly goal is paused.',
      onUndo: () => s.setMeta(kLifeStatusMeta, prev),
    );
  }

  Future<void> _ate(String todayKey, PlannedMeal meal) async {
    final undo = await ref.read(repoProvider).logMeal(todayKey, meal, 'eaten');
    if (!mounted) return;
    showRfToast(context, '${meal.meal} logged: ${meal.proteinG.round()} g protein', icon: CupertinoIcons.checkmark_alt, onUndo: undo);
  }

  void _preview(StripDay d, ProgramBundle bundle, Map<String, Exercise> exMap, List<Session> weekSessions) {
    if (d.isToday) return;
    final day = d.day;
    showRfSheet<void>(
      context,
      builder: (_) => DayPreviewSheet(
        day: d,
        planned: day == null ? const [] : bundle.plannedFor(day.id),
        exMap: exMap,
        isPast: d.date.isBefore(dateOnly(ref.read(clockProvider)())),
        done: d.mark == DayMark.done,
      ),
    );
  }
}
