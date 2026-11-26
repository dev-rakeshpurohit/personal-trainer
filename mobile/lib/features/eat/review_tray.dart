// Review tray: every parsed item is a row with a unit/qty chip and (for cooked dishes) an oil chip;
// the meal has a Ghar ka / Bahar ka chip; the footer shows the day impact and Log. Edited dishes
// are remembered as "My dal" for the next parse.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'eat_logic.dart';
import 'eat_screen.dart';
import 'eat_service.dart';
import 'food_db.dart';
import 'food_parser.dart';

Future<void> showReviewTray(BuildContext context, {required EatDay day, String text = '', PlannedMeal? forMeal, required MealSlot slot}) =>
    showRfSheet<void>(context, tall: true, builder: (_) => ReviewTray(day: day, text: text, forMeal: forMeal, slot: slot, host: context));

class ReviewTray extends ConsumerStatefulWidget {
  const ReviewTray({super.key, required this.day, required this.text, required this.slot, required this.host, this.forMeal});
  final EatDay day;
  final String text;
  final MealSlot slot;
  final PlannedMeal? forMeal;

  /// The Eat screen's context, for the toast after the sheet closes.
  final BuildContext host;

  @override
  ConsumerState<ReviewTray> createState() => _ReviewTrayState();
}

class _ReviewTrayState extends ConsumerState<ReviewTray> {
  late List<PlateItem> _items;
  late List<String> _unknown;
  late bool _bahar;
  late MealSlot _slot;
  late PortionSize _katori;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final mine = widget.day.prefs.mine;
    _slot = widget.slot;
    _katori = widget.day.prefs.katori;
    final m = widget.forMeal;
    if (widget.text.trim().isNotEmpty) {
      final r = parseFood(widget.text, mine: mine);
      _items = r.items;
      _unknown = r.unknown;
      _bahar = r.bahar ?? false;
    } else if (m != null) {
      final r = parseFood(m.items.join(', '), mine: mine);
      _items = r.items;
      _unknown = const [];
      _bahar = false;
    } else {
      _items = [];
      _unknown = const [];
      _bahar = false;
    }
  }

  Nutrition get _totals => plateTotals(_items, bahar: _bahar, katori: _katori);

  Future<void> _log() async {
    if (_items.isEmpty || _busy) return;
    setState(() => _busy = true);
    final svc = ref.read(eatServiceProvider);
    final t = _totals;
    final label = '${plateLabel(_items, katori: _katori)}${_bahar ? ' · bahar ka' : ''}';
    final remembered = await svc.rememberEdited(_items);
    final undo = await svc.logPlate(dayKey: widget.day.dayKey, slot: _slot, label: label, proteinG: t.protein, kcal: t.kcal, forMeal: widget.forMeal);
    if (widget.text.trim().isNotEmpty) await svc.rememberText(widget.text, _slot);
    Haptics.setDone();
    if (mounted) Navigator.of(context).pop();
    final host = widget.host;
    if (host.mounted) {
      final mineNote = remembered.isEmpty ? '' : ' · saved as My ${remembered.first.toLowerCase()}';
      showRfToast(host, 'Logged · +${t.protein.round()} g protein$mineNote', icon: CupertinoIcons.checkmark_alt, onUndo: () => undo());
    }
  }

  Future<void> _edit(int i) async {
    final out = await showRfSheet<PlateItem>(context, builder: (_) => _ItemEditor(item: _items[i], katori: _katori, bahar: _bahar));
    if (out != null) setState(() => _items[i] = out);
  }

  void _cycleOil(int i) {
    final it = _items[i];
    final cur = effectiveOil(it, bahar: _bahar);
    final next = OilLevel.values[(cur.index + 1) % OilLevel.values.length];
    setState(() => _items[i] = it.copyWith(oil: next, edited: true));
  }

  Future<void> _add() async {
    final d = await showRfSheet<Dish>(context, tall: true, builder: (_) => _DishPicker(dietType: widget.day.dietType, intolerances: widget.day.intolerances));
    if (d == null) return;
    setState(() => _items.add(PlateItem(dish: d, qty: d.defaultQty, unit: d.unit, mine: widget.day.prefs.mine[d.id])));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final t = _totals;
    final dayP = widget.day.totals.proteinG + t.protein;
    final m = widget.forMeal;
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 12), children: [
            Text(m == null ? 'Review your plate' : 'Instead of ${m.meal.toLowerCase()}', style: RfType.headline.copyWith(color: c.text)),
            const SizedBox(height: 2),
            Text(
              widget.text.trim().isNotEmpty ? '“${widget.text.trim()}”' : 'Tap a chip to fix a portion. Close enough is fine.',
              style: RfType.callout.copyWith(color: c.muted),
            ),
            const SizedBox(height: 14),
            if (m == null) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in MealSlot.values) ...[
                    RfChip(label: s.label, selected: _slot == s, onTap: () => setState(() => _slot = s)),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            for (var i = 0; i < _items.length; i++) ...[
              _ItemRow(
                key: ValueKey('tray-row-$i-${_items[i].dish.id}'),
                item: _items[i],
                bahar: _bahar,
                katori: _katori,
                onEdit: () => _edit(i),
                onOil: () => _cycleOil(i),
                onRemove: () => setState(() => _items.removeAt(i)),
              ),
              const SizedBox(height: 8),
            ],
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing matched yet. Add items from the list.', style: RfType.callout.copyWith(color: c.muted)),
              ),
            if (_unknown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(CupertinoIcons.info_circle, size: 16, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Not in the list yet: ${_unknown.map((u) => '“$u”').join(', ')}. Add the closest dish below.',
                        style: RfType.caption.copyWith(color: c.muted)),
                  ),
                ]),
              ),
            RfButton(label: 'Add item', icon: CupertinoIcons.plus, kind: RfButtonKind.ghost, onPressed: _add),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              RfChip(label: 'Ghar ka', icon: CupertinoIcons.house, selected: !_bahar, onTap: () => setState(() => _bahar = false)),
              RfChip(label: 'Bahar ka', icon: Icons.storefront_outlined, selected: _bahar, onTap: () => setState(() => _bahar = true)),
            ]),
            if (_bahar)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Restaurant food usually has twice the oil: cooked dishes are counted richer.', style: RfType.caption.copyWith(color: c.muted)),
              ),
            const SizedBox(height: 14),
            Text('Your katori (one-time setting)', style: RfType.callout.copyWith(color: c.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in PortionSize.values)
                RfChip(
                  label: '${s.label} · ${kKatoriMl[s]!.round()} ml',
                  selected: _katori == s,
                  onTap: () {
                    setState(() => _katori = s);
                    ref.read(eatServiceProvider).setKatori(s);
                  },
                ),
            ]),
          ]),
        ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line, width: 0.5))),
          padding: const EdgeInsets.fromLTRB(Rf.gutter, 12, Rf.gutter, 12),
          child: Column(children: [
            Semantics(
              liveRegion: true,
              child: Text(
                '+${t.protein.round()} g protein · ${t.kcal.round()} kcal · day ${dayP.round()}/${widget.day.targets.protein.round()} g',
                key: const ValueKey('tray-impact'),
                style: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            const SizedBox(height: 10),
            RfButton(label: 'Log', icon: CupertinoIcons.checkmark_alt, expand: true, busy: _busy, onPressed: _items.isEmpty ? null : _log),
          ]),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({super.key, required this.item, required this.bahar, required this.katori, required this.onEdit, required this.onOil, required this.onRemove});
  final PlateItem item;
  final bool bahar;
  final PortionSize katori;
  final VoidCallback onEdit;
  final VoidCallback onOil;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final n = itemNutrition(item, bahar: bahar, katori: katori);
    return RfCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(item.displayName, style: RfType.bodyStrong.copyWith(color: c.text))),
                if (item.mine != null) ...[
                  const SizedBox(width: 6),
                  StatusPill(label: 'Mine', color: c.accentInk, icon: CupertinoIcons.heart_fill),
                ],
              ]),
              Text('${n.protein.round()} g protein · ${n.kcal.round()} kcal',
                  style: RfType.caption.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          Semantics(
            button: true,
            label: 'Remove ${item.displayName}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox(width: Rf.tap, height: Rf.tap, child: Icon(CupertinoIcons.xmark, size: 18, color: c.muted)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          RfChip(label: qtyLabel(item, katori: katori), icon: CupertinoIcons.slider_horizontal_3, onTap: onEdit),
          if (item.dish.cooked) RfChip(label: effectiveOil(item, bahar: bahar).label, icon: CupertinoIcons.drop, selected: item.oil != null, onTap: onOil),
        ]),
      ]),
    );
  }
}

