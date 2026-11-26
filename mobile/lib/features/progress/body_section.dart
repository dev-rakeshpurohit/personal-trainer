// Body: trend weight (7-day average), rate, projection to goal, weight/waist logging with a
// BigStepper sheet, the weight trend chart, waist, and a photos placeholder.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/schedule.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'progress_screen.dart';

enum BodyMetric { weight, waist }

/// Opens the BigStepper sheet and saves today's weight or waist via Repo.upsertBody.
Future<void> showBodyLogSheet(BuildContext context, WidgetRef ref, ProgressModel m, BodyMetric metric) async {
  final today = dateOnly(ref.read(clockProvider)());
  final k = dayKey(today);
  final todayLog = m.body.where((b) => b.dayKey == k).firstOrNull;
  final units = m.units;
  double start;
  if (metric == BodyMetric.weight) {
    final kg = todayLog?.weightKg ?? (m.weights.isEmpty ? m.profile.startWeightKg : m.weights.last.value);
    start = units == 'kg' ? (kg * 10).round() / 10 : toUserUnits(kg, units);
  } else {
    final lastWaist = m.body.reversed.where((b) => b.waistCm != null).firstOrNull?.waistCm;
    start = todayLog?.waistCm ?? lastWaist ?? 85;
  }
  final saved = await showRfSheet<double>(
    context,
    builder: (ctx) => _BodyLogSheet(metric: metric, start: start, units: units),
  );
  if (saved == null) return;
  final repo = ref.read(repoProvider);
  if (metric == BodyMetric.weight) {
    await repo.upsertBody(k, weightKg: fromUserUnits(saved, units));
  } else {
    await repo.upsertBody(k, waistCm: saved);
  }
  if (context.mounted) {
    showRfToast(context, metric == BodyMetric.weight ? 'Weight logged · ${saved.toStringAsFixed(1)} $units' : 'Waist logged · ${saved.toStringAsFixed(1)} cm', icon: CupertinoIcons.checkmark_alt);
  }
}

class _BodyLogSheet extends StatefulWidget {
  const _BodyLogSheet({required this.metric, required this.start, required this.units});
  final BodyMetric metric;
  final double start;
  final String units;
  @override
  State<_BodyLogSheet> createState() => _BodyLogSheetState();
}

class _BodyLogSheetState extends State<_BodyLogSheet> {
  late double _v = widget.start;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final weight = widget.metric == BodyMetric.weight;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(weight ? 'Log weight' : 'Log waist', style: RfType.headline.copyWith(color: c.text)),
          const SizedBox(height: 18),
          BigStepper(
            value: _v,
            step: weight ? (widget.units == 'kg' ? 0.1 : 0.2) : 0.5,
            min: weight ? 20 : 40,
            max: weight ? 400 : 200,
            label: weight ? 'Body weight' : 'Waist',
            unit: weight ? widget.units : 'cm',
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v) => setState(() => _v = v),
          ),
          const SizedBox(height: 12),
          Text(
            weight ? 'Same time each morning, after the bathroom, before food. The 7-day average is what counts.' : 'At the navel, relaxed, every two weeks.',
            textAlign: TextAlign.center,
            style: RfType.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 18),
          RfButton(
            label: 'Save',
            expand: true,
            onPressed: () {
              Haptics.setDone();
              Navigator.of(context).pop(_v);
            },
          ),
        ]),
      ),
    );
  }
}

class BodySection extends ConsumerWidget {
  const BodySection({super.key, required this.model});
  final ProgressModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final m = model;
    final today = dateOnly(m.now);
    final u = m.units;
    String w(double kg) => (u == 'kg' ? kg : kgToLb(kg)).toStringAsFixed(1);
    final avg = current7dAvg(m.weights, today);
    final rate = rateKgPerWeek(m.weights, today);
    final goal = m.profile.goalWeightKg;
    final proj = projectedGoalDate(avg, goal, rate?.lossPerWeek, today);
    final week = weeklyAverage(m.weights, today);
    final waist = m.body.where((b) => b.waistCm != null).toList();

