// Coach tab (UX spec, "AI coach edit: preview, approve, undo"): a thread of you, the AI coach
// (violet) and your trainer (teal), where every plan request is answered with a proposal card.
// Nothing changes until you approve, and every approve can be undone.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/shell.dart' show kTabBarHeight;
import '../../data/services/coach_client.dart';
import '../../data/services/common.dart';
import '../../domain/ai_plan.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'coach_composer.dart';
import 'coach_models.dart';
import 'coach_safety.dart';
import 'coach_service.dart';
import 'plan_history_screen.dart';
import 'proposal_card.dart';

/// A short title for a proposal from what the person asked.
String proposalTitle(String text, CoachMode mode, NormPlan plan) {
  if (mode == CoachMode.newPlan) return plan.workout?.name.trim().isNotEmpty == true ? plan.workout!.name : 'Your new plan';
  final t = text.toLowerCase();
  final rules = <(RegExp, String)>[
    (RegExp(r'vrat|fast\b|fasting|navratri|ekadashi|festival|upvas'), 'Vrat day'),
    (RegExp(r'travel|trip|hotel|away next|out of town'), 'Travel week'),
    (RegExp(r'knee'), 'Knee-friendly week'),
    (RegExp(r'pain|hurt|injur|dard|sprain|strain'), 'Easier on what hurts'),
    (RegExp(r'\b\d{2} ?min|short on time|less time|no time|time kam'), 'Short on time'),
    (RegExp(r'legs?.*(sat|saturday)'), 'Legs moved to Saturday'),
    (RegExp(r'\bmove\b|\bshift\b|swap days'), 'Days moved'),
    (RegExp(r'harder|tougher|challenge|more volume|too easy'), 'A harder week'),
    (RegExp(r'easier|too hard|tired|deload'), 'An easier week'),
  ];
  for (final (re, title) in rules) {
    if (re.hasMatch(t)) return title;
  }
  return plan.workout != null ? 'Your plan, adjusted' : 'Diet update';
}

/// Streaming-feel progress while the coach thinks.
List<String> coachSteps({required bool diet, required bool workout}) => [
      'Reading your last 3 weeks…',
      if (workout) 'Checking your equipment…',
      if (workout) 'Balancing your week…',
      if (workout) 'Planning sets, reps and rest…',
      if (diet) 'Writing your meals…',
      'Checking it all adds up…',
    ];

class _Failure {
  const _Failure(this.message, {this.needsCode = false, this.retry = true});
  final String message;
  final bool needsCode;
  final bool retry;
}

