// After Finish: a narrated plain-English recap ("Bench press 40 kg × 10 — next time 42.5. Great
// start!"), workout ordinal, duration / sets / volume, PRs (a first lift is a baseline PR), the next
// session's targets with reasons, then a short feedback step that tunes the next session.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/services/common.dart' show parseIsoLocal, thousands;
import '../../data/services/session_service.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/units.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'rest_band.dart' show buzz;
import 'workout_math.dart';

class SummaryData {
  const SummaryData({
    required this.summary,
    required this.ordinal,
    required this.narration,
    required this.closing,
    required this.prs,
    required this.preview,
    required this.names,
    required this.units,
  });
  final SessionSummary summary;
  final int ordinal;
  final List<String> narration;
  final String closing;

  /// PR lines; baseline PRs for first-ever lifts are included.
  final List<({String name, String what, bool baseline})> prs;

  /// Next session of this day: exercise and the coach's reason.
  final List<({String name, String message, SuggestionKind kind})> preview;
  final Map<String, String> names;
  final String units;
}

/// First value of a stream provider. Listens (instead of reading `.future`) so an unlistened
/// provider isn't paused before it emits.
Future<T> _first<T>(WidgetRef ref, ProviderListenable<AsyncValue<T>> p) {
  final done = Completer<T>();
  final sub = ref.listenManual<AsyncValue<T>>(p, (_, next) {
    if (done.isCompleted) return;
    if (next.hasValue) {
      done.complete(next.requireValue);
    } else if (next.hasError) {
      done.completeError(next.error!, next.stackTrace);
    }
  }, fireImmediately: true);
  return done.future.whenComplete(sub.close);
}

/// Build the summary content.
Future<SummaryData?> loadSummaryData(WidgetRef ref, String sessionId) async {
  final svc = ref.read(sessionServiceProvider);
  final sum = await svc.summary(sessionId);
  if (sum == null) return null;
  final profile = await _first(ref, profileProvider);
  final exMap = await _first(ref, exerciseMapProvider);
  final bundle = await _first(ref, programBundleProvider);
  final done = await _first(ref, doneSessionsProvider);
  final prog = ref.read(progressionDataProvider);
  final units = profile?.units ?? 'kg';
  final nextDate = ref.read(clockProvider)().add(const Duration(days: 7));

  final idx = done.indexWhere((s) => s.id == sessionId);
  final ordinal = idx >= 0 ? idx + 1 : done.length + 1;
  final names = {for (final id in sum.exercises) id: exMap[id]?.name ?? id};

  PlannedExercise? plannedFor(List<SetLog> sets) {
    for (final pe in sum.planned) {
      if (sets.any((x) => x.plannedExerciseId == pe.id)) return pe;
    }
    return null;
  }

  final narration = <String>[];
  final prs = <({String name, String what, bool baseline})>[];
  for (final id in sum.exercises) {
    final sets = sum.sets.where((x) => x.exerciseId == id).toList();
    final top = topSet(sets);
    if (top == null) continue;
    final ex = exMap[id];
    final pe = plannedFor(sets);
    final unit = pe?.unit ?? (top.seconds != null ? Unit.seconds : (top.meters != null ? Unit.meters : Unit.reps));
    Suggestion? next;
    if (pe != null && bundle != null && profile != null) {
      try {
        next = (await prog.suggestionFor(pe, id, ex, profile, bundle.program, nextDate)).suggestion;
      } catch (_) {}
    }
    narration.add(narrateExercise(name: names[id]!, top: top, unit: unit, units: units, bodyweight: ex?.isBodyweight == true, next: next));
    if ((sum.prior[id] ?? const []).isEmpty) {
      prs.add((name: names[id]!, what: 'Baseline ${setText(valuesOf(top), unit, units, bodyweight: ex?.isBodyweight == true)}', baseline: true));
    }
  }
  for (final p in sum.prs) {
    final what = p.types.map((t) => switch (t) { PRType.weight => 'heaviest yet', PRType.e1rm => 'best estimated max', PRType.reps => 'most reps' }).join(', ');
    prs.add((name: names[p.exerciseId] ?? p.exerciseId, what: what, baseline: false));
  }

  final preview = <({String name, String message, SuggestionKind kind})>[];
  if (bundle != null && profile != null) {
    for (final pe in sum.planned) {
      try {
        final sg = await prog.suggestionFor(pe, pe.exerciseId, exMap[pe.exerciseId], profile, bundle.program, nextDate);
        preview.add((name: exMap[pe.exerciseId]?.name ?? pe.exerciseId, message: sg.message, kind: sg.kind));
      } catch (_) {}
    }
  }
  final plannedSets = sum.planned.fold<int>(0, (a, p) => a + p.sets);
  return SummaryData(
    summary: sum,
    ordinal: ordinal,
    narration: narration,
    closing: closingLine(ordinal: ordinal, prCount: sum.prs.length, allDone: plannedSets == 0 || sum.count >= plannedSets),
    prs: prs,
    preview: preview,
    names: names,
    units: units,
  );
}

