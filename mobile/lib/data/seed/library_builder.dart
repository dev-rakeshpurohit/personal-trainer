// Port of src/data/seed-import.ts (pure parts), src/data/schemas.ts (seed shapes) and the
// library half of src/data/plan-builder.ts. Pure Dart: no Flutter imports, no I/O.
// Callers pass already-decoded JSON (Map/List) and get domain objects back; writing them to
// the database is the data layer's job.
import 'dart:convert';

import '../../domain/models.dart';
import '../../domain/schedule.dart';

/* ================================================================ constants */

/// Bump when the bundled library changes so existing installs pick up new exercises and metadata.
const int kLibraryVersion = 2;

/// Library metadata we own and may refresh on existing rows (never the user's own settings like Track weight).
const List<String> kRefreshFields = [
  'demoId',
  'secondaryMuscles',
  'bodyPart',
  'source',
  'instructions',
  'pattern',
  'level',
  'primaryMuscles',
];

/// Seed swaps that have no free-exercise-db id get the closest available demo (doc 09 notes).
const Map<String, String> kNullSwapImages = {
  'Outdoor brisk walk later in the day': 'Trail_Running_Walking',
  'Weighted plate crunch': 'Weighted_Crunches',
  'Band face pull': 'Band_Pull_Apart',
  'Dumbbell swing': 'Vertical_Swing',
  "Farmer's march in place, 40 s": 'Farmers_Walk',
};

const Set<String> kBodyweightEquip = {'body only', 'bands', 'none', 'foam roll', 'exercise ball'};

const List<HabitDef> kDefaultHabits = [
  HabitDef(id: 'water', label: 'Water', kind: 'number', target: 3000, unit: 'ml', order: 0),
  HabitDef(id: 'steps', label: 'Steps', kind: 'number', target: 8000, unit: 'steps', order: 1),
  HabitDef(id: 'sleep', label: 'Sleep', kind: 'number', target: 7, unit: 'h', order: 2),
];

/* ================================================================ slug */

final RegExp _apostrophes = RegExp('[’\']');
final RegExp _nonAlnum = RegExp('[^a-z0-9]+');
final RegExp _edgeDash = RegExp(r'^-|-$');

/// Same as src/lib/slug.ts: "Farmer's carry" → "farmers-carry".
String slugify(String s) =>
    s.toLowerCase().replaceAll(_apostrophes, '').replaceAll(_nonAlnum, '-').replaceAll(_edgeDash, '');

/* ================================================================ defensive JSON parsing
 * Mirrors the zod schemas in src/data/schemas.ts: required fields must be present with the
 * right type (otherwise a FormatException naming the path is thrown), optional fields may be
 * missing or null, unknown keys are ignored.
 */

Never _bad(String path, String expected, Object? got) =>
    throw FormatException('Seed JSON: $path should be $expected, got ${got.runtimeType}: ${_preview(got)}');

String _preview(Object? v) {
  final s = jsonEncode(v);
  return s.length > 80 ? '${s.substring(0, 80)}…' : s;
}

Map<String, Object?> _map(Object? v, String path) => v is Map ? v.cast<String, Object?>() : _bad(path, 'an object', v);
List<Object?> _list(Object? v, String path) => v is List ? v.cast<Object?>() : _bad(path, 'an array', v);
List<Object?>? _listOpt(Object? v, String path) => v == null ? null : _list(v, path);
String _str(Object? v, String path) => v is String ? v : _bad(path, 'a string', v);
String? _strOpt(Object? v, String path) => v == null ? null : _str(v, path);
num _num(Object? v, String path) => v is num ? v : _bad(path, 'a number', v);
num? _numOpt(Object? v, String path) => v == null ? null : _num(v, path);
bool _bool(Object? v, String path) => v is bool ? v : _bad(path, 'a boolean', v);
bool? _boolOpt(Object? v, String path) => v == null ? null : _bool(v, path);
List<String> _strs(Object? v, String path) {
  final l = _list(v, path);
  return [for (var i = 0; i < l.length; i++) _str(l[i], '$path[$i]')];
}

List<String>? _strsOpt(Object? v, String path) => v == null ? null : _strs(v, path);
int _intOf(num n) => n is int ? n : n.round();

T _enum<T extends Wire>(List<T> values, Object? v, String path) {
  for (final e in values) {
    if (e.wire == v) return e;
  }
  return _bad(path, 'one of ${values.map((e) => e.wire).join('|')}', v);
}

/// `freeDbId` is tri-state in the seed: absent (no library entry), null (entry without photos), or an id.
class _FreeDb {
  const _FreeDb(this.present, this.id);
  final bool present;
  final String? id;
  static _FreeDb of(Map<String, Object?> j, String path) =>
      _FreeDb(j.containsKey('freeDbId'), _strOpt(j['freeDbId'], '$path.freeDbId'));
}

/* ================================================================ seed program */

class SeedTarget {
  const SeedTarget({required this.sets, required this.repsMin, required this.repsMax, required this.unit, required this.perSide});
  final int sets;
  final num repsMin;
  final num repsMax;
  final Unit unit;
  final bool perSide;
  factory SeedTarget.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    final sets = _num(j['sets'], '$path.sets');
    if (sets is! int && sets != sets.roundToDouble() || sets <= 0) _bad('$path.sets', 'a positive integer', sets);
    return SeedTarget(
      sets: _intOf(sets),
      repsMin: _num(j['repsMin'], '$path.repsMin'),
      repsMax: _num(j['repsMax'], '$path.repsMax'),
      unit: _enum(Unit.values, j['unit'], '$path.unit'),
      perSide: _bool(j['perSide'], '$path.perSide'),
    );
  }
}

