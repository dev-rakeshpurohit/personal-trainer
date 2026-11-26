// The second half of onboarding: building the plan (real steps), the reveal, the first AI edit,
// save, notifications, the one-time paywall and the first workout.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/services/coach_client.dart';
import '../../data/services/common.dart';
import '../../domain/ai_plan.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'draft.dart';
import 'ob_widgets.dart';
import 'plan_logic.dart';
import 'steps.dart' show showCodeSheet;

/// Everything the reveal needs, produced by the build step.
class BuiltPlan {
  const BuiltPlan({required this.profile, required this.bundle, required this.diet, required this.meals, required this.check, required this.exMap});
  final Profile profile;
  final ProgramBundle bundle;
  final DietPlan? diet;
  final List<PlannedMeal> meals;
  final CheckSummary check;
  final Map<String, Exercise> exMap;
}

/// Scrollable body with actions pinned in the thumb zone.
class StepFrame extends StatelessWidget {
  const StepFrame({super.key, required this.body, this.footer, this.scroll = true});
  final Widget body;
  final Widget? footer;
  final bool scroll;
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(children: [
      Expanded(
        child: scroll
            ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(Rf.gutter + 4, 8, Rf.gutter + 4, 24), child: body)
            : Padding(padding: const EdgeInsets.fromLTRB(Rf.gutter + 4, 8, Rf.gutter + 4, 0), child: body),
      ),
      if (footer != null) Padding(padding: EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, bottom > 0 ? bottom : 16), child: footer),
    ]);
  }
}

String friendlyTime(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first) ?? 9;
  final m = p.length > 1 ? p[1] : '00';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m ${h < 12 ? 'am' : 'pm'}';
}

/* ------------------------------------------------------------ building */

typedef BuildRun = Future<BuiltPlan> Function(void Function(String line) report);

class BuildingStep extends StatefulWidget {
  const BuildingStep({super.key, required this.run, required this.onDone});
  final BuildRun run;
  final ValueChanged<BuiltPlan> onDone;
  @override
  State<BuildingStep> createState() => _BuildingStepState();
}

class _BuildingStepState extends State<BuildingStep> {
  final _shown = <String>[];
  final _queue = <String>[];
  Timer? _tick;
  BuiltPlan? _result;
  Object? _error;
  bool _started = false;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = context.reduceMotion;
    if (!_started) {
      _started = true;
      _go();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _go() async {
    try {
      final r = await widget.run(_report);
      if (mounted) setState(() => _result = r);
    } catch (e, st) {
      debugPrint('Onboarding build failed: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  void _report(String line) {
    _queue.add(line);
    _pump();
  }

  // Lines are revealed one at a time so they can be read; the work itself is not delayed.
  void _pump() {
    if (_tick != null || _queue.isEmpty) return;
    _tick = Timer(Duration(milliseconds: _reduce ? 0 : 320), () {
      _tick = null;
      if (!mounted) return;
      setState(() => _shown.add(_queue.removeAt(0)));
      _pump();
    });
  }

  bool get _done => _result != null && _queue.isEmpty && _tick == null;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return StepFrame(
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StepHeading(_done ? 'Your plan is ready' : 'Building your plan', sub: 'Here is what your answers changed.'),
        for (final l in _shown) BuildLine(l),
        if (!_done && _error == null) const BuildLine('Working…', done: false),
        if (_error != null)
          RfCard(
            child: Text('Something went wrong while saving your plan. Nothing was lost. Please try again.', style: RfType.callout.copyWith(color: c.text)),
          ),
      ]),
      footer: _error != null
          ? RfButton(
              label: 'Try again',
              expand: true,
              onPressed: () {
                setState(() {
                  _error = null;
                  _shown.clear();
                });
                _go();
              },
            )
          : RfButton(
              key: const Key('ob-see-plan'),
              label: 'See my plan',
              icon: CupertinoIcons.sparkles,
              expand: true,
              height: Rf.gymTap,
              onPressed: _done ? () => widget.onDone(_result!) : null,
            ),
    );
  }
}

