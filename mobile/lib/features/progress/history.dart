// Workout history: recent sessions on Progress, the full list, and a session's sets (pushed inside
// this feature with Navigator so nobody edits the router).
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'progress_screen.dart';

String _when(Session s) {
  final d = DateTime.tryParse(s.startedAt)?.toLocal() ?? fromDayKey(s.dayKey);
  return DateFormat('EEE d MMM').format(d);
}

int? _minutes(Session s) {
  final a = DateTime.tryParse(s.startedAt);
  final b = s.endedAt == null ? null : DateTime.tryParse(s.endedAt!);
  return a == null || b == null ? null : b.difference(a).inMinutes;
}

/// Sessions newest first, with the set count and any PR flags from the lift series.
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.model, this.limit});
  final ProgressModel model;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final all = model.sessions.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (all.isEmpty) {
      return const RfCard(child: EmptyState(icon: Icons.history, title: 'No workouts yet', body: 'Finished sessions show up here with every set.'));
    }
    final prSessions = {for (final s in model.series.values) for (final p in s) if (p.pr) p.sessionId};
    final list = limit == null ? all : all.take(limit!).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < list.length; i++) ...[
        _SessionRow(session: list[i], ordinal: all.length - i, pr: prSessions.contains(list[i].id)),
        const SizedBox(height: 8),
      ],
      if (limit != null && all.length > limit!)
        RfButton(
          label: 'See all ${all.length} workouts',
          kind: RfButtonKind.ghost,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
        ),
      if (list.isEmpty) Text('Nothing yet', style: RfType.callout.copyWith(color: c.muted)),
    ]);
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.ordinal, required this.pr});
  final Session session;
  final int ordinal;
  final bool pr;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final mins = _minutes(session);
    return RfCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      semanticLabel: 'Workout ${session.title}, ${_when(session)}',
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: session.id))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.bodyStrong.copyWith(color: c.text)),
            Text('${_when(session)}${mins != null ? ' · $mins min' : ''} · workout #$ordinal', style: RfType.caption.copyWith(color: c.muted)),
          ]),
        ),
        if (pr) ...[StatusPill(label: 'PR', color: c.pr, icon: CupertinoIcons.star_fill), const SizedBox(width: 6)],
        Icon(CupertinoIcons.chevron_right, size: 18, color: c.muted),
      ]),
    );
  }
}

/// The full workout history (all completed sessions).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final done = ref.watch(doneSessionsProvider).value ?? const <Session>[];
    final all = [...done]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: all.isEmpty
          ? const Center(child: EmptyState(icon: Icons.history, title: 'No workouts yet'))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, MediaQuery.paddingOf(context).bottom + 16),
              itemCount: all.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _SessionRow(session: all[i], ordinal: all.length - i, pr: false),
            ),
      backgroundColor: c.bg,
    );
  }
}

/// One session's working sets, grouped by exercise, with best e1RM per exercise.
class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final done = ref.watch(doneSessionsProvider).value ?? const <Session>[];
    final session = done.where((s) => s.id == sessionId).firstOrNull;
    final sets = ref.watch(sessionSetsProvider(sessionId)).value;
    final exMap = ref.watch(exerciseMapProvider).value ?? const <String, Exercise>{};
    final groups = <String, List<SetLog>>{};
    for (final s in sets ?? const <SetLog>[]) {
      (groups[s.exerciseId] ??= []).add(s);
    }
    final ordered = groups.entries.toList()..sort((a, b) => a.value.first.completedAt.compareTo(b.value.first.completedAt));
    final units = ref.watch(profileProvider).value?.units ?? 'kg';
    String wt(double kg) => units == 'kg' ? '${kg.toStringAsFixed(kg == kg.roundToDouble() ? 0 : 1)} kg' : '${(kg / 0.45359237).round()} lb';
    String setText(SetLog s) {
      final parts = <String>[
        if (s.weightKg != null && s.weightKg! > 0) wt(s.weightKg!),
        if (s.reps != null) '${s.reps} reps',
        if (s.seconds != null) '${s.seconds} s',
        if (s.meters != null) '${s.meters!.round()} m',
      ];
      return parts.isEmpty ? 'Done' : parts.join(' × ');
    }

    final mins = session == null ? null : _minutes(session);
    return Scaffold(
      appBar: AppBar(title: Text(session?.title ?? 'Workout')),
      backgroundColor: c.bg,
      body: sets == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, MediaQuery.paddingOf(context).bottom + 16), children: [
              if (session != null)
                Text(
                  '${_when(session)}${mins != null ? ' · $mins min' : ''}${session.rpe != null ? ' · effort ${session.rpe}/10' : ''} · ${sets.length} sets',
                  style: RfType.callout.copyWith(color: c.muted),
                ),
              const SizedBox(height: 12),
              if (ordered.isEmpty) Text('No sets were logged in this session.', style: RfType.callout.copyWith(color: c.muted)),
              for (final g in ordered) ...[
                RfCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(exMap[g.key]?.name ?? g.key, style: RfType.bodyStrong.copyWith(color: c.text)),
                    Builder(builder: (_) {
                      final best = g.value.map((s) => e1rm(s.weightKg, s.reps) ?? 0.0).fold(0.0, (a, b) => a > b ? a : b);
                      return best > 0 ? Text('Best estimated 1-rep max ${wt(best)}', style: RfType.caption.copyWith(color: c.muted)) : const SizedBox.shrink();
                    }),
                    const SizedBox(height: 8),
                    for (final s in (g.value..sort((a, b) => a.setIndex - b.setIndex)))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          SizedBox(
                            width: 56,
                            child: Text(s.isWarmup ? 'Warm-up' : 'Set ${s.setIndex + 1}', style: RfType.caption.copyWith(color: c.muted)),
                          ),
                          Expanded(child: Text(setText(s), style: RfType.callout.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()]))),
                          if (s.rir != null) Text('${s.rir} in reserve', style: RfType.caption.copyWith(color: c.muted)),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
            ]),
    );
  }
}