class SeedSwap {
  const SeedSwap({required this.name, this.freeDbId, this.youtubeQuery, this.reason});
  final String name;
  final String? freeDbId;
  final String? youtubeQuery;
  final String? reason;
  factory SeedSwap.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    return SeedSwap(
      name: _str(j['name'], '$path.name'),
      freeDbId: _strOpt(j['freeDbId'], '$path.freeDbId'),
      youtubeQuery: _strOpt(j['youtubeQuery'], '$path.youtubeQuery'),
      reason: _strOpt(j['reason'], '$path.reason'),
    );
  }
}

class SeedExercise {
  const SeedExercise({
    required this.slot,
    required this.name,
    this.freeDbId,
    this.youtubeQuery,
    this.cue,
    required this.target,
    required this.restSec,
    this.supersetGroup,
    this.swap,
  });
  final String slot;
  final String name;
  final String? freeDbId;
  final String? youtubeQuery;
  final String? cue;
  final SeedTarget target;
  final num restSec;
  final String? supersetGroup;
  final SeedSwap? swap;
  factory SeedExercise.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    final rest = _num(j['restSec'], '$path.restSec');
    if (rest < 0) _bad('$path.restSec', 'a number >= 0', rest);
    return SeedExercise(
      slot: _str(j['slot'], '$path.slot'),
      name: _str(j['name'], '$path.name'),
      freeDbId: _strOpt(j['freeDbId'], '$path.freeDbId'),
      youtubeQuery: _strOpt(j['youtubeQuery'], '$path.youtubeQuery'),
      cue: _strOpt(j['cue'], '$path.cue'),
      target: SeedTarget.fromJson(j['target'], '$path.target'),
      restSec: rest,
      supersetGroup: _strOpt(j['supersetGroup'], '$path.supersetGroup'),
      swap: j['swap'] == null ? null : SeedSwap.fromJson(j['swap'], '$path.swap'),
    );
  }
}

class SeedWarmupItem {
  const SeedWarmupItem({required this.name, this.minutes, this.reps, required this.hasFreeDbId, this.freeDbId, this.youtubeQuery});
  final String name;
  final num? minutes;
  final String? reps;

  /// True when the seed lists `freeDbId` (even as null): the item then becomes a library exercise.
  final bool hasFreeDbId;
  final String? freeDbId;
  final String? youtubeQuery;
  factory SeedWarmupItem.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    final f = _FreeDb.of(j, path);
    return SeedWarmupItem(
      name: _str(j['name'], '$path.name'),
      minutes: _numOpt(j['minutes'], '$path.minutes'),
      reps: _strOpt(j['reps'], '$path.reps'),
      hasFreeDbId: f.present,
      freeDbId: f.id,
      youtubeQuery: _strOpt(j['youtubeQuery'], '$path.youtubeQuery'),
    );
  }
}

class SeedDay {
  const SeedDay({required this.weekday, required this.type, required this.title, this.durationMin, this.notes, this.exercises});
  final Weekday weekday;
  final DayType type;
  final String title;
  final num? durationMin;
  final String? notes;
  final List<SeedExercise>? exercises;

  /// Same as the TS spread `{ ...d, weekday, type, title }`.
  SeedDay copyWith({Weekday? weekday, DayType? type, String? title}) => SeedDay(
        weekday: weekday ?? this.weekday,
        type: type ?? this.type,
        title: title ?? this.title,
        durationMin: durationMin,
        notes: notes,
        exercises: exercises,
      );

  static final DayLens<SeedDay> lens = DayLens<SeedDay>(
    weekday: (d) => d.weekday,
    type: (d) => d.type,
    title: (d) => d.title,
    copy: (d, weekday, type, title) => d.copyWith(weekday: weekday, type: type, title: title),
  );

  factory SeedDay.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    final ex = _listOpt(j['exercises'], '$path.exercises');
    return SeedDay(
      weekday: _enum(Weekday.values, j['weekday'], '$path.weekday'),
      type: _enum(DayType.values, j['type'], '$path.type'),
      title: _str(j['title'], '$path.title'),
      durationMin: _numOpt(j['durationMin'], '$path.durationMin'),
      notes: _strOpt(j['notes'], '$path.notes'),
      exercises: ex == null ? null : [for (var i = 0; i < ex.length; i++) SeedExercise.fromJson(ex[i], '$path.exercises[$i]')],
    );
  }
}

class SeedProgram {
  const SeedProgram({
    required this.id,
    required this.name,
    this.warmupDurationMin,
    required this.warmup,
    required this.cooldown,
    required this.rules,
    required this.progression,
    required this.days,
  });
  final String id;
  final String name;
  final num? warmupDurationMin;
  final List<SeedWarmupItem> warmup;
  final String cooldown;
  final List<String> rules;

  /// model, increments and cycle (no `weeks`; those come from the research file).
  final ProgressionCfg progression;
  final List<SeedDay> days;

