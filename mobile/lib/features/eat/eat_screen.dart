// Eat tab: protein ring, the day's timeline (Breakfast · Lunch · Snacks · Dinner) of planned meals
// as ghost cards, a vrat-day toggle, water & habits, and the Hinglish log bar pinned above the tabs.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/diet.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'eat_logic.dart';
import 'eat_service.dart';
import 'habits_row.dart';
import 'log_bar.dart';
import 'meal_cards.dart';
import 'review_tray.dart';

/// Everything the Eat tab needs for one day, derived from providers.
class EatDay {
  const EatDay({
    required this.date,
    required this.today,
    required this.dayKey,
    required this.meals,
    required this.logs,
    required this.targets,
    required this.totals,
    required this.hitDays,
    required this.prefs,
    required this.restDay,
    required this.dietType,
    required this.intolerances,
    this.planName,
  });
  final DateTime date;
  final DateTime today;
  final String dayKey;
  final List<PlannedMeal> meals;
  final List<MealLog> logs;
  final DayTargets targets;
  final Totals totals;
  final ({int hit, int days}) hitDays;
  final EatPrefs prefs;
  final bool restDay;
  final DietType dietType;
  final List<String> intolerances;
  final String? planName;

  bool get vrat => targets.vrat;
  bool get isToday => daysBetween(today, date) == 0;

  /// The day's protein target without the vrat easing.
  double get baseProtein => vrat ? targets.protein / kVratProteinShare : targets.protein;
}

class EatScreen extends ConsumerStatefulWidget {
  const EatScreen({super.key});
  @override
  ConsumerState<EatScreen> createState() => _EatScreenState();
}

class _EatScreenState extends ConsumerState<EatScreen> {
  DateTime? _date;

  EatDay? _load() {
    final now = ref.watch(clockProvider)();
    final today = dateOnly(now);
    final date = _date ?? today;
    final k = dayKey(date);
    final profile = ref.watch(profileProvider).value;
    final diet = ref.watch(dietProvider).value;
    final dietLoading = ref.watch(dietProvider).isLoading;
    if (dietLoading && diet == null) return null;
    final logs = ref.watch(mealLogsForDayProvider(k)).value ?? const <MealLog>[];
    final weekLogs = ref.watch(weekMealLogsProvider(mondayKeyOf(date))).value ?? const <MealLog>[];
    final prefs = ref.watch(eatPrefsProvider).value ?? EatPrefs.empty;
    final week = ref.watch(weekPlanProvider(date)).value;
    final bundle = ref.watch(programBundleProvider).value;
    ProgramDay? day;
    if (week != null && week.byDate.containsKey(k)) {
      day = week.byDate[k];
    } else if (bundle != null) {
      day = getDayPlan(bundle.days, date, (d) => d.weekday);
    }
    final restDay = day == null || !day.type.isTraining;
    final meals = diet == null ? const <PlannedMeal>[] : mealsForDay(diet.meals, restDay);
    final pTarget = diet?.plan.proteinTargetG ?? profile?.proteinTargetG ?? 0;
    final kTarget = diet?.plan.kcalTarget ?? profile?.kcalTarget ?? 0;
    final targets = targetsFor(protein: pTarget, kcal: kTarget, vrat: prefs.vratDays.contains(k));
    final weekEnd = addDays(weekStartOf(date), 6);
    final hit = proteinHitDays(
      today: weekEnd.isBefore(today) ? weekEnd : today,
      weekLogs: weekLogs,
      proteinTarget: pTarget,
      kcalTarget: kTarget,
      vratDays: prefs.vratDays,
    );
    return EatDay(
      date: date,
      today: today,
      dayKey: k,
      meals: meals,
      logs: logs,
      targets: targets,
      totals: dayTotals(logs),
      hitDays: hit,
      prefs: prefs,
      restDay: restDay,
      dietType: profile?.dietType ?? DietType.vegEgg,
      intolerances: profile?.intolerances ?? const [],
      planName: diet?.plan.name,
    );
  }

  void _shift(int days, DateTime today) {
    final cur = _date ?? today;
    final next = addDays(cur, days);
    if (next.isAfter(today)) return;
    Haptics.tick();
    setState(() => _date = next);
  }