/// Quantity, unit, size, variant, oil and "my numbers" for one row.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.item, required this.katori, required this.bahar});
  final PlateItem item;
  final PortionSize katori;
  final bool bahar;
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late PlateItem _it = widget.item;
  late bool _custom = widget.item.mine?.kcal != null;

  double get _step => _it.unit == FoodUnit.gm ? 25 : _it.unit == _it.dish.unit ? _it.dish.qtyStep : 0.5;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final d = _it.dish;
    final n = itemNutrition(_it, bahar: widget.bahar, katori: widget.katori);
    final family = familyOf(d);
    final perK = _it.mine?.kcal ?? d.kcal;
    final perP = _it.mine?.protein ?? d.protein;
    final baseLabel = d.unit == FoodUnit.gm ? '100 g' : '1 ${d.unit.id}';
    return SafeArea(
      top: false,
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 16), children: [
        Text(_it.displayName, style: RfType.headline.copyWith(color: c.text)),
        Text('${n.protein.round()} g protein · ${n.kcal.round()} kcal', style: RfType.callout.copyWith(color: c.muted)),
        const SizedBox(height: 16),
        BigStepper(
          value: _it.qty,
          step: _step,
          min: _step,
          max: _it.unit == FoodUnit.gm ? 2000 : 20,
          label: 'Quantity',
          unit: _it.unit == FoodUnit.gm ? 'grams' : _it.unit.id,
          format: _it.unit == FoodUnit.gm ? (v) => '${v.round()}' : fmtQty,
          onChanged: (v) => setState(() => _it = _it.copyWith(qty: v)),
        ),
        const SizedBox(height: 14),
        _label(context, 'Unit'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final u in unitOptions(d)) RfChip(label: u.id, selected: _it.unit == u, onTap: () => setState(() => _it = convertUnit(_it, u, katori: widget.katori))),
        ]),
        if (_it.unit == FoodUnit.katori || (_it.unit == FoodUnit.piece && d.unit == FoodUnit.piece)) ...[
          const SizedBox(height: 14),
          _label(context, _it.unit == FoodUnit.katori ? 'Katori size' : 'Size'),
          Wrap(spacing: 8, children: [
            for (final s in PortionSize.values)
              RfChip(
                label: s.label,
                selected: (_it.size ?? _it.mine?.size ?? (_it.unit == FoodUnit.katori ? widget.katori : PortionSize.m)) == s,
                onTap: () => setState(() => _it = _it.copyWith(size: s, edited: true)),
              ),
          ]),
        ],
        if (family.length > 1) ...[
          const SizedBox(height: 14),
          _label(context, 'Type'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in family)
              RfChip(
                label: f.name,
                selected: f.id == d.id,
                onTap: () => setState(() => _it = PlateItem(dish: f, qty: f.unit == _it.unit ? _it.qty : f.defaultQty, unit: f.unit, size: _it.size, oil: _it.oil)),
              ),
          ]),
        ],
        if (d.cooked) ...[
          const SizedBox(height: 14),
          _label(context, 'Oil'),
          Wrap(spacing: 8, children: [
            for (final o in OilLevel.values)
              RfChip(label: o.label, selected: effectiveOil(_it, bahar: widget.bahar) == o, onTap: () => setState(() => _it = _it.copyWith(oil: o, edited: true))),
          ]),
          const SizedBox(height: 4),
          Text('${d.oilTsp} tsp oil per $baseLabel at normal; 1 tsp ≈ 40 kcal.', style: RfType.caption.copyWith(color: c.muted)),
        ],
        const SizedBox(height: 14),
        RfChip(
          label: _custom ? 'My numbers for $baseLabel' : 'Adjust numbers (my ${d.name.toLowerCase()})',
          icon: CupertinoIcons.pencil,
          selected: _custom,
          onTap: () => setState(() => _custom = !_custom),
        ),
        if (_custom) ...[
          const SizedBox(height: 12),
          BigStepper(
            compact: true,
            value: perP,
            step: 1,
            max: 100,
            label: 'Protein per $baseLabel',
            unit: 'g protein per $baseLabel',
            onChanged: (v) => setState(() => _it = _it.copyWith(mine: MyDish(dishId: d.id, kcal: perK, protein: v, oil: _it.mine?.oil, size: _it.mine?.size), edited: true)),
          ),
          const SizedBox(height: 8),
          BigStepper(
            compact: true,
            value: perK,
            step: 10,
            max: 2000,
            label: 'Calories per $baseLabel',
            unit: 'kcal per $baseLabel',
            format: (v) => '${v.round()}',
            onChanged: (v) => setState(() => _it = _it.copyWith(mine: MyDish(dishId: d.id, kcal: v, protein: perP, oil: _it.mine?.oil, size: _it.mine?.size), edited: true)),
          ),
        ],
        if (_it.edited) ...[
          const SizedBox(height: 10),
          Text('Saved as “My ${d.name.toLowerCase()}” when you log, so next time gives the same numbers.', style: RfType.caption.copyWith(color: c.muted)),
        ],
        const SizedBox(height: 16),
        RfButton(label: 'Done', expand: true, onPressed: () => Navigator.of(context).pop(_it)),
      ]),
    );
  }

  Widget _label(BuildContext context, String t) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t.toUpperCase(), style: RfType.overline.copyWith(color: context.rf.muted)));
}