_Failure _friendly(Object e) {
  if (e is CoachError) {
    final s = e.status;
    if (s == 401 || s == 403) {
      return const _Failure('The coach needs your invite code. Enter the code from your TestFlight invite and send again — your message is kept.',
          needsCode: true, retry: false);
    }
    if (s == 429) return const _Failure('The coach is getting a lot of requests right now. Wait a minute and try again — your message is kept.');
    if (s != null && s >= 500) return const _Failure('The coach is unavailable right now. Your current plan still works; try again in a bit.');
    return _Failure(e.message);
  }
  if (e is AiPlanException) return _Failure(e.message);
  return const _Failure('Something went wrong talking to the coach. Your plan didn’t change; try again.');
}

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});
  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _code = TextEditingController();
  CoachMode _mode = CoachMode.change;
  bool _workout = true;
  bool _diet = false;

  bool _busy = false;
  int _gen = 0;
  int _step = 0;
  Timer? _timer;
  String? _pendingText;
  List<String> _steps = const [];
  _Failure? _failure;
  bool _limitHit = false;
  bool _prefilled = false;

  /// "Change this" from the Train tab's Why sheet opens /coach?q=… with a ready prompt.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    String? q;
    try {
      q = GoRouterState.of(context).uri.queryParameters['q'];
    } catch (_) {
      q = null; // not under go_router (tests)
    }
    if (q != null && q.isNotEmpty && _input.text.isEmpty) _input.text = q;
  }

  /// Message id of a proposal being approved / undone.
  String? _working;

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _code.dispose();
    super.dispose();
  }

  /* ------------------------------------------------------------ send */

  Future<void> _send() async {
    if (_busy) return;
    final text = _input.text.trim();
    if (text.isEmpty && _mode == CoachMode.change) return;
    final st = ref.read(coachStateProvider).value;
    if (st != null && !st.canAsk) {
      setState(() => _limitHit = true);
      return;
    }
    FocusScope.of(context).unfocus();
    final want = CoachWant(workout: _workout, diet: _diet);
    final gen = ++_gen;
    setState(() {
      _busy = true;
      _failure = null;
      _limitHit = false;
      _pendingText = text.isEmpty ? 'Build me a new plan.' : text;
      _steps = coachSteps(diet: _diet, workout: _workout);
      _step = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (mounted && _step < _steps.length - 1) setState(() => _step++);
    });
    try {
      final svc = ref.read(coachServiceProvider);
      final before = await svc.snapshot();
      final safety = CoachSafety.of(text);
      final notes = [if (text.isNotEmpty) text else 'Build me a new plan.', if (safety.any) safety.promptNote].join('\n');
      final r = await ref.read(coachClientProvider).askCoach(mode: _mode, want: want, notes: notes, code: st?.accessCode);
      if (gen != _gen || !mounted) return;
      final proposal = CoachProposal(
        title: proposalTitle(text, _mode, r.plan),
        request: text,
        mode: _mode,
        want: want,
        before: before,
        after: r.plan,
        model: r.model,
      );
      final user = await svc.message(CoachVoice.user, text: _pendingText!);
      final card = await svc.message(CoachVoice.proposal, proposal: proposal);
      await svc.append([user, card]);
      await svc.recordEdit();
      _input.clear();
      Haptics.approve();
    } catch (e) {
      if (gen == _gen && mounted) setState(() => _failure = _friendly(e));
    } finally {
      if (gen == _gen) {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _busy = false;
            _pendingText = null;
          });
        }
      }
    }
  }

  void _stop() {
    _gen++;
    _timer?.cancel();
    setState(() {
      _busy = false;
      _pendingText = null;
    });
  }

  Future<void> _saveCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    await ref.read(coachServiceProvider).setAccessCode(code);
    _code.clear();
    if (!mounted) return;
    setState(() => _failure = null);
    showRfToast(context, 'Invite code saved. Send your message again.', icon: CupertinoIcons.checkmark_alt);
  }

  /* ------------------------------------------------------------ proposal actions */

  Future<CoachProposal?> _latest(String id) async {
    final list = await ref.read(coachServiceProvider).thread();
    for (final m in list) {
      if (m.id == id) return m.proposal;
    }
    return null;
  }

  Future<void> _approve(String id) async {
    if (_working != null) return;
    setState(() => _working = id);
    try {
      final svc = ref.read(coachServiceProvider);
      final p = await _latest(id);
      if (p == null || p.status != ProposalStatus.pending) return;
      final builder = await ref.read(planBuilderProvider.future);
      final done = await svc.approve(p, builder);
      await svc.updateProposal(id, done);
      Haptics.approve();
      if (mounted) showRfToast(context, 'Plan updated', icon: CupertinoIcons.checkmark_alt, onUndo: () => _undo(id));
    } catch (_) {
      if (mounted) showRfToast(context, 'Couldn’t update your plan. Nothing changed; try again.');
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _undo(String id) async {
    final svc = ref.read(coachServiceProvider);
    final p = await _latest(id);
    if (p == null || p.status != ProposalStatus.approved) return;
    if (mounted) setState(() => _working = id);
    try {
      await svc.updateProposal(id, await svc.undo(p));
      if (mounted) showRfToast(context, 'Previous plan restored', icon: CupertinoIcons.arrow_uturn_left);
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _discard(String id) async {
    final svc = ref.read(coachServiceProvider);
    final p = await _latest(id);
    if (p == null || p.status != ProposalStatus.pending) return;
    Haptics.tick();
    await svc.updateProposal(id, p.copyWith(status: ProposalStatus.discarded, decidedAt: isoString(ref.read(clockProvider)())));
  }

  Future<void> _adjust(String id, NormPlan plan) async {
    final svc = ref.read(coachServiceProvider);
    final p = await _latest(id);
    if (p == null || p.status != ProposalStatus.pending) return;
    await svc.updateProposal(id, p.copyWith(after: plan, adjusted: true));
  }

  /* ------------------------------------------------------------ build */

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final state = ref.watch(coachStateProvider);
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    final goal = ref.watch(profileProvider).value?.goal;
    final bottom = _composerBottom(context);
    final st = state.value;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(children: [
        PageHeader(
          title: 'Coach',
          eyebrow: 'Your AI coach',
          trailing: Semantics(
            button: true,
            label: 'Plan history',
            excludeSemantics: true,
            child: Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlanHistoryScreen())),
              child: SizedBox(width: Rf.tap, height: Rf.tap, child: Icon(CupertinoIcons.clock, color: c.accentInk)),
            ),
          ),
        ),
        _Banner(state: st),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(icon: CupertinoIcons.exclamationmark_circle, title: 'Couldn’t load your coach thread', body: '$e'),
            data: (st) => _thread(context, st, exMap, goal),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: CoachComposer(
            controller: _input,
            mode: _mode,
            workout: _workout,
            diet: _diet,
            busy: _busy,
            onMode: (m) => setState(() => _mode = m),
            onWorkout: (v) => setState(() => _workout = v),
            onDiet: (v) => setState(() => _diet = v),
            onSend: _send,
            onStop: _stop,
          ),
        ),
      ]),
    );
  }

  /// Space under the composer. The shell's Scaffold (extendBody) already reports the tab bar in
  /// padding.bottom, and it resizes its body for the keyboard and strips the inset.
  double _composerBottom(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.viewInsets.bottom > 0) return mq.viewInsets.bottom + 8; // no ancestor resized for the keyboard
    if (View.of(context).viewInsets.bottom > 0) return 8; // keyboard open, body already above it
    final tabBar = mq.padding.bottom >= kTabBarHeight ? mq.padding.bottom : kTabBarHeight + mq.padding.bottom;
    return tabBar + 8;
  }

  Widget _thread(BuildContext context, CoachState st, Map<String, Exercise> exMap, Goal? goal) {
    final items = <Widget>[
      if (st.thread.isEmpty)
        const _Bubble(
          voice: CoachVoice.coach,
          text: 'Tell me what changed: short on time, a sore knee, travel, a vrat day. I’ll show you exactly what I’d change '
              'and why. Nothing changes until you approve, and you can always undo. Hinglish is fine.',
        ),
      for (final m in st.thread)
        if (m.voice == CoachVoice.proposal && m.proposal != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 8),
            child: ProposalCard(
              key: ValueKey('proposal-${m.id}'),
              proposal: m.proposal!,
              exMap: exMap,
              goal: goal,
              busy: _working == m.id,
              onApprove: () => _approve(m.id),
              onDiscard: () => _discard(m.id),
              onAdjusted: (plan) => _adjust(m.id, plan),
              onUndo: st.canUndo(m.proposal!) ? () => _undo(m.id) : null,
            ),
          )
        else
          _Bubble(voice: m.voice, text: m.text, author: m.author, at: m.createdAt),
      if (_pendingText != null) _Bubble(voice: CoachVoice.user, text: _pendingText!),
      if (_busy) _Thinking(steps: _steps, step: _step),
      if (_failure != null) _failureCard(context, _failure!),
      if (_limitHit || (!st.canAsk && !_busy)) _limitCard(context),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: items.reversed.toList(),
    );
  }

  Widget _failureCard(BuildContext context, _Failure f) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 8),
      child: RfCard(
        color: c.caution.withValues(alpha: 0.10),
        border: c.caution.withValues(alpha: 0.4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(f.needsCode ? CupertinoIcons.lock : CupertinoIcons.wifi_exclamationmark, size: 20, color: c.caution),
            const SizedBox(width: 10),
            Expanded(child: Text(f.message, style: RfType.callout.copyWith(color: c.text))),
          ]),
          if (f.needsCode) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('coach-code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              style: RfType.body.copyWith(color: c.text),
              decoration: InputDecoration(
                labelText: 'Invite code',
                hintText: 'RPM-XXXX-XXXX',
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _saveCode(),
            ),
            const SizedBox(height: 10),
            RfButton(label: 'Save code', icon: CupertinoIcons.lock_open, kind: RfButtonKind.secondary, onPressed: _saveCode),
          ],
          if (f.retry) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: RfButton(label: 'Try again', icon: CupertinoIcons.refresh, kind: RfButtonKind.secondary, onPressed: _send)),
          ],
        ]),
      ),
    );
  }

  Widget _limitCard(BuildContext context) {
    final c = context.rf;
    final now = ref.read(clockProvider)();
    final next = DateTime(now.year, now.month + 1, 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 8),
      child: RfCard(
        border: c.coach.withValues(alpha: 0.4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You’ve used your $kFreeEditsPerMonth free edits this month', style: RfType.bodyStrong.copyWith(color: c.text)),
          const SizedBox(height: 4),
          Text('They come back on ${DateFormat('d MMMM').format(next)}. Your plan keeps working as it is. Pro (coming soon) gives unlimited coach edits.',
              style: RfType.callout.copyWith(color: c.muted)),
        ]),
      ),
    );
  }
}