/* ------------------------------------------------------------ reveal */

class RevealStep extends StatefulWidget {
  const RevealStep({super.key, required this.built, required this.d, required this.onDone});
  final BuiltPlan built;
  final OnboardingDraft d;
  final VoidCallback onDone;
  @override
  State<RevealStep> createState() => _RevealStepState();
}

class _RevealStepState extends State<RevealStep> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= 2) return widget.onDone();
    _pages.animateToPage(_page + 1, duration: Duration(milliseconds: context.reduceMotion ? 1 : 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Column(children: [
      Expanded(
        child: PageView(
          controller: _pages,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            _WeekPage(built: widget.built, d: widget.d),
            _CheckPage(built: widget.built, d: widget.d),
            _DietPage(built: widget.built, d: widget.d),
          ],
        ),
      ),
      Semantics(
        label: 'Page ${_page + 1} of 3',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: Duration(milliseconds: context.reduceMotion ? 0 : 200),
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              width: i == _page ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(color: i == _page ? c.accent : c.line, borderRadius: BorderRadius.circular(8)),
            ),
        ]),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 16),
        child: RfButton(key: const Key('ob-reveal-next'), label: _page < 2 ? 'Next' : 'Looks good', expand: true, height: Rf.gymTap, onPressed: _next),
      ),
    ]);
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(Rf.gutter + 4, 8, Rf.gutter + 4, 16), children: children);
}

class _WeekPage extends StatelessWidget {
  const _WeekPage({required this.built, required this.d});
  final BuiltPlan built;
  final OnboardingDraft d;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final b = built.bundle;
    final training = b.days.where((x) => x.type.isTraining).length;
    return _PageScroll(children: [
      const StepHeading('Week 1'),
      ReasonChip('Because you said $training days a week, ${d.sessionMin} min, to ${goalLabel(d.goal)}'),
      const SizedBox(height: 16),
      for (final w in Weekday.values)
        () {
          final day = b.days.where((x) => x.weekday == w).firstOrNull;
          final on = day != null && day.type.isTraining;
          final ex = on ? b.plannedFor(day.id) : const <PlannedExercise>[];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RfCard(
              color: on ? c.surface : c.bg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 44, child: Text(w.label, style: RfType.bodyStrong.copyWith(color: on ? c.accentInk : c.muted))),
                Expanded(
                  child: on
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(day.title, style: RfType.bodyStrong.copyWith(color: c.text)),
                          Text('${ex.length} exercises · ${day.durationMin ?? d.sessionMin} min', style: RfType.caption.copyWith(color: c.muted)),
                          if (ex.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                ex.take(3).map((p) => built.exMap[p.exerciseId]?.name ?? p.exerciseId).join(' · '),
                                style: RfType.caption.copyWith(color: c.text.withValues(alpha: 0.8)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ])
                      : Text(day?.title.isNotEmpty == true && day!.type == DayType.activeRecovery ? day.title : 'Rest', style: RfType.body.copyWith(color: c.muted)),
                ),
              ]),
            ),
          );
        }(),
    ]);
  }
}

