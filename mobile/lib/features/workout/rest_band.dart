// The rest band that slides up after "Done set": countdown ring driven by the stored end timestamp
// (the widget only repaints; it never counts), −15 / +15, "Next: 80 × 8", optional effort chips.
import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'set_widgets.dart';
import 'workout_math.dart';

/// Run a haptic without letting a platform error reach the UI.
void buzz(Future<void> Function() h) => unawaited(h().catchError((Object _) {}));

class RestBand extends StatefulWidget {
  const RestBand({
    super.key,
    required this.endsAt,
    required this.totalSec,
    required this.now,
    required this.onAdjust,
    required this.onRestOver,
    this.nextLabel,
    this.effort,
    this.onEffort,
    this.effortNote,
    this.offerAlerts = false,
    this.onEnableAlerts,
  });
  final DateTime endsAt;
  final int totalSec;
  final DateTime Function() now;
  final ValueChanged<int> onAdjust;
  final VoidCallback onRestOver;
  final String? nextLabel;
  final Effort? effort;
  final ValueChanged<Effort>? onEffort;
  final String? effortNote;
  final bool offerAlerts;
  final VoidCallback? onEnableAlerts;

  @override
  State<RestBand> createState() => _RestBandState();
}

class _RestBandState extends State<RestBand> {
  Timer? _tick;
  bool _soonFired = false;
  bool _overFired = false;

  Duration get _left => widget.endsAt.difference(widget.now());

  @override
  void initState() {
    super.initState();
    // Resumed after the rest already ended (app was in the background): close quietly.
    if (_left.inMilliseconds <= 0) {
      _overFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onRestOver();
      });
    } else {
      _soonFired = _left.inMilliseconds <= 10000;
    }
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void didUpdateWidget(RestBand old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt) {
      _soonFired = _left.inMilliseconds <= 10000;
      _overFired = false;
    }
  }

  void _onTick() {
    if (!mounted) return;
    final ms = _left.inMilliseconds;
    if (!_soonFired && ms <= 10000 && ms > 0) {
      _soonFired = true;
      buzz(Haptics.restSoon);
    }
    if (!_overFired && ms <= 0) {
      _overFired = true;
      buzz(Haptics.restOver);
      final view = View.maybeOf(context);
      if (view != null) unawaited(SemanticsService.sendAnnouncement(view, 'Rest over. Time for your next set.', TextDirection.ltr).catchError((Object _) {}));
      widget.onRestOver();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final leftSec = math.max(0, (_left.inMilliseconds / 1000).ceil());
    final total = math.max(1, widget.totalSec);
    final frac = (leftSec / total).clamp(0.0, 1.0);
    final time = formatDuration(leftSec);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Rf.cardRadius)),
        border: Border(top: BorderSide(color: c.line, width: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 14, Rf.gutter, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          NumeralScale(
            child: ProgressRing(
              value: frac,
              size: 116,
              stroke: 9,
              semanticLabel: 'Rest, $leftSec seconds left',
              child: Text(time, style: RfType.timer.copyWith(fontSize: 34, color: c.text)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('REST', style: RfType.overline.copyWith(color: c.muted)),
              if (widget.nextLabel != null) ...[
                const SizedBox(height: 2),
                Text('Next: ${widget.nextLabel}', maxLines: 2, overflow: TextOverflow.ellipsis, style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _AdjustButton(label: '−15', semantic: 'Remove 15 seconds of rest', onTap: () => widget.onAdjust(-15))),
                const SizedBox(width: 8),
                Expanded(child: _AdjustButton(label: '+15', semantic: 'Add 15 seconds of rest', onTap: () => widget.onAdjust(15))),
              ]),
            ]),
          ),
        ]),
        if (widget.onEffort != null) ...[
          const SizedBox(height: 12),
          Text('How hard was that set? (optional)', style: RfType.captionStrong.copyWith(color: c.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in Effort.values) RfChip(label: e.label, selected: widget.effort == e, onTap: () => widget.onEffort!(e)),
          ]),
        ],
        if (widget.effortNote != null) ...[
          const SizedBox(height: 8),
          ReasonChip(widget.effortNote!),
        ],
        if (widget.offerAlerts && widget.onEnableAlerts != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: RfButton(label: 'Alert me when rest ends', icon: CupertinoIcons.bell, kind: RfButtonKind.ghost, height: Rf.tap, onPressed: widget.onEnableAlerts),
          ),
        ],
      ]),
    );
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.label, required this.semantic, required this.onTap});
  final String label;
  final String semantic;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          buzz(Haptics.tick);
          onTap();
        },
        child: Container(
          height: Rf.gymTap,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
          child: NumeralScale(child: Text(label, style: RfType.headline.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]))),
        ),
      ),
    );
  }
}
