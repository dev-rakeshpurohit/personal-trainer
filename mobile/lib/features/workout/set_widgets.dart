// Set-level widgets of the logger: the current set card, set rows, the edit sheet and the
// custom number pad (gym floor: no system keyboard).
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../data/services/session_service.dart';
import '../../domain/models.dart';
import '../../domain/units.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'workout_math.dart';

/// Caps numerals at 1.3× so set values stay on one line at large text sizes.
class NumeralScale extends StatelessWidget {
  const NumeralScale({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);
}

/// The values editor for one set (weight + reps / seconds / minutes / meters), shared by the
/// current set card and the edit sheet.
class SetValueSteppers extends StatelessWidget {
  const SetValueSteppers({
    super.key,
    required this.unit,
    required this.values,
    required this.onChanged,
    required this.units,
    required this.weightStep,
    required this.bodyweight,
    this.perSide = false,
    this.label = 'Set',
  });
  final Unit unit;
  final SetValues values;
  final ValueChanged<SetValues> onChanged;
  final String units;
  final double weightStep;
  final bool bodyweight;
  final bool perSide;
  final String label;

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final w = values.weightKg == null ? 0.0 : toUserUnits(values.weightKg!, units);
    SetValues withWeight(double v) => SetValues(
          weightKg: v <= 0 ? null : fromUserUnits(v, units),
          reps: values.reps,
          seconds: values.seconds,
          meters: values.meters,
          rir: values.rir,
        );
    final second = switch (unit) {
      Unit.reps => BigStepper(
          label: '$label reps',
          value: (values.reps ?? 0).toDouble(),
          step: 1,
          max: 100,
          unit: perSide ? 'reps / side' : 'reps',
          onChanged: (v) => onChanged(values.merge(SetValues(reps: v.round()))),
          onTapValue: () => _pad(context, 'Reps', (values.reps ?? 0).toDouble(), false, (v) => onChanged(values.merge(SetValues(reps: v.round())))),
        ),
      Unit.seconds => BigStepper(
          label: '$label seconds',
          value: (values.seconds ?? 0).toDouble(),
          step: 5,
          max: 900,
          unit: perSide ? 'seconds / side' : 'seconds',
          onChanged: (v) => onChanged(values.merge(SetValues(seconds: v.round()))),
          onTapValue: () => _pad(context, 'Seconds', (values.seconds ?? 0).toDouble(), false, (v) => onChanged(values.merge(SetValues(seconds: v.round())))),
        ),
      Unit.minutes => BigStepper(
          label: '$label minutes',
          value: ((values.seconds ?? 0) / 60).roundToDouble(),
          step: 1,
          max: 180,
          unit: 'minutes',
          onChanged: (v) => onChanged(values.merge(SetValues(seconds: (v * 60).round()))),
          onTapValue: () => _pad(context, 'Minutes', ((values.seconds ?? 0) / 60).roundToDouble(), false, (v) => onChanged(values.merge(SetValues(seconds: (v * 60).round())))),
        ),
      Unit.meters => BigStepper(
          label: '$label meters',
          value: values.meters ?? 0,
          step: 5,
          max: 10000,
          unit: 'meters',
          onChanged: (v) => onChanged(values.merge(SetValues(meters: v))),
          onTapValue: () => _pad(context, 'Meters', values.meters ?? 0, false, (v) => onChanged(values.merge(SetValues(meters: v)))),
        ),
    };
    return NumeralScale(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!bodyweight) ...[
          BigStepper(
            label: '$label weight',
            value: w,
            step: weightStep,
            max: units == 'kg' ? 500 : 1100,
            unit: units,
            format: _fmt,
            onChanged: (v) => onChanged(withWeight(v)),
            onTapValue: () => _pad(context, 'Weight ($units)', w, true, (v) => onChanged(withWeight(v))),
          ),
          const SizedBox(height: 10),
        ],
        second,
      ]),
    );
  }

  Future<void> _pad(BuildContext context, String title, double initial, bool decimal, ValueChanged<double> done) async {
    final v = await showNumberPad(context, title: title, initial: initial, decimal: decimal);
    if (v != null) done(v);
  }
}