    Widget tile(String label, String value, String sub) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.surface2.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: RfType.captionStrong.copyWith(color: c.muted)),
              const SizedBox(height: 2),
              Text(value, style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(sub, maxLines: 2, style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
        );

    String rateSub() {
      if (rate == null) return 'Needs about 10 weigh-ins';
      final l = rate.lossPerWeek;
      if (l >= 0.5 && l <= 0.75) return 'In the sweet spot';
      if (l > 1) return 'Fast: keep protein high';
      if (l < 0.3 && goal < (avg ?? goal)) return 'Slow and steady';
      return 'Steady';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: RfButton(label: 'Log weight', icon: CupertinoIcons.plus, kind: RfButtonKind.secondary, expand: true, onPressed: () => showBodyLogSheet(context, ref, m, BodyMetric.weight))),
        const SizedBox(width: 8),
        Expanded(child: RfButton(label: 'Log waist', icon: CupertinoIcons.plus, kind: RfButtonKind.secondary, expand: true, onPressed: () => showBodyLogSheet(context, ref, m, BodyMetric.waist))),
      ]),
      const SizedBox(height: 12),
      RfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            tile('Trend weight', avg == null ? '–' : '${w(avg)} $u', 'Goal ${w(goal)} $u'),
            const SizedBox(width: 8),
            tile('Rate', rate == null ? '–' : '${rate.lossPerWeek >= 0 ? '−' : '+'}${w(rate.lossPerWeek.abs())} $u/wk', rateSub()),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            tile('To go', avg == null ? '–' : '${w((avg - goal).abs())} $u', proj == null ? 'Projection needs a steady trend' : 'Around ${DateFormat('d MMM').format(proj)}'),
            const SizedBox(width: 8),
            tile('This week', '${week.count} weigh-in${week.count == 1 ? '' : 's'}', week.valid ? 'Avg ${w(week.avg!)} $u' : '${week.needed} more for a weekly average'),
          ]),
          const SizedBox(height: 14),
          if (m.weights.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Log your weight a few mornings to see the trend.', style: RfType.callout.copyWith(color: c.muted))),
            )
          else
            SizedBox(
              height: 200,
              child: Semantics(
                label: 'Weight chart: daily weigh-ins, 7-day average${avg != null ? ' ${w(avg)} $u' : ''}, goal ${w(goal)} $u',
                excludeSemantics: true,
                child: _WeightChart(model: m, projected: proj, avg: avg),
              ),
            ),
          const SizedBox(height: 8),
          Text('Dots are daily weigh-ins; the line is your 7-day average, which ignores water swings. Dashed: goal and projection.', style: RfType.caption.copyWith(color: c.muted)),
        ]),
      ),
      if (waist.length >= 2) ...[
        const SizedBox(height: 12),
        RfCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Waist', style: RfType.bodyStrong.copyWith(color: c.text)),
            Text(
              '${waist.last.waistCm!.toStringAsFixed(1)} cm · ${(waist.last.waistCm! - waist.first.waistCm!) <= 0 ? '−' : '+'}${(waist.last.waistCm! - waist.first.waistCm!).abs().toStringAsFixed(1)} cm since ${DateFormat('d MMM').format(fromDayKey(waist.first.dayKey))}',
              style: RfType.callout.copyWith(color: c.muted),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      RfCard(
        child: Row(children: [
          Container(
            width: 52,
            height: 64,
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
            child: Icon(CupertinoIcons.camera, color: c.muted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Progress photos', style: RfType.bodyStrong.copyWith(color: c.text)),
                StatusPill(label: 'Coming soon', color: c.muted),
              ]),
              const SizedBox(height: 2),
              Text('Front, side and back, stored only on this phone, with a ghost overlay to match your pose.', style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.model, required this.projected, required this.avg});
  final ProgressModel model;
  final DateTime? projected;
  final double? avg;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final m = model;
    final today = dateOnly(m.now);
    final from = addDays(today, -60);
    final u = m.units;
    double y(double kg) => u == 'kg' ? kg : kgToLb(kg);
    double x(DateTime d) => daysBetween(d, from).toDouble();
    final recent = m.weights.where((p) => !fromDayKey(p.dayKey).isBefore(from)).toList();
    final ma = movingAverage7(m.weights).where((p) => !fromDayKey(p.dayKey).isBefore(from)).toList();
    final raw = [for (final p in recent) FlSpot(x(fromDayKey(p.dayKey)), y(p.value))];
    final line = [for (final p in ma) FlSpot(x(fromDayKey(p.dayKey)), y(p.value))];
    final showProj = projected != null && avg != null && daysBetween(projected!, today) < 120;
    final proj = showProj ? [FlSpot(x(today), y(avg!)), FlSpot(x(projected!), y(m.profile.goalWeightKg))] : const <FlSpot>[];
    final goalY = y(m.profile.goalWeightKg);
    final ys = [...raw.map((s) => s.y), ...proj.map((s) => s.y), goalY];
    final lo = ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.reduce((a, b) => a > b ? a : b);
    final maxX = showProj ? x(projected!) : x(today);
    final df = DateFormat('d MMM');
    return LineChart(
      LineChartData(
        minX: raw.isEmpty ? 0 : raw.first.x,
        maxX: maxX,
        minY: (lo - 0.5).floorToDouble(),
        maxY: (hi + 0.5).ceilToDouble(),
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: c.line.withValues(alpha: 0.5), strokeWidth: 0.6)),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: goalY,
            color: c.done,
            strokeWidth: 1.2,
            dashArray: [4, 4],
            label: HorizontalLineLabel(show: true, alignment: Alignment.topRight, style: RfType.caption.copyWith(color: c.done, fontSize: 11), labelResolver: (_) => 'Goal'),
          ),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.round().toString(), style: RfType.caption.copyWith(color: c.muted, fontSize: 11))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: ((maxX - (raw.isEmpty ? 0 : raw.first.x)) / 3).clamp(1, 400).roundToDouble(),
              getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(df.format(addDays(from, v.round())), style: RfType.caption.copyWith(color: c.muted, fontSize: 11))),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: raw,
            barWidth: 0,
            color: Colors.transparent,
            dotData: FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 2.6, color: c.muted.withValues(alpha: 0.55), strokeWidth: 0, strokeColor: Colors.transparent)),
          ),
          LineChartBarData(spots: line, barWidth: 3, color: c.accent, isCurved: true, preventCurveOverShooting: true, dotData: const FlDotData(show: false)),
          if (proj.isNotEmpty) LineChartBarData(spots: proj, barWidth: 2, color: c.accent, dashArray: [6, 5], dotData: const FlDotData(show: false)),
        ],
      ),
      duration: Duration(milliseconds: context.reduceMotion ? 0 : 250),
    );
  }
}
