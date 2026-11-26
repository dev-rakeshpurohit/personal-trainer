// Eat-tab writes and feature-local reads. Meal logs go through Repo (with Undo); the Eat tab's own
// preferences (vrat days, "My dal", katori size, recent logs) live in meta.
//
// NOTE for the shared layer: Repo has no meta setter and no "log food that isn't a planned meal".
// This service wraps Stores.setMeta for the eat.* keys and logs extras via Repo.logMeal with a
// stand-in planned meal (`extra:<slot>:<id>`). Moving both into Repo is a small follow-up.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/store.dart';
import '../../data/services/common.dart';
import '../../data/services/repo.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../state/providers.dart';
import 'eat_logic.dart';
import 'food_db.dart';
import 'food_parser.dart';

class EatService {
  EatService(this.s, this.repo, {required this.newId});
  final Stores s;
  final Repo repo;
  final IdGen newId;

  /// Marks or unmarks a vrat day; returns an undo.
  Future<Undo> toggleVrat(String dayKey) async {
    final before = decodeDays(await s.getMeta<Object?>(kVratDaysKey));
    final next = {...before};
    if (!next.remove(dayKey)) next.add(dayKey);
    await s.setMeta(kVratDaysKey, (next.toList()..sort()));
    return () => s.setMeta(kVratDaysKey, (before.toList()..sort()));
  }

  Future<void> setKatori(PortionSize size) => s.setMeta(kKatoriKey, size.id);

  /// Saves edited rows as the user's own version of each dish ("My dal").
  Future<List<String>> rememberEdited(Iterable<PlateItem> items) async {
    final edited = items.where((i) => i.edited).toList();
    if (edited.isEmpty) return const [];
    final all = Map<String, Object?>.from((await s.getMeta<Object?>(kMyDishesKey)) as Map? ?? const {});
    for (final it in edited) {
      final m = MyDish(
        dishId: it.dish.id,
        kcal: it.mine?.kcal,
        protein: it.mine?.protein,
        oil: it.oil ?? it.mine?.oil,
        size: it.size ?? it.mine?.size,
      );
      all[it.dish.id] = m.toJson();
    }
    await s.setMeta(kMyDishesKey, all);
    return [for (final it in edited) it.dish.name];
  }

  Future<void> forgetMyDish(String dishId) async {
    final all = Map<String, Object?>.from((await s.getMeta<Object?>(kMyDishesKey)) as Map? ?? const {})..remove(dishId);
    await s.setMeta(kMyDishesKey, all);
  }

  /// Keeps the last 12 distinct free-text logs for time-of-day go-tos.
  Future<void> rememberText(String text, MealSlot slot) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final list = RecentLog.decodeAll(await s.getMeta<Object?>(kRecentKey)).where((r) => r.text.toLowerCase() != t.toLowerCase()).toList();
    await s.setMeta(kRecentKey, [RecentLog(t, slot).toJson(), ...list.take(11).map((r) => r.toJson())]);
  }

  /// Logs a reviewed plate. With [forMeal] it replaces that planned meal ("Ate something else");
  /// otherwise it is an extra in [slot]. Returns Repo's undo.
  Future<Undo> logPlate({
    required String dayKey,
    required MealSlot slot,
    required String label,
    required double proteinG,
    required double kcal,
    PlannedMeal? forMeal,
  }) {
    final p = proteinG.roundToDouble();
    final k = kcal.roundToDouble();
    if (forMeal != null) return repo.logMeal(dayKey, forMeal, 'swapped', label: label, proteinG: p, kcal: k);
    return repo.logMeal(dayKey, extraMeal(newId(), slot, proteinG: p, kcal: k), 'eaten', label: label);
  }
}

final eatServiceProvider = Provider<EatService>(
  (ref) => EatService(ref.watch(storesProvider), ref.watch(repoProvider), newId: ref.watch(idGenProvider)),
);

/// Meal logs of the week (Mon–Sun) containing a date; key = the Monday's yyyy-MM-dd.
final weekMealLogsProvider = StreamProvider.family<List<MealLog>, String>((ref, mondayKey) {
  final s = ref.watch(storesProvider);
  final monday = fromDayKey(mondayKey);
  final sunday = dayKey(addDays(monday, 6));
  return s.live({'mealLogs'}, () => s.mealLogs.k1Between(mondayKey, sunday));
});

/// The eat.* preferences in one value.
class EatPrefs {
  const EatPrefs({required this.vratDays, required this.mine, required this.katori, required this.recent});
  final Set<String> vratDays;
  final Map<String, MyDish> mine;
  final PortionSize katori;
  final List<RecentLog> recent;
  static const empty = EatPrefs(vratDays: {}, mine: {}, katori: PortionSize.m, recent: []);
}

final eatPrefsProvider = StreamProvider<EatPrefs>((ref) {
  final s = ref.watch(storesProvider);
  return s.live({'meta'}, () async => EatPrefs(
        vratDays: decodeDays(await s.getMeta<Object?>(kVratDaysKey)),
        mine: MyDish.decodeAll(await s.getMeta<Object?>(kMyDishesKey)),
        katori: decodeKatori(await s.getMeta<Object?>(kKatoriKey)),
        recent: RecentLog.decodeAll(await s.getMeta<Object?>(kRecentKey)),
      ));
});

/// Monday key of the week containing [d].
String mondayKeyOf(DateTime d) => dayKey(weekStartOf(dateOnly(d)));