  factory SeedProgram.fromJson(Object? raw) {
    const p = 'program';
    final j = _map(raw, p);
    final w = _map(j['warmup'], '$p.warmup');
    final items = _list(w['items'], '$p.warmup.items');
    final pr = _map(j['progression'], '$p.progression');
    if (pr['model'] != 'double_progression') _bad('$p.progression.model', '"double_progression"', pr['model']);
    final cycle = _list(pr['cycle'], '$p.progression.cycle');
    final days = _list(j['days'], '$p.days');
    return SeedProgram(
      id: _str(j['id'], '$p.id'),
      name: _str(j['name'], '$p.name'),
      warmupDurationMin: _numOpt(w['durationMin'], '$p.warmup.durationMin'),
      warmup: [for (var i = 0; i < items.length; i++) SeedWarmupItem.fromJson(items[i], '$p.warmup.items[$i]')],
      cooldown: _str(j['cooldown'], '$p.cooldown'),
      rules: _strs(j['rules'], '$p.rules'),
      progression: ProgressionCfg(
        model: 'double_progression',
        dumbbellIncrementKg: _num(pr['dumbbellIncrementKg'], '$p.progression.dumbbellIncrementKg').toDouble(),
        barIncrementKg: _num(pr['barIncrementKg'], '$p.progression.barIncrementKg').toDouble(),
        cycle: [
          for (var i = 0; i < cycle.length; i++)
            () {
              final path = '$p.progression.cycle[$i]';
              final c = _map(cycle[i], path);
              final weeks = _list(c['weeks'], '$path.weeks');
              return CycleEntry(
                weeks: [for (var k = 0; k < weeks.length; k++) _intOf(_num(weeks[k], '$path.weeks[$k]'))],
                rir: _intOf(_num(c['rir'], '$path.rir')),
                deload: _boolOpt(c['deload'], '$path.deload') ?? false,
                note: _strOpt(c['note'], '$path.note'),
              );
            }(),
        ],
      ),
      days: [for (var i = 0; i < days.length; i++) SeedDay.fromJson(days[i], '$p.days[$i]')],
    );
  }
}

/* ================================================================ seed diet */

class SeedMeal {
  const SeedMeal({
    required this.time,
    required this.meal,
    required this.items,
    this.rotate,
    required this.proteinG,
    required this.kcal,
    this.optional,
    this.skipOnRestDay,
  });
  final String time;
  final String meal;
  final List<String> items;
  final List<String>? rotate;
  final num proteinG;
  final num kcal;
  final bool? optional;
  final bool? skipOnRestDay;
  factory SeedMeal.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    return SeedMeal(
      time: _str(j['time'], '$path.time'),
      meal: _str(j['meal'], '$path.meal'),
      items: _strs(j['items'], '$path.items'),
      rotate: _strsOpt(j['rotate'], '$path.rotate'),
      proteinG: _num(j['proteinG'], '$path.proteinG'),
      kcal: _num(j['kcal'], '$path.kcal'),
      optional: _boolOpt(j['optional'], '$path.optional'),
      skipOnRestDay: _boolOpt(j['skipOnRestDay'], '$path.skipOnRestDay'),
    );
  }
}

class SeedHabit {
  const SeedHabit({required this.id, required this.label, this.target, this.unit});
  final String id;
  final String label;
  final num? target;
  final String? unit;
  factory SeedHabit.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    return SeedHabit(
      id: _str(j['id'], '$path.id'),
      label: _str(j['label'], '$path.label'),
      target: _numOpt(j['target'], '$path.target'),
      unit: _strOpt(j['unit'], '$path.unit'),
    );
  }
}

class AdjustmentRule {
  const AdjustmentRule({required this.ifText, required this.then});
  final String ifText;
  final String then;
  Map<String, Object?> toJson() => {'if': ifText, 'then': then};
}

class SeedDiet {
  const SeedDiet({
    required this.id,
    required this.name,
    required this.kcalTarget,
    required this.proteinTargetG,
    this.constraints,
    required this.trainingDay,
    required this.habits,
    this.adjustmentRules,
    this.annualChecks,
  });
  final String id;
  final String name;
  final num kcalTarget;
  final num proteinTargetG;
  final List<String>? constraints;
  final List<SeedMeal> trainingDay;
  final List<SeedHabit> habits;
  final List<AdjustmentRule>? adjustmentRules;
  final List<String>? annualChecks;
  factory SeedDiet.fromJson(Object? raw) {
    const p = 'diet';
    final j = _map(raw, p);
    final meals = _list(j['trainingDay'], '$p.trainingDay');
    final habits = _list(j['habits'], '$p.habits');
    final rules = _listOpt(j['adjustmentRules'], '$p.adjustmentRules');
    return SeedDiet(
      id: _str(j['id'], '$p.id'),
      name: _str(j['name'], '$p.name'),
      kcalTarget: _num(j['kcalTarget'], '$p.kcalTarget'),
      proteinTargetG: _num(j['proteinTargetG'], '$p.proteinTargetG'),
      constraints: _strsOpt(j['constraints'], '$p.constraints'),
      trainingDay: [for (var i = 0; i < meals.length; i++) SeedMeal.fromJson(meals[i], '$p.trainingDay[$i]')],
      habits: [for (var i = 0; i < habits.length; i++) SeedHabit.fromJson(habits[i], '$p.habits[$i]')],
      adjustmentRules: rules == null
          ? null
          : [
              for (var i = 0; i < rules.length; i++)
                () {
                  final r = _map(rules[i], '$p.adjustmentRules[$i]');
                  return AdjustmentRule(ifText: _str(r['if'], '$p.adjustmentRules[$i].if'), then: _str(r['then'], '$p.adjustmentRules[$i].then'));
                }(),
            ],
      annualChecks: _strsOpt(j['annualChecks'], '$p.annualChecks'),
    );
  }
}