/// The current set: "Set 2 of 4", target values on big steppers, "Last time" in grey and the
/// plate / dumbbell line.
class CurrentSetCard extends StatelessWidget {
  const CurrentSetCard({
    super.key,
    required this.se,
    required this.exercise,
    required this.setIndex,
    required this.totalSets,
    required this.values,
    required this.onChanged,
    required this.units,
    required this.weightStep,
    this.lastTime,
    this.calibrating = false,
    this.edited = false,
  });
  final SessionExercise se;
  final Exercise? exercise;
  final int setIndex;
  final int totalSets;
  final SetValues values;
  final ValueChanged<SetValues> onChanged;
  final String units;
  final double weightStep;
  final String? lastTime;
  final bool calibrating;
  final bool edited;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final bodyweight = exercise?.isBodyweight == true;
    final line = bodyweight ? null : implementLine(exercise, values.weightKg, units);
    return RfCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            header: true,
            child: Text('SET ${setIndex + 1} OF $totalSets', style: RfType.overline.copyWith(color: c.accentInk)),
          ),
          const SizedBox(width: 8),
          Text(edited ? 'Your set' : 'Target', style: RfType.captionStrong.copyWith(color: c.muted)),
          const Spacer(),
          if (lastTime != null)
            Flexible(
              flex: 3,
              child: Text('Last time $lastTime', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.caption.copyWith(color: c.muted)),
            ),
        ]),
        if (calibrating) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(CupertinoIcons.scope, size: 18, color: c.text),
            const SizedBox(width: 8),
            Expanded(child: Text(calibrationCopy(se), style: RfType.callout.copyWith(color: c.text))),
          ]),
        ],
        const SizedBox(height: 12),
        SetValueSteppers(
          unit: se.unit,
          values: values,
          onChanged: onChanged,
          units: units,
          weightStep: weightStep,
          bodyweight: bodyweight,
          perSide: se.perSide,
          label: 'Set ${setIndex + 1}',
        ),
        if (line != null) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.fitness_center, size: 16, color: c.muted),
            const SizedBox(width: 6),
            Flexible(child: Text(line, style: RfType.callout.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
          ]),
        ],
      ]),
    );
  }
}

/// One row in the set list: done (leaf + ✓, tap to edit), the current set, or upcoming (neutral).
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.index,
    required this.unit,
    required this.units,
    required this.bodyweight,
    this.done,
    this.draft,
    this.current = false,
    this.onTap,
  });
  final int index;
  final Unit unit;
  final String units;
  final bool bodyweight;
  final SetLog? done;
  final SetValues? draft;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final d = done;
    final text = d != null
        ? setText(valuesOf(d), unit, units, bodyweight: bodyweight)
        : draft == null
            ? '–'
            : setText(draft!, unit, units, bodyweight: bodyweight);
    final effort = d == null ? null : Effort.ofRir(d.rir);
    final status = d != null ? 'done' : (current ? 'up now' : 'upcoming');
    final row = Container(
      constraints: const BoxConstraints(minHeight: Rf.gymTap),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: d != null ? c.done.withValues(alpha: 0.10) : c.surface,
        borderRadius: BorderRadius.circular(Rf.btnRadius),
        border: Border.all(color: d != null ? c.done.withValues(alpha: 0.45) : (current ? c.text.withValues(alpha: 0.5) : c.line), width: current ? 1.4 : 0.8),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: d != null ? c.done : c.surface2, shape: BoxShape.circle),
          child: d != null
              ? Icon(CupertinoIcons.checkmark_alt, size: 20, color: c.bg)
              : Text('${index + 1}', style: RfType.bodyStrong.copyWith(color: current ? c.text : c.muted)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: RfType.bodyStrong.copyWith(fontSize: 19, color: d != null || current ? c.text : c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        if (effort != null) Text(effort.label, style: RfType.caption.copyWith(color: c.muted)),
        if (current && d == null) Text('Up now', style: RfType.captionStrong.copyWith(color: c.text)),
        if (d != null) ...[const SizedBox(width: 6), Icon(CupertinoIcons.pencil, size: 16, color: c.muted)],
      ]),
    );
    return Semantics(
      label: 'Set ${index + 1}, $status, $text${effort != null ? ', ${effort.label}' : ''}',
      button: onTap != null,
      hint: d != null ? 'Double tap to edit' : null,
      excludeSemantics: true,
      child: onTap == null ? row : Pressable(onTap: onTap, child: row),
    );
  }
}