class _CheckPage extends StatelessWidget {
  const _CheckPage({required this.built, required this.d});
  final BuiltPlan built;
  final OnboardingDraft d;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final s = built.check;
    return _PageScroll(children: [
      const StepHeading('Plan check'),
      Text(s.headline, style: RfType.headline.copyWith(color: c.text)),
      const SizedBox(height: 6),
      Text('Weekly working sets per muscle group, against the minimum for your goal.', style: RfType.callout.copyWith(color: c.muted)),
      const SizedBox(height: 14),
      for (final r in s.rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
            label: '${r.group.label}: ${_fmt(r.have)} of ${r.need} sets, ${r.have >= r.need ? 'enough' : 'a little light'}',
            excludeSemantics: true,
            child: Row(children: [
              Icon(r.have >= r.need ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.arrow_up_circle, size: 20, color: r.have >= r.need ? c.done : c.caution),
              const SizedBox(width: 10),
              SizedBox(width: 92, child: Text(r.group.label, style: RfType.callout.copyWith(color: c.text))),
              Expanded(child: LinearMeter(value: r.need == 0 ? 1 : r.have / r.need, color: r.have >= r.need ? c.done : c.caution)),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: Text('${_fmt(r.have)} / ${r.need}', textAlign: TextAlign.right, style: RfType.caption.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        ),
      if (s.covered < s.total) ...[
        const SizedBox(height: 6),
        Text('Light groups get a one-tap fix in Train → Plan check.', style: RfType.caption.copyWith(color: c.muted)),
      ],
    ]);
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _DietPage extends StatelessWidget {
  const _DietPage({required this.built, required this.d});
  final BuiltPlan built;
  final OnboardingDraft d;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final plan = built.diet;
    final meals = built.meals;
    final hasWhey = meals.any((m) => m.items.any((i) => i.toLowerCase().contains('whey')));
    return _PageScroll(children: [
      const StepHeading('A day of eating'),
      if (plan == null)
        Text('No diet plan yet.', style: RfType.body.copyWith(color: c.muted))
      else ...[
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
          Text('${plan.proteinTargetG}', style: RfType.setNumeral.copyWith(color: c.text)),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('g protein a day', style: RfType.bodyStrong.copyWith(color: c.text))),
        ]),
        Text('About ${thousandsOf(plan.kcalTarget)} kcal', style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 10),
        ReasonChip('Because you said ${dietLabel(d.diet)}. ${targetsWhy(d)}'),
        const SizedBox(height: 16),
        for (final m in meals)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RfCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 52, child: Text(m.time, style: RfType.captionStrong.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.meal, style: RfType.bodyStrong.copyWith(color: c.text)),
                    Text(m.items.join(', '), style: RfType.caption.copyWith(color: c.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: 8),
                Text('${m.proteinG.round()} g', style: RfType.captionStrong.copyWith(color: c.text)),
              ]),
            ),
          ),
        if (d.whey == 'no' && hasWhey)
          Text('Your plan includes a protein shake for now. Swap it in Eat, or ask the coach for food instead.', style: RfType.caption.copyWith(color: c.muted)),
      ],
    ]);
  }
}

/* ------------------------------------------------------------ first edit */

enum _EditState { idle, asking, proposal, unavailable }

class FirstEditStep extends ConsumerStatefulWidget {
  const FirstEditStep({super.key, required this.built, required this.d, required this.onDone});
  final BuiltPlan built;
  final OnboardingDraft d;
  final VoidCallback onDone;
  @override
  ConsumerState<FirstEditStep> createState() => _FirstEditStepState();
}

class _FirstEditStepState extends ConsumerState<FirstEditStep> {
  final _ctl = TextEditingController();
  _EditState _state = _EditState.idle;
  String _message = '';
  CoachResult? _result;
  List<DiffLine> _diff = const [];
  String? _dietDiff;
  bool _applying = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String get _hint {
    final pain = widget.d.pain ?? const [];
    if (pain.contains('knee')) return "Try: 'no deep squats, my knee is sensitive'";
    if (pain.contains('lower_back')) return "Try: 'go easy on my lower back'";
    if (pain.contains('shoulder')) return "Try: 'no overhead pressing, shoulder hurts'";
    return "Try: 'no squats, knee is sensitive' or 'more arm work'";
  }