/* ================================================================ media index (free-exercise-db) */

class MediaEntry {
  const MediaEntry({required this.id, required this.name, required this.instructions, required this.primaryMuscles, required this.equipment, required this.category});
  final String id;
  final String name;
  final List<String> instructions;
  final List<String> primaryMuscles;
  final List<String> equipment;
  final String category;
  factory MediaEntry.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    return MediaEntry(
      id: _str(j['id'], '$path.id'),
      name: _str(j['name'], '$path.name'),
      instructions: _strs(j['instructions'], '$path.instructions'),
      primaryMuscles: _strs(j['primaryMuscles'], '$path.primaryMuscles'),
      equipment: _strs(j['equipment'], '$path.equipment'),
      category: _str(j['category'], '$path.category'),
    );
  }
}

List<MediaEntry> parseMediaIndex(Object? raw) {
  final l = _list(raw, 'mediaIndex');
  return [for (var i = 0; i < l.length; i++) MediaEntry.fromJson(l[i], 'mediaIndex[$i]')];
}

/* ================================================================ research (alternates + periodization) */

class ResearchAlternate {
  const ResearchAlternate({required this.name, required this.freeDbId, required this.equipment, required this.level, this.why, required this.unit});
  final String name;
  final String freeDbId;
  final String equipment;
  final num level;
  final String? why;
  final Unit unit;
  factory ResearchAlternate.fromJson(Object? raw, String path) {
    final j = _map(raw, path);
    return ResearchAlternate(
      name: _str(j['name'], '$path.name'),
      freeDbId: _str(j['freeDbId'], '$path.freeDbId'),
      equipment: _str(j['equipment'], '$path.equipment'),
      level: _num(j['level'], '$path.level'),
      why: _strOpt(j['why'], '$path.why'),
      unit: _enum(Unit.values, j['unit'], '$path.unit'),
    );
  }
}

class HomeFallbackItem {
  const HomeFallbackItem({required this.name, required this.freeDbId, required this.sets, required this.reps});
  final String name;
  final String freeDbId;
  final num sets;
  final String reps;
}

class Research {
  const Research({required this.patterns, required this.alternates, required this.weeks, required this.homeFallback, required this.parentTips});
  final Map<String, String> patterns;
  final Map<String, List<ResearchAlternate>> alternates;

  /// periodization.weeks with `setsDelta` defaulted to 0 (as importProgramTemplate does).
  /// Note: the seed's `setsMultiplier` is not part of the shared WeekFocus model and is dropped.
  final List<WeekFocus> weeks;
  final List<HomeFallbackItem> homeFallback;
  final List<String> parentTips;

  factory Research.fromJson(Object? raw) {
    const p = 'research';
    final j = _map(raw, p);
    final pat = _map(j['patterns'], '$p.patterns');
    final alts = _map(j['alternates'], '$p.alternates');
    final weeks = _list(_map(j['periodization'], '$p.periodization')['weeks'], '$p.periodization.weeks');
    final home = _list(j['homeFallback'], '$p.homeFallback');
    return Research(
      patterns: {for (final e in pat.entries) e.key: _str(e.value, '$p.patterns.${e.key}')},
      alternates: {
        for (final e in alts.entries)
          e.key: () {
            final l = _list(e.value, '$p.alternates.${e.key}');
            return [for (var i = 0; i < l.length; i++) ResearchAlternate.fromJson(l[i], '$p.alternates.${e.key}[$i]')];
          }(),
      },
      weeks: [
        for (var i = 0; i < weeks.length; i++)
          () {
            final path = '$p.periodization.weeks[$i]';
            final w = _map(weeks[i], path);
            return WeekFocus(
              week: _intOf(_num(w['week'], '$path.week')),
              rirMain: _intOf(_num(w['rirMain'], '$path.rirMain')),
              rirAccessory: _intOf(_num(w['rirAccessory'], '$path.rirAccessory')),
              focus: _str(w['focus'], '$path.focus'),
              note: _str(w['note'], '$path.note'),
              setsDelta: _intOf(_numOpt(w['setsDelta'], '$path.setsDelta') ?? 0),
              deload: _bool(w['deload'], '$path.deload'),
            );
          }(),
      ],
      homeFallback: [
        for (var i = 0; i < home.length; i++)
          () {
            final path = '$p.homeFallback[$i]';
            final h = _map(home[i], path);
            return HomeFallbackItem(
              name: _str(h['name'], '$path.name'),
              freeDbId: _str(h['freeDbId'], '$path.freeDbId'),
              sets: _num(h['sets'], '$path.sets'),
              reps: _str(h['reps'], '$path.reps'),
            );
          }(),
      ],
      parentTips: _strs(j['parentTips'], '$p.parentTips'),
    );
  }
}