/// Edit a logged set (values only; the rest timer is untouched). Delete offers Undo.
Future<void> showEditSetSheet(
  BuildContext context, {
  required SetLog set,
  required Unit unit,
  required String units,
  required bool bodyweight,
  required double weightStep,
  required Future<void> Function(SetValues v) onSave,
  required Future<void> Function() onDelete,
}) =>
    showRfSheet<void>(
      context,
      builder: (ctx) => _EditSetBody(set: set, unit: unit, units: units, bodyweight: bodyweight, weightStep: weightStep, onSave: onSave, onDelete: onDelete),
    );

class _EditSetBody extends StatefulWidget {
  const _EditSetBody({required this.set, required this.unit, required this.units, required this.bodyweight, required this.weightStep, required this.onSave, required this.onDelete});
  final SetLog set;
  final Unit unit;
  final String units;
  final bool bodyweight;
  final double weightStep;
  final Future<void> Function(SetValues v) onSave;
  final Future<void> Function() onDelete;
  @override
  State<_EditSetBody> createState() => _EditSetBodyState();
}

class _EditSetBodyState extends State<_EditSetBody> {
  late SetValues v = valuesOf(widget.set);
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text('Edit set ${widget.set.setIndex + 1}', style: RfType.headline.copyWith(color: c.text))),
          const SizedBox(height: 4),
          Text('Your rest timer keeps running.', style: RfType.caption.copyWith(color: c.muted)),
          const SizedBox(height: 16),
          SetValueSteppers(
            unit: widget.unit,
            values: v,
            onChanged: (x) => setState(() => v = x),
            units: widget.units,
            weightStep: widget.weightStep,
            bodyweight: widget.bodyweight,
            label: 'Edited set',
          ),
          const SizedBox(height: 20),
          Row(children: [
            RfButton(
              label: 'Delete',
              icon: CupertinoIcons.trash,
              kind: RfButtonKind.destructive,
              height: Rf.gymTap,
              onPressed: () async {
                Navigator.of(context).pop();
                await widget.onDelete();
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RfButton(
                label: 'Save',
                expand: true,
                height: Rf.gymTap,
                onPressed: () async {
                  Navigator.of(context).pop();
                  await widget.onSave(v);
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/* ------------------------------------------------------------------ number pad */

/// Custom numeric pad in a sheet (no system keyboard). Returns null when dismissed.
Future<double?> showNumberPad(BuildContext context, {required String title, required double initial, bool decimal = true}) =>
    showRfSheet<double>(context, builder: (_) => _NumberPad(title: title, initial: initial, decimal: decimal));

class _NumberPad extends StatefulWidget {
  const _NumberPad({required this.title, required this.initial, required this.decimal});
  final String title;
  final double initial;
  final bool decimal;
  @override
  State<_NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<_NumberPad> {
  String text = '';
  bool fresh = true;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    text = i == 0 ? '' : (i == i.roundToDouble() ? i.toInt().toString() : i.toString());
  }

  void _key(String k) => setState(() {
        if (fresh) {
          text = '';
          fresh = false;
        }
        if (k == '⌫') {
          if (text.isNotEmpty) text = text.substring(0, text.length - 1);
        } else if (k == '.') {
          if (!text.contains('.')) text = text.isEmpty ? '0.' : '$text.';
        } else if (text.length < 6) {
          text = text == '0' ? k : '$text$k';
        }
      });

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', widget.decimal ? '.' : '', '0', '⌫'];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: RfType.captionStrong.copyWith(color: c.muted)),
          NumeralScale(
            child: Semantics(
              liveRegion: true,
              label: '${widget.title} ${text.isEmpty ? 'empty' : text}',
              child: Text(text.isEmpty ? '0' : text, textAlign: TextAlign.center, style: RfType.timer.copyWith(color: text.isEmpty ? c.muted : c.text)),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: [
              for (final k in keys)
                k.isEmpty
                    ? const SizedBox()
                    : Semantics(
                        button: true,
                        label: k == '⌫' ? 'Delete digit' : (k == '.' ? 'Decimal point' : k),
                        excludeSemantics: true,
                        child: Pressable(
                          onTap: () => _key(k),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
                            child: k == '⌫'
                                ? Icon(CupertinoIcons.delete_left, color: c.text)
                                : Text(k, style: RfType.title.copyWith(color: c.text)),
                          ),
                        ),
                      ),
            ],
          ),
          const SizedBox(height: 12),
          RfButton(
            label: 'Use this',
            expand: true,
            height: Rf.gymTap,
            onPressed: () => Navigator.of(context).pop(double.tryParse(text) ?? 0),
          ),
        ]),
      ),
    );
  }
}
