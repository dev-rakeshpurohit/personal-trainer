// Port of src/data/repo.ts: body, habit and meal log helpers.
import '../../domain/models.dart';
import '../db/store.dart';
import 'common.dart';

/// Restores the state before a log action.
typedef Undo = Future<void> Function();

class Repo {
  Repo(this.s, {IdGen? newId, Clock? now})
      : newId = newId ?? defaultIdGen,
        now = now ?? systemNow;
  final Stores s;
  final IdGen newId;
  final Clock now;

  /* ------------------------------------------------------------ body */

  Future<BodyLog?> bodyFor(String dayKey) async {
    final l = await s.bodyLogs.whereK1(dayKey);
    return l.isEmpty ? null : l.first;
  }

  /// One body log per day (the PWA's unique `&dayKey` index). Only the given fields change;
  /// pass `clearWaist` / `clearNote` / `clearWeight` to remove a value.
  Future<void> upsertBody(
    String dayKey, {
    double? weightKg,
    double? waistCm,
    String? note,
    bool clearWeight = false,
    bool clearWaist = false,
    bool clearNote = false,
  }) async {
    final existing = await bodyFor(dayKey);
    final patch = <String, Object?>{
      if (weightKg != null || clearWeight) 'weightKg': weightKg,
      if (waistCm != null || clearWaist) 'waistCm': waistCm,
      if (note != null || clearNote) 'note': note,
    };
    if (existing != null) {
      await s.bodyLogs.patch(existing.id, patch);
    } else {
      await s.bodyLogs.put(BodyLog(id: newId(), dayKey: dayKey, weightKg: weightKg, waistCm: waistCm, note: note));
    }
  }

  Future<List<BodyLog>> _bodyDesc() async => (await s.bodyLogs.all())..sort((a, b) => b.dayKey.compareTo(a.dayKey));

  /// Latest logged weight (by day).
  Future<double?> lastWeight() async {
    for (final l in await _bodyDesc()) {
      if (l.weightKg != null) return l.weightKg;
    }
    return null;
  }

  /// Latest logged waist (by day).
  Future<double?> lastWaist() async {
    for (final l in await _bodyDesc()) {
      if (l.waistCm != null) return l.waistCm;
    }
    return null;
  }

  /* ------------------------------------------------------------ habits */

  Future<HabitLog?> _habit(String dayKey, String habitId) async {
    for (final h in await s.habitLogs.whereK1(dayKey)) {
      if (h.habitId == habitId) return h;
    }
    return null;
  }

  Future<void> setHabit(String dayKey, String habitId, double value) async {
    final existing = await _habit(dayKey, habitId);
    await s.habitLogs.put(HabitLog(id: existing?.id ?? newId(), dayKey: dayKey, habitId: habitId, value: value));
  }

  Future<double> getHabit(String dayKey, String habitId) async => (await _habit(dayKey, habitId))?.value ?? 0;

  /* ------------------------------------------------------------ meals */

  Future<MealLog?> _meal(String dayKey, String mealId) async {
    for (final m in await s.mealLogs.whereK1(dayKey)) {
      if (m.plannedMealId == mealId) return m;
    }
    return null;
  }

  /// Log a meal state ('eaten' | 'swapped' | 'skipped'); returns an undo restoring the previous state.
  Future<Undo> logMeal(
    String dayKey,
    PlannedMeal meal,
    String state, {
    String? label,
    double? proteinG,
    double? kcal,
    String? chosenRotation,
  }) async {
    final prev = await _meal(dayKey, meal.id);
    final skipped = state == 'skipped';
    final row = MealLog(
      id: prev?.id ?? newId(),
      dayKey: dayKey,
      plannedMealId: meal.id,
      state: state,
      label: label,
      proteinG: skipped ? 0 : (proteinG ?? meal.proteinG),
      kcal: skipped ? 0 : (kcal ?? meal.kcal),
      chosenRotation: chosenRotation ?? prev?.chosenRotation,
      loggedAt: isoString(now()),
    );
    await s.mealLogs.put(row);
    return () async {
      if (prev != null) {
        await s.mealLogs.put(prev);
      } else {
        await s.mealLogs.delete(row.id);
      }
    };
  }

  /// Remove a day's log of a planned meal; returns an undo.
  Future<Undo> clearMeal(String dayKey, String mealId) async {
    final prev = await _meal(dayKey, mealId);
    if (prev != null) await s.mealLogs.delete(prev.id);
    return () async {
      if (prev != null) await s.mealLogs.put(prev);
    };
  }
}
