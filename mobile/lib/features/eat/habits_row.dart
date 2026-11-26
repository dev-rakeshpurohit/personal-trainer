// Water + daily habits for a day: water with +250 / +500 ml, check habits as chips, number habits
// (steps, sleep) open a BigStepper sheet. Writes go through Repo.setHabit.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class HabitsRow extends ConsumerWidget {
  const HabitsRow({super.key, required this.dayKey});
  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final defs = ref.watch(habitDefsProvider).value ?? const <HabitDef>[];
    final logs = ref.watch(habitLogsForDayProvider(dayKey)).value ?? const <HabitLog>[];
    double val(String id) => logs.where((l) => l.habitId == id).firstOrNull?.value ?? 0;
    final repo = ref.read(repoProvider);
    final water = defs.where((d) => d.id == 'water').firstOrNull;
    final others = defs.where((d) => d.id != 'water').toList();
    final nf = NumberFormat.decimalPattern();

    Future<void> editNumber(HabitDef h) async {
      final isSteps = h.id == 'steps' || h.unit == 'steps';
      var v = val(h.id);
      await showRfSheet<void>(
        context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(h.label, style: RfType.headline.copyWith(color: ctx.rf.text)),
                const SizedBox(height: 16),
                BigStepper(
                  value: v,
                  step: isSteps ? 500 : 0.5,
                  max: isSteps ? 100000 : 24,
                  label: h.label,
                  unit: h.unit,
                  format: isSteps ? (x) => nf.format(x.round()) : null,
                  onChanged: (x) => set(() => v = x),
                ),
                if (h.target != null) ...[
                  const SizedBox(height: 8),
                  Text('Target ${isSteps ? nf.format(h.target!.round()) : h.target} ${h.unit ?? ''}', style: RfType.caption.copyWith(color: ctx.rf.muted)),
                ],
                const SizedBox(height: 16),
                RfButton(
                  label: 'Save',
                  expand: true,
                  onPressed: () async {
                    await repo.setHabit(dayKey, h.id, v);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ]),
            ),
          ),
        ),
      );
    }

    if (defs.isEmpty) return const SizedBox.shrink();
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (water != null) ...[
          Builder(builder: (_) {
            final v = val('water');
            final target = water.target ?? 3000;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(CupertinoIcons.drop, size: 20, color: c.accentInk),
                const SizedBox(width: 6),
                Text('Water', style: RfType.bodyStrong.copyWith(color: c.text)),
                const Spacer(),
                Text('${(v / 1000).toStringAsFixed(2)} / ${(target / 1000).toStringAsFixed(1)} L',
                    style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 8),
              LinearMeter(value: target > 0 ? v / target : 0, height: 6),
              const SizedBox(height: 10),
              Row(children: [
                Semantics(
                  button: true,
                  label: 'Remove 250 ml water',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: v <= 0 ? null : () => repo.setHabit(dayKey, 'water', (v - 250).clamp(0, 20000).toDouble()),
                    child: Container(
                      width: 56,
                      height: Rf.tap,
                      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
                      child: Icon(CupertinoIcons.minus, size: 18, color: c.text),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RfButton(
                    label: '+250 ml',
                    kind: RfButtonKind.secondary,
                    height: Rf.tap,
                    expand: true,
                    onPressed: () {
                      Haptics.tick();
                      repo.setHabit(dayKey, 'water', v + 250);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RfButton(
                    label: '+500 ml',
                    kind: RfButtonKind.secondary,
                    height: Rf.tap,
                    expand: true,
                    onPressed: () {
                      Haptics.tick();
                      repo.setHabit(dayKey, 'water', v + 500);
                    },
                  ),
                ),
              ]),
            ]);
          }),
          if (others.isNotEmpty) const SizedBox(height: 14),
        ],
        if (others.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in others)
              if (h.kind == 'check')
                RfChip(
                  label: h.label,
                  icon: val(h.id) > 0 ? CupertinoIcons.checkmark_alt : CupertinoIcons.circle,
                  selected: val(h.id) > 0,
                  tone: c.done,
                  onTap: () => repo.setHabit(dayKey, h.id, val(h.id) > 0 ? 0 : 1),
                )
              else
                RfChip(
                  label: '${h.label} · ${(h.id == 'steps' || h.unit == 'steps') ? nf.format(val(h.id).round()) : _trim(val(h.id))}${h.target != null && val(h.id) >= h.target! ? ' ✓' : ''}',
                  selected: h.target != null && val(h.id) >= h.target!,
                  tone: c.done,
                  onTap: () => editNumber(h),
                ),
          ]),
      ]),
    );
  }
}

String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