  Future<void> _ask() async {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    final s = ref.read(storesProvider);
    final code = await s.getMeta<String>(ObMeta.accessCode);
    if (code == null || code.isEmpty) {
      setState(() {
        _state = _EditState.unavailable;
        _message = 'Plan edits in plain words live in the Coach tab. During the beta the AI coach needs an invite code; you can add one there any time. Your note is a good first request.';
      });
      return;
    }
    setState(() => _state = _EditState.asking);
    try {
      final lang = widget.d.coachLanguage == 'hinglish' ? '\nReply in Hinglish.' : '';
      final r = await ref.read(coachClientProvider).askCoach(
            mode: CoachMode.change,
            want: CoachWant(workout: true, diet: mentionsFood(text)),
            notes: '$text$lang',
            code: code,
          );
      final bundle = await loadProgramBundle(s) ?? widget.built.bundle;
      final exMap = {...widget.built.exMap};
      final diet = await s.activeDiet();
      if (!mounted) return;
      setState(() {
        _result = r;
        _diff = r.plan.workout == null ? const [] : workoutDiff(bundle, r.plan.workout!, exMap);
        _dietDiff = dietDiff(diet, r.plan.diet);
        _state = _EditState.proposal;
      });
    } on CoachError catch (e) {
      if (mounted) _unavailable('${e.message} Your plan is saved; you can ask again from the Coach tab.');
    } on AiPlanException catch (e) {
      if (mounted) _unavailable('The coach replied with something unusable (${e.message}). Your plan is unchanged; try again from the Coach tab.');
    }
  }

  void _unavailable(String msg) => setState(() {
        _state = _EditState.unavailable;
        _message = msg;
      });

  Future<void> _approve() async {
    final r = _result;
    if (r == null) return;
    setState(() => _applying = true);
    final b = await ref.read(planBuilderProvider.future);
    final p = widget.built.profile;
    final w = r.plan.workout;
    final diet = r.plan.diet;
    if (w != null) await b.saveAiWorkout(p, w);
    if (diet != null) await b.saveAiDiet(diet);
    Haptics.setDone();
    if (!mounted) return;
    showRfToast(context, 'Plan updated by the coach', icon: CupertinoIcons.checkmark_alt, onUndo: () async {
      if (w != null) await b.saveGeneratedProgram(p);
      if (diet != null) await b.saveGeneratedDiet(p);
    });
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('Want to change anything?', sub: 'Say it in your own words. The coach proposes a change; you approve it or not.'),
      TextField(
        key: const Key('ob-edit-field'),
        controller: _ctl,
        minLines: 2,
        maxLines: 4,
        enabled: _state != _EditState.asking,
        style: RfType.body.copyWith(color: c.text),
        decoration: InputDecoration(hintText: _hint, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      if (_state == _EditState.idle || _state == _EditState.unavailable)
        Align(
          alignment: Alignment.centerLeft,
          child: RfButton(
            key: const Key('ob-edit-ask'),
            label: 'Ask the coach',
            icon: Icons.auto_awesome,
            kind: RfButtonKind.coach,
            onPressed: _ctl.text.trim().isEmpty ? null : _ask,
          ),
        ),
      if (_state == _EditState.asking)
        RfCard(
          border: c.coach.withValues(alpha: 0.4),
          child: Row(children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.coach)),
            const SizedBox(width: 12),
            Expanded(child: Text('Sending your plan and note to the coach. This can take up to a minute.', style: RfType.callout.copyWith(color: c.text))),
          ]),
        ),
      if (_state == _EditState.unavailable) ...[
        const SizedBox(height: 12),
        RfCard(
          key: const Key('ob-edit-unavailable'),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_awesome, color: c.coach, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(_message, style: RfType.callout.copyWith(color: c.text))),
          ]),
        ),
      ],
      if (_state == _EditState.proposal && _result != null) ...[
        const SizedBox(height: 4),
        _ProposalCard(summary: _result!.plan.summary, diff: _diff, dietDiff: _dietDiff, warnings: _result!.plan.warnings),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: RfButton(label: 'Approve', icon: CupertinoIcons.checkmark_alt, busy: _applying, expand: true, onPressed: _approve)),
          const SizedBox(width: 10),
          Expanded(
            child: RfButton(
              label: 'Discard',
              kind: RfButtonKind.secondary,
              expand: true,
              onPressed: _applying
                  ? null
                  : () => setState(() {
                        _state = _EditState.idle;
                        _result = null;
                      }),
            ),
          ),
        ]),
      ],
    ]);
    return StepFrame(
      body: body,
      footer: RfButton(
        key: const Key('ob-edit-skip'),
        label: _state == _EditState.proposal ? 'Keep my plan as it is' : 'No changes, continue',
        kind: _state == _EditState.proposal ? RfButtonKind.ghost : RfButtonKind.primary,
        expand: true,
        height: Rf.gymTap,
        onPressed: _state == _EditState.asking || _applying ? null : widget.onDone,
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.summary, required this.diff, required this.dietDiff, required this.warnings});
  final String summary;
  final List<DiffLine> diff;
  final String? dietDiff;
  final List<String> warnings;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return RfCard(
      border: c.coach.withValues(alpha: 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CoachDot(),
          const SizedBox(width: 8),
          Text('Coach proposal', style: RfType.captionStrong.copyWith(color: c.coach)),
        ]),
        if (summary.isNotEmpty) ...[const SizedBox(height: 8), Text(summary, style: RfType.callout.copyWith(color: c.text))],
        const SizedBox(height: 10),
        if (diff.isEmpty && dietDiff == null) Text('No exercise changes.', style: RfType.callout.copyWith(color: c.muted)),
        for (final l in diff.take(7))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.label, style: RfType.captionStrong.copyWith(color: c.text)),
              for (final r in l.removed) _diffRow(c, '−', r, c.muted, strike: true),
              for (final a in l.added) _diffRow(c, '+', a, c.coach),
            ]),
          ),
        if (diff.length > 7) Text('and ${diff.length - 7} more days', style: RfType.caption.copyWith(color: c.muted)),
        if (dietDiff != null) ...[
          Text('Diet', style: RfType.captionStrong.copyWith(color: c.text)),
          _diffRow(c, '→', dietDiff!, c.coach),
        ],
        for (final w in warnings.take(2)) Padding(padding: const EdgeInsets.only(top: 6), child: Text(w, style: RfType.caption.copyWith(color: c.caution))),
      ]),
    );
  }

  Widget _diffRow(RfColors c, String sign, String text, Color color, {bool strike = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 18, child: Text(sign, style: RfType.bodyStrong.copyWith(color: color))),
          Expanded(
            child: Text(text, style: RfType.callout.copyWith(color: strike ? c.muted : c.text, decoration: strike ? TextDecoration.lineThrough : null)),
          ),
        ]),
      );
}