/* ================================================================ demo map + curated meta */

class DemoMap {
  const DemoMap({required this.map, required this.files, required this.fallbackPhotos});

  /// Curated exercise id → 3D demo id (null = keep the free-exercise-db photos).
  final Map<String, String?> map;

  /// Demo id → source file in the dataset.
  final Map<String, String> files;

  /// free-exercise-db ids whose photos are still needed (no 3D demo).
  final List<String> fallbackPhotos;

  factory DemoMap.fromJson(Object? raw) {
    const p = 'demoMap';
    final j = _map(raw, p);
    final m = _map(j['map'], '$p.map');
    final f = j['files'] == null ? const <String, Object?>{} : _map(j['files'], '$p.files');
    return DemoMap(
      map: {for (final e in m.entries) e.key: _strOpt(e.value, '$p.map.${e.key}')},
      files: {for (final e in f.entries) e.key: _str(e.value, '$p.files.${e.key}')},
      fallbackPhotos: _strsOpt(j['fallbackPhotos'], '$p.fallbackPhotos') ?? const [],
    );
  }
}

class CuratedMetaEntry {
  const CuratedMetaEntry({this.secondaryMuscles, required this.bodyPart, required this.instructions});
  final List<String>? secondaryMuscles;
  final String bodyPart;
  final List<String> instructions;
}

/// library.curated-meta.json `meta`: demo id → helper muscles, body part, instructions.
Map<String, CuratedMetaEntry> parseCuratedMeta(Object? raw) {
  const p = 'curatedMeta';
  final m = _map(_map(raw, p)['meta'], '$p.meta');
  return {
    for (final e in m.entries)
      e.key: () {
        final path = '$p.meta.${e.key}';
        final j = _map(e.value, path);
        return CuratedMetaEntry(
          secondaryMuscles: _strsOpt(j['secondaryMuscles'], '$path.secondaryMuscles'),
          bodyPart: _str(j['bodyPart'], '$path.bodyPart'),
          instructions: _strs(j['instructions'], '$path.instructions'),
        );
      }(),
  };
}

/// library.dataset.json `exercises` (already in Exercise JSON shape).
List<Exercise> parseDatasetExercises(Object? raw) {
  const p = 'dataset';
  final l = _list(_map(raw, p)['exercises'], '$p.exercises');
  return [
    for (var i = 0; i < l.length; i++)
      () {
        final j = _map(l[i], '$p.exercises[$i]');
        _str(j['id'], '$p.exercises[$i].id');
        return Exercise.fromJson(j);
      }(),
  ];
}

/* ================================================================ seed bundle */

/// Every bundled seed, parsed. Build with [SeedData.fromJson] from decoded JSON.
class SeedData {
  SeedData({
    required this.program,
    required this.diet,
    required this.mediaIndex,
    required this.research,
    required this.demoMap,
    required this.curatedMeta,
    required this.dataset,
  });

  /// Keys match the asset file names without `.json` (see SeedAssets in seed_loader.dart).
  factory SeedData.fromJson({
    required Object? program,
    required Object? diet,
    required Object? mediaIndex,
    required Object? research,
    required Object? demoMap,
    required Object? curatedMeta,
    required Object? dataset,
  }) =>
      SeedData(
        program: SeedProgram.fromJson(program),
        diet: SeedDiet.fromJson(diet),
        mediaIndex: parseMediaIndex(mediaIndex),
        research: Research.fromJson(research),
        demoMap: DemoMap.fromJson(demoMap),
        curatedMeta: parseCuratedMeta(curatedMeta),
        dataset: parseDatasetExercises(dataset),
      );

  final SeedProgram program;
  final SeedDiet diet;
  final List<MediaEntry> mediaIndex;
  final Research research;
  final DemoMap demoMap;
  final Map<String, CuratedMetaEntry> curatedMeta;
  final List<Exercise> dataset;

  List<Exercise>? _curated;
  List<Exercise>? _static;
}

/* ================================================================ exercise library */

Category _category(String? dbCat, List<String> muscles, Unit unit) {
  if (unit == Unit.minutes || dbCat == 'cardio') return Category.cardio;
  if (dbCat == 'stretching') return Category.mobility;
  if (dbCat == 'plyometrics' || dbCat == 'olympic weightlifting') return Category.power;
  if (muscles.contains('abdominals')) return Category.core;
  return Category.strength;
}

