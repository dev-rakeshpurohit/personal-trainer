// Per-lift e1RM chart (PR markers, 1M/3M/6M/1Y) and the strength level per main lift.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/schedule.dart';
import '../../domain/stats.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'progress_data.dart';
import 'progress_screen.dart';

String _w(double kg, String units) => units == 'kg' ? kg.toStringAsFixed(kg >= 100 ? 0 : 1) : (kg / 0.45359237).toStringAsFixed(0);

class LiftChartCard extends StatefulWidget {
  const LiftChartCard({super.key, required this.model});
  final ProgressModel model;
  @override
  State<LiftChartCard> createState() => _LiftChartCardState();
}

class _LiftChartCardState extends State<LiftChartCard> {
  String? _lift;
  ChartRange _range = ChartRange.m3;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final m = widget.model;
    if (m.mainLifts.isEmpty) {
      return const RfCard(
        child: EmptyState(icon: Icons.show_chart, title: 'No lifts logged yet', body: 'Finish a session and your strength trend appears here.'),
      );
    }
    final id = m.mainLifts.contains(_lift) ? _lift! : m.mainLifts.first;
    final all = m.series[id] ?? const <LiftPoint>[];
    final pts = inRange(all, _range, m.now);
    final weighted = all.any((p) => p.weighted);
    final name = m.exercises[id]?.name ?? id;
    final change = pctChange(pts.map((p) => p.v).toList());
    final prs = pts.where((p) => p.pr).length;
    String val(double v) => weighted ? '${_w(v, m.units)} ${m.units}' : v.round().toString();

    return RfCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final l in m.mainLifts) ...[
              RfChip(label: m.exercises[l]?.name ?? l, selected: l == id, onTap: () => setState(() => _lift = l)),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        Text(name, style: RfType.bodyStrong.copyWith(color: c.text)),
        Text(
          pts.isEmpty
              ? 'Nothing logged in this range'
              : '${weighted ? 'Estimated 1-rep max' : 'Best reps'} ${val(pts.last.v)}'
                  '${change == null ? '' : ' · ${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(0)}% in ${_range.label}'}'
                  '${prs > 0 ? ' · $prs PR${prs == 1 ? '' : 's'}' : ''}',
          style: RfType.callout.copyWith(color: c.muted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: pts.length < 2
              ? Center(child: Text(pts.isEmpty ? 'Log a session to start the line.' : 'One more session draws the line.', style: RfType.callout.copyWith(color: c.muted)))
              : Semantics(
                  label: '$name chart: ${pts.length} sessions, latest ${val(pts.last.v)}, $prs personal records',
                  excludeSemantics: true,
                  child: _LiftLine(points: pts, units: m.units, weighted: weighted, now: m.now, range: _range),
                ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final r in ChartRange.values) ...[
            RfChip(label: r.label, selected: r == _range, onTap: () => setState(() => _range = r)),
            const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(CupertinoIcons.star_fill, size: 13, color: c.pr),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              weighted ? 'Your best set each session as an estimated 1-rep max. Gold dots are personal records.' : 'Best reps or seconds each session. Gold dots are personal records.',
              style: RfType.caption.copyWith(color: c.muted),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _LiftLine extends StatelessWidget {
  const _LiftLine({required this.points, required this.units, required this.weighted, required this.now, required this.range});
  final List<LiftPoint> points;
  final String units;
  final bool weighted;
  final DateTime now;
  final ChartRange range;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final start = addDays(dateOnly(now), -range.days);
    double x(DateTime t) => t.difference(start).inHours / 24;
    double y(double v) => weighted && units != 'kg' ? v / 0.45359237 : v;
    final spots = [for (final p in points) FlSpot(x(p.t), y(p.v))];
    final ys = spots.map((s) => s.y);
    final lo = ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((hi - lo) * 0.2).clamp(1, double.infinity);
    final df = DateFormat('d MMM');
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: range.days.toDouble() + 1,
        minY: (lo - pad).floorToDouble(),
        maxY: (hi + pad).ceilToDouble(),
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: c.line.withValues(alpha: 0.5), strokeWidth: 0.6)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.round().toString(), style: RfType.caption.copyWith(color: c.muted, fontSize: 11))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (range.days / 3).roundToDouble(),
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(df.format(addDays(start, v.round())), style: RfType.caption.copyWith(color: c.muted, fontSize: 11)),
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
                  '${df.format(points[s.spotIndex].t)}\n${s.y.toStringAsFixed(weighted ? 1 : 0)}${weighted ? ' $units' : ''}${points[s.spotIndex].pr ? ' · PR' : ''}',
                  RfType.caption.copyWith(color: c.text, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: c.accent,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(show: true, color: c.accent.withValues(alpha: 0.08)),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, i) => points[i].pr
                  ? FlDotCirclePainter(radius: 5.5, color: c.pr, strokeWidth: 2, strokeColor: c.surface)
                  : FlDotCirclePainter(radius: 2.5, color: c.accent, strokeWidth: 0, strokeColor: c.surface),
            ),
          ),
        ],
      ),
      duration: Duration(milliseconds: context.reduceMotion ? 0 : 250),
    );
  }
}