/* ------------------------------------------------------------ save */

class SaveStep extends StatelessWidget {
  const SaveStep({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    Widget row(IconData i, String t, String s) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, color: c.done, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: RfType.bodyStrong.copyWith(color: c.text)),
                Text(s, style: RfType.callout.copyWith(color: c.muted)),
              ]),
            ),
          ]),
        );
    return StepFrame(
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const StepHeading('Your plan is saved on this phone'),
        row(CupertinoIcons.device_phone_portrait, 'Works offline, even in a basement gym', 'Every set is saved the moment you tick it.'),
        row(CupertinoIcons.person_crop_circle_badge_checkmark, 'Accounts come later', 'Sign in with Apple to sync arrives in a later beta. Nothing to set up today.'),
        row(CupertinoIcons.phone_down, 'We will never call you', 'No phone number, no sales calls. Ever.'),
      ]),
      footer: RfButton(key: const Key('ob-save-next'), label: 'Continue', expand: true, height: Rf.gymTap, onPressed: onDone),
    );
  }
}

/* ------------------------------------------------------------ notifications */

class NotifyStep extends ConsumerStatefulWidget {
  const NotifyStep({super.key, required this.d, required this.built, required this.onDone});
  final OnboardingDraft d;
  final BuiltPlan built;
  final VoidCallback onDone;
  @override
  ConsumerState<NotifyStep> createState() => _NotifyStepState();
}

class _NotifyStepState extends ConsumerState<NotifyStep> {
  bool _busy = false;