/// Build library entries for every exercise/swap/warm-up item in the seed (upsert by slug),
/// add research alternates and patterns, then enrich with 3D-demo metadata. Same as TS buildExercises.
Map<String, Exercise> buildExercises(
  SeedProgram program,
  List<MediaEntry> media, {
  Research? research,
  DemoMap? demoMap,
  Map<String, CuratedMetaEntry>? curatedMeta,
}) {
  final byDb = {for (final m in media) m.id: m};
  final out = <String, Exercise>{};

  String add(String name, String? rawId, Unit unit, {String? cue, String? youtubeQuery, int? level, String? pattern, String? equipment}) {
    final id = slugify(name);
    final freeDbId = rawId ?? kNullSwapImages[name];
    final m = freeDbId != null ? byDb[freeDbId] : null;
    final List<String> equip = (m != null && m.equipment.isNotEmpty)
        ? m.equipment
        : equipment != null
            ? [equipment == 'bodyweight' ? 'body only' : equipment]
            : const [];
    final cat = _category(m?.category, m?.primaryMuscles ?? const [], unit);
    final prev = out[id];
    out[id] = Exercise(
      id: id,
      name: name,
      freeDbId: freeDbId,
      primaryMuscles: m?.primaryMuscles ?? const [],
      equipment: equip,
      category: cat,
      cue: prev?.cue ?? cue,
      instructions: m?.instructions,
      youtubeQuery: prev?.youtubeQuery ?? youtubeQuery,
      custom: false,
      isBodyweight: cat == Category.cardio || cat == Category.mobility || m == null || equip.every(kBodyweightEquip.contains),
      defaultUnit: prev?.defaultUnit ?? unit,
      level: prev?.level ?? level,
      pattern: prev?.pattern ?? pattern,
      alternates: prev?.alternates,
    );
    return id;
  }

  void addAlternates(String name) {
    final alts = research?.alternates[name];
    if (alts == null) return;
    final pattern = research?.patterns[name];
    final ids = [for (final a in alts) add(a.name, a.freeDbId, a.unit, level: _intOf(a.level), pattern: pattern, equipment: a.equipment)];
    final parent = out[slugify(name)]!;
    out[parent.id] = _rebuild(parent, pattern: parent.pattern ?? pattern, alternates: ids.where((x) => x != parent.id).toList());
  }

  for (final w in program.warmup) {
    if (w.hasFreeDbId) add(w.name, w.freeDbId, Unit.reps, youtubeQuery: w.youtubeQuery);
  }
  for (final d in program.days) {
    for (final e in d.exercises ?? const <SeedExercise>[]) {
      add(e.name, e.freeDbId, e.target.unit, cue: e.cue, youtubeQuery: e.youtubeQuery);
      final s = e.swap;
      if (s != null) add(s.name, s.freeDbId, e.target.unit, youtubeQuery: s.youtubeQuery);
    }
  }
  for (final d in program.days) {
    for (final e in d.exercises ?? const <SeedExercise>[]) {
      addAlternates(e.name);
      final s = e.swap;
      if (s != null) addAlternates(s.name);
    }
  }

  // Curated exercises that share a 3D demo get its helper muscles and matching instructions.
  final dm = demoMap?.map ?? const <String, String?>{};
  final meta = curatedMeta ?? const <String, CuratedMetaEntry>{};
  for (final id in out.keys.toList()) {
    final ex = out[id]!;
    final demoId = dm[id];
    final m = demoId != null ? meta[demoId] : null;
    out[id] = _rebuild(
      ex,
      source: 'curated',
      demoId: demoId,
      secondaryMuscles: m?.secondaryMuscles?.where((x) => !ex.primaryMuscles.contains(x)).toList(),
      bodyPart: m?.bodyPart,
      instructions: (m != null && m.instructions.isNotEmpty) ? m.instructions : ex.instructions,
      setEnrichment: true,
    );
  }
  return out;
}

/// Copy with explicit values (Exercise.copyWith can't clear fields; the TS spread can).
Exercise _rebuild(
  Exercise e, {
  String? pattern,
  List<String>? alternates,
  String? source,
  String? demoId,
  List<String>? secondaryMuscles,
  String? bodyPart,
  List<String>? instructions,
  bool setEnrichment = false,
}) =>
    Exercise(
      id: e.id,
      name: e.name,
      freeDbId: e.freeDbId,
      primaryMuscles: e.primaryMuscles,
      equipment: e.equipment,
      category: e.category,
      cue: e.cue,
      instructions: setEnrichment ? instructions : e.instructions,
      youtubeQuery: e.youtubeQuery,
      custom: e.custom,
      isBodyweight: e.isBodyweight,
      defaultUnit: e.defaultUnit,
      pattern: pattern ?? e.pattern,
      level: e.level,
      alternates: alternates ?? e.alternates,
      secondaryMuscles: setEnrichment ? secondaryMuscles : e.secondaryMuscles,
      bodyPart: setEnrichment ? bodyPart : e.bodyPart,
      demoId: setEnrichment ? demoId : e.demoId,
      source: setEnrichment ? source : e.source,
    );

/// Curated plan exercises (seed + research alternates), enriched with 3D demo metadata. Cached per [SeedData].
List<Exercise> curatedLibrary(SeedData s) => s._curated ??= List.unmodifiable(
      buildExercises(s.program, s.mediaIndex, research: s.research, demoMap: s.demoMap, curatedMeta: s.curatedMeta).values,
    );

/// Full static library: curated + ~1,100 exercises from the 3D dataset. Cached per [SeedData].
List<Exercise> staticLibrary(SeedData s) => s._static ??= List.unmodifiable([...curatedLibrary(s), ...s.dataset]);

/// Result of comparing the bundled library with stored rows (the pure half of TS ensureLibrary).
class LibraryUpgrade {
  const LibraryUpgrade({required this.missing, required this.updates});
  final List<Exercise> missing;
  final List<Exercise> updates;
}