/// Search the built-in dish table.
class _DishPicker extends StatefulWidget {
  const _DishPicker({required this.dietType, required this.intolerances});
  final DietType dietType;
  final List<String> intolerances;
  @override
  State<_DishPicker> createState() => _DishPickerState();
}

class _DishPickerState extends State<_DishPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final q = _q.trim().toLowerCase();
    final list = allDishes
        .where((d) => dishAllowed(d, widget.dietType, widget.intolerances))
        .where((d) => q.isEmpty || d.name.toLowerCase().contains(q) || d.aliases.any((a) => a.contains(q)))
        .toList();
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Rf.gutter, 0, Rf.gutter, 8),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            style: RfType.body.copyWith(color: c.text),
            decoration: const InputDecoration(hintText: 'Search dishes (dal, paneer, idli…)', prefixIcon: Icon(CupertinoIcons.search)),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (_, i) {
              final d = list[i];
              final per = d.unit == FoodUnit.gm ? '100 g' : '1 ${d.unit.id}';
              return Pressable(
                onTap: () => Navigator.of(context).pop(d),
                semanticLabel: 'Add ${d.name}',
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 8),
                  child: Row(children: [
                    Expanded(child: Text(d.name, style: RfType.body.copyWith(color: c.text))),
                    Text('${d.protein.round()} g · ${d.kcal.round()} kcal / $per', style: RfType.caption.copyWith(color: c.muted)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