  Future<void> _set(bool want) async {
    setState(() => _busy = true);
    var granted = false;
    if (want) granted = await ref.read(notificationPermissionProvider)();
    await ref.read(storesProvider).setMeta(ObMeta.reminders, {'enabled': want && granted, 'time': widget.d.sessionTime});
    if (!mounted) return;
    if (want && !granted) showRfToast(context, 'Reminders are off. You can turn them on in iPhone Settings any time.');
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final first = widget.built.bundle.days.where((x) => x.type.isTraining).firstOrNull;
    final time = friendlyTime(widget.d.sessionTime);
    return StepFrame(
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StepHeading('Remind you on training days at $time?', sub: 'One reminder on training days. Nothing on rest days, no offers, quiet at night.'),
        RfCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.fitness_center, size: 20, color: c.onAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('REPFELLOW', style: RfType.overline.copyWith(color: c.muted))),
                  Text(time, style: RfType.caption.copyWith(color: c.muted)),
                ]),
                const SizedBox(height: 2),
                Text(
                  first == null ? 'Training today' : '${first.title} · ${first.durationMin ?? widget.d.sessionMin} min',
                  style: RfType.bodyStrong.copyWith(color: c.text),
                ),
                Text('Your plan is ready. Tap to start when you get to the gym.', style: RfType.callout.copyWith(color: c.muted)),
              ]),
            ),
          ]),
        ),
      ]),
      footer: Column(mainAxisSize: MainAxisSize.min, children: [
        RfButton(key: const Key('ob-notify-yes'), label: 'Yes, remind me', busy: _busy, expand: true, height: Rf.gymTap, onPressed: () => _set(true)),
        const SizedBox(height: 6),
        RfButton(key: const Key('ob-notify-no'), label: 'Not now', kind: RfButtonKind.ghost, expand: true, onPressed: _busy ? null : () => _set(false)),
      ]),
    );
  }
}

/* ------------------------------------------------------------ paywall (organic only, shown once) */

/// BETA prices: StoreKit isn't wired yet, so these are indicative and nothing is charged.
const kBetaAnnualInr = 2499;
const kBetaMonthlyInr = 349;