/// Library rows to add, and existing non-custom rows whose [kRefreshFields] differ from the bundle.
/// User-edited fields (cue, Track weight, alternates) are never touched.
LibraryUpgrade planLibraryUpgrade(List<Exercise> library, Map<String, Exercise> existing) {
  final missing = <Exercise>[];
  final updates = <Exercise>[];
  for (final e in library) {
    final cur = existing[e.id];
    if (cur == null) {
      missing.add(e);
      continue;
    }
    if (cur.custom) continue;
    final next = cur.toJson();
    final lib = e.toJson();
    var changed = false;
    for (final k in kRefreshFields) {
      if (!lib.containsKey(k)) continue; // TS: v !== undefined
      if (jsonEncode(next[k]) != jsonEncode(lib[k])) {
        next[k] = lib[k];
        changed = true;
      }
    }
    if (changed) updates.add(Exercise.fromJson(next));
  }
  return LibraryUpgrade(missing: missing, updates: updates);
}

/* ================================================================ remapDays */

/// Accessors that let [remapDays] work on any day-like type (SeedDay, ProgramDay, generated days…).
class DayLens<T> {
  const DayLens({required this.weekday, required this.type, required this.title, required this.copy});
  final Weekday Function(T) weekday;
  final DayType Function(T) type;
  final String Function(T) title;

  /// Same as the TS spread `{ ...d, weekday, type, title }` (keep every other field).
  final T Function(T d, Weekday weekday, DayType type, String title) copy;
}

final DayLens<ProgramDay> programDayLens = DayLens<ProgramDay>(
  weekday: (d) => d.weekday,
  type: (d) => d.type,
  title: (d) => d.title,
  copy: (d, weekday, type, title) => d.copyWith(weekday: weekday, type: type, title: title),
);

int _wdOrder(Weekday w) => kWeekdays.indexOf(w);

/// Remap template training days onto the user's chosen weekdays (in order).
/// Unchosen weekdays become rest, except the template's active-recovery day which is kept.
/// Returns [days] itself (identical) when nothing changes.
List<T> remapDays<T>(List<T> days, List<Weekday>? chosen, DayLens<T> lens) {
  if (chosen == null || chosen.isEmpty) return days;
  final training = days.where((d) => lens.type(d).isTraining).toList()
    ..sort((a, b) => _wdOrder(lens.weekday(a)) - _wdOrder(lens.weekday(b)));
  final picks = [...chosen]..sort((a, b) => _wdOrder(a) - _wdOrder(b));
  var same = training.length == picks.length;
  for (var i = 0; same && i < training.length; i++) {
    if (lens.weekday(training[i]) != picks[i]) same = false;
  }
  if (same) return days;
  final result = <T>[];
  for (var i = 0; i < training.length && i < picks.length; i++) {
    final t = training[i];
    result.add(lens.copy(t, picks[i], lens.type(t), lens.title(t)));
  }
  for (final w in kWeekdays) {
    if (result.any((r) => lens.weekday(r) == w)) continue;
    T? orig;
    for (final d in days) {
      if (lens.weekday(d) == w && !lens.type(d).isTraining) {
        orig = d;
        break;
      }
    }
    if (orig != null && lens.type(orig) == DayType.activeRecovery) {
      result.add(orig);
    } else {
      // TS falls back to the template's first rest day; if there is none, the first day.
      final base = orig ?? days.firstWhere((d) => lens.type(d) == DayType.rest, orElse: () => days.first);
      result.add(lens.copy(base, w, DayType.rest, 'Rest'));
    }
  }
  result.sort((a, b) => _wdOrder(lens.weekday(a)) - _wdOrder(lens.weekday(b)));
  return result;
}

/* ================================================================ template program */

/// Generates unique ids (the app passes a uuid v4 generator; tests pass a counter).
typedef IdGen = String Function();

class ProgramTemplate {
  const ProgramTemplate({required this.program, required this.days, required this.planned, required this.exercises});
  final Program program;
  final List<ProgramDay> days;
  final List<PlannedExercise> planned;

  /// Library entries the template uses (upsert these before saving the program).
  final Map<String, Exercise> exercises;

  int get daysWithExercises => planned.map((p) => p.dayId).toSet().length;
}

/// Mirror of TS importProgramTemplate's mapping (without the DB write): the seed program for the
/// chosen training days, starting the Monday of [today]'s week.
ProgramTemplate buildTemplateProgram(SeedData seed, {List<Weekday>? trainingDays, required DateTime today, required IdGen newId}) {
  final program = seed.program;
  final exercises = buildExercises(program, seed.mediaIndex, research: seed.research, demoMap: seed.demoMap, curatedMeta: seed.curatedMeta);
  final programId = newId();
  final p = Program(
    id: programId,
    name: program.name,
    active: true,
    startedOn: dayKey(weekStartOf(today, weekStart: 'mon')),
    warmup: [
      for (final w in program.warmup)
        WarmupItem(name: w.name, minutes: w.minutes?.toDouble(), reps: w.reps, exerciseId: w.hasFreeDbId ? slugify(w.name) : null),
    ],
    cooldown: program.cooldown,
    rules: program.rules,
    progression: ProgressionCfg(
      model: program.progression.model,
      dumbbellIncrementKg: program.progression.dumbbellIncrementKg,
      barIncrementKg: program.progression.barIncrementKg,
      cycle: program.progression.cycle,
      weeks: seed.research.weeks,
    ),
    templateId: program.id,
  );
  final mapped = remapDays(program.days, trainingDays, SeedDay.lens);
  final days = <ProgramDay>[];
  final planned = <PlannedExercise>[];
  for (var i = 0; i < mapped.length; i++) {
    final d = mapped[i];
    final dayId = newId();
    days.add(ProgramDay(
      id: dayId,
      programId: programId,
      weekday: d.weekday,
      type: d.type,
      title: d.title,
      durationMin: d.durationMin == null ? null : _intOf(d.durationMin!),
      notes: d.notes,
      order: i,
    ));
    final exs = d.exercises ?? const <SeedExercise>[];
    for (var j = 0; j < exs.length; j++) {
      final e = exs[j];
      planned.add(PlannedExercise(
        id: newId(),
        dayId: dayId,
        order: j,
        slot: e.slot,
        exerciseId: slugify(e.name),
        swapExerciseId: e.swap != null ? slugify(e.swap!.name) : null,
        supersetGroup: e.supersetGroup,
        sets: e.target.sets,
        repsMin: _intOf(e.target.repsMin),
        repsMax: _intOf(e.target.repsMax),
        unit: e.target.unit,
        perSide: e.target.perSide,
        restSec: _intOf(e.restSec),
        cue: e.cue,
      ));
    }
  }
  return ProgramTemplate(program: p, days: days, planned: planned, exercises: exercises);
}