class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key, required this.sessionId});
  final String sessionId;
  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  SummaryData? _data;
  bool _loading = true;
  int _step = 0;
  Feel _feel = Feel.justRight;
  int? _rpe;
  final _pain = <String>{};
  bool _late = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(loadSummaryData(ref, widget.sessionId).then((d) {
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      if (d != null && d.prs.any((p) => !p.baseline)) buzz(Haptics.pr);
    }).catchError((Object e) {
      if (mounted) setState(() => _loading = false);
    }));
  }

  int get _derivedRpe => _rpe ?? switch (_feel) { Feel.tooEasy => 5, Feel.justRight => 7, Feel.tooHard => 9 };

  Future<void> _save() async {
    setState(() => _saving = true);
    final svc = ref.read(sessionServiceProvider);
    final a = await svc.saveFeedback(
      widget.sessionId,
      SessionFeedback(rpe: _derivedRpe, feel: _feel, pain: _pain.toList(), ranOutOfTime: _late),
    );
    if (!mounted) return;
    buzz(Haptics.approve);
    showRfToast(context, a.reasons.isNotEmpty ? a.reasons.first : 'Thanks! Your next session stays on track.', icon: CupertinoIcons.checkmark_alt);
    context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final d = _data;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : d == null
                ? Center(
                    child: EmptyState(
                      icon: CupertinoIcons.exclamationmark_circle,
                      title: 'Summary unavailable',
                      body: 'Your sets are saved.',
                      action: RfButton(label: 'Back to Today', onPressed: () => context.go('/today')),
                    ),
                  )
                : _step == 0
                    ? _summary(context, d)
                    : _feedback(context, d),
        bottomNavigationBar: d == null
            ? null
            : DoneBar(
                child: _step == 0
                    ? RfButton(label: 'Quick check-in', icon: CupertinoIcons.chevron_right, expand: true, height: Rf.doneBar, onPressed: () => setState(() => _step = 1))
                    : Row(children: [
                        RfButton(label: 'Skip', kind: RfButtonKind.ghost, height: Rf.doneBar, onPressed: () => context.go('/today')),
                        const SizedBox(width: 8),
                        Expanded(child: RfButton(label: 'Save & done', expand: true, busy: _saving, height: Rf.doneBar, onPressed: _save)),
                      ]),
              ),
      ),
    );
  }

  Widget _summary(BuildContext context, SummaryData d) {
    final c = context.rf;
    final s = d.summary;
    final started = parseIsoLocal(s.session.startedAt);
    final vol = d.units == 'kg' ? s.volume : kgToLb(s.volume);
    return ListView(
      padding: EdgeInsets.fromLTRB(Rf.gutter, MediaQuery.paddingOf(context).top + 24, Rf.gutter, 24),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.done.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(CupertinoIcons.checkmark_alt, size: 34, color: c.done),
          ),
        ),
        const SizedBox(height: 12),
        Text('WORKOUT #${d.ordinal}', textAlign: TextAlign.center, style: RfType.overline.copyWith(color: c.accentInk)),
        const SizedBox(height: 4),
        Semantics(header: true, child: Text(s.session.title, textAlign: TextAlign.center, style: RfType.title.copyWith(color: c.text))),
        Text(DateFormat('EEEE d MMMM').format(started), textAlign: TextAlign.center, style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 18),
        RfCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CoachDot(),
              const SizedBox(width: 8),
              Expanded(child: Text('Your recap', style: RfType.captionStrong.copyWith(color: c.coach))),
            ]),
            const SizedBox(height: 8),
            for (final line in d.narration)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(line, style: RfType.body.copyWith(color: c.text))),
            Text(d.closing, style: RfType.bodyStrong.copyWith(color: c.text)),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Stat(icon: CupertinoIcons.timer, label: 'Duration', value: formatDuration(s.durationSec))),
          const SizedBox(width: 8),
          Expanded(child: _Stat(icon: CupertinoIcons.square_stack_3d_up, label: 'Sets', value: '${s.count}')),
          const SizedBox(width: 8),
          Expanded(child: _Stat(icon: Icons.fitness_center, label: 'Volume', value: '${thousands(vol.round())} ${d.units}')),
        ]),
        if (d.prs.isNotEmpty) ...[
          const SizedBox(height: 12),
          RfCard(
            border: c.pr.withValues(alpha: 0.6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.emoji_events, color: c.pr),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${d.prs.length} personal record${d.prs.length == 1 ? '' : 's'}',
                    style: RfType.bodyStrong.copyWith(color: c.pr),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              for (final p in d.prs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${p.name} · ${p.what}', style: RfType.callout.copyWith(color: c.text)),
                ),
              if (d.prs.any((p) => p.baseline))
                Text('First lifts set your baseline. Beat them next time.', style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
        ],
        if (d.preview.isNotEmpty) ...[
          const SectionTitle('Next time', padding: EdgeInsets.fromLTRB(0, 22, 0, 10)),
          RfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in d.preview) ...[
                Text(p.name, style: RfType.bodyStrong.copyWith(color: c.text)),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerLeft, child: ReasonChip(p.message)),
                if (p != d.preview.last) Divider(height: 20, color: c.line),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  Widget _feedback(BuildContext context, SummaryData d) {
    final c = context.rf;
    const feels = [
      (Feel.tooEasy, 'Too easy', CupertinoIcons.smiley),
      (Feel.justRight, 'Just right', CupertinoIcons.hand_thumbsup),
      (Feel.tooHard, 'Too hard', CupertinoIcons.flame),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(Rf.gutter, MediaQuery.paddingOf(context).top + 16, Rf.gutter, 24),
      children: [
        Semantics(header: true, child: Text('How did it feel?', style: RfType.title.copyWith(color: c.text))),
        const SizedBox(height: 4),
        Text('This tunes your next session: weights, sets and Express mode.', style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 14),
        Row(children: [
          for (final f in feels) ...[
            Expanded(
              child: Semantics(
                button: true,
                selected: _feel == f.$1,
                label: f.$2,
                excludeSemantics: true,
                child: Pressable(
                  onTap: () {
                    buzz(Haptics.tick);
                    setState(() => _feel = f.$1);
                  },
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: context.reduceMotion ? 0 : 160),
                    constraints: const BoxConstraints(minHeight: 84),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: _feel == f.$1 ? c.accent.withValues(alpha: 0.16) : c.surface,
                      borderRadius: BorderRadius.circular(Rf.btnRadius),
                      border: Border.all(color: _feel == f.$1 ? c.accent : c.line, width: _feel == f.$1 ? 1.4 : 0.8),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(f.$3, color: c.text),
                      const SizedBox(height: 6),
                      Text(f.$2, textAlign: TextAlign.center, style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
            if (f != feels.last) const SizedBox(width: 8),
          ],
        ]),
        const SectionTitle('Effort, 1–10 (optional)', padding: EdgeInsets.fromLTRB(0, 22, 0, 8)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var r = 5; r <= 10; r++) RfChip(label: '$r', selected: _rpe == r, onTap: () => setState(() => _rpe = _rpe == r ? null : r)),
        ]),
        const SizedBox(height: 6),
        Text('10 means nothing left in the tank.', style: RfType.caption.copyWith(color: c.muted)),
        const SectionTitle('Something hurt? (joints, not muscle burn)', padding: EdgeInsets.fromLTRB(0, 22, 0, 8)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in d.summary.exercises)
            RfChip(
              label: d.names[id] ?? id,
              selected: _pain.contains(id),
              icon: _pain.contains(id) ? CupertinoIcons.bandage : null,
              tone: c.caution,
              onTap: () => setState(() => _pain.contains(id) ? _pain.remove(id) : _pain.add(id)),
            ),
        ]),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: RfChip(label: 'Ran out of time', icon: CupertinoIcons.timer, selected: _late, onTap: () => setState(() => _late = !_late)),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: RfCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(children: [
          Icon(icon, size: 18, color: c.accentInk),
          const SizedBox(height: 4),
          FittedBox(child: Text(value, style: RfType.headline.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]))),
          Text(label, style: RfType.caption.copyWith(color: c.muted)),
        ]),
      ),
    );
  }
}
