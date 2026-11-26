// The question screens of onboarding (port of src/features/onboarding/steps.tsx, regrouped for
// the Repfellow flow). Each step edits the shared draft through [Update]; the screen owns navigation.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../domain/equipment.dart';
import '../../domain/generator.dart';
import '../../domain/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'draft.dart';
import 'ob_widgets.dart';

typedef Update = void Function(void Function() change);

/* ------------------------------------------------------------ welcome */

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, required this.fresh, this.code});
  final bool fresh;
  final String? code;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 24),
      Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [c.accent, c.accentInk], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Icon(Icons.fitness_center, size: 34, color: c.onAccent),
      ),
      const SizedBox(height: 28),
      Semantics(
        header: true,
        child: Text(
          fresh ? 'Start fresh.\nKeep your history.' : 'Your gym coach + Indian diet plan.',
          style: RfType.title.copyWith(color: c.text, fontSize: 34, height: 1.1),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        fresh
            ? 'Build a new plan from new answers. Your sessions, meals and weigh-ins stay.'
            : 'It explains every change. No sales calls.',
        style: RfType.body.copyWith(color: c.muted, fontSize: 19),
      ),
      const SizedBox(height: 28),
      if (!fresh) ...[
        _Promise(icon: CupertinoIcons.chat_bubble_text, text: 'Every change comes with a reason you can read'),
        _Promise(icon: Icons.restaurant_outlined, text: 'Dal, paneer, roti: a diet built from food you already eat'),
        _Promise(icon: CupertinoIcons.lock, text: 'Your answers stay on this phone'),
      ],
      if (code != null) ...[
        const SizedBox(height: 16),
        RfCard(
          color: c.trainer.withValues(alpha: 0.10),
          border: c.trainer.withValues(alpha: 0.5),
          child: Row(children: [
            Icon(CupertinoIcons.checkmark_seal_fill, color: c.trainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Code $code applied. Pro is included while it is active.', style: RfType.callout.copyWith(color: c.text)),
            ),
          ]),
        ),
      ],
    ]);
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Icon(icon, size: 22, color: c.accentInk),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: RfType.callout.copyWith(color: c.text))),
      ]),
    );
  }
}

/// Bottom sheet to enter a trainer / promo / invite code. Returns the trimmed code or null.
Future<String?> showCodeSheet(BuildContext context) => showRfSheet<String>(context, builder: (_) => const _CodeSheet());

class _CodeSheet extends StatefulWidget {
  const _CodeSheet();
  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _ctl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _apply() {
    final code = _ctl.text.trim();
    if (code.length < 3 || code.length > 20 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(code)) {
      setState(() => _error = 'Codes are 3 to 20 letters or numbers.');
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Rf.gutter, 20, Rf.gutter, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Trainer or promo code', style: RfType.headline.copyWith(color: c.text)),
        const SizedBox(height: 6),
        Text('From your trainer, your gym or a creator. It unlocks Pro and the AI coach.', style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 16),
        TextField(
          key: const Key('ob-code-field'),
          controller: _ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: RfType.body.copyWith(color: c.text, letterSpacing: 1.2),
          decoration: InputDecoration(labelText: 'Code', errorText: _error, border: const OutlineInputBorder()),
          onSubmitted: (_) => _apply(),
        ),
        const SizedBox(height: 16),
        RfButton(key: const Key('ob-code-apply'), label: 'Apply code', expand: true, onPressed: _apply),
      ]),
    );
  }
}

/* ------------------------------------------------------------ goal / experience */

IconData _goalIcon(Goal g) => switch (g) {
      Goal.fatLoss => CupertinoIcons.flame,
      Goal.lean => Icons.bolt,
      Goal.muscle => Icons.fitness_center,
      Goal.strength => CupertinoIcons.arrow_up_right,
      Goal.general => CupertinoIcons.heart,
    };

class GoalStep extends StatelessWidget {
  const GoalStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const StepHeading('What do you want most?', sub: 'This sets the kind of plan you get. You can change it later.'),
        for (final g in kGoals)
          OptionCard(title: g.label, sub: g.sub, icon: _goalIcon(g.id), selected: d.goal == g.id, onTap: () => set(() => d.goal = g.id)),
      ]);
}