/* ------------------------------------------------------------ header banner */

class _Banner extends StatelessWidget {
  const _Banner({required this.state});
  final CoachState? state;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final st = state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 2, Rf.gutter, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(CupertinoIcons.info_circle, size: 14, color: c.muted),
          const SizedBox(width: 6),
          Expanded(child: Text('Coach can be wrong — review before approving', style: RfType.caption.copyWith(color: c.muted))),
        ]),
        if (st != null) ...[
          const SizedBox(height: 8),
          if (st.pro)
            Align(alignment: Alignment.centerLeft, child: StatusPill(label: 'Pro beta · unlimited edits', color: c.coach, icon: Icons.auto_awesome))
          else
            Semantics(
              label: '${st.freeLeft} of $kFreeEditsPerMonth free edits left this month',
              excludeSemantics: true,
              child: Row(children: [
                Flexible(flex: 3, child: Text('${st.freeLeft} of $kFreeEditsPerMonth free edits left this month', style: RfType.captionStrong.copyWith(color: c.text))),
                const SizedBox(width: 10),
                Expanded(flex: 1, child: LinearMeter(value: st.freeLeft / kFreeEditsPerMonth, color: c.coach, height: 6)),
              ]),
            ),
        ],
      ]),
    );
  }
}

/* ------------------------------------------------------------ bubbles */

