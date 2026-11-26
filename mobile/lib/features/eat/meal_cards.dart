// Timeline cards: planned meals as ghost cards (Ate as planned · Swap · Something else), logged
// meals with ✓ and Undo, and extra food logged from the log bar.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'eat_logic.dart';
import 'eat_screen.dart';

String _g(double v) => '${v.round()} g';
String _kcal(double v) => '${v.round()} kcal';

class PlannedMealCard extends ConsumerWidget {
  const PlannedMealCard({super.key, required this.meal, required this.log, required this.day, required this.vratIndex, required this.onSomethingElse});
  final PlannedMeal meal;
  final MealLog? log;
  final EatDay day;

  /// Position of this meal within its slot, to vary the vrat suggestion.
  final int vratIndex;
  final VoidCallback onSomethingElse;

  VratMeal? get _vrat {
    if (!day.vrat) return null;
    final opts = vratOptions(slotOf(meal), dairyOk: dairyOkFor(day.dietType, day.intolerances));
    return opts[vratIndex % opts.length];
  }

  Future<void> _ateAsPlanned(BuildContext context, WidgetRef ref) async {
    Haptics.tick();
    final repo = ref.read(repoProvider);
    final v = _vrat;
    final undo = v == null
        ? await repo.logMeal(day.dayKey, meal, 'eaten')
        : await repo.logMeal(day.dayKey, meal, 'swapped', label: 'Vrat: ${v.label}', proteinG: v.totals.protein.roundToDouble(), kcal: v.totals.kcal.roundToDouble());
    if (!context.mounted) return;
    final p = v == null ? meal.proteinG : v.totals.protein;
    showRfToast(context, '${meal.meal} logged · +${_g(p)} protein', icon: CupertinoIcons.checkmark_alt, onUndo: () => undo());
  }

