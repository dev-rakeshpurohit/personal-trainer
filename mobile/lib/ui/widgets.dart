// Repfellow shared widgets. Screens compose these; they never hard-code colours.
import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import 'haptics.dart';
import 'theme.dart';

/* ------------------------------------------------------------------ buttons */

enum RfButtonKind { primary, secondary, ghost, coach, destructive }

class RfButton extends StatelessWidget {
  const RfButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = RfButtonKind.primary,
    this.expand = false,
    this.height = Rf.tap + 4,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final RfButtonKind kind;
  final bool expand;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final (bg, fg) = switch (kind) {
      RfButtonKind.primary => (c.accent, c.onAccent),
      RfButtonKind.secondary => (c.surface2, c.text),
      RfButtonKind.ghost => (Colors.transparent, c.accentInk),
      RfButtonKind.coach => (c.coach.withValues(alpha: 0.16), c.coach),
      RfButtonKind.destructive => (c.destructive.withValues(alpha: 0.14), c.destructive),
    };
    final enabled = onPressed != null && !busy;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.bodyStrong.copyWith(color: fg, fontSize: height >= Rf.doneBar ? 19 : 17)),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: _Pressable(
          onTap: enabled ? onPressed : null,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Rf.btnRadius)),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Scales down slightly while pressed (spring back), the tactile feel used across the app.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Duration(milliseconds: context.reduceMotion ? 0 : 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Public pressable for custom tappable cards.
class Pressable extends StatelessWidget {
  const Pressable({super.key, required this.child, this.onTap, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: semanticLabel,
        child: _Pressable(onTap: onTap, child: child),
      );
}

/// The 64pt primary action bar pinned in the thumb zone (gym floor).
class DoneBar extends StatelessWidget {
  const DoneBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line, width: 0.5))),
      padding: EdgeInsets.fromLTRB(Rf.gutter, 10, Rf.gutter, math.max(bottom, 12)),
      child: child,
    );
  }
}

/* ------------------------------------------------------------------ surfaces */

class RfCard extends StatelessWidget {
  const RfCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.border, this.semanticLabel});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(Rf.cardRadius),
        border: Border.all(color: border ?? c.line.withValues(alpha: 0.6), width: 0.6),
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap, semanticLabel: semanticLabel, child: box);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(Rf.gutter, 22, Rf.gutter, 10)});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(text.toUpperCase(), style: RfType.overline.copyWith(color: context.rf.muted)))),
          ?trailing,
        ]),
      );
}

/// Large-title page with an optional trailing action, iOS style.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.eyebrow, this.trailing});
  final String title;
  final String? eyebrow;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: EdgeInsets.fromLTRB(Rf.gutter, MediaQuery.paddingOf(context).top + 10, Rf.gutter, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (eyebrow != null) Text(eyebrow!, style: RfType.captionStrong.copyWith(color: c.accentInk)),
            Semantics(header: true, child: Text(title, style: RfType.title.copyWith(color: c.text, fontSize: 32))),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/* ------------------------------------------------------------------ chips & marks */

class RfChip extends StatelessWidget {
  const RfChip({super.key, required this.label, this.selected = false, this.onTap, this.icon, this.tone});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final t = tone ?? c.accent;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap == null
            ? null
            : () {
                Haptics.tick();
                onTap!();
              },
        child: AnimatedContainer(
          duration: Duration(milliseconds: context.reduceMotion ? 0 : 160),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? t.withValues(alpha: 0.16) : c.surface,
            borderRadius: BorderRadius.circular(Rf.chipRadius),
            border: Border.all(color: selected ? t : c.line, width: selected ? 1.4 : 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: selected ? (tone ?? c.accentInk) : c.muted), const SizedBox(width: 6)],
            Flexible(child: Text(label, style: RfType.callout.copyWith(color: selected ? c.text : c.text.withValues(alpha: 0.9), fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
          ]),
        ),
      ),
    );
  }
}

/// "Show your working": the violet reason chip on any AI-authored value.
class ReasonChip extends StatelessWidget {
  const ReasonChip(this.reason, {super.key, this.onTap});
  final String reason;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Coach reason: $reason',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.coach.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(Rf.chipRadius)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c.coach, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Flexible(child: Text(reason, style: RfType.caption.copyWith(color: c.coach, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

/// Small violet dot marking "the coach changed this".
class CoachDot extends StatelessWidget {
  const CoachDot({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Changed by coach',
        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: context.rf.coach, shape: BoxShape.circle)),
      );
}

/// Teal check with the trainer's initials: "approved by your trainer".
class TrainerMark extends StatelessWidget {
  const TrainerMark({super.key, required this.initials});
  final String initials;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      label: 'Approved by trainer',
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
        decoration: BoxDecoration(color: c.trainer.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Rf.chipRadius)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 9, backgroundColor: c.trainer, child: Text(initials, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white))),
          const SizedBox(width: 5),
          Icon(CupertinoIcons.checkmark_alt, size: 14, color: c.trainer),
        ]),
      ),
    );
  }
}

