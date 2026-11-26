// The signature proposal card ("show your working"): title + scope, the diff against the active
// plan, the impact strip (weekly sets per muscle, Plan check, session time), the diet diff, the
// grounded "why", warnings and safety notes, then Approve / Adjust / Discard (or Undo).
// Reusable from other screens: give it a [CoachProposal] and the callbacks you support.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/services/common.dart';
import '../../domain/ai_plan.dart';
import '../../domain/models.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'coach_models.dart';
import 'coach_safety.dart';
import 'proposal_diff.dart';

class ProposalCard extends StatefulWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.exMap,
    this.goal,
    this.onApprove,
    this.onDiscard,
    this.onAdjusted,
    this.onUndo,
    this.busy = false,
    this.compact = false,
  });

  final CoachProposal proposal;
  final Map<String, Exercise> exMap;
  final Goal? goal;

  /// Pending-state actions (omit to hide them, e.g. a read-only history view).
  final VoidCallback? onApprove;
  final VoidCallback? onDiscard;

  /// Called with the edited proposed plan after each Adjust edit.
  final ValueChanged<NormPlan>? onAdjusted;

  /// Shown on an approved proposal while its plans are still active.
  final VoidCallback? onUndo;
  final bool busy;

  /// Hide the "why" and warnings (history list previews).
  final bool compact;

  @override
  State<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<ProposalCard> {
  bool _adjusting = false;
  String? _editing;

  CoachProposal get p => widget.proposal;
  bool get _pending => p.status == ProposalStatus.pending;

  String _name(String id) => widget.exMap[id]?.name ?? id;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final diff = diffWorkouts(p.before.workout, p.after.workout, widget.exMap);
    final diet = diffDiets(p.before.diet, p.after.diet);
    final impact = p.after.workout == null ? null : impactOf(p.before.workout, p.after.workout, widget.exMap, widget.goal);
    final safety = CoachSafety.of(p.request);

    return Semantics(
      container: true,
      label: 'Coach proposal: ${p.title}',
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Rf.cardRadius),
          border: Border.all(color: c.coach.withValues(alpha: _pending ? 0.55 : 0.25), width: _pending ? 1.2 : 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context),
          if (safety.any) _safety(context, safety),
          if (p.after.workout != null) _workoutDiff(context, diff),
          if (diet != null) _dietDiff(context, diet),
          if (impact != null) _impact(context, impact),
          if (!widget.compact) _why(context),
          if (!widget.compact && p.after.warnings.isNotEmpty) _warnings(context),
          _actions(context),
        ]),
      ),
    );
  }

  /* ------------------------------------------------------------ header */

  Widget _header(BuildContext context) {
    final c = context.rf;
    final scope = [
      if (p.touchesWorkout) 'Weekly workout',
      if (p.touchesDiet) 'Diet',
    ].join(' + ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 16, color: c.coach),
          const SizedBox(width: 6),
          Expanded(child: Text(p.mode == CoachMode.newPlan ? 'NEW PLAN PROPOSAL' : 'PROPOSED CHANGE', style: RfType.overline.copyWith(color: c.coach))),
          _statusPill(context),
        ]),
        const SizedBox(height: 8),
        Text(p.title, style: RfType.headline.copyWith(color: c.text)),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Applies to: '),
            TextSpan(text: scope, style: RfType.captionStrong.copyWith(color: c.text)),
            const TextSpan(text: ' · from this week'),
            if (p.adjusted) const TextSpan(text: ' · adjusted by you'),
          ]),
          style: RfType.caption.copyWith(color: c.muted),
        ),
      ]),
    );
  }

  Widget _statusPill(BuildContext context) {
    final c = context.rf;
    final when = p.decidedAt == null ? '' : ' · ${DateFormat('d MMM').format(parseIsoLocal(p.decidedAt!))}';
    return switch (p.status) {
      ProposalStatus.pending => StatusPill(label: 'Needs your OK', color: c.coach, icon: CupertinoIcons.hand_raised),
      ProposalStatus.approved => StatusPill(label: 'Approved$when', color: c.done, icon: CupertinoIcons.checkmark_alt),
      ProposalStatus.discarded => StatusPill(label: 'Discarded$when', color: c.muted, icon: CupertinoIcons.xmark),
      ProposalStatus.undone => StatusPill(label: 'Undone$when', color: c.muted, icon: CupertinoIcons.arrow_uturn_left),
    };
  }

  Widget _safety(BuildContext context, CoachSafety s) {
    final c = context.rf;
    Widget note(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: c.caution),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: RfType.caption.copyWith(color: c.text))),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      decoration: BoxDecoration(color: c.caution.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.pain) note(CupertinoIcons.bandage, kPainNote),
        if (s.medical) note(CupertinoIcons.heart, kMedicalNote),
      ]),
    );
  }

  /* ------------------------------------------------------------ workout diff */

  Widget _section(BuildContext context, String title, List<Widget> children, {Widget? trailing}) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Semantics(header: true, child: Text(title.toUpperCase(), style: RfType.overline.copyWith(color: c.muted)))),
          ?trailing,
        ]),
        const SizedBox(height: 6),
        ...children,
      ]),
    );
  }

  Widget _workoutDiff(BuildContext context, WorkoutDiff diff) {
    final c = context.rf;
    final days = diff.days.where((d) => d.hasChanges).toList();
    final unchangedDays = diff.days.length - days.length;
    return _section(
      context,
      'What changes',
      [
        if (days.isEmpty) Text('No changes to your workout.', style: RfType.callout.copyWith(color: c.muted)),
        for (final d in days) _day(context, d),
        if (unchangedDays > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$unchangedDays other ${unchangedDays == 1 ? 'day stays' : 'days stay'} the same.', style: RfType.caption.copyWith(color: c.muted)),
          ),
      ],
    );
  }

  Widget _day(BuildContext context, DayDiff d) {
    final c = context.rf;
    final header = <InlineSpan>[
      TextSpan(text: d.weekday.label, style: RfType.captionStrong.copyWith(color: c.text)),
      const TextSpan(text: '  '),
      TextSpan(text: d.title, style: RfType.captionStrong.copyWith(color: c.muted)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
          Text.rich(TextSpan(children: header)),
          if (d.movedFrom != null) _tag(context, 'Moved ${d.movedFrom!.label} → ${d.weekday.label}', CupertinoIcons.arrow_right_arrow_left),
          if (d.fromTitle != null && d.movedFrom == null) _tag(context, 'was ${d.fromTitle}', CupertinoIcons.pencil),
          if (d.isNewDay) _tag(context, 'New day', CupertinoIcons.plus),
          if (d.isDropped) _tag(context, 'Now a rest day', CupertinoIcons.moon),
        ]),
        for (final l in d.lines) _line(context, l),
        if (d.unchanged > 0 && d.lines.isNotEmpty)
          Text('+ ${d.unchanged} unchanged', style: RfType.caption.copyWith(color: c.muted)),
      ]),
    );
  }

  Widget _tag(BuildContext context, String text, IconData icon) {
    final c = context.rf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.coach.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Rf.chipRadius)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c.coach),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: RfType.caption.copyWith(color: c.coach, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _line(BuildContext context, DiffLine l) {
    final c = context.rf;
    final struck = RfType.callout.copyWith(color: c.muted, decoration: TextDecoration.lineThrough, decorationColor: c.muted);
    final bold = RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w700);
    final plain = RfType.callout.copyWith(color: c.text);
    final arrow = Icon(CupertinoIcons.arrow_right, size: 14, color: c.coach);
    final (IconData icon, String sem, List<Widget> parts) = switch (l.kind) {
      DiffKind.removed => (
          CupertinoIcons.minus_circle,
          'Removed ${_name(l.from!.exerciseId)} ${doseOf(l.from!)}',
          [Text(_name(l.from!.exerciseId), style: struck), Text(doseOf(l.from!), style: struck)],
        ),
      DiffKind.added => (
          CupertinoIcons.plus_circle,
          'Added ${_name(l.to!.exerciseId)} ${doseOf(l.to!)}',
          [Text(_name(l.to!.exerciseId), style: bold), Text(doseOf(l.to!), style: bold.copyWith(fontFeatures: RfType.numeral.fontFeatures))],
        ),
      DiffKind.changed => (
          CupertinoIcons.slider_horizontal_3,
          'Changed ${_name(l.to!.exerciseId)} from ${doseOf(l.from!)} to ${doseOf(l.to!)}',
          [Text(_name(l.to!.exerciseId), style: plain), Text('${doseOf(l.from!)} → ${doseOf(l.to!)}', style: bold.copyWith(fontFeatures: RfType.numeral.fontFeatures))],
        ),
      DiffKind.replaced => (
          CupertinoIcons.arrow_2_squarepath,
          'Swapped ${_name(l.from!.exerciseId)} ${doseOf(l.from!)} for ${_name(l.to!.exerciseId)} ${doseOf(l.to!)}',
          [
            Text('${_name(l.from!.exerciseId)} ${doseOf(l.from!)}', style: struck),
            arrow,
            Text('${_name(l.to!.exerciseId)} ${doseOf(l.to!)}', style: bold),
          ],
        ),
    };
    final editable = _adjusting && _pending && widget.onAdjusted != null;
    final canEdit = editable && l.to != null && l.to!.unit != Unit.minutes;
    final open = _editing == l.key && canEdit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: editable ? Rf.tap : 30),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Semantics(
              label: sem,
              excludeSemantics: true,
              child: Row(children: [
                Icon(icon, size: 16, color: l.kind == DiffKind.removed ? c.muted : c.coach),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: parts),
                  ),
                ),
              ]),
            ),
          ),
          if (canEdit)
            _iconButton(context, open ? CupertinoIcons.checkmark_alt : CupertinoIcons.pencil, open ? 'Done editing' : 'Edit sets and reps', () {
              setState(() => _editing = open ? null : l.key);
            }),
          if (editable)
            _iconButton(context, CupertinoIcons.xmark, 'Keep current plan for this line', () {
              Haptics.tick();
              setState(() => _editing = null);
              widget.onAdjusted!(revertLine(p.after, l, p.before.workout));
            }, key: ValueKey('keep-line-${l.to?.exerciseId ?? l.from!.exerciseId}')),
        ]),
      ),
      if (open) _doseEditor(context, l),
    ]);
  }

  Widget _iconButton(BuildContext context, IconData icon, String label, VoidCallback onTap, {Key? key}) => Semantics(
        key: key,
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(width: Rf.tap, height: Rf.tap, child: Icon(icon, size: 20, color: context.rf.muted)),
        ),
      );

  Widget _doseEditor(BuildContext context, DiffLine l) {
    final c = context.rf;
    final e = l.to!;
    final timed = e.unit == Unit.seconds;
    void set({int? sets, int? lo, int? hi}) {
      var repsMin = lo ?? e.repsMin;
      var repsMax = hi ?? e.repsMax;
      if (lo != null && repsMax < repsMin) repsMax = repsMin;
      if (hi != null && repsMin > repsMax) repsMin = repsMax;
      widget.onAdjusted!(setDose(p.after, l.weekday, e.exerciseId, sets: sets ?? e.sets, repsMin: repsMin, repsMax: repsMax));
    }

    final step = timed ? 5.0 : 1.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        BigStepper(value: e.sets.toDouble(), min: 1, max: 10, step: 1, label: 'Sets', compact: true, onChanged: (v) => set(sets: v.round())),
        const SizedBox(height: 8),
        BigStepper(
            value: e.repsMin.toDouble(), min: 1, max: timed ? 600 : 50, step: step, label: timed ? 'Seconds (low)' : 'Reps (low)', compact: true, onChanged: (v) => set(lo: v.round())),
        const SizedBox(height: 8),
        BigStepper(
            value: e.repsMax.toDouble(), min: 1, max: timed ? 600 : 50, step: step, label: timed ? 'Seconds (high)' : 'Reps (high)', compact: true, onChanged: (v) => set(hi: v.round())),
      ]),
    );
  }

  /* ------------------------------------------------------------ diet */

  Widget _dietDiff(BuildContext context, DietDiff d) {
    final c = context.rf;
    String n(double? v) => v == null ? '–' : thousands(jsRound(v));
    Widget target(String label, double? from, double to, String unit) {
      final same = from != null && jsRound(from) == jsRound(to);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: RfType.caption.copyWith(color: c.muted)),
            const SizedBox(height: 2),
            Text(same ? '${n(to)} $unit · same' : '${n(from)} → ${n(to)} $unit',
                style: RfType.bodyStrong.copyWith(color: c.text, fontFeatures: RfType.numeral.fontFeatures)),
          ]),
        ),
      );
    }

    Widget meal(MealDiff m) {
      final (IconData icon, String head) = switch (m.kind) {
        MealChange.added => (CupertinoIcons.plus_circle, 'Added'),
        MealChange.removed => (CupertinoIcons.minus_circle, 'Removed'),
        MealChange.changed => (CupertinoIcons.slider_horizontal_3, 'Changed'),
      };
      final from = m.from == null ? null : '${m.from!.items.join(', ')} · ${jsRound(m.from!.proteinG)} g protein';
      final to = m.to == null ? null : '${m.to!.items.join(', ')} · ${jsRound(m.to!.proteinG)} g protein';
      return Semantics(
        label: '$head meal ${m.meal}',
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: m.kind == MealChange.removed ? c.muted : c.coach),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(m.to ?? m.from)!.time} · ${m.meal}', style: RfType.captionStrong.copyWith(color: c.text)),
                if (from != null)
                  Text(from, style: RfType.caption.copyWith(color: c.muted, decoration: m.kind == MealChange.added ? null : TextDecoration.lineThrough)),
                if (to != null) Text(to, style: RfType.caption.copyWith(color: c.text, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
      );
    }

    return _section(context, 'Diet', [
      Row(children: [
        target('Calories', d.kcalBefore, d.kcalAfter, 'kcal'),
        const SizedBox(width: 8),
        target('Protein', d.proteinBefore, d.proteinAfter, 'g'),
      ]),
      for (final m in d.meals) meal(m),
      if (d.unchangedMeals > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${d.unchangedMeals} ${d.unchangedMeals == 1 ? 'meal stays' : 'meals stay'} the same.', style: RfType.caption.copyWith(color: c.muted)),
        ),
    ]);
  }

  /* ------------------------------------------------------------ impact */

  Widget _impact(BuildContext context, PlanImpact i) {
    final c = context.rf;
    Widget cell(String text, {IconData? icon, Color? tone, String? semantics}) => Semantics(
          label: semantics ?? text,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: (tone ?? c.text).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 14, color: tone ?? c.muted), const SizedBox(width: 5)],
              Flexible(child: Text(text, style: RfType.caption.copyWith(color: c.text, fontWeight: FontWeight.w600, fontFeatures: RfType.numeral.fontFeatures))),
            ]),
          ),
        );
    final gaps = i.gapsAfter;
    final check = i.balanced
        ? cell('Plan check: balanced', icon: CupertinoIcons.checkmark_seal, tone: c.done)
        : cell('Plan check: ${gaps.length} ${gaps.length == 1 ? 'gap' : 'gaps'} (${gaps.take(3).map((g) => g.label).join(', ')}${gaps.length > 3 ? '…' : ''})',
            icon: CupertinoIcons.exclamationmark_circle, tone: c.caution);
    final delta = i.gapsAfter.length - i.gapsBefore.length;
    final mins = i.minutesAfter == null
        ? null
        : i.minutesBefore == null || i.minutesBefore == i.minutesAfter
            ? cell('Session ~${i.minutesAfter} min', icon: CupertinoIcons.timer)
            : cell('Session time ${i.minutesBefore} → ${i.minutesAfter} min', icon: CupertinoIcons.timer);
    return _section(context, 'Impact', [
      Text(
        i.balanced
            ? 'Every muscle group still gets enough weekly sets.'
            : delta < 0
                ? 'This closes ${-delta} ${delta == -1 ? 'gap' : 'gaps'} in your week.'
                : delta > 0
                    ? 'Heads up: this leaves ${gaps.length} muscle ${gaps.length == 1 ? 'group' : 'groups'} under target.'
                    : 'Weekly sets per muscle group, before → after.',
        style: RfType.caption.copyWith(color: c.muted),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final g in i.highlights.take(6))
          cell(g.changed ? '${g.group.label} ${setsLabel(g.before)} → ${setsLabel(g.after)}' : '${g.group.label} ${setsLabel(g.after)}',
              semantics: '${g.group.label}: ${setsLabel(g.before)} to ${setsLabel(g.after)} weekly sets'),
        check,
        ?mins,
      ]),
    ]);
  }

  /* ------------------------------------------------------------ why + warnings */

  Widget _why(BuildContext context) {
    final c = context.rf;
    final summary = p.after.summary.trim();
    return _section(context, 'Why', [
      if (summary.isNotEmpty) Text(summary, style: RfType.callout.copyWith(color: c.text)),
      const SizedBox(height: 4),
      Row(children: [
        Icon(CupertinoIcons.doc_text_search, size: 14, color: c.coach),
        const SizedBox(width: 6),
        Expanded(child: Text('Based on your plan and last sessions${p.request.isEmpty ? '' : ', and what you said'}.', style: RfType.caption.copyWith(color: c.coach))),
      ]),
    ]);
  }

  Widget _warnings(BuildContext context) {
    final c = context.rf;
    return _section(context, 'Worth knowing', [
      for (final w in p.after.warnings)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(CupertinoIcons.info_circle, size: 15, color: c.caution),
            const SizedBox(width: 8),
            Expanded(child: Text(w, style: RfType.caption.copyWith(color: c.text))),
          ]),
        ),
    ]);
  }

  /* ------------------------------------------------------------ actions */

  Widget _actions(BuildContext context) {
    final c = context.rf;
    final pad = const EdgeInsets.fromLTRB(16, 16, 16, 16);
    switch (p.status) {
      case ProposalStatus.pending:
        if (widget.onApprove == null && widget.onDiscard == null) return const SizedBox(height: 16);
        return Padding(
          padding: pad,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_adjusting)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Tap ✎ to change sets or reps, or × to keep that part of your current plan.', style: RfType.caption.copyWith(color: c.muted)),
              ),
            if (widget.onApprove != null) RfButton(label: 'Approve', icon: CupertinoIcons.checkmark_alt, expand: true, busy: widget.busy, onPressed: widget.onApprove),
            const SizedBox(height: 8),
            Row(children: [
              if (widget.onAdjusted != null && p.after.workout != null)
                Expanded(
                  child: RfButton(
                    label: _adjusting ? 'Done adjusting' : 'Adjust',
                    icon: _adjusting ? CupertinoIcons.checkmark : CupertinoIcons.slider_horizontal_3,
                    kind: RfButtonKind.secondary,
                    onPressed: widget.busy ? null : () => setState(() {
                      _adjusting = !_adjusting;
                      _editing = null;
                    }),
                  ),
                ),
              if (widget.onAdjusted != null && p.after.workout != null) const SizedBox(width: 8),
              if (widget.onDiscard != null)
                Expanded(child: RfButton(label: 'Discard', icon: CupertinoIcons.xmark, kind: RfButtonKind.ghost, onPressed: widget.busy ? null : widget.onDiscard)),
            ]),
          ]),
        );
      case ProposalStatus.approved:
        return Padding(
          padding: pad,
          child: Row(children: [
            Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: c.done),
            const SizedBox(width: 8),
            Expanded(child: Text('This is your plan now. History is kept.', style: RfType.caption.copyWith(color: c.text))),
            if (widget.onUndo != null) RfButton(label: 'Undo', icon: CupertinoIcons.arrow_uturn_left, kind: RfButtonKind.secondary, busy: widget.busy, onPressed: widget.onUndo),
          ]),
        );
      case ProposalStatus.discarded:
        return Padding(padding: pad, child: Text('Discarded. Your plan didn’t change.', style: RfType.caption.copyWith(color: c.muted)));
      case ProposalStatus.undone:
        return Padding(padding: pad, child: Text('Undone. Your previous plan is back.', style: RfType.caption.copyWith(color: c.muted)));
    }
  }
}