/// Beginner → Novice → Intermediate → Advanced per main lift, from e1RM relative to body weight.
class StrengthCard extends StatelessWidget {
  const StrengthCard({super.key, required this.model});
  final ProgressModel model;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final m = model;
    final bw = m.bodyweightKg;
    final rows = <Widget>[];
    for (final id in m.mainLifts) {
      final ex = m.exercises[id];
      final s = m.series[id];
      if (ex == null || s == null) continue;
      final best = s.where((p) => p.weighted).map((p) => p.v).fold(0.0, (a, b) => a > b ? a : b);
      final r = best > 0 ? strengthRating(exercise: ex, e1rmKg: best, bodyweightKg: bw, sex: m.profile.sex) : null;
      if (r == null) continue;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Semantics(
          label: '${ex.name}: ${r.level.label}${r.next != null ? ', next ${r.next!.label} at ${_w(r.nextKg!, m.units)} ${m.units}' : ''}',
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(ex.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.bodyStrong.copyWith(color: c.text))),
              const SizedBox(width: 8),
              StatusPill(label: r.level.label, color: r.level.index >= 2 ? c.done : c.accentInk, icon: r.level == StrengthLevel.advanced ? CupertinoIcons.star_fill : CupertinoIcons.chart_bar_alt_fill),
            ]),
            const SizedBox(height: 6),
            Row(children: [for (var i = 0; i < 4; i++) Expanded(child: Padding(padding: EdgeInsets.only(right: i < 3 ? 4 : 0), child: _Seg(fill: i < r.level.index ? 1 : i == r.level.index ? r.progress : 0)))]),
            const SizedBox(height: 4),
            Text(
              'Best e1RM ${_w(best, m.units)} ${m.units} (${r.ratio.toStringAsFixed(2)}× body weight)'
              '${r.next != null ? ' · ${r.next!.label} at ${_w(r.nextKg!, m.units)} ${m.units}' : ''}',
              style: RfType.caption.copyWith(color: c.muted),
            ),
          ]),
        ),
      ));
    }
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'A rough guide from your best estimated 1-rep max relative to body weight. Dumbbell lifts count the weight in one hand.',
          style: RfType.callout.copyWith(color: c.muted),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty) Text('Log a few weighted main lifts to see your level.', style: RfType.callout.copyWith(color: c.muted)) else ...rows,
        Row(children: [
          for (final l in StrengthLevel.values)
            Expanded(child: Text(l.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: RfType.caption.copyWith(color: c.muted, fontSize: 11))),
        ]),
      ]),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.fill});
  final double fill;
  @override
  Widget build(BuildContext context) => LinearMeter(value: fill, height: 6);
}
