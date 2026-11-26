// The gym-floor logger (UX spec "Gym-floor workout logger"): full-screen Focus view, one exercise
// per page with horizontal swipe and a List overview, a 64pt Done bar in the thumb zone, the rest
// band, swap, calibration and resume. Every tap is persisted through SessionService first; the
// rest timer is the stored end timestamp. Gym mode (dark) and the wake lock are on while open.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/ui_state.dart' show GymMode, gymModeProvider;
import '../../data/services/common.dart' show equipmentOf, parseIsoLocal;
import '../../data/services/session_service.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart' show SuggestionKind;
import '../../domain/session_flow.dart' show nextStep;
import '../../domain/units.dart';
import '../../state/providers.dart';
import '../../ui/demo_player.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'rest_alerts.dart';
import 'rest_band.dart';
import 'set_widgets.dart';
import 'summary_screen.dart';
import 'swap_sheet.dart';
import 'workout_math.dart';

/// The set just logged, for the effort question asked during rest.
class _LastLogged {
  _LastLogged({required this.setId, required this.exIdx, required this.setIndex, required this.calibrating, required this.weightKg, required this.incrementKg});
  final String setId;
  final int exIdx;
  final int setIndex;
  final bool calibrating;
  final double? weightKg;
  final double incrementKg;
  Effort? effort;
  String? note;
}

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});
  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  late final GymMode _gym;
  late final ScreenAwake _awake;
  late final List<RestTimerSurface> _surfaces;
  ProviderSubscription<AsyncValue<PlayerState?>>? _sub;

  PageController? _pages;
  int? _page;
  int? _seenIdx;
  bool _animating = false;
  bool _list = false;
  bool _busy = false;
  bool? _demoOpen;
  bool _alertsGranted = true; // until checked: don't flash the offer
  bool _alertsDeclined = false;
  String? _syncedRestEnd;
  String? _finishedSessionId;
  _LastLogged? _last;

  final _drafts = <String, SetValues>{};
  final _sugs = <String, ActiveSuggestion>{};
  final _sugLoading = <String>{};

  SessionService get _svc => ref.read(sessionServiceProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    _gym = ref.read(gymModeProvider.notifier);
    _awake = ref.read(screenAwakeProvider);
    _surfaces = ref.read(restSurfacesProvider);
    Future.microtask(() {
      try {
        _gym.set(true);
      } catch (_) {}
    });
    unawaited(_awake.set(true));
    unawaited(ref.read(restAlertPermissionProvider).granted().then((g) {
      if (mounted) setState(() => _alertsGranted = g);
    }).catchError((Object _) {}));
    _sub = ref.listenManual<AsyncValue<PlayerState?>>(playerStateProvider, (_, next) => _onState(next.value), fireImmediately: true);
  }

  @override
  void dispose() {
    _sub?.close();
    _pages?.dispose();
    final gym = _gym;
    Future.microtask(() {
      try {
        gym.set(false);
      } catch (_) {}
    });
    unawaited(_awake.set(false));
    super.dispose();
  }

  /* ------------------------------------------------------------ state sync */

  void _onState(PlayerState? st) {
    if (st == null) {
      if (_syncedRestEnd != null) {
        _syncedRestEnd = null;
        unawaited(_surfaces.clearAll());
      }
      return;
    }
    _syncRest(st);
    // Follow the stored position only when it moves (logging advanced the flow, resume), so a
    // re-query caused by an unrelated write never yanks the lifter off the page they swiped to.
    final target = st.idx;
    if (_pages == null) {
      _page = target;
      _pages = PageController(initialPage: target);
    } else if (target != _seenIdx && _page != target && !_animating) {
      _goToPage(target);
    }
    _seenIdx = target;
    _loadSuggestions(st);
  }

  void _syncRest(PlayerState st, {bool force = false}) {
    final end = st.active.restEndsAt;
    if (end == _syncedRestEnd && !force) return;
    _syncedRestEnd = end;
    final at = st.restEndsAt;
    if (at == null || !at.isAfter(_now())) {
      unawaited(_surfaces.clearAll());
      return;
    }
    final se = st.current;
    if (se == null) return;
    final exMap = ref.read(exerciseMapProvider).value ?? const {};
    final n = st.nextSetIdx ?? 0;
    unawaited(_surfaces.showAll(RestTimerInfo(
      endsAt: at,
      totalSec: st.active.restTotalSec ?? 60,
      exerciseName: exMap[se.exerciseId]?.name ?? 'Next exercise',
      nextLabel: 'Set ${n + 1} · ${setText(_draft(st, st.idx, n), se.unit, _units, bodyweight: exMap[se.exerciseId]?.isBodyweight == true)}',
      sessionStartedAt: parseIsoLocal(st.session.startedAt),
    )));
  }

  void _goToPage(int i) {
    final ctrl = _pages;
    if (ctrl == null || !ctrl.hasClients) {
      _page = i;
      return;
    }
    setState(() => _page = i);
    if (context.reduceMotion) {
      ctrl.jumpToPage(i);
      return;
    }
    _animating = true;
    ctrl.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic).whenComplete(() => _animating = false);
  }

  /// The lifter swiped or tapped an exercise: show it and persist it for resume.
  void _select(int i) {
    if (_list) {
      _showFocus(i);
    } else {
      _goToPage(i);
    }
    unawaited(_svc.goToExercise(i));
  }

  /// Back from the List overview: the PageView is rebuilt, so start it on [i].
  void _showFocus(int i) {
    _pages?.dispose();
    _pages = PageController(initialPage: i);
    setState(() {
      _page = i;
      _list = false;
    });
  }

  String _sugKey(PlayerState st, int i) => '${st.session.id}:$i:${st.plan[i].exerciseId}:${st.totalSets(i)}';

  void _loadSuggestions(PlayerState st) {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final exMap = ref.read(exerciseMapProvider).value ?? const {};
    for (var i = 0; i < st.plan.length; i++) {
      final key = _sugKey(st, i);
      if (_sugs.containsKey(key) || !_sugLoading.add(key)) continue;
      _svc.suggestionForActive(st.active, i, profile, exercise: exMap[st.plan[i].exerciseId]).then((s) {
        if (mounted) setState(() => _sugs[key] = s);
      }).catchError((Object e) {
        _sugLoading.remove(key);
      });
    }
  }

  /* ------------------------------------------------------------ values */

  String get _units => ref.read(profileProvider).value?.units ?? 'kg';
  StepKg get _stepKg => ref.read(profileProvider).value?.stepKg ?? const StepKg();

  String _draftKey(SessionExercise se, int s) => '${se.plannedExerciseId}:${se.exerciseId}:$s';

  SetValues _draft(PlayerState st, int i, int s) {
    final se = st.plan[i];
    return _drafts[_draftKey(se, s)] ?? draftFor(se, _sugs[_sugKey(st, i)]?.suggestion, st.setsFor(i), s);
  }

  bool _calibrating(PlayerState st, int i) => _sugs[_sugKey(st, i)]?.suggestion.kind == SuggestionKind.first;

  /* ------------------------------------------------------------ actions */

  Future<void> _doneSet(PlayerState st, int i) async {
    final s = nextSetIndexOf(st.active, st.sets, i);
    if (_busy || s == null) return;
    _busy = true;
    final se = st.plan[i];
    final ex = ref.read(exerciseMapProvider).value?[se.exerciseId];
    final values = _draft(st, i, s);
    try {
      final res = await _svc.logAndAdvance(i, s, values, exercise: ex);
      buzz(Haptics.setDone);
      if (!mounted) return;
      setState(() {
        _last = se.unit == Unit.reps && res.restEndsAt != null
            ? _LastLogged(
                setId: res.row.id,
                exIdx: i,
                setIndex: s,
                calibrating: _calibrating(st, i),
                weightKg: res.row.weightKg,
                incrementKg: incrementKg(ex, _stepKg),
              )
            : null;
      });
      if (res.showPr) {
        buzz(Haptics.pr);
        _prToast(ex?.name ?? 'this lift', res.prs.map((p) => p.wire).toList());
      } else if (res.allDone) {
        showRfToast(context, "All sets done. Finish when you're ready.", icon: CupertinoIcons.checkmark_alt);
      }
    } on ArgumentError catch (e) {
      if (mounted) showRfToast(context, '${e.message}');
    } finally {
      _busy = false;
    }
  }

  void _prToast(String name, List<String> types) {
    final c = context.rf;
    final what = types.contains('weight') ? 'heaviest yet' : (types.contains('e1rm') ? 'best estimated max' : 'most reps');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rf.btnRadius), side: BorderSide(color: c.pr, width: 1.2)),
        content: Semantics(
          liveRegion: true,
          child: Row(children: [
            Icon(Icons.emoji_events, color: c.pr),
            const SizedBox(width: 10),
            Expanded(child: Text('New PR: $name · $what', style: RfType.bodyStrong.copyWith(color: c.text))),
          ]),
        ),
      ));
  }

  Future<void> _onEffort(PlayerState st, Effort e) async {
    final l = _last;
    if (l == null) return;
    await _svc.updateSet(l.setId, {'rir': e.rir});
    String? note;
    if (l.calibrating) {
      final se = st.plan[l.exIdx];
      final nextIdx = l.setIndex + 1;
      final w = calibratedWeight(e, l.weightKg, l.incrementKg);
      if (w != null && nextIdx < st.totalSets(l.exIdx)) {
        _drafts[_draftKey(se, nextIdx)] = _draft(st, l.exIdx, nextIdx).merge(SetValues(weightKg: w));
        final inc = '${displayWeight(l.incrementKg, _units)} $_units';
        note = e == Effort.easy ? 'Easy → +$inc next set' : 'Max → −$inc next set';
      } else if (nextIdx < st.totalSets(l.exIdx)) {
        note = '${e.label} → same weight next set';
      }
    }
    if (mounted) {
      setState(() {
        l.effort = e;
        l.note = note;
      });
    }
  }

  Future<void> _enableAlerts(PlayerState st) async {
    final ok = await ref.read(restAlertPermissionProvider).request();
    if (!mounted) return;
    setState(() {
      _alertsGranted = ok;
      _alertsDeclined = !ok;
    });
    if (ok) {
      _syncRest(st, force: true);
      showRfToast(context, "Rest alerts on. I'll ping you when rest ends.", icon: CupertinoIcons.bell);
    } else {
      showRfToast(context, 'Notifications are off. You can turn them on in Settings.');
    }
  }

  Future<void> _swap(PlayerState st, int i, {SwapReason? reason}) async {
    final se = st.plan[i];
    final lib = ref.read(exerciseMapProvider).value ?? const {};
    final original = lib[se.originalExerciseId] ?? lib[se.exerciseId];
    final profile = ref.read(profileProvider).value;
    if (original == null) return;
    String? planSwapId;
    for (final p in ref.read(programBundleProvider).value?.planned ?? const <PlannedExercise>[]) {
      if (p.id == se.plannedExerciseId) planSwapId = p.swapExerciseId;
    }
    final choice = await showSwapSheet(
      context,
      original: original,
      currentId: se.exerciseId,
      library: lib,
      equipment: profile == null ? equipmentOf(_fallbackProfile) : equipmentOf(profile),
      planSwapId: planSwapId,
      exclude: {for (final p in st.plan) if (p.plannedExerciseId != se.plannedExerciseId) p.exerciseId},
      initialReason: reason,
    );
    if (choice == null || !mounted) return;
    final prev = se.exerciseId;
    await _svc.swapExercise(i, choice.exerciseId, always: choice.always);
    if (!mounted) return;
    final name = lib[choice.exerciseId]?.name ?? 'the new exercise';
    showRfToast(
      context,
      choice.always ? '$name is now in your plan' : 'Swapped to $name for today',
      icon: CupertinoIcons.arrow_2_squarepath,
      onUndo: () => unawaited(_svc.swapExercise(i, prev, always: choice.always)),
    );
  }

  Future<void> _editSet(PlayerState st, int i, SetLog set) async {
    final se = st.plan[i];
    final ex = ref.read(exerciseMapProvider).value?[se.exerciseId];
    await showEditSetSheet(
      context,
      set: set,
      unit: se.unit,
      units: _units,
      bodyweight: ex?.isBodyweight == true,
      weightStep: weightStep(ex, _stepKg, _units),
      onSave: (v) => _svc.updateSet(set.id, {'weightKg': v.weightKg, 'reps': v.reps, 'seconds': v.seconds, 'meters': v.meters}),
      onDelete: () async {
        final undo = await _svc.deleteSet(set.id);
        if (mounted) showRfToast(context, 'Set ${set.setIndex + 1} deleted', onUndo: () => unawaited(undo()));
      },
    );
  }

  Future<void> _finish(PlayerState st) async {
    final remaining = st.flow.where((s) => !st.doneKeys.contains('${s.ex}:${s.set}')).length;
    if (st.sets.isEmpty) {
      final discard = await _confirm(
        title: 'Nothing logged yet',
        body: 'There are no sets to save. Keep going, or discard this workout?',
        keep: 'Keep going',
        action: 'Discard workout',
        destructive: true,
      );
      if (discard == true) await _discard(st);
      return;
    }
    if (remaining > 0) {
      final ok = await _confirm(
        title: 'Finish now?',
        body: '$remaining ${remaining == 1 ? 'set is' : 'sets are'} not logged. Everything you logged is saved.',
        keep: 'Keep going',
        action: 'Finish',
      );
      if (ok != true) return;
    }
    await _surfaces.clearAll();
    await _svc.finishSession(st.session.id);
    if (!mounted) return;
    setState(() => _finishedSessionId = st.session.id);
    buzz(Haptics.approve);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SummaryScreen(sessionId: st.session.id)));
  }

  Future<void> _discard(PlayerState st) async {
    await _surfaces.clearAll();
    await _svc.discardSession(st.session.id);
    if (mounted) context.go('/today');
  }

  Future<bool?> _confirm({required String title, required String body, required String keep, required String action, bool destructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.rf;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(title, style: RfType.headline.copyWith(color: c.text)),
          content: Text(body, style: RfType.body.copyWith(color: c.muted)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(keep, style: RfType.bodyStrong.copyWith(color: c.text))),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(action, style: RfType.bodyStrong.copyWith(color: destructive ? c.destructive : c.accentInk)),
            ),
          ],
        );
      },
    );
  }

  void _minimise() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/today');
    }
  }

  Future<void> _menu(PlayerState st, int i) async {
    final c = context.rf;
    final se = st.plan[i];
    await showRfSheet<void>(context, builder: (ctx) {
      Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) => Pressable(
            semanticLabel: label,
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: Rf.gymTap),
              padding: const EdgeInsets.symmetric(horizontal: Rf.gutter),
              child: Row(children: [
                Icon(icon, color: color ?? c.text),
                const SizedBox(width: 14),
                Expanded(child: Text(label, style: RfType.body.copyWith(color: color ?? c.text))),
              ]),
            ),
          );
      return SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          item(CupertinoIcons.plus_circle, 'Add a set', () => unawaited(_svc.addExtraSet(se.plannedExerciseId))),
          item(CupertinoIcons.arrow_2_squarepath, 'Swap exercise', () => unawaited(_swap(st, i))),
          if (i < st.plan.length - 1) item(CupertinoIcons.forward, 'Go to next exercise', () => _select(i + 1)),
          if (!_alertsGranted) item(CupertinoIcons.bell, 'Alert me when rest ends', () => unawaited(_enableAlerts(st))),
          item(CupertinoIcons.trash, 'Discard workout', () async {
            final ok = await _confirm(
              title: 'Discard this workout?',
              body: 'Logged sets from this session will be deleted.',
              keep: 'Keep',
              action: 'Discard',
              destructive: true,
            );
            if (ok == true) await _discard(st);
          }, color: c.destructive),
          const SizedBox(height: 8),
        ]),
      );
    });
  }

  /* ------------------------------------------------------------ build */

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final async = ref.watch(playerStateProvider);
    ref.watch(profileProvider);
    ref.watch(programBundleProvider); // plan swap ids for the swap sheet
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    final st = async.value;

    if (st == null) {
      if (_finishedSessionId != null || async.isLoading) {
        return Scaffold(body: Center(child: async.isLoading ? CircularProgressIndicator(color: c.accent) : const SizedBox()));
      }
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: CupertinoIcons.sportscourt,
            title: 'No workout running',
            body: 'Start one from Today when you are ready.',
            action: RfButton(label: 'Back to Today', onPressed: () => context.go('/today')),
          ),
        ),
      );
    }
    if (st.plan.isEmpty) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: CupertinoIcons.list_bullet,
            title: 'This session has no exercises',
            action: RfButton(label: 'Close', onPressed: () => _discard(st)),
          ),
        ),
      );
    }
    _loadSuggestions(st);
    final page = (_page ?? st.idx).clamp(0, st.plan.length - 1);
    final now = _now();
    final restAt = st.restEndsAt;
    final resting = restAt != null && restAt.isAfter(now.subtract(const Duration(seconds: 1)));
    final reduce = context.reduceMotion;

    return Scaffold(
      body: Column(children: [
        _TopBar(
          startedAt: parseIsoLocal(st.session.startedAt),
          now: _now,
          count: st.plan.length,
          index: page,
          doneFlags: [for (var i = 0; i < st.plan.length; i++) st.setsFor(i).length >= st.totalSets(i)],
          express: st.session.mode == SessionMode.express,
          listOpen: _list,
          onToggleList: () => _list ? _showFocus(page) : setState(() => _list = true),
          onFinish: () => _finish(st),
          onMinimise: _minimise,
        ),
        Expanded(
          child: _list
              ? _overview(st, exMap, page)
              : PageView.builder(
                  controller: _pages,
                  itemCount: st.plan.length,
                  onPageChanged: (i) {
                    if (_animating) return;
                    setState(() => _page = i);
                    unawaited(_svc.goToExercise(i));
                  },
                  itemBuilder: (ctx, i) => _focusPage(ctx, st, i, exMap),
                ),
        ),
      ]),
      // In the bottom bar slot so toasts float above the rest band and the Done bar.
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedSwitcher(
          duration: Duration(milliseconds: reduce ? 0 : 260),
          transitionBuilder: (child, anim) => reduce
              ? FadeTransition(opacity: anim, child: child)
              : SizeTransition(sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic), alignment: Alignment.topCenter, child: FadeTransition(opacity: anim, child: child)),
          child: resting ? _restBand(st, exMap, page) : const SizedBox(key: ValueKey('no-rest'), width: double.infinity),
        ),
        DoneBar(child: _doneButton(st, page, resting)),
      ]),
    );
  }

  Widget _doneButton(PlayerState st, int page, bool resting) {
    if (resting) {
      return RfButton(
        key: const ValueKey('skip-rest'),
        label: 'Skip rest',
        icon: CupertinoIcons.forward_end,
        expand: true,
        height: Rf.doneBar,
        onPressed: () {
          buzz(Haptics.tick);
          unawaited(_svc.skipRest());
        },
      );
    }
    final next = nextSetIndexOf(st.active, st.sets, page);
    if (next != null) {
      return RfButton(
        key: const ValueKey('done-set'),
        label: 'Done set',
        icon: CupertinoIcons.checkmark_alt,
        expand: true,
        height: Rf.doneBar,
        onPressed: () => _doneSet(st, page),
      );
    }
    if (!st.allDone) {
      final n = nextStep(st.flow, st.doneKeys, from: (ex: page, set: st.totalSets(page) - 1));
      return RfButton(
        key: const ValueKey('next-exercise'),
        label: 'Next exercise',
        icon: CupertinoIcons.chevron_right,
        expand: true,
        height: Rf.doneBar,
        onPressed: n == null ? null : () => _select(n.ex),
      );
    }
    return RfButton(
      key: const ValueKey('finish'),
      label: 'Finish workout',
      icon: CupertinoIcons.flag_fill,
      expand: true,
      height: Rf.doneBar,
      onPressed: () => _finish(st),
    );
  }

  Widget _restBand(PlayerState st, Map<String, Exercise> exMap, int page) {
    final se = st.current!;
    final ex = exMap[se.exerciseId];
    final n = st.nextSetIdx;
    String? next;
    if (n != null) {
      final v = shortSetText(_draft(st, st.idx, n), se.unit, _units, bodyweight: ex?.isBodyweight == true);
      next = st.idx == page ? v : '${se.slot.isEmpty ? '' : '${se.slot} '}${ex?.name ?? ''} · $v';
    }
    final l = _last;
    return RestBand(
      key: const ValueKey('rest'),
      endsAt: st.restEndsAt!,
      totalSec: st.active.restTotalSec ?? 60,
      now: _now,
      nextLabel: next,
      onAdjust: (d) => unawaited(_svc.adjustRest(d)),
      onRestOver: () => unawaited(_svc.skipRest()),
      effort: l?.effort,
      onEffort: l == null ? null : (e) => unawaited(_onEffort(st, e)),
      effortNote: l?.note,
      offerAlerts: !_alertsGranted && !_alertsDeclined,
      onEnableAlerts: () => unawaited(_enableAlerts(st)),
    );
  }

  /* ------------------------------------------------------------ focus page */

  Widget _focusPage(BuildContext context, PlayerState st, int i, Map<String, Exercise> exMap) {
    final c = context.rf;
    final se = st.plan[i];
    final ex = exMap[se.exerciseId];
    final sug = _sugs[_sugKey(st, i)];
    final calibrating = sug?.suggestion.kind == SuggestionKind.first;
    final total = st.totalSets(i);
    final logged = st.setsFor(i);
    final next = nextSetIndexOf(st.active, st.sets, i);
    final units = _units;
    final bodyweight = ex?.isBodyweight == true;
    final pain = st.active.pain ?? const <String>[];
    final painful = pain.contains(se.exerciseId) || pain.contains(se.originalExerciseId);
    final kind = sug?.suggestion.kind;
    final changed = kind == SuggestionKind.increase ||
        kind == SuggestionKind.decrease ||
        kind == SuggestionKind.timeIncrease ||
        kind == SuggestionKind.timeCap ||
        (kind == SuggestionKind.hold && (st.active.hold == true || painful));
    final partnerIdx = se.supersetGroup == null || se.supersetGroup!.isEmpty
        ? null
        : [for (var k = 0; k < st.plan.length; k++) if (k != i && st.plan[k].supersetGroup == se.supersetGroup) k].firstOrNull;
    final lastParts = sug?.last?.split(', ');
    final lastTime = lastParts == null || next == null ? null : (next < lastParts.length ? lastParts[next] : lastParts.last);
    // Open for a first-time lift until its first set is logged; the lifter's toggle wins after that.
    final demoOpen = _demoOpen ?? (calibrating && logged.isEmpty);
    final cues = formCues(se, ex);

    return ListView(
      key: PageStorageKey('ex-$i'),
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, 24),
      children: [
        // Demo header (collapsible; swipe up or tap to hide).
        AnimatedSize(
          duration: Duration(milliseconds: context.reduceMotion ? 0 : 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: demoOpen
              ? GestureDetector(
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -200) setState(() => _demoOpen = false);
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Stack(children: [
                      DemoPlayer(exercise: ex, height: 180),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: RfChip(
                          label: 'Busy / not in my gym',
                          icon: CupertinoIcons.arrow_2_squarepath,
                          onTap: () => _swap(st, i, reason: SwapReason.busy),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Semantics(
                          button: true,
                          label: 'Hide demo',
                          excludeSemantics: true,
                          child: Pressable(
                            onTap: () => setState(() => _demoOpen = false),
                            child: Container(
                              width: Rf.tap,
                              height: Rf.tap,
                              alignment: Alignment.center,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                                child: const Icon(CupertinoIcons.chevron_up, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                    if (cues.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final cue in cues)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(padding: const EdgeInsets.only(top: 3), child: Icon(CupertinoIcons.checkmark_seal, size: 16, color: c.muted)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(cue, maxLines: 2, overflow: TextOverflow.ellipsis, style: RfType.callout.copyWith(color: c.text))),
                          ]),
                        ),
                    ],
                  ]),
                )
              : RfCard(
                  padding: const EdgeInsets.all(8),
                  semanticLabel: 'Show demo and form cues',
                  onTap: () => setState(() => _demoOpen = true),
                  child: Row(children: [
                    ExerciseThumb(exercise: ex, size: 44),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Demo & form cues', style: RfType.callout.copyWith(color: c.text))),
                    Icon(CupertinoIcons.chevron_down, size: 18, color: c.muted),
                  ]),
                ),
        ),
        const SizedBox(height: 14),
        // Exercise header.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (se.slot.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(6)),
                    child: Text(se.slot, style: RfType.captionStrong.copyWith(color: c.text)),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    se.exerciseId != se.originalExerciseId ? 'Swapped today' : (se.isMain ? 'Main lift' : 'Accessory'),
                    style: RfType.captionStrong.copyWith(color: c.muted),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Semantics(header: true, child: Text(ex?.name ?? se.exerciseId, style: RfType.title.copyWith(fontSize: 24, color: c.text))),
              const SizedBox(height: 2),
              Text(
                targetLine(se, total),
                style: RfType.bodyStrong.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Swap ${ex?.name ?? 'exercise'}',
            excludeSemantics: true,
            child: Pressable(
              onTap: () => _swap(st, i),
              child: Container(
                height: Rf.tap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(CupertinoIcons.arrow_2_squarepath, size: 18, color: c.text),
                  const SizedBox(width: 6),
                  Text('Swap', style: RfType.bodyStrong.copyWith(color: c.text)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'More options',
            excludeSemantics: true,
            child: Pressable(
              onTap: () => _menu(st, i),
              child: Container(
                width: Rf.tap,
                height: Rf.tap,
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
                child: Icon(CupertinoIcons.ellipsis, color: c.text),
              ),
            ),
          ),
        ]),
        if (sug != null && changed) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: ReasonChip(sug.suggestion.message)),
        ] else if (sug != null && kind == SuggestionKind.hold) ...[
          const SizedBox(height: 6),
          Text(sug.suggestion.message, style: RfType.callout.copyWith(color: c.muted)),
        ],
        if (partnerIdx != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(CupertinoIcons.arrow_right_arrow_left, size: 16, color: c.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Superset ${se.supersetGroup}: alternate with ${st.plan[partnerIdx].slot} ${exMap[st.plan[partnerIdx].exerciseId]?.name ?? ''}',
                style: RfType.callout.copyWith(color: c.muted),
              ),
            ),
          ]),
        ],
        if (se.note != null && se.note!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(se.note!, style: RfType.callout.copyWith(color: c.muted)),
        ],
        if (painful) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(CupertinoIcons.bandage, size: 18, color: c.caution),
            const SizedBox(width: 6),
            Expanded(child: Text('You said this hurt last time. Keep it light or swap it.', style: RfType.callout.copyWith(color: c.caution))),
          ]),
        ],
        const SizedBox(height: 14),
        if (next != null)
          CurrentSetCard(
            se: se,
            exercise: ex,
            setIndex: next,
            totalSets: total,
            values: _draft(st, i, next),
            edited: _drafts.containsKey(_draftKey(se, next)),
            onChanged: (v) => setState(() => _drafts[_draftKey(se, next)] = v),
            units: units,
            weightStep: weightStep(ex, _stepKg, units),
            lastTime: lastTime,
            calibrating: calibrating && !bodyweight,
          )
        else
          RfCard(
            child: Row(children: [
              Icon(CupertinoIcons.checkmark_circle_fill, color: c.done),
              const SizedBox(width: 10),
              Expanded(child: Text('All $total sets done', style: RfType.bodyStrong.copyWith(color: c.text))),
            ]),
          ),
        const SectionTitle('Sets', padding: EdgeInsets.fromLTRB(0, 20, 0, 8)),
        for (var s = 0; s < total; s++) ...[
          Builder(builder: (_) {
            SetLog? done;
            for (final l in logged) {
              if (l.setIndex == s) done = l;
            }
            return SetRow(
              index: s,
              unit: se.unit,
              units: units,
              bodyweight: bodyweight,
              done: done,
              draft: done == null ? _draft(st, i, s) : null,
              current: s == next,
              onTap: done == null ? null : () => _editSet(st, i, done!),
            );
          }),
          const SizedBox(height: 8),
        ],
        RfButton(
          label: 'Add a set',
          icon: CupertinoIcons.plus,
          kind: RfButtonKind.ghost,
          expand: true,
          onPressed: () => unawaited(_svc.addExtraSet(se.plannedExerciseId)),
        ),
      ],
    );
  }

  /* ------------------------------------------------------------ list overview */

  Widget _overview(PlayerState st, Map<String, Exercise> exMap, int page) {
    final c = context.rf;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, 24),
      children: [
        for (var i = 0; i < st.plan.length; i++) ...[
          if (st.plan[i].supersetGroup != null &&
              st.plan[i].supersetGroup!.isNotEmpty &&
              (i == 0 || st.plan[i - 1].supersetGroup != st.plan[i].supersetGroup))
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text('SUPERSET ${st.plan[i].supersetGroup}', style: RfType.overline.copyWith(color: c.muted)),
            ),
          Builder(builder: (_) {
            final se = st.plan[i];
            final ex = exMap[se.exerciseId];
            final done = st.setsFor(i).length;
            final total = st.totalSets(i);
            final complete = done >= total;
            final status = complete ? 'done' : (i == page ? 'current' : '$done of $total sets');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RfCard(
                padding: const EdgeInsets.all(10),
                border: i == page ? c.text.withValues(alpha: 0.5) : null,
                semanticLabel: '${se.slot} ${ex?.name ?? ''}, $status',
                onTap: () => _select(i),
                child: Row(children: [
                  ExerciseThumb(exercise: ex, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${se.slot.isEmpty ? '' : '${se.slot} · '}${ex?.name ?? se.exerciseId}', style: RfType.bodyStrong.copyWith(color: c.text)),
                      Text('$done of $total sets · ${repsLabel(se)}', style: RfType.caption.copyWith(color: c.muted)),
                    ]),
                  ),
                  if (complete) Icon(CupertinoIcons.checkmark_circle_fill, color: c.done),
                ]),
              ),
            );
          }),
        ],
      ],
    );
  }
}

