// Plan history: every plan version with who wrote it, when, a one-line diff, and Restore.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/schedule.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'train_data.dart';

class PlanHistoryScreen extends ConsumerWidget {
  const PlanHistoryScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlanHistoryScreen()));

  Future<void> _restore(BuildContext context, WidgetRef ref, PlanVersion v) async {
    final ok = await showRfSheet<bool>(context, builder: (ctx) {
      final c = ctx.rf;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Restore “${v.program.name}”?', style: RfType.headline.copyWith(color: c.text)),
          const SizedBox(height: 6),
          Text('It becomes your active plan from today. Your current plan stays here in history, and your logs are never touched.',
              style: RfType.callout.copyWith(color: c.muted)),
          const SizedBox(height: 18),
          RfButton(label: 'Restore this plan', icon: CupertinoIcons.arrow_counterclockwise, expand: true, onPressed: () => Navigator.of(ctx).pop(true)),
          const SizedBox(height: 8),
          RfButton(label: 'Keep current plan', kind: RfButtonKind.secondary, expand: true, onPressed: () => Navigator.of(ctx).pop(false)),
        ]),
      );
    });
    if (ok != true) return;
    final ops = ref.read(planOpsProvider);
    final prev = await ops.activate(v.program.id);
    if (!context.mounted) return;
    showRfToast(context, '“${v.program.name}” is your plan now', icon: CupertinoIcons.checkmark_alt, onUndo: prev == null ? null : () => ops.activate(prev));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final versions = ref.watch(planVersionsProvider).value;
    final current = versions?.where((v) => v.program.active).firstOrNull;
    final df = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Plan history')),
      body: versions == null
          ? const Center(child: CircularProgressIndicator())
          : versions.isEmpty
              ? const EmptyState(icon: CupertinoIcons.clock, title: 'No plans yet')
              : ListView(
                  padding: EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, MediaQuery.paddingOf(context).bottom + 16),
                  children: [
                    Text('Every version of your plan. Restore any of them; nothing you logged is lost.', style: RfType.callout.copyWith(color: c.muted)),
                    const SizedBox(height: 12),
                    for (final v in versions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RfCard(
                          border: v.program.active ? c.accent : null,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(v.program.name, style: RfType.bodyStrong.copyWith(color: c.text))),
                              if (v.program.active) StatusPill(label: 'Active', color: c.accentInk, icon: CupertinoIcons.checkmark_alt),
                            ]),
                            const SizedBox(height: 6),
                            _Author(author: authorOf(v.program)),
                            const SizedBox(height: 6),
                            Text(
                              '${v.program.startedOn.isEmpty ? '' : 'Started ${df.format(fromDayKey(v.program.startedOn))} · '}${diffLine(v, current)}',
                              style: RfType.caption.copyWith(color: c.muted),
                            ),
                            if (!v.program.active) ...[
                              const SizedBox(height: 10),
                              RfButton(
                                label: 'Restore',
                                icon: CupertinoIcons.arrow_counterclockwise,
                                kind: RfButtonKind.secondary,
                                onPressed: () => _restore(context, ref, v),
                              ),
                            ],
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _Author extends StatelessWidget {
  const _Author({required this.author});
  final PlanAuthor author;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final (icon, color) = switch (author) {
      PlanAuthor.coach => (Icons.auto_awesome, c.coach),
      PlanAuthor.you => (CupertinoIcons.person, c.text),
      PlanAuthor.generated => (CupertinoIcons.wand_stars, c.muted),
      PlanAuthor.template => (CupertinoIcons.doc_text, c.muted),
    };
    return Row(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Text(authorLabel(author), style: RfType.captionStrong.copyWith(color: color)),
    ]);
  }
}