/* ================================================================ diet template */

class DietTemplate {
  const DietTemplate({
    required this.plan,
    required this.meals,
    required this.habits,
    required this.adjustmentRules,
    required this.annualChecks,
    required this.constraints,
  });
  final DietPlan plan;
  final List<PlannedMeal> meals;
  final List<HabitDef> habits;

  /// Stored in meta as 'adjustmentRules', 'annualChecks' and 'dietConstraints' (JSON-ready).
  final List<Map<String, Object?>> adjustmentRules;
  final List<String> annualChecks;
  final List<String> constraints;
}

/// Mirror of TS importDietTemplate's mapping (without the DB write).
DietTemplate buildDietTemplate(SeedDiet diet, {required IdGen newId}) {
  final dietPlanId = newId();
  final meals = <PlannedMeal>[
    for (var i = 0; i < diet.trainingDay.length; i++)
      PlannedMeal(
        id: newId(),
        dietPlanId: dietPlanId,
        order: i,
        time: diet.trainingDay[i].time,
        meal: diet.trainingDay[i].meal,
        items: diet.trainingDay[i].items,
        rotate: diet.trainingDay[i].rotate,
        proteinG: diet.trainingDay[i].proteinG.toDouble(),
        kcal: diet.trainingDay[i].kcal.toDouble(),
        optional: diet.trainingDay[i].optional,
        skipOnRestDay: diet.trainingDay[i].skipOnRestDay,
      ),
  ];
  final habits = <HabitDef>[
    for (var i = 0; i < diet.habits.length; i++)
      () {
        final h = diet.habits[i];
        return h.unit == 'L'
            ? HabitDef(id: h.id, label: h.label, kind: 'number', target: ((h.target ?? 3) * 1000).roundToDouble(), unit: 'ml', order: i)
            : HabitDef(id: h.id, label: h.label, kind: h.target != null ? 'number' : 'check', target: h.target?.toDouble(), unit: h.unit, order: i);
      }(),
  ];
  return DietTemplate(
    plan: DietPlan(id: dietPlanId, name: diet.name, active: true, kcalTarget: _intOf(diet.kcalTarget), proteinTargetG: _intOf(diet.proteinTargetG)),
    meals: meals,
    habits: habits,
    adjustmentRules: [for (final r in diet.adjustmentRules ?? const <AdjustmentRule>[]) r.toJson()],
    annualChecks: diet.annualChecks ?? const [],
    constraints: diet.constraints ?? const [],
  );
}

/* ================================================================ blank program */

class BlankPlan {
  const BlankPlan({required this.program, required this.days, required this.dietPlan, required this.habits});
  final Program program;
  final List<ProgramDay> days;
  final DietPlan dietPlan;
  final List<HabitDef> habits;
}

/// "Start blank": one empty workout per chosen day, rest otherwise, plus a diet with the given
/// targets and the default habits. Mirror of TS createBlankProgram (without the DB write).
BlankPlan createBlankProgram(
  List<Weekday> trainingDays,
  int kcal,
  int protein, {
  required ProgressionCfg seedProgression,
  required DateTime today,
  required IdGen newId,
}) {
  final programId = newId();
  final program = Program(
    id: programId,
    name: 'My plan',
    active: true,
    startedOn: dayKey(weekStartOf(today, weekStart: 'mon')),
    warmup: const [],
    cooldown: '5 min walk + stretch',
    rules: const [],
    progression: seedProgression,
  );
  final days = [
    for (var i = 0; i < kWeekdays.length; i++)
      ProgramDay(
        id: newId(),
        programId: programId,
        weekday: kWeekdays[i],
        type: trainingDays.contains(kWeekdays[i]) ? DayType.strength : DayType.rest,
        title: trainingDays.contains(kWeekdays[i]) ? 'Workout' : 'Rest',
        order: i,
      ),
  ];
  return BlankPlan(
    program: program,
    days: days,
    dietPlan: DietPlan(id: newId(), name: 'My diet', active: true, kcalTarget: kcal, proteinTargetG: protein),
    habits: kDefaultHabits,
  );
}
