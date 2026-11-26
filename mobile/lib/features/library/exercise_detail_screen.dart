// Exercise detail: demo, how-to, muscles, alternates, the user's history (e1RM with PR markers)
// and "Add to my plan".
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/equipment.dart';
import '../../domain/models.dart';
import '../../domain/units.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../train/train_data.dart' show planOpsProvider;
import 'library_data.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId, this.showAddToPlan = true});
  final String exerciseId;
  final bool showAddToPlan;

  static Future<void> open(BuildContext context, String id, {bool showAddToPlan = true}) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => ExerciseDetailScreen(exerciseId: id, showAddToPlan: showAddToPlan)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final exMap = ref.watch(exerciseMapProvider).value;
    final ex = exMap?[exerciseId];
    if (exMap == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (ex == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: CupertinoIcons.question_circle, title: 'Exercise not found'));
    }
    final eq = ref.watch(availableEquipmentProvider);
    final fits = isAvailable(ex, eq);
    final alternates = [for (final id in ex.alternates ?? const <String>[]) ?exMap[id]];
    final helpers = ex.secondaryMuscles ?? const <String>[];
    final equipment = ex.equipment.where((x) => x != 'other' && x != 'body only').toList();

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, MediaQuery.paddingOf(context).bottom + 16),
        children: [
          Semantics(header: true, child: Text(ex.name, style: RfType.title.copyWith(color: c.text))),
          const SizedBox(height: 12),
          DemoPlayer(exercise: ex, height: 260),
          const SizedBox(height: 12),
          if (showAddToPlan) ...[
            RfButton(label: 'Add to my plan', icon: CupertinoIcons.calendar_badge_plus, expand: true, onPressed: () => _addToPlan(context, ref, ex, fits)),
            const SizedBox(height: 4),
          ],
          if (!fits)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(CupertinoIcons.info_circle, size: 16, color: c.caution),
                const SizedBox(width: 6),
                Expanded(child: Text('Needs equipment you haven’t marked as available in your gym.', style: RfType.caption.copyWith(color: c.caution))),
              ]),
            ),
          if (ex.cue != null || (ex.instructions?.isNotEmpty ?? false)) ...[
            const SectionTitle('How to', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            RfCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (ex.cue != null) Text(ex.cue!, style: RfType.bodyStrong.copyWith(color: c.text)),
                for (final (i, step) in (ex.instructions ?? const <String>[]).indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 22, child: Text('${i + 1}.', style: RfType.callout.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
                      Expanded(child: Text(step, style: RfType.callout.copyWith(color: c.text))),
                    ]),
                  ),
              ]),
            ),
          ],
          const SectionTitle('Muscles', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in ex.primaryMuscles) _Tag(label: _cap(m), filled: true),
            for (final m in helpers) _Tag(label: _cap(m), filled: false),
          ]),
          const SizedBox(height: 6),
          Text(
            helpers.isEmpty ? 'Main muscles worked.' : 'Filled: main muscles · Outlined: helpers (count half in Plan check).',
            style: RfType.caption.copyWith(color: c.muted),
          ),
          if (equipment.isNotEmpty || ex.level != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in equipment) _Tag(label: _cap(e), filled: false, icon: Icons.fitness_center),
              if (ex.level != null) _Tag(label: 'Difficulty ${ex.level} of 5', filled: false, icon: CupertinoIcons.chart_bar),
            ]),
          ],
          const SectionTitle('Your history', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
          _History(ex: ex),
          if (alternates.isNotEmpty) ...[
            const SectionTitle('Alternates', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
            Text('Same movement, different equipment or difficulty. Each keeps its own history.', style: RfType.caption.copyWith(color: c.muted)),
            const SizedBox(height: 8),
            for (final a in alternates)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RfCard(
                  padding: const EdgeInsets.all(8),
                  onTap: () => ExerciseDetailScreen.open(context, a.id, showAddToPlan: showAddToPlan),
                  semanticLabel: '${a.name}${isAvailable(a, eq) ? '' : ', needs other equipment'}',
                  child: Row(children: [
                    ExerciseThumb(exercise: a, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, style: RfType.bodyStrong.copyWith(color: c.text)),
                        Text(isAvailable(a, eq) ? 'Fits your gym' : 'Needs other equipment', style: RfType.caption.copyWith(color: c.muted)),
                      ]),
                    ),
                    Icon(CupertinoIcons.chevron_right, size: 18, color: c.muted),
                  ]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _addToPlan(BuildContext context, WidgetRef ref, Exercise ex, bool fits) async {
    final bundle = ref.read(programBundleProvider).value;
    if (bundle == null) {
      showRfToast(context, 'Set up a plan first.');
      return;
    }
    final dayId = await showRfSheet<String>(context, builder: (ctx) {
      final c = ctx.rf;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 24),
        children: [
          Text('Add ${ex.name}', style: RfType.headline.copyWith(color: c.text)),
          const SizedBox(height: 4),
          Text('Adds 3 sets at the end of the day. Fine-tune it in the day editor.', style: RfType.callout.copyWith(color: c.muted)),
          const SizedBox(height: 12),
          for (final d in [...bundle.days]..sort((a, b) => a.order - b.order))
            Builder(builder: (_) {
              final already = bundle.plannedFor(d.id).any((p) => p.exerciseId == ex.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Opacity(
                  opacity: already ? 0.55 : 1,
                  child: RfCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: already ? null : () => Navigator.of(ctx).pop(d.id),
                    semanticLabel: '${d.weekday.label}, ${d.title}${already ? ', already in this day' : ''}',
                    child: Row(children: [
                      SizedBox(width: 44, child: Text(d.weekday.label, style: RfType.captionStrong.copyWith(color: c.muted))),
                      Expanded(child: Text(d.title, style: RfType.bodyStrong.copyWith(color: c.text))),
                      if (already)
                        StatusPill(label: 'Already there', color: c.done, icon: CupertinoIcons.checkmark_alt)
                      else
                        Text(d.type.isTraining ? '' : 'Becomes a workout', style: RfType.caption.copyWith(color: c.muted)),
                    ]),
                  ),
                ),
              );
            }),
        ],
      );
    });
    if (dayId == null) return;
    final pe = await ref.read(planEditProvider).addExerciseToDay(dayId, ex.id);
    Haptics.setDone();
    if (!context.mounted) return;
    final day = bundle.days.firstWhere((d) => d.id == dayId);
    final ops = ref.read(planOpsProvider);
    final wasType = day.type;
    showRfToast(context, 'Added to ${day.title} · ${pe.sets} sets', icon: CupertinoIcons.checkmark_alt, onUndo: () async {
      await ops.remove(pe.id);
      if (!wasType.isTraining) await ops.updateDay(day);
    });
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.filled, this.icon});
  final String label;
  final bool filled;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? c.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(Rf.chipRadius),
        border: Border.all(color: filled ? c.surface2 : c.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c.muted), const SizedBox(width: 5)],
        Text(label, style: RfType.caption.copyWith(color: filled ? c.text : c.muted, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.ex});
  final Exercise ex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final history = ref.watch(liftHistoryProvider(ex.id)).value;
    final units = ref.watch(profileProvider).value?.units ?? 'kg';
    if (history == null) return const SizedBox(height: 80);
    if (history.isEmpty) {
      return RfCard(
        child: Row(children: [
          Icon(CupertinoIcons.chart_bar_alt_fill, color: c.muted),
          const SizedBox(width: 10),
          Expanded(child: Text('No sets logged yet. Your trend and PRs show here after your first session.', style: RfType.callout.copyWith(color: c.muted))),
        ]),
      );
    }
    final withE1rm = [for (final h in history) if (h.bestE1rm != null) h];
    final df = DateFormat('d MMM');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (withE1rm.isNotEmpty) _E1rmCard(sessions: withE1rm, units: units),
      if (withE1rm.isEmpty)
        RfCard(
          child: Text(
            ex.defaultUnit == Unit.seconds
                ? 'Longest hold: ${history.map((h) => h.bestSeconds).reduce((a, b) => a > b ? a : b)} s across ${history.length} sessions.'
                : 'Best: ${history.map((h) => h.bestReps).reduce((a, b) => a > b ? a : b)} reps across ${history.length} sessions.',
            style: RfType.bodyStrong.copyWith(color: c.text),
          ),
        ),
      const SizedBox(height: 10),
      RfCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(children: [
          for (final h in history.reversed.take(6))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.4), width: 0.5))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 64, child: Text(df.format(DateTime.parse(h.session.startedAt).toLocal()), style: RfType.captionStrong.copyWith(color: c.muted))),
                Expanded(
                  child: Text(
                    h.sets.map((s) => _setText(s, units)).join(' · '),
                    style: RfType.callout.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

String _setText(SetLog s, String units) {
  if (s.seconds != null) return '${s.seconds}s';
  if (s.meters != null) return '${s.meters!.round()} m';
  final w = s.weightKg != null && s.weightKg! > 0 ? '${displayWeight(s.weightKg, units)}×' : '';
  return '$w${s.reps ?? ''}';
}

class _E1rmCard extends StatelessWidget {
  const _E1rmCard({required this.sessions, required this.units});
  final List<LiftSession> sessions;
  final String units;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final values = [for (final s in sessions) s.bestE1rm!];
    final prs = prIndexes(values).toSet();
    final first = DateTime.parse(sessions.first.session.startedAt).toLocal();
    final xs = [for (final s in sessions) DateTime.parse(s.session.startedAt).toLocal().difference(first).inHours / 24];
    final display = [for (final v in values) toUserUnits(v, units)];
    final meaning = _meaning(values, first);
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(xs[i], display[i])];
    final minY = display.reduce((a, b) => a < b ? a : b);
    final maxY = display.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.25).clamp(2.0, double.infinity);

    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(meaning, style: RfType.bodyStrong.copyWith(color: c.text)),
        const SizedBox(height: 2),
        Text('Estimated 1-rep max · latest ${displayWeight(values.last, units)} $units', style: RfType.caption.copyWith(color: c.muted)),
        const SizedBox(height: 14),
        Semantics(
          label: 'Estimated one-rep max trend: $meaning',
          child: SizedBox(
            height: 160,
            child: spots.length == 1
                ? Center(child: Text('${displayWeight(values.first, units)} $units', style: RfType.setNumeral.copyWith(color: c.text)))
                : LineChart(
                    LineChartData(
                      minY: minY - pad,
                      maxY: maxY + pad,
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(color: c.line.withValues(alpha: 0.5), strokeWidth: 0.6),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        bottomTitles: const AxisTitles(),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (v, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(meta.formattedValue, style: RfType.caption.copyWith(color: c.muted, fontSize: 11)),
                            ),
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => c.surface2,
                          getTooltipItems: (spots) => [
                            for (final s in spots)
                              LineTooltipItem(
                                '${DateFormat('d MMM').format(first.add(Duration(hours: (s.x * 24).round())))}\n${displayWeight(values[s.spotIndex], units)} $units${prs.contains(s.spotIndex) ? ' · PR' : ''}',
                                RfType.caption.copyWith(color: c.text, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          color: c.accent,
                          barWidth: 2.5,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          dotData: FlDotData(
                            getDotPainter: (spot, _, _, i) => prs.contains(i)
                                ? FlDotCirclePainter(radius: 6, color: c.pr, strokeColor: c.surface, strokeWidth: 2)
                                : FlDotCirclePainter(radius: 3, color: c.accent, strokeColor: c.surface, strokeWidth: 1),
                          ),
                          belowBarData: BarAreaData(show: true, color: c.accent.withValues(alpha: 0.08)),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (prs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(CupertinoIcons.rosette, size: 16, color: c.pr),
            const SizedBox(width: 6),
            Text('${prs.length} ${prs.length == 1 ? 'PR' : 'PRs'} · gold dots', style: RfType.caption.copyWith(color: c.muted)),
          ]),
        ],
      ]),
    );
  }

  String _meaning(List<double> v, DateTime first) {
    if (v.length == 1) return 'One session logged: your trend starts here.';
    final d = v.last - v.first;
    final since = DateFormat('d MMM').format(first);
    final amount = '${displayWeight(d.abs(), units)} $units';
    if (d.abs() < 0.5) return 'Holding steady since $since.';
    return d > 0 ? 'Up $amount since $since.' : 'Down $amount since $since: normal inside a block.';
  }
}