/// Status pill (done / PR / caution / neutral) — always icon + text, never colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(Rf.chipRadius)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: RfType.captionStrong.copyWith(color: color, fontSize: 12)),
        ]),
      );
}

/* ------------------------------------------------------------------ stepper */

/// Big −/+ stepper with long-press repeat (gym floor: no keyboard). Value shown with tabular figures.
class BigStepper extends StatefulWidget {
  const BigStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.step,
    required this.label,
    this.min = 0,
    this.max = 999,
    this.format,
    this.unit,
    this.onTapValue,
    this.compact = false,
  });
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final String label;
  final double min;
  final double max;
  final String Function(double)? format;
  final String? unit;
  final VoidCallback? onTapValue;
  final bool compact;
  @override
  State<BigStepper> createState() => _BigStepperState();
}

class _BigStepperState extends State<BigStepper> {
  Timer? _repeat;
  Timer? _cap;

  void _stop() {
    _repeat?.cancel();
    _cap?.cancel();
    _repeat = null;
  }

  void _bump(int dir) {
    final next = (widget.value + dir * widget.step).clamp(widget.min, widget.max).toDouble();
    if (next != widget.value) {
      Haptics.tick();
      widget.onChanged(double.parse(next.toStringAsFixed(2)));
    }
  }

  void _startRepeat(int dir) {
    _stop();
    _repeat = Timer.periodic(const Duration(milliseconds: 110), (_) => _bump(dir));
    // Safety cap: never repeat for more than 6 s even if the release event is lost.
    _cap = Timer(const Duration(seconds: 6), _stop);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Widget _btn(IconData icon, int dir, String hint) {
    final c = context.rf;
    final size = widget.compact ? Rf.tap + 4 : Rf.gymTap + 4;
    return Semantics(
      button: true,
      label: '$hint ${widget.label}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _bump(dir),
        onLongPressStart: (_) => _startRepeat(dir),
        onLongPressEnd: (_) => _stop(),
        onLongPressCancel: _stop,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
          child: Icon(icon, size: 26, color: c.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final text = widget.format?.call(widget.value) ?? _trim(widget.value);
    return Row(children: [
      _btn(CupertinoIcons.minus, -1, 'Decrease'),
      Expanded(
        child: Semantics(
          label: '${widget.label} $text ${widget.unit ?? ''}',
          button: widget.onTapValue != null,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTapValue,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(text, style: (widget.compact ? RfType.headline : RfType.setNumeral).copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
              if (widget.unit != null) Text(widget.unit!, style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
        ),
      ),
      _btn(CupertinoIcons.plus, 1, 'Increase'),
    ]);
  }
}

String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);

/* ------------------------------------------------------------------ rings & progress */

class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 72, this.stroke = 8, this.color, this.child, this.semanticLabel});
  final double value; // 0..1 (can exceed 1)
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
          duration: Duration(milliseconds: context.reduceMotion ? 0 : 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => CustomPaint(
            painter: _RingPainter(v, color ?? c.accent, c.surface2, stroke),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v;
  final Color color;
  final Color track;
  final double stroke;
  @override
  void paint(Canvas canvas, Size size) {
    final r = (math.min(size.width, size.height) - stroke) / 2;
    final center = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, r, p..color = track);
    if (v > 0) canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

class LinearMeter extends StatelessWidget {
  const LinearMeter({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: c.surface2,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: value.clamp(0, 1).toDouble(), child: Container(color: color ?? c.accent)),
      ),
    );
  }
}

/* ------------------------------------------------------------------ feedback */

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 36, color: c.muted),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: RfType.headline.copyWith(color: c.text)),
        if (body != null) ...[const SizedBox(height: 6), Text(body!, textAlign: TextAlign.center, style: RfType.callout.copyWith(color: c.muted))],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Toast with an optional Undo (every destructive or AI change is undoable).
void showRfToast(BuildContext context, String message, {VoidCallback? onUndo, IconData? icon}) {
  final c = context.rf;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: Duration(seconds: onUndo != null ? 10 : 3),
      content: Row(children: [
        if (icon != null) ...[Icon(icon, size: 18, color: c.done), const SizedBox(width: 8)],
        Expanded(child: Text(message)),
      ]),
      action: onUndo == null ? null : SnackBarAction(label: 'Undo', onPressed: onUndo),
    ));
}

/// Modal bottom sheet with Repfellow defaults (drag handle, safe area, scrollable).
Future<T?> showRfSheet<T>(BuildContext context, {required WidgetBuilder builder, bool tall = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * (tall ? 0.92 : 0.75)),
      child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: builder(ctx)),
    ),
  );
}
