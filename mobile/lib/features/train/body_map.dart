// Plan check body map: a simple stylised front/back silhouette with tappable muscle regions in
// three states — below range (outline), in range (accent fill), above range (amber hatching).
// Never red. Each figure is drawn in a 100 × 210 virtual box and scaled to fit.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../domain/balance.dart';
import '../../ui/theme.dart';
import 'train_data.dart';

const _w = 100.0;
const _h = 210.0;

RRect _rr(double l, double t, double r, double b, double rad) => RRect.fromLTRBR(l, t, r, b, Radius.circular(rad));

Path _rrPath(List<RRect> rects) {
  final p = Path();
  for (final r in rects) {
    p.addRRect(r);
  }
  return p;
}

Path _ovals(List<Rect> rects) {
  final p = Path();
  for (final r in rects) {
    p.addOval(r);
  }
  return p;
}

/// Neutral silhouette (head, torso, limbs).
Path _silhouette() {
  final p = Path()
    ..addOval(Rect.fromCenter(center: const Offset(50, 13), width: 18, height: 22))
    ..addRect(const Rect.fromLTRB(45, 21, 55, 31))
    ..addRRect(_rr(32, 29, 68, 96, 12))
    ..addRRect(_rr(34, 86, 66, 114, 10))
    ..addRRect(_rr(22, 33, 34, 72, 6))
    ..addRRect(_rr(66, 33, 78, 72, 6))
    ..addRRect(_rr(19, 69, 31, 104, 6))
    ..addRRect(_rr(69, 69, 81, 104, 6))
    ..addOval(Rect.fromCenter(center: const Offset(25, 110), width: 10, height: 13))
    ..addOval(Rect.fromCenter(center: const Offset(75, 110), width: 10, height: 13))
    ..addRRect(_rr(35, 104, 50, 198, 7))
    ..addRRect(_rr(50, 104, 65, 198, 7))
    ..addOval(Rect.fromCenter(center: const Offset(42, 202), width: 14, height: 8))
    ..addOval(Rect.fromCenter(center: const Offset(58, 202), width: 14, height: 8));
  return p;
}

/// Muscle regions of one side of the body, in paint order.
List<(MuscleGroup, Path)> bodyRegions({required bool back}) {
  final shoulders = _ovals([const Rect.fromLTRB(25, 30, 39, 46), const Rect.fromLTRB(61, 30, 75, 46)]);
  if (!back) {
    return [
      (MuscleGroup.shoulders, shoulders),
      (MuscleGroup.chest, _rrPath([_rr(37.5, 34, 49.5, 52, 5), _rr(50.5, 34, 62.5, 52, 5)])),
      (MuscleGroup.biceps, _rrPath([_rr(24, 47, 33, 68, 4.5), _rr(67, 47, 76, 68, 4.5)])),
      (MuscleGroup.core, _rrPath([_rr(40, 55, 60, 92, 6)])),
      (MuscleGroup.quads, _rrPath([_rr(36.5, 110, 49, 152, 6), _rr(51, 110, 63.5, 152, 6)])),
      (MuscleGroup.calves, _rrPath([_rr(38, 162, 48, 192, 5), _rr(52, 162, 62, 192, 5)])),
    ];
  }
  final traps = Path()
    ..moveTo(41, 29)
    ..lineTo(59, 29)
    ..lineTo(66, 40)
    ..lineTo(50, 50)
    ..lineTo(34, 40)
    ..close();
  final backPath = Path()
    ..addPath(traps, Offset.zero)
    ..addRRect(_rr(36, 43, 49, 80, 6))
    ..addRRect(_rr(51, 43, 64, 80, 6));
  return [
    (MuscleGroup.shoulders, shoulders),
    (MuscleGroup.back, backPath),
    (MuscleGroup.triceps, _rrPath([_rr(24, 46, 33, 69, 4.5), _rr(67, 46, 76, 69, 4.5)])),
    (MuscleGroup.glutes, _rrPath([_rr(36, 90, 50, 113, 9), _rr(50, 90, 64, 113, 9)])),
    (MuscleGroup.hamstrings, _rrPath([_rr(36.5, 116, 49, 154, 6), _rr(51, 116, 63.5, 154, 6)])),
    (MuscleGroup.calves, _rrPath([_rr(37.5, 160, 48.5, 194, 7), _rr(51.5, 160, 62.5, 194, 7)])),
  ];
}

/// Scale and offset that fit the virtual box into [size].
({double scale, Offset origin}) _fit(Size size) {
  final scale = math.min(size.width / _w, size.height / _h);
  return (scale: scale, origin: Offset((size.width - _w * scale) / 2, (size.height - _h * scale) / 2));
}