  Future<void> _swap(BuildContext context, WidgetRef ref) async {
    final options = swapOptionsFor(meal, dietType: day.dietType, intolerances: day.intolerances, mine: day.prefs.mine);
    final picked = await showRfSheet<SwapOption>(context, builder: (_) => _SwapSheet(meal: meal, options: options, onSomethingElse: onSomethingElse));
    if (picked == null) return;
    final undo = await ref.read(repoProvider).logMeal(
          day.dayKey,
          meal,
          'swapped',
          label: picked.label,
          proteinG: picked.proteinG,
          kcal: picked.kcal,
          chosenRotation: picked.rotation,
        );
    if (!context.mounted) return;
    showRfToast(context, '${meal.meal} swapped · ${_g(picked.proteinG)} protein', icon: CupertinoIcons.arrow_2_squarepath, onUndo: () => undo());
  }

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    final undo = await ref.read(repoProvider).clearMeal(day.dayKey, meal.id);
    if (!context.mounted) return;
    showRfToast(context, '${meal.meal} back to planned', onUndo: () => undo());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    final l = log;
    if (l != null) {
      final skipped = l.state == 'skipped';
      return RfCard(
        color: skipped ? c.surface : c.done.withValues(alpha: 0.08),
        border: skipped ? null : c.done.withValues(alpha: 0.35),
        semanticLabel: '${meal.meal} ${skipped ? 'skipped' : 'logged'}',
        child: Row(children: [
          Icon(skipped ? CupertinoIcons.minus_circle : CupertinoIcons.checkmark_circle_fill, size: 26, color: skipped ? c.muted : c.done),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${meal.time} · ${meal.meal}', style: RfType.captionStrong.copyWith(color: c.muted)),
              const SizedBox(height: 2),
              Text(
                skipped ? 'Skipped' : l.state == 'swapped' ? (l.label ?? 'Swapped') : meal.items.join(' + '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RfType.callout.copyWith(color: c.text),
              ),
              if (!skipped)
                Text('${_g(l.proteinG)} protein · ${_kcal(l.kcal)}', style: RfType.caption.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          const SizedBox(width: 8),
          _UndoButton(label: 'Undo ${meal.meal}', onTap: () => _undo(context, ref)),
        ]),
      );
    }

    final v = _vrat;
    final items = v == null ? meal.items.join(' + ') : v.label;
    final p = v == null ? meal.proteinG : v.totals.protein;
    final k = v == null ? meal.kcal : v.totals.kcal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(Rf.cardRadius),
        border: Border.all(color: c.line, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${meal.time} · ${meal.meal}${meal.optional == true ? ' · optional' : ''}${v != null ? ' · vrat' : ''}',
              style: RfType.captionStrong.copyWith(color: c.muted),
            ),
          ),
          Text('${_g(p)} protein', style: RfType.captionStrong.copyWith(color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 4),
        Text(items, style: RfType.body.copyWith(color: c.text.withValues(alpha: 0.88))),
        Text(_kcal(k), style: RfType.caption.copyWith(color: c.muted)),
        const SizedBox(height: 12),
        RfButton(label: 'Ate as planned', icon: CupertinoIcons.checkmark_alt, expand: true, onPressed: () => _ateAsPlanned(context, ref)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: RfButton(label: 'Swap', icon: CupertinoIcons.arrow_2_squarepath, kind: RfButtonKind.secondary, expand: true, onPressed: () => _swap(context, ref))),
          const SizedBox(width: 8),
          Expanded(child: RfButton(label: 'Other', icon: CupertinoIcons.pencil, kind: RfButtonKind.secondary, expand: true, onPressed: onSomethingElse)),
        ]),
      ]),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Rf.tap, minWidth: Rf.tap),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Rf.btnRadius)),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.arrow_uturn_left, size: 16, color: c.text),
            const SizedBox(width: 6),
            Text('Undo', style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Food logged from the log bar (not a planned meal).
class ExtraLogCard extends ConsumerWidget {
  const ExtraLogCard({super.key, required this.log, required this.dayKey});
  final MealLog log;
  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.rf;
    return RfCard(
      color: c.done.withValues(alpha: 0.08),
      border: c.done.withValues(alpha: 0.35),
      child: Row(children: [
        Icon(CupertinoIcons.checkmark_circle_fill, size: 26, color: c.done),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(log.label ?? 'Logged food', maxLines: 3, overflow: TextOverflow.ellipsis, style: RfType.callout.copyWith(color: c.text)),
            Text('${_g(log.proteinG)} protein · ${_kcal(log.kcal)}', style: RfType.caption.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        const SizedBox(width: 8),
        _UndoButton(
          label: 'Undo ${log.label ?? 'logged food'}',
          onTap: () async {
            final id = log.plannedMealId;
            if (id == null) return;
            final undo = await ref.read(repoProvider).clearMeal(dayKey, id);
            if (!context.mounted) return;
            showRfToast(context, 'Removed', onUndo: () => undo());
          },
        ),
      ]),
    );
  }
}

class _SwapSheet extends StatelessWidget {
  const _SwapSheet({required this.meal, required this.options, required this.onSomethingElse});
  final PlannedMeal meal;
  final List<SwapOption> options;
  final VoidCallback onSomethingElse;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return SafeArea(
      top: false,
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 16), children: [
        Text('Swap ${meal.meal.toLowerCase()}', style: RfType.headline.copyWith(color: c.text)),
        const SizedBox(height: 4),
        Text('Planned: ${meal.items.join(' + ')} · ${_g(meal.proteinG)} protein', style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 14),
        if (options.isEmpty) Text('No equal-protein swaps for this one. Log what you ate instead.', style: RfType.callout.copyWith(color: c.muted)),
        for (final o in options) ...[
          RfCard(
            onTap: () => Navigator.of(context).pop(o),
            semanticLabel: 'Swap to ${o.label}',
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.label, style: RfType.bodyStrong.copyWith(color: c.text)),
                  Text(o.detail, style: RfType.caption.copyWith(color: c.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_g(o.proteinG)} protein', style: RfType.captionStrong.copyWith(color: c.text)),
                Text(_kcal(o.kcal), style: RfType.caption.copyWith(color: c.muted)),
              ]),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        RfButton(
          label: 'Ate something else',
          icon: CupertinoIcons.pencil,
          kind: RfButtonKind.ghost,
          expand: true,
          onPressed: () {
            Navigator.of(context).pop();
            onSomethingElse();
          },
        ),
      ]),
    );
  }
}