class _Bubble extends StatelessWidget {
  const _Bubble({required this.voice, required this.text, this.author, this.at});
  final CoachVoice voice;
  final String text;
  final String? author;
  final String? at;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final mine = voice == CoachVoice.user;
    final tone = voice == CoachVoice.trainer ? c.trainer : c.coach;
    final who = switch (voice) {
      CoachVoice.user => 'You',
      CoachVoice.trainer => author ?? 'Your trainer',
      _ => 'Coach',
    };
    final time = at == null || at!.isEmpty ? null : DateFormat('d MMM, H:mm').format(parseIsoLocal(at!));
    return Semantics(
      label: '$who: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 5),
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              decoration: BoxDecoration(
                color: mine ? c.surface2 : tone.withValues(alpha: 0.10),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
                border: mine ? null : Border.all(color: tone.withValues(alpha: 0.25), width: 0.8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (voice == CoachVoice.trainer)
                        TrainerMark(initials: who.isEmpty ? 'T' : who.substring(0, 1).toUpperCase())
                      else
                        Icon(Icons.auto_awesome, size: 14, color: tone),
                      const SizedBox(width: 6),
                      Flexible(child: Text(who, style: RfType.captionStrong.copyWith(color: tone))),
                    ]),
                  ),
                Text(text, style: RfType.callout.copyWith(color: c.text)),
                if (time != null) ...[
                  const SizedBox(height: 4),
                  Text(time, style: RfType.caption.copyWith(color: c.muted, fontSize: 11)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach "thinking": finished steps get a check, the current one a spinner.
class _Thinking extends StatelessWidget {
  const _Thinking({required this.steps, required this.step});
  final List<String> steps;
  final int step;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      liveRegion: true,
      label: steps.isEmpty ? 'Coach is thinking' : steps[step],
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.coach.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Rf.cardRadius),
            border: Border.all(color: c.coach.withValues(alpha: 0.25), width: 0.8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome, size: 14, color: c.coach),
              const SizedBox(width: 6),
              Flexible(child: Text('Coach is working on it', style: RfType.captionStrong.copyWith(color: c.coach))),
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i <= step && i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: i < step
                        ? Icon(CupertinoIcons.checkmark_alt, size: 16, color: c.done)
                        : context.reduceMotion
                            ? Icon(CupertinoIcons.ellipsis, size: 16, color: c.coach)
                            : CircularProgressIndicator(strokeWidth: 2, color: c.coach),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(steps[i], style: RfType.callout.copyWith(color: i < step ? c.muted : c.text))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
