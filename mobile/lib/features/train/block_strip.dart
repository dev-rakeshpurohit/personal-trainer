// Block strip: the 8-week wave grouped into phases (Base → Build → Peak → Recovery) with a
// "you are here" marker. Tapping a week selects it. The recovery week is drawn calm, not as a dip.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import 'train_data.dart';

class BlockStrip extends StatelessWidget {
  const BlockStrip({super.key, required this.phases, required this.current, required this.selected, required this.onSelect});
  final List<BlockPhase> phases;
  final int current;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    Widget segment(int w, BlockPhase p) {
      final isCur = w == current;
      final isSel = w == selected;
      final past = w < current;
      final bg = p.deload
          ? c.done.withValues(alpha: 0.14)
          : isCur
              ? c.accent
              : past
                  ? c.accent.withValues(alpha: 0.32)
                  : c.surface2;
      final fg = isCur && !p.deload ? c.onAccent : c.text;
      return Expanded(
        child: Semantics(
          button: true,
          selected: isSel,
          label: 'Week $w, ${p.label}${isCur ? ', this week' : ''}',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tick();
              onSelect(w);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                height: Rf.tap,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSel ? c.text : Colors.transparent, width: 1.6),
                ),
                child: p.deload
                    ? Icon(CupertinoIcons.leaf_arrow_circlepath, size: 18, color: c.done)
                    : Text('$w', style: RfType.captionStrong.copyWith(color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final p in phases)
          Expanded(
            flex: p.to - p.from + 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: p.label, style: RfType.captionStrong.copyWith(color: p.contains(current) ? c.text : c.muted)),
                    TextSpan(text: ' ${p.range}', style: RfType.caption.copyWith(color: c.muted)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (final p in phases)
          for (var w = p.from; w <= p.to; w++) segment(w, p),
      ]),
      const SizedBox(height: 4),
      ExcludeSemantics(
        child: Align(
          alignment: Alignment(-1 + 2 * ((current - 0.5) / 8), 0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.arrowtriangle_up_fill, size: 9, color: c.accentInk),
            Text('You are here', style: RfType.caption.copyWith(color: c.accentInk, fontWeight: FontWeight.w600, fontSize: 11)),
          ]),
        ),
      ),
    ]);
  }
}