  Future<void> _toggleVrat(EatDay d) async {
    final svc = ref.read(eatServiceProvider);
    final undo = await svc.toggleVrat(d.dayKey);
    if (!mounted) return;
    final on = !d.vrat;
    final eased = (d.baseProtein * kVratProteinShare).round();
    showRfToast(
      context,
      on ? 'Vrat day on · fasting menu, protein eased to $eased g' : 'Vrat day off · regular plan back',
      icon: CupertinoIcons.moon_stars,
      onUndo: () => undo(),
    );
  }

  Future<void> _openTray(EatDay d, {String text = '', PlannedMeal? forMeal, MealSlot? slot}) async {
    await showReviewTray(context, day: d, text: text, forMeal: forMeal, slot: slot ?? (d.isToday ? slotForTime(hhmmOf(ref.read(clockProvider)())) : MealSlot.dinner));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final d = _load();
    // The shell uses extendBody, so this padding already includes the tab bar's height. While the
    // keyboard is up the shell's body is resized to end at the keyboard, so the bar sits at 0.
    final keyboardUp = MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;
    final tabPad = MediaQuery.paddingOf(context).bottom;
    final barBottom = keyboardUp ? 0.0 : tabPad;
    return Scaffold(
      backgroundColor: c.bg,
      // The log bar lives in the bottom slot so toasts (with Undo) float above it, not over it.
      extendBody: true,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: d == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: barBottom),
              child: LogBar(
                goTos: goTosFor(d.prefs.recent, d.isToday ? slotForTime(hhmmOf(ref.read(clockProvider)())) : MealSlot.dinner),
                onSubmit: (text) => _openTray(d, text: text),
              ),
            ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverToBoxAdapter(child: PageHeader(title: 'Eat', eyebrow: d.planName)),
              SliverToBoxAdapter(child: _DayHeader(day: d, onPrev: () => _shift(-1, d.today), onNext: () => _shift(1, d.today), onVrat: () => _toggleVrat(d))),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, 0),
                  child: ProteinCard(day: d),
                ),
              ),
              if (d.meals.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.restaurant_outlined,
                    title: 'No diet plan yet',
                    body: 'Log anything you eat with the bar below. A plan adds one-tap meals here.',
                  ),
                ),
              for (final slot in MealSlot.values) ..._slotSlivers(d, slot),
              const SliverToBoxAdapter(child: SectionTitle('Water & habits')),
              SliverToBoxAdapter(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: Rf.gutter), child: HabitsRow(dayKey: d.dayKey)),
              ),
              SliverToBoxAdapter(child: SizedBox(height: tabPad + LogBar.height + 24)),
            ]),
    );
  }

  List<Widget> _slotSlivers(EatDay d, MealSlot slot) {
    final planned = d.meals.where((m) => slotOf(m) == slot).toList();
    final extras = d.logs.where((l) => isExtraLog(l) && slotOfExtra(l) == slot).toList()..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    if (planned.isEmpty && extras.isEmpty && d.meals.isEmpty) return const [];
    final eaten = [
      for (final m in planned) ...d.logs.where((l) => l.plannedMealId == m.id && l.state != 'skipped'),
      ...extras,
    ].fold<double>(0, (a, l) => a + l.proteinG);
    return [
      SliverToBoxAdapter(
        child: SectionTitle(
          slot.label,
          trailing: eaten > 0 ? Text('${eaten.round()} g protein', style: RfType.captionStrong.copyWith(color: context.rf.muted)) : null,
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Rf.gutter),
        sliver: SliverList.list(children: [
          for (var i = 0; i < planned.length; i++) ...[
            PlannedMealCard(
              meal: planned[i],
              log: d.logs.where((l) => l.plannedMealId == planned[i].id).firstOrNull,
              day: d,
              vratIndex: i,
              onSomethingElse: () => _openTray(d, forMeal: planned[i], slot: slot),
            ),
            const SizedBox(height: 10),
          ],
          for (final l in extras) ...[
            ExtraLogCard(log: l, dayKey: d.dayKey),
            const SizedBox(height: 10),
          ],
          if (planned.isEmpty && extras.isEmpty)
            _EmptySlot(slot: slot, onTap: () => _openTray(d, slot: slot)),
        ]),
      ),
    ];
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.slot, required this.onTap});
  final MealSlot slot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Log ${slot.label.toLowerCase()}',
      child: Container(
        constraints: const BoxConstraints(minHeight: Rf.tap),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Rf.cardRadius), border: Border.all(color: c.line, width: 0.8)),
        child: Row(children: [
          Icon(CupertinoIcons.plus, size: 18, color: c.muted),
          const SizedBox(width: 8),
          Text('Add ${slot.label.toLowerCase()}', style: RfType.callout.copyWith(color: c.muted)),
        ]),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.onPrev, required this.onNext, required this.onVrat});
  final EatDay day;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onVrat;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final diff = daysBetween(day.today, day.date);
    final title = diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : DateFormat('EEEE').format(day.date);
    Widget arrow(IconData icon, String label, VoidCallback? onTap) => Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          excludeSemantics: true,
          child: Opacity(
            opacity: onTap == null ? 0.3 : 1,
            child: Pressable(
              onTap: onTap,
              child: Container(
                width: Rf.tap,
                height: Rf.tap,
                decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: c.text),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, 4),
      child: Row(children: [
        arrow(CupertinoIcons.chevron_left, 'Previous day', onPrev),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: RfType.bodyStrong.copyWith(color: c.text)),
            Text(
              '${DateFormat('d MMM').format(day.date)} · ${day.vrat ? 'vrat menu' : day.restDay ? 'rest-day menu' : 'training-day menu'}',
              style: RfType.caption.copyWith(color: c.muted),
            ),
          ]),
        ),
        RfChip(label: 'Vrat day', icon: CupertinoIcons.moon_stars, selected: day.vrat, onTap: onVrat),
        const SizedBox(width: 8),
        arrow(CupertinoIcons.chevron_right, 'Next day', day.isToday ? null : onNext),
      ]),
    );
  }
}

