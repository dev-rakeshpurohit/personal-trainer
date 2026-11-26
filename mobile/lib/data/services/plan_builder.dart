// Port of src/data/plan-builder.ts plus the DB writers of src/data/seed-import.ts
// (importProgramTemplate, importDietTemplate, createBlankProgram).
// Writes generated / template / AI plans, adapts plans to equipment and applies setup changes.
// History (sessions, sets, meals, body) is never touched.
import '../../domain/ai_plan.dart';
import '../../domain/diet_gen.dart';
import '../../domain/equipment.dart';
import '../../domain/generator.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../db/store.dart';
import '../seed/library_builder.dart';
import 'common.dart';
import 'library_service.dart';

/// Result of [PlanBuilder.importProgramTemplate] (same fields as the TS ImportResult).
typedef ImportResult = ({String programId, int days, int daysWithExercises, int exercises, int mediaIds});

/// Result of [PlanBuilder.importDietTemplate].
typedef DietImportResult = ({String dietPlanId, int meals, int habits});

class PlanBuilder {
  PlanBuilder(this.s, this.seed, {IdGen? newId, Clock? now})
      : newId = newId ?? defaultIdGen,
        now = now ?? systemNow,
        library = LibraryService(s, seed);

  final Stores s;
  final SeedData seed;
  final IdGen newId;
  final Clock now;
  final LibraryService library;

  Future<({int added, int updated})> ensureLibrary() => library.ensureLibrary();

  /* ------------------------------------------------------------ helpers */

  Future<void> _deactivatePrograms() async {
    final active = await s.programs.whereK1('1');
    if (active.isNotEmpty) await s.programs.putAll(active.map((p) => p.copyWith(active: false)));
  }

  Future<void> _deactivateDiets() async {
    final active = await s.dietPlans.whereK1('1');
    if (active.isNotEmpty) await s.dietPlans.putAll(active.map((p) => p.copyWith(active: false)));
  }

  /// Exercises sorted by id (IndexedDB primary-key order, which the PWA's tie-breaks depend on).
  Future<List<Exercise>> _allExercises() async => (await s.exercises.all())..sort((a, b) => a.id.compareTo(b.id));

  /* ------------------------------------------------------------ generated program */

  /// Pure preview of the rule-based program for a profile (nothing is saved).
  GenProgram previewProgram(Profile p) => generateProgram(GenInput(
        goal: p.goal ?? Goal.lean,
        experience: p.experience ?? Experience.beginner,
        days: p.trainingDays,
        sessionMin: p.sessionMin ?? 60,
        equipment: equipmentOf(p),
        library: staticLibrary(seed),
      ));

  Future<String> saveGeneratedProgram(Profile p, {DateTime? today}) async {
    await ensureLibrary();
    final gen = previewProgram(p);
    return saveProgramDays(p, gen.name, gen.days, 'generated:${(p.goal ?? Goal.lean).wire}', today: today);
  }