class PaywallStep extends ConsumerStatefulWidget {
  const PaywallStep({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  ConsumerState<PaywallStep> createState() => _PaywallStepState();
}

class _PaywallStepState extends ConsumerState<PaywallStep> {
  bool _annual = true;
  bool _compare = false;

  Future<void> _leave({bool beta = false, String? code}) async {
    final s = ref.read(storesProvider);
    final now = ref.read(clockProvider)();
    await s.setMeta(ObMeta.paywallSeenAt, isoString(now));
    if (beta) await s.setMeta(ObMeta.proBeta, true);
    if (code != null) {
      await s.setMeta(ObMeta.accessCode, code);
      await s.setMeta(ObMeta.proViaCode, code);
    }
    if (!mounted) return;
    if (beta) showRfToast(context, 'Pro is on for the beta. No payment was taken.', icon: CupertinoIcons.checkmark_alt);
    if (code != null) showRfToast(context, 'Code applied. Pro is included.', icon: CupertinoIcons.checkmark_alt);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final now = ref.watch(clockProvider)();
    final fmt = DateFormat('d MMM');
    final top = MediaQuery.paddingOf(context).top;
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(Rf.gutter, top + 4, 6, 0),
        child: Row(children: [
          const TagBadge('BETA'),
          const Spacer(),
          IconButton(
            key: const Key('ob-paywall-close'),
            tooltip: 'Close, continue with the free plan',
            iconSize: 26,
            constraints: const BoxConstraints(minWidth: Rf.tap, minHeight: Rf.tap),
            icon: Icon(CupertinoIcons.xmark, color: c.muted),
            onPressed: () => _leave(),
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(Rf.gutter + 4, 0, Rf.gutter + 4, 16), children: [
          Semantics(header: true, child: Text('Keep your plan coaching itself', style: RfType.title.copyWith(color: c.text))),
          const SizedBox(height: 14),
          for (final (i, t) in [
            (CupertinoIcons.calendar_badge_plus, 'Re-plans your week when you miss a session'),
            (CupertinoIcons.chat_bubble_text, 'Unlimited plan edits in plain words'),
            (Icons.restaurant_outlined, 'Diet that adapts every week to your weight trend'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [Icon(i, color: c.accentInk, size: 22), const SizedBox(width: 12), Expanded(child: Text(t, style: RfType.body.copyWith(color: c.text)))]),
            ),
          const SizedBox(height: 12),
          _Timeline(entries: [
            ('Today', 'Full access to everything in Pro'),
            ('Day 5 · ${fmt.format(addDays(now, 4))}', 'We remind you the trial is ending'),
            ('Day 7 · ${fmt.format(addDays(now, 6))}', '₹${thousandsOf(_annual ? kBetaAnnualInr : kBetaMonthlyInr)}/${_annual ? 'year' : 'month'} starts. Cancel in Settings in two taps'),
          ]),
          const SizedBox(height: 16),
          _PlanOption(
            key: const Key('ob-plan-annual'),
            title: 'Yearly',
            price: '₹${thousandsOf(kBetaAnnualInr)}/year',
            sub: '₹${(kBetaAnnualInr / 12).round()}/month · 7 days free',
            badge: 'Best value',
            selected: _annual,
            onTap: () => setState(() => _annual = true),
          ),
          _PlanOption(
            key: const Key('ob-plan-monthly'),
            title: 'Monthly',
            price: '₹$kBetaMonthlyInr/month',
            sub: '7 days free',
            selected: !_annual,
            onTap: () => setState(() => _annual = false),
          ),
          const SizedBox(height: 6),
          Text(
            'Beta: in-app purchase isn\'t switched on yet, so no payment is taken and these prices may change. Pro is free while we test.',
            style: RfType.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _compare = !_compare),
            child: SizedBox(
              height: Rf.tap,
              child: Row(children: [
                Flexible(child: Text(_compare ? 'Hide Free vs Pro' : 'Compare Free and Pro', style: RfType.bodyStrong.copyWith(color: c.accentInk), overflow: TextOverflow.ellipsis)),
                Icon(_compare ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 16, color: c.accentInk),
              ]),
            ),
          ),
          if (_compare) const _CompareTable(),
          Row(children: [
            TextButton(
              key: const Key('ob-paywall-code'),
              onPressed: () async {
                final code = await showCodeSheet(context);
                if (code != null) await _leave(code: code);
              },
              child: Text('Have a code?', style: RfType.callout.copyWith(color: c.accentInk, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => showRfToast(context, 'Nothing to restore during the beta.'),
              child: Text('Restore', style: RfType.callout.copyWith(color: c.muted)),
            ),
          ]),
        ]),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RfButton(key: const Key('ob-paywall-beta'), label: 'Start free during beta', expand: true, height: Rf.gymTap, onPressed: () => _leave(beta: true)),
          const SizedBox(height: 4),
          RfButton(key: const Key('ob-paywall-free'), label: 'Continue with free plan', kind: RfButtonKind.ghost, expand: true, onPressed: () => _leave()),
        ]),
      ),
    ]);
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});
  final List<(String, String)> entries;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Column(children: [
      for (var i = 0; i < entries.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 28,
              child: Column(children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i == 0 ? c.accent : c.surface2, border: Border.all(color: i == 0 ? c.accent : c.line, width: 2)),
                ),
                if (i < entries.length - 1) Expanded(child: Container(width: 2, color: c.line)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entries[i].$1, style: RfType.bodyStrong.copyWith(color: c.text)),
                  Text(entries[i].$2, style: RfType.callout.copyWith(color: c.muted)),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({super.key, required this.title, required this.price, required this.sub, required this.selected, required this.onTap, this.badge});
  final String title;
  final String price;
  final String sub;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        label: '$title, $price, $sub',
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? c.accent.withValues(alpha: 0.12) : c.surface,
              borderRadius: BorderRadius.circular(Rf.cardRadius),
              border: Border.all(color: selected ? c.accent : c.line, width: selected ? 1.6 : 0.8),
            ),
            child: Row(children: [
              Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: selected ? c.accentInk : c.line),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 4, children: [
                    Text(title, style: RfType.bodyStrong.copyWith(color: c.text)),
                    if (badge != null) ...[const SizedBox(width: 8), TagBadge(badge!, color: c.done)],
                  ]),
                  Text(sub, style: RfType.caption.copyWith(color: c.muted)),
                ]),
              ),
              Text(price, style: RfType.bodyStrong.copyWith(color: c.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable();
  static const _rows = [
    ('Logger, rest timer, plate calculator, all demos', 'Yes', 'Yes'),
    ('AI plan edits in plain words', '3 a month', 'Unlimited'),
    ('Missed session: shift the week', 'Yes', 'Yes'),
    ('AI re-plans: merge, travel weeks, 30-min versions', '—', 'Yes'),
    ('Plan check', 'Status', 'Status + fixes'),
    ('Indian diet plan with weekly check-in', 'Protein target', 'Full plan'),
    ('Progress history', '3 months', 'All of it'),
  ];
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    TextStyle h = RfType.captionStrong.copyWith(color: c.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
        children: [
          TableRow(children: [Text('', style: h), Text('Free', style: h), Text('Pro', style: h)]),
          for (final r in _rows)
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r.$1, style: RfType.caption.copyWith(color: c.text))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r.$2, style: RfType.caption.copyWith(color: c.muted))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(r.$3, style: RfType.captionStrong.copyWith(color: c.text))),
            ]),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------ start */

