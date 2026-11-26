// Plan history: every coach proposal with its date and outcome; tap one to see its full card.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/services/common.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'coach_models.dart';
import 'coach_service.dart';
import 'proposal_card.dart';
import 'proposal_diff.dart';

String outcomeLabel(ProposalStatus s) => switch (s) {
      ProposalStatus.pending => 'Waiting for you',
      ProposalStatus.approved => 'Approved',
      ProposalStatus.discarded => 'Discarded',
      ProposalStatus.undone => 'Undone',
    };

/// One-line summary of a proposal's diff ("3 changes · diet 1,900 → 2,100 kcal").
String proposalOneLiner(CoachProposal p, Map<String, Exercise> exMap) {
  final parts = <String>[];
  if (p.after.workout != null) {
    final n = diffWorkouts(p.before.workout, p.after.workout, exMap).changeCount;
    parts.add(n == 0 ? 'workout unchanged' : '$n workout ${n == 1 ? 'change' : 'changes'}');
  }
  final d = p.after.diet;
  if (d != null) {
    final b = p.before.diet;
    parts.add(b == null || jsRound(b.kcalTarget) == jsRound(d.kcalTarget)
        ? 'diet ${thousands(jsRound(d.kcalTarget))} kcal'
        : 'diet ${thousands(jsRound(b.kcalTarget))} → ${thousands(jsRound(d.kcalTarget))} kcal');
  }
  return parts.join(' · ');
}

class PlanHistoryScreen extends ConsumerWidget {
  const PlanHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final st = ref.watch(coachStateProvider).value;
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    final goal = ref.watch(profileProvider).value?.goal;
    final entries = [
      for (final m in (st?.thread ?? const <CoachMessage>[]).reversed)
        if (m.proposal != null) m,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Plan history')),
      body: entries.isEmpty
          ? const Center(
              child: EmptyState(
                icon: CupertinoIcons.clock,
                title: 'No plan changes yet',
                body: 'Every change the coach proposes shows up here with what you decided.',
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, MediaQuery.paddingOf(context).bottom + 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final m = entries[i];
                final p = m.proposal!;
                final date = DateFormat('EEE d MMM').format(parseIsoLocal(m.createdAt));
                final (Color tone, IconData icon) = switch (p.status) {
                  ProposalStatus.pending => (c.coach, CupertinoIcons.hand_raised),
                  ProposalStatus.approved => (c.done, CupertinoIcons.checkmark_alt),
                  ProposalStatus.discarded => (c.muted, CupertinoIcons.xmark),
                  ProposalStatus.undone => (c.muted, CupertinoIcons.arrow_uturn_left),
                };
                return RfCard(
                  semanticLabel: '${p.title}, $date, ${outcomeLabel(p.status)}',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(p.title)),
                      body: ListView(padding: const EdgeInsets.all(Rf.gutter), children: [
                        ProposalCard(proposal: p, exMap: exMap, goal: goal),
                      ]),
                    ),
                  )),
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 18, color: c.coach),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, style: RfType.bodyStrong.copyWith(color: c.text)),
                        const SizedBox(height: 2),
                        Text('$date · by coach${p.adjusted ? ', adjusted by you' : ''}', style: RfType.caption.copyWith(color: c.muted)),
                        Text(proposalOneLiner(p, exMap), style: RfType.caption.copyWith(color: c.muted)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(label: outcomeLabel(p.status), color: tone, icon: icon),
                  ]),
                );
              },
            ),
    );
  }
}