  /// Write a full week (generated or AI) as the new active program. History is never touched.
  Future<String> saveProgramDays(Profile p, String name, List<GenDay> genDays, String templateId, {DateTime? today}) async {
    final sp = seed.program;
    final eq = equipmentOf(p);
    final bands = eq.contains('bands');
    final programId = newId();
    final days = [
      for (var i = 0; i < genDays.length; i++)
        ProgramDay(
          id: newId(),
          programId: programId,
          weekday: genDays[i].weekday,
          type: genDays[i].type,
          title: genDays[i].title,
          durationMin: genDays[i].durationMin,
          notes: genDays[i].notes,
          order: i,
        ),
    ];
    final planned = <PlannedExercise>[
      for (var i = 0; i < genDays.length; i++)
        for (var j = 0; j < genDays[i].exercises.length; j++) _planned(genDays[i].exercises[j], days[i].id, j),
    ];
    final bandRe = RegExp('band', caseSensitive: false);
    final program = Program(
      id: programId,
      name: name,
      active: true,
      startedOn: dayKey(weekStartOf(today ?? now(), weekStart: 'mon')),
      warmup: [
        const WarmupItem(name: 'Easy cardio or brisk walk', minutes: 5),
        const WarmupItem(name: "World's greatest stretch", reps: '4 / side', exerciseId: 'worlds-greatest-stretch'),
        const WarmupItem(name: 'Glute bridge', reps: '10', exerciseId: 'glute-bridge'),
        if (bands) const WarmupItem(name: 'Band pull-apart', reps: '15', exerciseId: 'band-pull-apart'),
        const WarmupItem(name: '2 light sets of the first exercise', reps: '–'),
      ],
      cooldown: '5 min walk + stretch hips, hamstrings, chest, calves',
      rules: sp.rules.where((r) => bands || !bandRe.hasMatch(r)).toList(),
      progression: ProgressionCfg(
        model: sp.progression.model,
        dumbbellIncrementKg: sp.progression.dumbbellIncrementKg,
        barIncrementKg: sp.progression.barIncrementKg,
        cycle: sp.progression.cycle,
        weeks: seed.research.weeks,
      ),
      templateId: templateId,
    );
    await s.transaction(() async {
      await _deactivatePrograms();
      await s.programs.put(program);
      await s.programDays.putAll(days);
      await s.plannedExercises.putAll(planned);
    });
    return programId;
  }

  PlannedExercise _planned(GenExercise e, String dayId, int order) => PlannedExercise(
        id: newId(),
        dayId: dayId,
        order: order,
        slot: e.slot,
        exerciseId: e.exerciseId,
        swapExerciseId: e.swapExerciseId,
        supersetGroup: e.supersetGroup,
        sets: e.sets,
        repsMin: e.repsMin,
        repsMax: e.repsMax,
        unit: e.unit,
        perSide: e.perSide,
        restSec: e.restSec,
        cue: e.cue,
      );

  /* ------------------------------------------------------------ AI coach plans */

  /// Save an AI coach workout: adds a gym-safe swap for each exercise from its alternates or same-pattern lifts.
  Future<String> saveAiWorkout(Profile p, NormWorkout w, {DateTime? today}) async {
    await ensureLibrary();
    final eq = equipmentOf(p);
    final lib = await _allExercises();
    final byId = {for (final e in lib) e.id: e};
    final days = [
      for (final d in w.days)
        () {
          final used = d.exercises.map((e) => e.exerciseId).toList();
          return GenDay(
            weekday: d.weekday,
            type: d.type,
            title: d.title,
            durationMin: d.durationMin ?? p.sessionMin,
            notes: d.notes,
            exercises: [
              for (final e in d.exercises)
                () {
                  final ex = byId[e.exerciseId];
                  final cands = ex == null
                      ? const <Exercise?>[]
                      : <Exercise?>[
                          ...(ex.alternates ?? const <String>[]).map((id) => byId[id]),
                          ...lib.where((x) => x.pattern != null && x.pattern!.isNotEmpty && x.pattern == ex.pattern && x.source == 'curated'),
                        ];
                  final swap = ex == null ? null : bestReplacement(ex, cands, eq, exclude: used);
                  return GenExercise(
                    slot: e.slot,
                    exerciseId: e.exerciseId,
                    swapExerciseId: swap?.id,
                    supersetGroup: e.supersetGroup,
                    sets: e.sets,
                    repsMin: e.repsMin,
                    repsMax: e.repsMax,
                    unit: e.unit,
                    perSide: e.perSide,
                    restSec: e.restSec,
                    cue: e.cue ?? ex?.cue,
                  );
                }(),
            ],
          );
        }(),
    ];
    return saveProgramDays(p, w.name, days, 'ai-coach', today: today);
  }