class StartStep extends ConsumerWidget {
  const StartStep({super.key, required this.built, required this.name, required this.onFinish});
  final BuiltPlan built;
  final String name;

  /// [startDayId] = start this program day now (only today's session can be started).
  final void Function({String? startDayId}) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final now = ref.watch(clockProvider)();
    final today = dateOnly(now);
    final week = ref.watch(weekPlanProvider(today)).value;
    final bundle = ref.watch(programBundleProvider).value ?? built.bundle;
    final todayDay = week?.byDate[dayKey(today)];
    final canStart = todayDay != null && todayDay.type.isTraining && bundle.plannedFor(todayDay.id).isNotEmpty;
    ProgramDay? next;
    var nextDate = today;
    if (!canStart) {
      for (var i = 1; i <= 7 && next == null; i++) {
        final d = addDays(today, i);
        final p = bundle.days.where((x) => x.weekday == weekdayOf(d) && x.type.isTraining).firstOrNull;
        if (p != null) (next, nextDate) = (p, d);
      }
    }
    final hello = name.trim().isEmpty || name == 'there' ? 'You\'re all set.' : 'You\'re all set, ${name.trim()}.';
    return StepFrame(
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        Icon(CupertinoIcons.checkmark_seal_fill, size: 48, color: c.done),
        const SizedBox(height: 16),
        StepHeading(hello, sub: canStart ? 'Workout 1 is planned for today.' : 'Your first workout is on its way.'),
        RfCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(canStart ? 'TODAY' : (next == null ? 'NEXT' : DateFormat('EEEE d MMM').format(nextDate).toUpperCase()), style: RfType.overline.copyWith(color: c.accentInk)),
            const SizedBox(height: 4),
            Text(canStart ? todayDay.title : (next?.title ?? 'Rest'), style: RfType.headline.copyWith(color: c.text)),
            if (canStart || next != null)
              Text(
                '${bundle.plannedFor((canStart ? todayDay : next)!.id).length} exercises · ${(canStart ? todayDay : next)!.durationMin ?? built.profile.sessionMin ?? 45} min',
                style: RfType.callout.copyWith(color: c.muted),
              ),
          ]),
        ),
      ]),
      footer: Column(mainAxisSize: MainAxisSize.min, children: [
        if (canStart) ...[
          RfButton(
            key: const Key('ob-start-now'),
            label: 'Start Workout 1 now',
            icon: CupertinoIcons.play_fill,
            expand: true,
            height: Rf.doneBar,
            onPressed: () => onFinish(startDayId: todayDay.id),
          ),
          const SizedBox(height: 4),
          RfButton(key: const Key('ob-later'), label: 'Later', kind: RfButtonKind.ghost, expand: true, onPressed: () => onFinish()),
        ] else
          RfButton(key: const Key('ob-later'), label: 'Go to Today', expand: true, height: Rf.gymTap, onPressed: () => onFinish()),
      ]),
    );
  }
}