class ExperienceStep extends StatelessWidget {
  const ExperienceStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const StepHeading('How long have you been training?', sub: 'Newer lifters get simpler moves and more room to learn.'),
        for (final e in kExperience)
          OptionCard(title: e.label, sub: e.sub, selected: d.experience == e.id, onTap: () => set(() => d.experience = e.id)),
        const SizedBox(height: 12),
        ChipGroup(
          label: 'Know your working weights?',
          hint: 'If not, your first session finds them with light sets.',
          children: [
            for (final (v, l) in [(true, 'Yes'), (false, 'No')])
              RfChip(label: l, selected: d.knowsWeights == v, onTap: () => set(() => d.knowsWeights = v)),
          ],
        ),
      ]);
}

/* ------------------------------------------------------------ schedule */

class ScheduleStep extends StatelessWidget {
  const ScheduleStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) {
    final n = d.days.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('When can you train?', sub: 'Pick real days. A plan you can keep beats a perfect one.'),
      ChipGroup(
        label: 'Days',
        hint: n == 0
            ? 'Pick at least one day.'
            : n > 6
                ? 'Seven days leaves no rest. Six is the most we plan.'
                : '$n ${n == 1 ? 'day' : 'days'} a week${n >= 2 && n <= 4 ? ', a great start' : ''}.',
        children: [
          for (final w in Weekday.values)
            RfChip(
              label: w.label,
              selected: d.days.contains(w),
              onTap: () => set(() => d.days.contains(w) ? d.days.remove(w) : d.days.add(w)),
            ),
        ],
      ),
      ChipGroup(
        label: 'Session length',
        hint: 'Including warm-up. Short sessions keep the big lifts and drop extras.',
        children: [
          for (final m in kSessionLengths) RfChip(label: '$m min', selected: d.sessionMin == m, onTap: () => set(() => d.sessionMin = m)),
        ],
      ),
      ChipGroup(
        label: 'Usually at',
        hint: 'Used for your reminder time.',
        children: [
          for (final t in kTrainTimes) RfChip(label: t.label, selected: d.trainWindow == t.id, onTap: () => set(() => d.trainWindow = t.id)),
        ],
      ),
    ]);
  }
}

/* ------------------------------------------------------------ gym / equipment */

class GymStep extends StatefulWidget {
  const GymStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  State<GymStep> createState() => _GymStepState();
}

class _GymStepState extends State<GymStep> {
  bool _edit = false;
  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final c = context.rf;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('Where do you train?', sub: 'Your plan only uses equipment you have. Swaps stay inside the same list.'),
      for (final g in kGymPresets)
        OptionCard(
          title: g.label,
          sub: g.sub,
          selected: d.gymPreset == g.id,
          onTap: () => widget.set(() {
            d.gymPreset = g.id;
            d.equipment = List.of(g.equipment);
          }),
        ),
      const SizedBox(height: 6),
      Semantics(
        button: true,
        expanded: _edit,
        child: InkWell(
          onTap: () => setState(() => _edit = !_edit),
          child: SizedBox(
            height: Rf.tap,
            child: Row(children: [
              Icon(_edit ? CupertinoIcons.chevron_up : CupertinoIcons.slider_horizontal_3, size: 18, color: c.accentInk),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _edit ? 'Hide the equipment list' : 'Edit the list (${d.equipment.length} items)',
                  style: RfType.bodyStrong.copyWith(color: c.accentInk),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ),
      if (_edit)
        ChipGroup(
          label: 'Equipment you have',
          hint: 'Bodyweight moves are always included.',
          children: [
            for (final e in kEquipment)
              RfChip(
                label: e.label,
                selected: d.equipment.contains(e.id),
                onTap: () => widget.set(() {
                  d.equipment.contains(e.id) ? d.equipment.remove(e.id) : d.equipment.add(e.id);
                  d.gymPreset = 'custom';
                }),
              ),
          ],
        ),
    ]);
  }
}

/* ------------------------------------------------------------ body check */

class BodyStep extends StatelessWidget {
  const BodyStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final pain = d.pain;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('Anything that hurts or is injured?', sub: 'The coach keeps load off these areas and offers swaps.'),
      OptionCard(
        title: 'None',
        sub: 'Nothing bothers me right now',
        icon: CupertinoIcons.hand_thumbsup,
        selected: pain != null && pain.isEmpty,
        onTap: () => set(() => d.pain = []),
      ),
      const SizedBox(height: 8),
      ChipGroup(
        label: 'Or tap the areas',
        children: [
          for (final a in kPainAreas)
            RfChip(
              label: a.label,
              tone: c.caution,
              icon: (pain ?? const []).contains(a.id) ? CupertinoIcons.bandage : null,
              selected: (pain ?? const []).contains(a.id),
              onTap: () => set(() {
                final next = List.of(pain ?? const <String>[]);
                next.contains(a.id) ? next.remove(a.id) : next.add(a.id);
                d.pain = next.isEmpty ? null : next;
              }),
            ),
        ],
      ),
      Text('Sharp or worsening pain needs a doctor, not an app.', style: RfType.caption.copyWith(color: c.muted)),
    ]);
  }
}