/// Large protein ring ("78 / 110 g"), calories as a secondary bar, and protein-hit days this week.
class ProteinCard extends StatelessWidget {
  const ProteinCard({super.key, required this.day});
  final EatDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final p = day.totals.proteinG;
    final pt = day.targets.protein;
    final k = day.totals.kcal;
    final kt = day.targets.kcal;
    final hitToday = proteinHit(p, pt);
    final left = (pt - p).clamp(0, double.infinity).round();
    final nf = NumberFormat.decimalPattern();
    return RfCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ProgressRing(
            value: pt > 0 ? p / pt : 0,
            size: 128,
            stroke: 12,
            color: hitToday ? c.done : c.accent,
            semanticLabel: 'Protein ${p.round()} of ${pt.round()} grams',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${p.round()}', style: RfType.setNumeral.copyWith(color: c.text)),
              Text('/ ${pt.round()} g', style: RfType.captionStrong.copyWith(color: c.muted)),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Protein', style: RfType.headline.copyWith(color: c.text)),
              const SizedBox(height: 2),
              Row(children: [
                if (hitToday) ...[Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: c.done), const SizedBox(width: 4)],
                Flexible(
                  child: Text(
                    hitToday ? 'Target hit today' : '$left g to go${day.vrat ? ' · vrat target' : ''}',
                    style: RfType.callout.copyWith(color: hitToday ? c.done : c.muted, fontWeight: hitToday ? FontWeight.w600 : null),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Text('Calories', style: RfType.captionStrong.copyWith(color: c.muted)),
              const SizedBox(height: 5),
              LinearMeter(value: kt > 0 ? k / kt : 0, color: c.muted, height: 6),
              const SizedBox(height: 4),
              Text('${nf.format(k.round())} / ${nf.format(kt.round())} kcal', style: RfType.caption.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        _HitDays(hit: day.hitDays.hit, days: day.hitDays.days),
      ]),
    );
  }
}

class _HitDays extends StatelessWidget {
  const _HitDays({required this.hit, required this.days});
  final int hit;
  final int days;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      label: 'Protein-hit days $hit of $days this week',
      excludeSemantics: true,
      child: Row(children: [
        Expanded(
          child: Text(
            'Protein-hit days $hit/$days',
            maxLines: 2,
            style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        for (var i = 0; i < days; i++)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < hit ? c.done : Colors.transparent,
                border: Border.all(color: i < hit ? c.done : c.line, width: 1.2),
              ),
            ),
          ),
      ]),
    );
  }
}