  /// Save an AI coach diet as the active diet plan.
  Future<String> saveAiDiet(AiDiet diet) async {
    final dietPlanId = newId();
    await s.transaction(() async {
      await _deactivateDiets();
      await s.dietPlans.put(DietPlan(
        id: dietPlanId,
        name: 'AI coach · ${thousands(diet.kcalTarget)} kcal',
        active: true,
        kcalTarget: jsRound(diet.kcalTarget),
        proteinTargetG: jsRound(diet.proteinTargetG),
      ));
      await s.plannedMeals.putAll([
        for (var i = 0; i < diet.meals.length; i++)
          PlannedMeal(
            id: newId(),
            dietPlanId: dietPlanId,
            order: i,
            time: diet.meals[i].time.padLeft(5, '0'),
            meal: diet.meals[i].meal,
            items: diet.meals[i].items,
            rotate: diet.meals[i].rotate,
            kcal: jsRound(diet.meals[i].kcal).toDouble(),
            proteinG: jsRound(diet.meals[i].proteinG).toDouble(),
            optional: diet.meals[i].optional,
          ),
      ]);
      if (await s.habitDefs.count() == 0) await s.habitDefs.putAll(kDefaultHabits);
    });
    return dietPlanId;
  }

  /* ------------------------------------------------------------ generated diet */

  Future<GeneratedDiet> saveGeneratedDiet(Profile p, {int? kcal, int? protein}) async {
    final age = now().year - p.birthYear;
    final d = generateDiet(DietInput(
      sex: p.sex,
      age: age,
      heightCm: p.heightCm,
      weightKg: p.startWeightKg,
      goalWeightKg: p.goalWeightKg,
      goal: p.goal ?? Goal.lean,
      trainingDays: p.trainingDays.length,
      dietType: p.dietType,
      intolerances: p.intolerances,
      kcalOverride: kcal,
      proteinOverride: protein,
    ));
    final dietPlanId = newId();
    await s.transaction(() async {
      await _deactivateDiets();
      await s.dietPlans.put(DietPlan(
        id: dietPlanId,
        name: 'My ${thousands(d.kcalTarget)} kcal plan',
        active: true,
        kcalTarget: d.kcalTarget,
        proteinTargetG: d.proteinTargetG,
      ));
      await s.plannedMeals.putAll([
        for (var i = 0; i < d.meals.length; i++)
          PlannedMeal(
            id: newId(),
            dietPlanId: dietPlanId,
            order: i,
            time: d.meals[i].time,
            meal: d.meals[i].meal,
            items: d.meals[i].items,
            rotate: d.meals[i].rotate,
            proteinG: d.meals[i].proteinG.toDouble(),
            kcal: d.meals[i].kcal.toDouble(),
            optional: d.meals[i].optional,
            skipOnRestDay: d.meals[i].skipOnRestDay,
          ),
      ]);
      if (await s.habitDefs.count() == 0) await s.habitDefs.putAll(kDefaultHabits);
    });
    return d;
  }

  /* ------------------------------------------------------------ equipment */

  /// Replace/remove planned exercises that need equipment the user doesn't have. Returns readable changes.
  Future<List<String>> adaptActivePlanToEquipment(List<String> equipment) async {
    final program = await s.activeProgram();
    if (program == null) return [];
    await ensureLibrary();
    final days = (await s.programDays.whereK1(program.id))..sort((a, b) => a.order - b.order);
    final exMap = {for (final e in await s.exercises.all()) e.id: e};
    final out = <String>[];
    for (final d in days) {
      final planned = (await s.plannedExercises.whereK1(d.id))..sort((a, b) => a.order - b.order);
      final changes = adaptToEquipment(planned, exMap, equipment);
      for (final c in changes) {
        final from = exMap[c.from]?.name ?? c.from;
        final to = c.to == null ? null : exMap[c.to]?.name;
        switch (c.kind) {
          case PlanChangeKind.replaced:
            await s.plannedExercises.patch(c.plannedExerciseId, {'exerciseId': c.to});
            out.add('${d.title}: $from → $to');
          case PlanChangeKind.removed:
            await s.plannedExercises.delete(c.plannedExerciseId);
            out.add('${d.title}: removed $from (no equipment for it or its alternates)');
          case PlanChangeKind.swapReplaced:
            await s.plannedExercises.patch(c.plannedExerciseId, {'swapExerciseId': c.to});
          case PlanChangeKind.swapRemoved:
            await s.plannedExercises.patch(c.plannedExerciseId, {'swapExerciseId': null});
        }
      }
    }
    return out;
  }