/// Used only if the profile hasn't loaded (full-gym equipment).
const _fallbackProfile = Profile(
  name: '',
  sex: Sex.other,
  birthYear: 1990,
  heightCm: 170,
  startWeightKg: 70,
  goalWeightKg: 70,
  dietType: DietType.vegEgg,
  kcalTarget: 0,
  proteinTargetG: 0,
  trainingDays: [],
  sessionTime: '09:00',
  createdAt: '',
);

/* ------------------------------------------------------------------ top bar */

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.startedAt,
    required this.now,
    required this.count,
    required this.index,
    required this.doneFlags,
    required this.express,
    required this.listOpen,
    required this.onToggleList,
    required this.onFinish,
    required this.onMinimise,
  });
  final DateTime startedAt;
  final DateTime Function() now;
  final int count;
  final int index;
  final List<bool> doneFlags;
  final bool express;
  final bool listOpen;
  final VoidCallback onToggleList;
  final VoidCallback onFinish;
  final VoidCallback onMinimise;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top + 2, 6, 4),
      child: Row(children: [
        Semantics(
          button: true,
          label: 'Minimise workout',
          excludeSemantics: true,
          child: Pressable(
            onTap: onMinimise,
            child: SizedBox(width: Rf.tap, height: Rf.tap, child: Icon(CupertinoIcons.chevron_down, color: c.text)),
          ),
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Exercise ${index + 1} of $count. ${listOpen ? 'Show focus view' : 'Show all exercises'}',
            excludeSemantics: true,
            child: Pressable(
              onTap: onToggleList,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _Elapsed(startedAt: startedAt, now: now),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Exercise ${index + 1} of $count', maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.caption.copyWith(color: c.muted)),
                  ),
                  const SizedBox(width: 4),
                  Icon(listOpen ? CupertinoIcons.rectangle : CupertinoIcons.list_bullet, size: 14, color: c.muted),
                  if (express) ...[const SizedBox(width: 6), StatusPill(label: 'Express', color: c.muted, icon: CupertinoIcons.bolt_fill)],
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: Duration(milliseconds: context.reduceMotion ? 0 : 200),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: i == index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == index ? c.accent : (doneFlags[i] ? c.done : c.line),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        RfButton(label: 'Finish', kind: RfButtonKind.ghost, height: Rf.tap, onPressed: onFinish),
      ]),
    );
  }
}

class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.startedAt, required this.now});
  final DateTime startedAt;
  final DateTime Function() now;
  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sec = widget.now().difference(widget.startedAt).inSeconds;
    final text = formatDuration(sec < 0 ? 0 : sec);
    return Semantics(
      label: 'Workout time $text',
      excludeSemantics: true,
      child: NumeralScale(child: Text(text, style: RfType.bodyStrong.copyWith(color: context.rf.text, fontFeatures: const [FontFeature.tabularFigures()]))),
    );
  }
}