/* ------------------------------------------------------------ about you */

class AboutStep extends StatefulWidget {
  const AboutStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  State<AboutStep> createState() => _AboutStepState();
}

class _AboutStepState extends State<AboutStep> {
  late final _name = TextEditingController(text: widget.d.name);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final set = widget.set;
    final c = context.rf;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('About you', sub: 'Used only to set your calories, protein and starting weights. Kilograms and centimetres.'),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        style: RfType.body.copyWith(color: c.text),
        decoration: const InputDecoration(labelText: 'What should we call you? (optional)', border: OutlineInputBorder()),
        onChanged: (v) => d.name = v,
      ),
      const SizedBox(height: 18),
      ChipGroup(
        label: 'Sex',
        hint: 'Calorie formulas differ slightly by sex.',
        children: [
          for (final (s, l) in [(Sex.male, 'Male'), (Sex.female, 'Female'), (Sex.other, 'Prefer not to say')])
            RfChip(label: l, selected: d.sex == s, onTap: () => set(() => d.sex = s)),
        ],
      ),
      MeasureRow(
        label: 'Age',
        why: 'Energy needs change with age',
        value: d.age.toDouble(),
        onChanged: (v) => set(() => d.age = v.round()),
        step: 1,
        min: 13,
        max: 90,
        unit: 'years',
      ),
      MeasureRow(
        label: 'Height',
        why: 'Part of your calorie target',
        value: d.heightCm,
        onChanged: (v) => set(() => d.heightCm = v),
        step: 1,
        min: 120,
        max: 230,
        unit: 'cm',
      ),
      MeasureRow(
        label: 'Weight',
        why: 'Your starting point. Only you see it',
        value: d.weightKg,
        onChanged: (v) => set(() => d.weightKg = v),
        step: 0.5,
        min: 30,
        max: 250,
        unit: 'kg',
      ),
      MeasureRow(
        label: 'Goal weight',
        why: 'Sets the direction: lose, keep or gain',
        value: d.goalWeightKg,
        onChanged: (v) => set(() => d.goalWeightKg = v),
        step: 0.5,
        min: 30,
        max: 250,
        unit: 'kg',
      ),
    ]);
  }
}

/* ------------------------------------------------------------ value interlude */

/// "Your coach shows its working": an example set row whose weight steps up, then a violet reason.
class InterludeStep extends StatefulWidget {
  const InterludeStep({super.key});
  @override
  State<InterludeStep> createState() => _InterludeStepState();
}

