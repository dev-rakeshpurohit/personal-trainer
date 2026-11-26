// Onboarding: organic (≈18 screens, paywall once), trainer/promo code (shorter, no paywall) and
// "redo setup" (`/onboarding?fresh=1`, history kept). Port of src/features/onboarding/Onboarding.tsx
// reshaped to the UX spec's flow: personalise → value → plan reveal → first edit → paywall.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/services/common.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../today/pending_start.dart';
import 'draft.dart';
import 'plan_logic.dart';
import 'plan_steps.dart';
import 'steps.dart';

enum ObStep { welcome, goal, experience, schedule, gym, body, about, interlude, diet, protein, language, building, reveal, firstEdit, save, notify, paywall, start }

enum ObMode { organic, invited, fresh }

/// Screens per entry branch. Invited users (trainer / promo code) never see the paywall.
List<ObStep> flowFor(ObMode m) => switch (m) {
      ObMode.organic => ObStep.values,
      ObMode.invited => const [
          ObStep.welcome, ObStep.goal, ObStep.experience, ObStep.schedule, ObStep.gym, ObStep.body, ObStep.about, //
          ObStep.diet, ObStep.protein, ObStep.building, ObStep.reveal, ObStep.save, ObStep.notify, ObStep.start,
        ],
      ObMode.fresh => const [
          ObStep.welcome, ObStep.goal, ObStep.experience, ObStep.schedule, ObStep.gym, ObStep.body, ObStep.about, //
          ObStep.diet, ObStep.protein, ObStep.language, ObStep.building, ObStep.reveal, ObStep.firstEdit, ObStep.start,
        ],
    };

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.fresh});

  /// Redo setup (history kept). Null = read `?fresh=1` from the route.
  final bool? fresh;
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OnboardingDraft _d = OnboardingDraft();
  ObMode _mode = ObMode.organic;
  bool _modeRead = false;
  bool _prefilled = false;
  Profile? _existing;
  String? _code;
  int _i = 0;
  BuiltPlan? _built;

  List<ObStep> get _steps => flowFor(_mode);
  ObStep get _step => _steps[_i];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_modeRead) return;
    _modeRead = true;
    var fresh = widget.fresh;
    if (fresh == null) {
      try {
        fresh = GoRouterState.of(context).uri.queryParameters['fresh'] == '1';
      } catch (_) {
        fresh = false;
      }
    }
    if (fresh) _mode = ObMode.fresh;
  }

  void _set(void Function() change) => setState(change);

  void _next() {
    if (_i < _steps.length - 1) setState(() => _i++);
  }

  void _back() {
    if (_i > 0) {
      setState(() => _i--);
    } else if (_mode == ObMode.fresh && context.canPop()) {
      context.pop();
    } else if (_mode == ObMode.fresh) {
      context.go('/today');
    }
  }

  bool get _canContinue => switch (_step) {
        ObStep.goal => _d.goal != null,
        ObStep.schedule => _d.days.isNotEmpty && _d.days.length <= 6,
        ObStep.body => _d.pain != null,
        _ => true,
      };

  Future<void> _enterCode() async {
    final code = await showCodeSheet(context);
    if (code == null || !mounted) return;
    final s = ref.read(storesProvider);
    await s.setMeta(ObMeta.accessCode, code);
    await s.setMeta(ObMeta.proViaCode, code);
    if (!mounted) return;
    setState(() {
      _code = code;
      _mode = ObMode.invited;
    });
  }

  /* ------------------------------------------------------------ commit (the real "building") */

  Future<BuiltPlan> _build(void Function(String) report) async {
    final s = ref.read(storesProvider);
    final now = ref.read(clockProvider)();
    final existing = await s.profile.get(Profile.id);
    _existing = existing;

    // The app router sends anyone with a profile away from /onboarding unless `fresh=1`. The profile
    // is written now (the first edit and Start need it), so keep the rest of this flow on screen.
    // Same page key, so this State (and the draft) survives.
    if (existing == null && mounted) {
      final router = GoRouter.maybeOf(context);
      if (router != null) router.go('/onboarding?fresh=1');
    }

    final builder = await ref.read(planBuilderProvider.future);
    await builder.ensureLibrary();
    report('Matched your answers against ${thousandsOf(await s.exercises.count())} exercises');

    var profile = _d.toProfile(now: now, createdAt: isoString(now), base: existing);
    final gen = builder.previewProgram(profile);
    report(splitLine(_d, gen));
    report(sessionLine(_d));
    report(equipmentLine(_d));
    await builder.saveGeneratedProgram(profile);
    final pain = painLine(_d);
    if (pain != null) report(pain);

    final diet = await builder.saveGeneratedDiet(profile);
    profile = profile.copyWith(kcalTarget: diet.kcalTarget, proteinTargetG: diet.proteinTargetG);
    report(dietLine(_d, diet.kcalTarget, diet.proteinTargetG));

    await s.profile.put(profile);
    await ref.read(repoProvider).upsertBody(dayKey(now), weightKg: _d.weightKg);
    if (existing == null) await s.setMeta(ObMeta.onboardedAt, isoString(now));
    await s.setMeta(ObMeta.setupChangedAt, isoString(now));
    await s.setMeta(ObMeta.painAreas, _d.pain ?? const <String>[]);
    await s.setMeta(ObMeta.coachLanguage, _d.coachLanguage);
    await s.setMeta(ObMeta.whey, _d.whey);
    await s.setMeta(ObMeta.trainWindow, _d.trainWindow);
    if (_d.knowsWeights != null) await s.setMeta(ObMeta.knowsWeights, _d.knowsWeights);

    final bundle = (await loadProgramBundle(s))!;
    final lib = await s.exercises.all();
    final exMap = {for (final e in lib) e.id: e};
    final check = summariseCheck(checkBundle(bundle, exMap, lib, profile));
    report('Plan check: ${check.headline.toLowerCase()}');
    final dietPlan = await s.activeDiet();
    final meals = dietPlan == null ? <PlannedMeal>[] : ((await s.plannedMeals.whereK1(dietPlan.id))..sort((a, b) => a.time.compareTo(b.time)));
    return BuiltPlan(profile: profile, bundle: bundle, diet: dietPlan, meals: meals, check: check, exMap: exMap);
  }

  void _finish({String? startDayId}) {
    if (startDayId != null) ref.read(pendingStartProvider.notifier).set(startDayId);
    final fresh = _mode == ObMode.fresh && _existing != null;
    context.go('/today');
    if (fresh) showRfToast(context, 'Fresh plan ready. Your history is kept.', icon: CupertinoIcons.checkmark_alt);
  }

  /* ------------------------------------------------------------ UI */

  @override
  Widget build(BuildContext context) {
    // Prefill "redo setup" once the profile is known.
    if (_mode == ObMode.fresh && !_prefilled) {
      final p = ref.watch(profileProvider).value;
      if (p != null) {
        _prefilled = true;
        _d = OnboardingDraft.fromProfile(p, year: ref.read(clockProvider)().year);
      }
    }
    final c = context.rf;
    final step = _step;
    final question = _steps.indexOf(ObStep.building);
    final showChrome = step.index < ObStep.building.index;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        if (showChrome) _header(context, question),
        if (!showChrome && step != ObStep.paywall) SizedBox(height: MediaQuery.paddingOf(context).top + 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: context.reduceMotion ? 0 : 220),
            child: KeyedSubtree(key: ValueKey(step), child: _body(step)),
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, int total) {
    final c = context.rf;
    final canBack = _i > 0 || _mode == ObMode.fresh;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top + 4, Rf.gutter, 4),
      child: Row(children: [
        SizedBox(
          width: Rf.tap,
          height: Rf.tap,
          child: canBack
              ? IconButton(
                  key: const Key('ob-back'),
                  tooltip: 'Back',
                  icon: Icon(CupertinoIcons.chevron_back, color: c.text),
                  onPressed: _back,
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: 'Step ${_i + 1} of $total',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearMeter(value: total == 0 ? 0 : (_i + 1) / total, height: 6),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _question(Widget body, {String label = 'Continue', Widget? extra}) => StepFrame(
        body: body,
        footer: Column(mainAxisSize: MainAxisSize.min, children: [
          RfButton(key: const Key('ob-next'), label: label, expand: true, height: Rf.gymTap, onPressed: _canContinue ? _next : null),
          ?extra,
        ]),
      );

  Widget _body(ObStep step) {
    final c = context.rf;
    switch (step) {
      case ObStep.welcome:
        return _question(
          WelcomeStep(fresh: _mode == ObMode.fresh, code: _code),
          label: _mode == ObMode.fresh ? 'Start' : 'Get started',
          extra: _mode == ObMode.organic
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: RfButton(
                    key: const Key('ob-have-code'),
                    label: 'I have a trainer or promo code',
                    kind: RfButtonKind.ghost,
                    expand: true,
                    onPressed: _enterCode,
                  ),
                )
              : null,
        );
      case ObStep.goal:
        return _question(GoalStep(d: _d, set: _set));
      case ObStep.experience:
        return _question(ExperienceStep(d: _d, set: _set));
      case ObStep.schedule:
        return _question(ScheduleStep(d: _d, set: _set));
      case ObStep.gym:
        return _question(GymStep(d: _d, set: _set));
      case ObStep.body:
        return _question(BodyStep(d: _d, set: _set));
      case ObStep.about:
        return _question(AboutStep(d: _d, set: _set));
      case ObStep.interlude:
        return _question(const InterludeStep());
      case ObStep.diet:
        return _question(DietStep(d: _d, set: _set));
      case ObStep.protein:
        return _question(ProteinStep(d: _d, set: _set));
      case ObStep.language:
        return _question(LanguageStep(d: _d, set: _set), label: 'Build my plan');
      case ObStep.building:
        return BuildingStep(run: _build, onDone: (b) => setState(() {
              _built = b;
              _i++;
            }));
      case ObStep.reveal:
        return _built == null ? _missing(c) : RevealStep(built: _built!, d: _d, onDone: _next);
      case ObStep.firstEdit:
        return _built == null ? _missing(c) : FirstEditStep(built: _built!, d: _d, onDone: _next);
      case ObStep.save:
        return SaveStep(onDone: _next);
      case ObStep.notify:
        return _built == null ? _missing(c) : NotifyStep(d: _d, built: _built!, onDone: _next);
      case ObStep.paywall:
        return PaywallStep(onDone: _next);
      case ObStep.start:
        return _built == null ? _missing(c) : StartStep(built: _built!, name: _d.name, onFinish: _finish);
    }
  }

  Widget _missing(RfColors c) => Center(child: RfButton(label: 'Go to Today', onPressed: () => _finish()));
}