/// Paint one muscle region in a state (also used by the legend swatches).
void paintRegion(Canvas canvas, Path path, VolumeState state, RfColors c, {bool selected = false, double unit = 1}) {
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  switch (state) {
    case VolumeState.below:
      canvas.drawPath(path, Paint()..color = c.surface);
      canvas.drawPath(path, stroke
        ..color = c.muted
        ..strokeWidth = 1.1 * unit);
    case VolumeState.inRange:
      canvas.drawPath(path, Paint()..color = c.accent);
    case VolumeState.above:
      canvas.drawPath(path, Paint()..color = c.caution.withValues(alpha: 0.16));
      canvas.save();
      canvas.clipPath(path);
      final b = path.getBounds();
      final hatch = Paint()
        ..color = c.caution
        ..strokeWidth = 1.1 * unit;
      for (var x = b.left - b.height; x < b.right; x += 3.6 * unit) {
        canvas.drawLine(Offset(x, b.bottom), Offset(x + b.height, b.top), hatch);
      }
      canvas.restore();
      canvas.drawPath(path, stroke
        ..color = c.caution
        ..strokeWidth = 0.9 * unit);
  }
  if (selected) {
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..color = c.text
      ..strokeWidth = 2 * unit);
  }
}

class _FigurePainter extends CustomPainter {
  _FigurePainter({required this.back, required this.states, required this.colors, required this.selected});
  final bool back;
  final Map<MuscleGroup, VolumeState> states;
  final RfColors colors;
  final MuscleGroup? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final f = _fit(size);
    canvas.save();
    canvas.translate(f.origin.dx, f.origin.dy);
    canvas.scale(f.scale);
    canvas.drawPath(_silhouette(), Paint()..color = colors.surface2);
    for (final (g, path) in bodyRegions(back: back)) {
      paintRegion(canvas, path, states[g] ?? VolumeState.below, colors, selected: g == selected);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FigurePainter o) => o.selected != selected || o.colors != colors || !_sameStates(o.states, states);

  static bool _sameStates(Map<MuscleGroup, VolumeState> a, Map<MuscleGroup, VolumeState> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

/// Which region (if any) is under [local] for a figure of [size].
MuscleGroup? hitRegion(Offset local, Size size, {required bool back}) {
  final f = _fit(size);
  final p = (local - f.origin) / f.scale;
  for (final (g, path) in bodyRegions(back: back).reversed) {
    if (path.contains(p)) return g;
  }
  // forgiving taps: nearest region within a few points
  MuscleGroup? best;
  var bestD = 6.0;
  for (final (g, path) in bodyRegions(back: back)) {
    final b = path.getBounds();
    final dx = math.max(0.0, math.max(b.left - p.dx, p.dx - b.right));
    final dy = math.max(0.0, math.max(b.top - p.dy, p.dy - b.bottom));
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < bestD) {
      bestD = d;
      best = g;
    }
  }
  return best;
}

String _stateWord(VolumeState s) => switch (s) {
      VolumeState.below => 'below range',
      VolumeState.inRange => 'in range',
      VolumeState.above => 'above range',
    };

/// Front + back body map. [onSelect] fires with the tapped group.
class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.states, this.selected, this.onSelect, this.height = 220});
  final Map<MuscleGroup, VolumeState> states;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup>? onSelect;
  final double height;

  Widget _figure(BuildContext context, {required bool back}) {
    final c = context.rf;
    final groups = bodyRegions(back: back).map((r) => r.$1).toList();
    final label = '${back ? 'Back' : 'Front'} body map: ${groups.map((g) => '${g.label} ${_stateWord(states[g] ?? VolumeState.below)}').join(', ')}';
    return Expanded(
      child: Column(children: [
        Semantics(
          label: label,
          image: true,
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, height);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onSelect == null
                  ? null
                  : (d) {
                      final g = hitRegion(d.localPosition, size, back: back);
                      if (g != null) onSelect!(g);
                    },
              child: CustomPaint(size: size, painter: _FigurePainter(back: back, states: states, colors: c, selected: selected)),
            );
          }),
        ),
        const SizedBox(height: 4),
        ExcludeSemantics(child: Text(back ? 'Back' : 'Front', style: RfType.caption.copyWith(color: c.muted))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _figure(context, back: false),
        _figure(context, back: true),
      ]);
}

/// Legend: one swatch per state, always with a label (never colour alone).
class BodyMapLegend extends StatelessWidget {
  const BodyMapLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    Widget item(VolumeState s, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(size: const Size(16, 16), painter: _SwatchPainter(s, c)),
          const SizedBox(width: 6),
          Text(label, style: RfType.caption.copyWith(color: c.muted)),
        ]);
    return Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
      item(VolumeState.below, 'Below range'),
      item(VolumeState.inRange, 'In range'),
      item(VolumeState.above, 'Above range'),
    ]);
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.state, this.colors);
  final VolumeState state;
  final RfColors colors;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)));
    paintRegion(canvas, path, state, colors);
  }

  @override
  bool shouldRepaint(_SwatchPainter o) => o.state != state || o.colors != colors;
}