class _InterludeStepState extends State<InterludeStep> {
  int _phase = 0;
  final _timers = <Timer>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timers.isNotEmpty || _phase > 0) return;
    if (context.reduceMotion) {
      _phase = 3;
      return;
    }
    for (final (ms, p) in [(700, 1), (1400, 2), (2300, 3)]) {
      _timers.add(Timer(Duration(milliseconds: ms), () => mounted ? setState(() => _phase = p) : null));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final ms = Duration(milliseconds: context.reduceMotion ? 0 : 350);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('Your coach shows its working', sub: 'Every change to your plan comes with a reason. You approve it, and you can undo it.'),
      RfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Example · Goblet squat · Set 2', style: RfType.captionStrong.copyWith(color: c.muted)),
          const SizedBox(height: 10),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 4, runSpacing: 8, children: [
            AnimatedSwitcher(
              duration: ms,
              child: Text(
                _phase >= 1 ? '22' : '20',
                key: ValueKey(_phase >= 1),
                style: RfType.setNumeral.copyWith(color: c.text),
              ),
            ),
            Padding(padding: const EdgeInsets.only(bottom: 6, right: 14), child: Text('kg', style: RfType.callout.copyWith(color: c.muted))),
            Text('× 10', style: RfType.setNumeral.copyWith(color: c.text)),
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: AnimatedOpacity(
                opacity: _phase >= 1 ? 1 : 0,
                duration: ms,
                child: StatusPill(label: '+2 kg', color: c.done, icon: CupertinoIcons.arrow_up),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          AnimatedOpacity(
            opacity: _phase >= 2 ? 1 : 0,
            duration: ms,
            child: const ReasonChip('+2 kg because you hit 12 reps on every set last time'),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      AnimatedOpacity(
        opacity: _phase >= 3 ? 1 : 0,
        duration: ms,
        child: RfCard(
          border: c.coach.withValues(alpha: 0.5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CoachDot(),
              const SizedBox(width: 8),
              Text('Coach proposal', style: RfType.captionStrong.copyWith(color: c.coach)),
            ]),
            const SizedBox(height: 8),
            Text('Swap back squat for leg press on Thursday', style: RfType.bodyStrong.copyWith(color: c.text)),
            const SizedBox(height: 4),
            Text('Because you said your knee is sensitive. Same muscles, less strain.', style: RfType.callout.copyWith(color: c.muted)),
            const SizedBox(height: 12),
            Row(children: [
              StatusPill(label: 'Approve', color: c.done, icon: CupertinoIcons.checkmark_alt),
              const SizedBox(width: 8),
              StatusPill(label: 'Discard', color: c.muted, icon: CupertinoIcons.xmark),
            ]),
          ]),
        ),
      ),
    ]);
  }
}

/* ------------------------------------------------------------ diet */

class DietStep extends StatelessWidget {
  const DietStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('How do you eat?', sub: 'Every meal in your plan follows this.'),
      for (final t in kDietTypes) OptionCard(title: t.label, sub: t.sub, selected: d.diet == t.id, onTap: () => set(() => d.diet = t.id)),
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(CupertinoIcons.info, size: 18, color: c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Jain, or no onion and garlic on some days? Pick Veg for now. Jain plans are coming; tell the coach and it will adjust meals.',
            style: RfType.caption.copyWith(color: c.muted),
          ),
        ),
      ]),
    ]);
  }
}

class ProteinStep extends StatelessWidget {
  const ProteinStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) {
    final sources = kProteinSources.where((s) => s.fits(d.diet)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const StepHeading('Where does your protein come from?', sub: 'Protein is the number we track first. Untick what you don\'t eat.'),
      ChipGroup(
        label: 'Foods you eat',
        children: [
          for (final s in sources)
            RfChip(
              label: s.label,
              selected: d.proteinSources.contains(s.id),
              onTap: () => set(() => d.proteinSources.contains(s.id) ? d.proteinSources.remove(s.id) : d.proteinSources.add(s.id)),
            ),
        ],
      ),
      ChipGroup(
        label: 'Whey or plant protein powder?',
        hint: 'Not required. It makes high protein targets easier.',
        children: [
          for (final (v, l) in [('yes', 'Yes'), ('no', 'No'), ('unsure', 'Not sure')])
            RfChip(label: l, selected: d.whey == v, onTap: () => set(() => d.whey = v)),
        ],
      ),
      ChipGroup(
        label: 'Anything to avoid?',
        children: [
          for (final a in kAvoid)
            RfChip(
              label: a.label,
              selected: d.avoid.contains(a.id),
              onTap: () => set(() => d.avoid.contains(a.id) ? d.avoid.remove(a.id) : d.avoid.add(a.id)),
            ),
        ],
      ),
    ]);
  }
}

/* ------------------------------------------------------------ coach language */

class LanguageStep extends StatelessWidget {
  const LanguageStep({super.key, required this.d, required this.set});
  final OnboardingDraft d;
  final Update set;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const StepHeading('How should your coach talk?', sub: 'The app stays in English. You can always type or speak in Hinglish.'),
        OptionCard(
          title: 'English',
          sub: '"Good session. Add 2 kg to the squat next time."',
          selected: d.coachLanguage == 'en',
          onTap: () => set(() => d.coachLanguage = 'en'),
        ),
        OptionCard(
          title: 'Hinglish',
          sub: '"Badhiya session! Agli baar squat mein 2 kg add karo."',
          selected: d.coachLanguage == 'hinglish',
          onTap: () => set(() => d.coachLanguage = 'hinglish'),
        ),
      ]);
}