  Future<List<String>> applyTemplateProgram(Profile p, {DateTime? today}) async {
    await importProgramTemplate(trainingDays: p.trainingDays, today: today);
    return adaptActivePlanToEquipment(equipmentOf(p));
  }

  /// Apply a changed setup. History (sessions, sets, meals, body) is always kept.
  Future<List<String>> applySetup(Profile next, {required bool rebuildWorkout, required bool rebuildDiet}) async {
    final notes = <String>[];
    await s.profile.put(next);
    if (rebuildWorkout) {
      if (next.planSource == 'template') {
        notes.addAll(await applyTemplateProgram(next));
      } else {
        await saveGeneratedProgram(next.copyWith(planSource: 'generated'));
        await s.profile.patch(Profile.id, {'planSource': 'generated'});
      }
      notes.insert(0, 'Workout plan rebuilt from your settings');
    } else {
      final changed = await adaptActivePlanToEquipment(equipmentOf(next));
      if (changed.isNotEmpty) notes.addAll(changed);
    }
    if (rebuildDiet) {
      if (next.dietSource == 'template') {
        await importDietTemplate();
      } else {
        await saveGeneratedDiet(next);
        await s.profile.patch(Profile.id, {'dietSource': 'generated'});
      }
      notes.add('Diet plan rebuilt');
    }
    await s.setMeta('setupChangedAt', isoString(now()));
    return notes;
  }

  /* ------------------------------------------------------------ seed writers (seed-import.ts) */

  /// Import the Lean & Athletic template as the active program (remapped to [trainingDays]).
  /// Like the PWA, the template's library entries are written over the stored ones.
  Future<ImportResult> importProgramTemplate({List<Weekday>? trainingDays, DateTime? today}) async {
    final t = buildTemplateProgram(seed, trainingDays: trainingDays, today: today ?? now(), newId: newId);
    await s.transaction(() async {
      await _deactivatePrograms();
      await s.exercises.putAll(t.exercises.values);
      await s.programs.put(t.program);
      await s.programDays.putAll(t.days);
      await s.plannedExercises.putAll(t.planned);
    });
    return (
      programId: t.program.id,
      days: t.days.length,
      daysWithExercises: t.daysWithExercises,
      exercises: t.exercises.length,
      mediaIds: seed.mediaIndex.length,
    );
  }

  /// Import the 2,000 kcal veg + egg diet template (with its habits) as the active diet.
  Future<DietImportResult> importDietTemplate() async {
    final t = buildDietTemplate(seed.diet, newId: newId);
    await s.transaction(() async {
      await _deactivateDiets();
      await s.dietPlans.put(t.plan);
      await s.plannedMeals.putAll(t.meals);
      await s.habitDefs.putAll(t.habits);
      await s.setMeta('adjustmentRules', t.adjustmentRules);
      await s.setMeta('annualChecks', t.annualChecks);
      await s.setMeta('dietConstraints', t.constraints);
    });
    return (dietPlanId: t.plan.id, meals: t.meals.length, habits: t.habits.length);
  }

  /// "Start blank": one empty workout per chosen day, rest otherwise, plus a diet with the given targets.
  /// Returns the new program id.
  Future<String> createBlankProgram(List<Weekday> trainingDays, int kcal, int protein, {DateTime? today}) async {
    final b = createBlankProgramData(trainingDays, kcal, protein,
        seedProgression: seed.program.progression, today: today ?? now(), newId: newId);
    await s.transaction(() async {
      await _deactivatePrograms();
      await _deactivateDiets();
      await s.programs.put(b.program);
      await s.programDays.putAll(b.days);
      await s.dietPlans.put(b.dietPlan);
      await s.habitDefs.putAll(b.habits);
    });
    return b.program.id;
  }
}

/// library_builder's pure createBlankProgram (re-exported under a name that doesn't clash with the writer).
const createBlankProgramData = createBlankProgram;
