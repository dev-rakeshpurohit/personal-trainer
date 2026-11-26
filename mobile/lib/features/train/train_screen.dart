// Train tab: the plan, with its working shown. Block strip (8-week wave, "you are here"),
// week selector, this week's focus, Plan check, day cards with "Why" on every value, and the
// way into the library, plan history and the day editor.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../library/library_screen.dart';
import 'block_strip.dart';
import 'day_card.dart';
import 'plan_check.dart';
import 'plan_history_screen.dart';
import 'train_data.dart';

class TrainScreen extends ConsumerStatefulWidget {
  const TrainScreen({super.key});
  @override
  ConsumerState<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends ConsumerState<TrainScreen> {
  int _offset = 0;
  TrainWeek? _last;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final bundle = ref.watch(programBundleProvider);
    final weekAsync = ref.watch(trainWeekProvider(_offset));
    final week = weekAsync.value ?? (_last?.offset == _offset ? _last : null);
    if (weekAsync.value != null) _last = weekAsync.value;
    final bottom = MediaQuery.paddingOf(context).bottom + 16;

    if (bundle.hasValue && bundle.value == null) {
      return Scaffold(
        body: CustomScrollView(slivers: [
          const SliverToBoxAdapter(child: PageHeader(title: 'Train')),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.fitness_center,
              title: 'No plan yet',
              body: 'Set up your week and Repfellow builds a plan that explains itself.',
              action: RfButton(label: 'Set up my plan', onPressed: () => context.go('/onboarding?fresh=1')),
            ),
          ),
        ]),
      );
    }

    final phase = week?.phase;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Train',
            eyebrow: week == null ? null : 'Week ${week.currentCycleWeek} of 8 · ${_phaseOf(week)} block',
            trailing: IconButton(
              tooltip: 'Exercise library',
              constraints: const BoxConstraints(minWidth: Rf.tap, minHeight: Rf.tap),
              icon: Icon(CupertinoIcons.book, color: c.text),
              onPressed: () => LibraryScreen.open(context),
            ),
          ),
        ),
        if (week == null)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, 0),
              child: Text(week.program.name, style: RfType.callout.copyWith(color: c.muted)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Rf.gutter, 14, Rf.gutter, 0),
              child: BlockStrip(
                phases: week.phases,
                current: week.currentCycleWeek,
                selected: week.cycleWeek,
                onSelect: (w) => setState(() => _offset = w - week.currentCycleWeek),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _WeekSelector(week: week, onChange: (o) => setState(() => _offset = o))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 12), child: _FocusCard(week: week, phase: phase))),
          if (week.offset == 0) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 12), child: PlanCheckCard())),
          SliverToBoxAdapter(child: SectionTitle(week.offset == 0 ? 'This week' : 'Week ${week.cycleWeek} · preview', padding: const EdgeInsets.fromLTRB(Rf.gutter, 10, Rf.gutter, 10))),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Rf.gutter),
            sliver: SliverList.separated(
              itemCount: week.days.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => DayCard(key: ValueKey('day-$i-${week.offset}'), day: week.days[i], week: week),
            ),
          ),
          if (week.dropped.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Rf.gutter, 10, Rf.gutter, 0),
                child: Text(
                  'Dropped this week to fit: ${week.dropped.map((d) => d.title).join(', ')}. A 30-minute brisk walk covers it if you can.',
                  style: RfType.callout.copyWith(color: c.muted),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(Rf.gutter, 18, Rf.gutter, bottom),
              child: Column(children: [
                _LinkTile(
                  icon: Icons.auto_awesome,
                  tone: c.coach,
                  title: 'Ask the coach to change the plan',
                  body: '“Make Friday shorter”, “my knee hurts”, “more variety”…',
                  onTap: () => context.go('/coach'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _LinkTile(icon: CupertinoIcons.book, title: 'Library', onTap: () => LibraryScreen.open(context))),
                  const SizedBox(width: 10),
                  Expanded(child: _LinkTile(icon: CupertinoIcons.clock, title: 'Plan history', onTap: () => PlanHistoryScreen.open(context))),
                ]),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  String _phaseOf(TrainWeek w) => w.phases.where((p) => p.contains(w.currentCycleWeek)).firstOrNull?.label ?? 'Base';
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({required this.week, required this.onChange});
  final TrainWeek week;
  final ValueChanged<int> onChange;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final df = DateFormat('d MMM');
    final first = week.cycleWeek <= 1;
    final last = week.cycleWeek >= 8;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(children: [
        IconButton(
          tooltip: 'Previous week',
          constraints: const BoxConstraints(minWidth: Rf.tap, minHeight: Rf.tap),
          onPressed: first ? null : () => onChange(week.offset - 1),
          icon: Icon(CupertinoIcons.chevron_left, color: first ? c.line : c.text),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(children: [
              Text(
                'Week ${week.cycleWeek} of 8${week.offset == 0 ? ' · This week' : ''}',
                style: RfType.bodyStrong.copyWith(color: c.text),
              ),
              Text('${df.format(week.start)} – ${df.format(week.end)}', style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
        ),
        if (week.offset != 0)
          TextButton(
            onPressed: () => onChange(0),
            child: Text('Today', style: RfType.callout.copyWith(color: c.accentInk, fontWeight: FontWeight.w600)),
          ),
        IconButton(
          tooltip: 'Next week',
          constraints: const BoxConstraints(minWidth: Rf.tap, minHeight: Rf.tap),
          onPressed: last ? null : () => onChange(week.offset + 1),
          icon: Icon(CupertinoIcons.chevron_right, color: last ? c.line : c.text),
        ),
      ]),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.week, required this.phase});
  final TrainWeek week;
  final BlockPhase? phase;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final f = week.focus;
    if (week.deload) {
      return RfCard(
        color: c.done.withValues(alpha: 0.08),
        border: c.done.withValues(alpha: 0.3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(CupertinoIcons.leaf_arrow_circlepath, color: c.done),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Recovery week — lighter on purpose', style: RfType.bodyStrong.copyWith(color: c.text)),
              const SizedBox(height: 4),
              Text(
                f?.note.isNotEmpty == true ? f!.note : 'Half the sets, same weights. Your body catches up so next week starts stronger.',
                style: RfType.callout.copyWith(color: c.muted),
              ),
            ]),
          ),
        ]),
      );
    }
    final rir = f != null ? 'Main lifts ${f.rirMain} reps in reserve, accessories ${f.rirAccessory}.' : null;
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("THIS WEEK'S FOCUS", style: RfType.overline.copyWith(color: c.muted)),
        const SizedBox(height: 4),
        Text(f != null ? '${f.focus}${phase != null ? ' · ${phase!.label} block' : ''}' : '${phase?.label ?? 'Base'} block',
            style: RfType.bodyStrong.copyWith(color: c.text)),
        if (rir != null) Text(rir, style: RfType.callout.copyWith(color: c.text)),
        if (f != null && f.note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(f.note, style: RfType.callout.copyWith(color: c.muted)),
        ],
      ]),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, this.body, this.onTap, this.tone});
  final IconData icon;
  final String title;
  final String? body;
  final VoidCallback? onTap;
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return RfCard(
      onTap: onTap,
      semanticLabel: title,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(children: [
          Icon(icon, size: 22, color: tone ?? c.text),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: RfType.bodyStrong.copyWith(color: c.text)),
              if (body != null) Text(body!, style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
          Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted),
        ]),
      ),
    );
  }
}
