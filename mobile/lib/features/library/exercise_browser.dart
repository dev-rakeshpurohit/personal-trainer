// Searchable, filterable, lazy exercise list shared by the Library and the exercise picker.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/equipment.dart';
import '../../domain/models.dart';
import '../../ui/demo_player.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'library_data.dart';

class ExerciseBrowser extends ConsumerStatefulWidget {
  const ExerciseBrowser({super.key, required this.onTap, this.bottomPadding = 0, this.autofocus = false, this.trailingFor});
  final ValueChanged<Exercise> onTap;
  final double bottomPadding;
  final bool autofocus;

  /// Optional trailing widget per row (defaults to a chevron).
  final Widget Function(Exercise e)? trailingFor;

  @override
  ConsumerState<ExerciseBrowser> createState() => _ExerciseBrowserState();
}

class _ExerciseBrowserState extends ConsumerState<ExerciseBrowser> {
  LibraryFilter _f = const LibraryFilter();
  final _search = TextEditingController();
  List<Exercise>? _cacheSrc;
  LibraryFilter? _cacheF;
  List<String>? _cacheEq;
  List<Exercise> _cache = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Exercise> _filtered(List<Exercise> all, List<String> eq) {
    if (!identical(all, _cacheSrc) || !identical(_f, _cacheF) || !identical(eq, _cacheEq)) {
      _cache = filterExercises(all, _f, eq);
      _cacheSrc = all;
      _cacheF = _f;
      _cacheEq = eq;
    }
    return _cache;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final all = ref.watch(sortedExercisesProvider).value;
    final eq = ref.watch(availableEquipmentProvider);
    final inPlan = ref.watch(inPlanIdsProvider);
    final list = all == null ? const <Exercise>[] : _filtered(all, eq);
    final hidden = all == null || !_f.fitsGym ? 0 : all.where((e) => !isAvailable(e, eq)).length;
    final equipChips = [for (final o in kEquipment) if (!_f.fitsGym || eq.contains(o.id)) o];

    Widget chips(List<Widget> children) => SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Rf.gutter),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Center(child: children[i]),
          ),
        );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 4, Rf.gutter, 8),
        child: TextField(
          controller: _search,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          style: RfType.body.copyWith(color: c.text),
          decoration: InputDecoration(
            hintText: 'Search name or muscle',
            prefixIcon: Icon(CupertinoIcons.search, color: c.muted),
            suffixIcon: _f.query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: Icon(CupertinoIcons.clear_circled_solid, color: c.muted),
                    onPressed: () {
                      _search.clear();
                      setState(() => _f = _f.copyWith(query: ''));
                    },
                  ),
          ),
          onChanged: (q) => setState(() => _f = _f.copyWith(query: q)),
        ),
      ),
      chips([
        RfChip(label: 'Fits my gym', icon: CupertinoIcons.checkmark_seal, selected: _f.fitsGym, onTap: () => setState(() => _f = _f.copyWith(fitsGym: !_f.fitsGym))),
        for (final a in kBodyAreas)
          RfChip(label: a.label, selected: _f.area == a.id, onTap: () => setState(() => _f = _f.copyWith(area: () => _f.area == a.id ? null : a.id))),
      ]),
      const SizedBox(height: 6),
      chips([
        RfChip(
          label: 'Bodyweight',
          selected: _f.equipment == kBodyweight,
          onTap: () => setState(() => _f = _f.copyWith(equipment: () => _f.equipment == kBodyweight ? null : kBodyweight)),
        ),
        for (final o in equipChips)
          RfChip(label: o.label, selected: _f.equipment == o.id, onTap: () => setState(() => _f = _f.copyWith(equipment: () => _f.equipment == o.id ? null : o.id))),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(Rf.gutter, 8, Rf.gutter, 4),
        child: Row(children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                all == null ? 'Loading…' : '${list.length} ${list.length == 1 ? 'match' : 'matches'}${hidden > 0 ? ' · $hidden need other equipment' : ''}',
                style: RfType.caption.copyWith(color: c.muted),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: all != null && list.isEmpty
            ? ListView(children: [
                EmptyState(
                  icon: CupertinoIcons.search,
                  title: 'No exercises match',
                  body: _f.fitsGym ? 'Try turning off “Fits my gym” or clearing a filter.' : 'Try a different word or clear the filters.',
                ),
              ])
            : ListView.builder(
                padding: EdgeInsets.only(bottom: widget.bottomPadding),
                itemCount: list.length,
                itemExtent: 76,
                itemBuilder: (context, i) => ExerciseRow(
                  exercise: list[i],
                  inPlan: inPlan.contains(list[i].id),
                  onTap: () => widget.onTap(list[i]),
                  trailing: widget.trailingFor?.call(list[i]),
                ),
              ),
      ),
    ]);
  }
}

String exerciseSubtitle(Exercise e) {
  final parts = [...e.primaryMuscles, ...e.equipment.where((x) => x != 'body only' && x != 'other')];
  return parts.isEmpty ? e.category.wire : parts.join(' · ');
}

class ExerciseRow extends StatelessWidget {
  const ExerciseRow({super.key, required this.exercise, required this.onTap, this.inPlan = false, this.trailing});
  final Exercise exercise;
  final VoidCallback onTap;
  final bool inPlan;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Pressable(
      onTap: onTap,
      semanticLabel: '${exercise.name}${inPlan ? ', in your plan' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.5), width: 0.5))),
        child: Row(children: [
          ExerciseThumb(exercise: exercise, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exercise.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.bodyStrong.copyWith(color: c.text)),
              Text(exerciseSubtitle(exercise), maxLines: 1, overflow: TextOverflow.ellipsis, style: RfType.caption.copyWith(color: c.muted)),
            ]),
          ),
          if (inPlan) ...[const SizedBox(width: 6), StatusPill(label: 'In plan', color: c.accentInk, icon: CupertinoIcons.calendar)],
          const SizedBox(width: 4),
          trailing ?? Icon(CupertinoIcons.chevron_right, size: 18, color: c.muted),
        ]),
      ),
    );
  }
}
