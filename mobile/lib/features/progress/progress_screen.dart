// Progress tab: the Weekly card (sessions, top sets, trend weight, protein-hit days, one sentence),
// lift charts with PR markers, strength level per main lift, body trend + logging, photos (soon)
// and workout history.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/stats.dart';
import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../eat/eat_logic.dart';
import '../eat/eat_service.dart';
import 'body_section.dart';
import 'history.dart';
import 'lift_charts.dart';
import 'progress_data.dart';

/// Every working set (warm-ups excluded), live.
final workSetsProvider = StreamProvider<List<SetLog>>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'sets'}, () async => (await s.sets.all()).where((x) => !x.isWarmup).toList());
});

/// Inputs every Progress section shares.
class ProgressModel {
  const ProgressModel({
    required this.now,
    required this.profile,
    required this.sessions,
    required this.exercises,
    required this.mainLifts,
    required this.series,
    required this.weights,
    required this.body,
  });
  final DateTime now;
  final Profile profile;
  final Map<String, Session> sessions;
  final Map<String, Exercise> exercises;
  final List<String> mainLifts;

  /// Lift series by exercise id (every exercise with logged sets).
  final Map<String, List<LiftPoint>> series;
  final List<StatPoint> weights;
  final List<BodyLog> body;

  String get units => profile.units;

  /// Body weight for strength ratios: the 7-day trend, else the last weigh-in, else the start weight.
  double get bodyweightKg => current7dAvg(weights, dateOnly(now)) ?? (weights.isEmpty ? profile.startWeightKg : weights.last.value);
}

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final profile = ref.watch(profileProvider).value;
    final done = ref.watch(doneSessionsProvider).value;
    final sets = ref.watch(workSetsProvider).value;
    final exMap = ref.watch(exerciseMapProvider).value;
    final body = ref.watch(bodyLogsProvider).value;
    final bundle = ref.watch(programBundleProvider).value;
    final bottom = MediaQuery.paddingOf(context).bottom + 16;

    if (profile == null || done == null || sets == null || exMap == null || body == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final sessions = {for (final s in done) s.id: s};
    final byEx = <String, List<SetLog>>{};
    for (final x in sets) {
      (byEx[x.exerciseId] ??= []).add(x);
    }
    final series = {for (final e in byEx.entries) e.key: liftSeries(e.value, sessions)}..removeWhere((_, v) => v.isEmpty);
    var mains = bundle == null ? <String>[] : mainLiftIds(bundle.planned, exMap);
    mains = mains.where(series.containsKey).toList();
    if (mains.isEmpty) {
      // No plan slots with data: fall back to the most-logged weighted lifts.
      mains = (series.entries.where((e) => e.value.any((p) => p.weighted)).toList()..sort((a, b) => b.value.length - a.value.length)).map((e) => e.key).take(4).toList();
    }
    final model = ProgressModel(
      now: now,
      profile: profile,
      sessions: sessions,
      exercises: exMap,
      mainLifts: mains,
      series: series,
      weights: [for (final b in body) if (b.weightKg != null) (dayKey: b.dayKey, value: b.weightKg!)],
      body: body,
    );

    return Scaffold(
      body: CustomScrollView(slivers: [
        const SliverToBoxAdapter(child: PageHeader(title: 'Progress')),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, bottom),
          sliver: SliverList.list(children: [
            WeeklyCard(model: model),
            const SectionTitle('Lifts', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            LiftChartCard(model: model),
            const SectionTitle('Strength level', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            StrengthCard(model: model),
            const SectionTitle('Body', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            BodySection(model: model),
            const SectionTitle('Workout history', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            HistoryList(model: model, limit: 5),
          ]),
        ),
      ]),
    );
  }
}

/// The one view no competitor has: this week's training, top sets, trend weight and protein on one card.
class WeeklyCard extends ConsumerWidget {
  const WeeklyCard({super.key, required this.model});
  final ProgressModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final now = model.now;
    final today = dateOnly(now);
    final weekSessions = ref.watch(weekSessionsProvider(today)).value ?? const <Session>[];
    final plan = ref.watch(weekPlanProvider(today)).value;
    final diet = ref.watch(dietProvider).value;
    final logs = ref.watch(weekMealLogsProvider(mondayKeyOf(today))).value ?? const <MealLog>[];
    final prefs = ref.watch(eatPrefsProvider).value ?? EatPrefs.empty;
    final done = weekSessions.where((s) => s.status == 'done').length;
    final planned = plan == null ? 0 : plan.byDate.values.where((d) => d != null && d.type.isTraining).length;
    final hit = proteinHitDays(
      today: today,
      weekLogs: logs,
      proteinTarget: diet?.plan.proteinTargetG ?? model.profile.proteinTargetG,
      kcalTarget: diet?.plan.kcalTarget ?? model.profile.kcalTarget,
      vratDays: prefs.vratDays,
    );
    final w = weeklySummary(
      now: now,
      done: done,
      planned: planned,
      mainSeries: {for (final id in model.mainLifts) id: model.series[id] ?? const []},
      weights: model.weights,
      proteinHit: hit.hit,
      goalWeightKg: model.profile.goalWeightKg,
    );
    final u = model.units;
    String kg(double v) => (u == 'kg' ? v : v / 0.45359237).toStringAsFixed(1);
    final delta = w.trendDeltaKg;

    Widget stat(IconData icon, String label, String value, String sub, {Color? tone, Key? key}) => Expanded(
          child: Semantics(
            label: '$label $value, $sub',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 15, color: tone ?? c.muted),
                const SizedBox(width: 5),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.captionStrong.copyWith(color: c.muted))),
              ]),
              const SizedBox(height: 3),
              Text(value, key: key, style: RfType.headline.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(sub, maxLines: 2, style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
        );

    return RfCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('This week', style: RfType.headline.copyWith(color: c.text))),
          if (planned > 0 && done >= planned) StatusPill(label: 'Goal hit', color: c.done, icon: CupertinoIcons.checkmark_alt),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          stat(Icons.fitness_center, 'Sessions', planned > 0 ? '$done/$planned' : '$done', 'done vs planned', tone: done > 0 ? c.done : null),
          const SizedBox(width: 12),
          stat(CupertinoIcons.arrow_up_right, 'Top sets', w.liftsTrained == 0 ? '–' : '${w.liftsUp}/${w.liftsTrained}', w.liftsUp > 0 ? 'lifts beat their best' : 'main lifts holding'),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          stat(
            CupertinoIcons.waveform_path,
            'Trend weight',
            w.trendKg == null ? '–' : '${kg(w.trendKg!)} $u',
            delta == null ? '7-day average' : '${delta <= 0 ? '−' : '+'}${kg(delta.abs())} $u this week',
            key: const ValueKey('weekly-trend'),
          ),
          const SizedBox(width: 12),
          stat(Icons.egg_alt_outlined, 'Protein days', '${w.proteinHit}/7', 'hit 90% of target', tone: w.proteinHit > 0 ? c.done : null),
        ]),
        const SizedBox(height: 14),
        Text(w.sentence, key: const ValueKey('weekly-sentence'), style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
