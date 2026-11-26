// Shared domain models (port of src/domain/types.ts). Pure Dart: no Flutter imports.
// JSON shapes match the web app exactly so seeds, backups and the AI coach API are shared.

/// Enum with a stable wire value (the string the web app and JSON use).
mixin Wire {
  String get wire;
}

T parseWire<T extends Wire>(List<T> values, Object? raw, T fallback) {
  for (final v in values) {
    if (v.wire == raw) return v;
  }
  return fallback;
}

enum Unit with Wire {
  reps('reps'),
  seconds('seconds'),
  minutes('minutes'),
  meters('meters');

  const Unit(this.wire);
  @override
  final String wire;
  static Unit parse(Object? s) => parseWire(values, s, Unit.reps);
}

enum DayType with Wire {
  strength('strength'),
  cardio('cardio'),
  conditioning('conditioning'),
  rest('rest'),
  activeRecovery('active_recovery');

  const DayType(this.wire);
  @override
  final String wire;
  static DayType parse(Object? s) => parseWire(values, s, DayType.rest);
  bool get isTraining => this == strength || this == cardio || this == conditioning;
}

enum Weekday with Wire {
  mon('MON', 'Mon'),
  tue('TUE', 'Tue'),
  wed('WED', 'Wed'),
  thu('THU', 'Thu'),
  fri('FRI', 'Fri'),
  sat('SAT', 'Sat'),
  sun('SUN', 'Sun');

  const Weekday(this.wire, this.label);
  @override
  final String wire;
  final String label;
  static Weekday parse(Object? s) => parseWire(values, s, Weekday.mon);

  /// DateTime.weekday is 1 (Mon) … 7 (Sun).
  static Weekday ofDate(DateTime d) => values[d.weekday - 1];
}

/// Week order MON..SUN (mirrors WEEKDAYS in the web app).
const List<Weekday> kWeekdays = Weekday.values;

enum Sex with Wire {
  male('male'),
  female('female'),
  other('other');

  const Sex(this.wire);
  @override
  final String wire;
  static Sex parse(Object? s) => parseWire(values, s, Sex.other);
}

enum DietType with Wire {
  veg('veg'),
  vegEgg('veg_egg'),
  nonveg('nonveg'),
  vegan('vegan');

  const DietType(this.wire);
  @override
  final String wire;
  static DietType parse(Object? s) => parseWire(values, s, DietType.vegEgg);
}

enum Goal with Wire {
  fatLoss('fat_loss'),
  lean('lean'),
  muscle('muscle'),
  strength('strength'),
  general('general');

  const Goal(this.wire);
  @override
  final String wire;
  static Goal parse(Object? s) => parseWire(values, s, Goal.lean);
}

enum Experience with Wire {
  beginner('beginner'),
  intermediate('intermediate'),
  advanced('advanced');

  const Experience(this.wire);
  @override
  final String wire;
  static Experience parse(Object? s) => parseWire(values, s, Experience.beginner);
}

enum Category with Wire {
  strength('strength'),
  cardio('cardio'),
  mobility('mobility'),
  power('power'),
  core('core');

  const Category(this.wire);
  @override
  final String wire;
  static Category parse(Object? s) => parseWire(values, s, Category.strength);
}

enum SessionMode with Wire {
  full('full'),
  express('express');

  const SessionMode(this.wire);
  @override
  final String wire;
  static SessionMode parse(Object? s) => parseWire(values, s, SessionMode.full);
}

enum Feel with Wire {
  tooEasy('too_easy'),
  justRight('just_right'),
  tooHard('too_hard');

  const Feel(this.wire);
  @override
  final String wire;
  static Feel parse(Object? s) => parseWire(values, s, Feel.justRight);
}

/* ---------------------------------------------------------------- helpers */

List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];
List<String>? _stringsOrNull(Object? v) => v is List ? v.map((e) => e.toString()).toList() : null;
double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _int(Object? v) => v is num ? v.round() : (v is String ? int.tryParse(v) : null);
Map<String, Object?> _clean(Map<String, Object?> m) => m..removeWhere((_, v) => v == null);

/* ---------------------------------------------------------------- profile */

class RestTimerPrefs {
  const RestTimerPrefs({this.sound = true, this.vibrate = true, this.notify = false});
  final bool sound;
  final bool vibrate;
  final bool notify;
  factory RestTimerPrefs.fromJson(Map<String, Object?> j) =>
      RestTimerPrefs(sound: j['sound'] != false, vibrate: j['vibrate'] != false, notify: j['notify'] == true);
  Map<String, Object?> toJson() => {'sound': sound, 'vibrate': vibrate, 'notify': notify};
}

class StepKg {
  const StepKg({this.dumbbell = 2, this.barbell = 5, this.machine = 5});
  final double dumbbell;
  final double barbell;
  final double machine;
  factory StepKg.fromJson(Map<String, Object?> j) =>
      StepKg(dumbbell: _num(j['dumbbell']) ?? 2, barbell: _num(j['barbell']) ?? 5, machine: _num(j['machine']) ?? 5);
  Map<String, Object?> toJson() => {'dumbbell': dumbbell, 'barbell': barbell, 'machine': machine};
}

class Profile {
  const Profile({
    required this.name,
    required this.sex,
    required this.birthYear,
    required this.heightCm,
    required this.startWeightKg,
    required this.goalWeightKg,
    this.targetDate,
    this.units = 'kg',
    this.theme = 'dark',
    required this.dietType,
    this.intolerances = const [],
    required this.kcalTarget,
    required this.proteinTargetG,
    required this.trainingDays,
    this.sessionTime = '09:15',
    this.restTimer = const RestTimerPrefs(),
    this.stepKg = const StepKg(),
    this.weekStart = 'mon',
    required this.createdAt,
    this.goal,
    this.experience,
    this.sessionMin,
    this.equipment,
    this.planSource,
    this.dietSource,
  });

  static const id = 'me';
  final String name;
  final Sex sex;
  final int birthYear;
  final double heightCm;
  final double startWeightKg;
  final double goalWeightKg;
  final String? targetDate;
  final String units; // 'kg' | 'lb'
  final String theme; // 'dark' | 'light' | 'system'
  final DietType dietType;
  final List<String> intolerances;
  final int kcalTarget;
  final int proteinTargetG;
  final List<Weekday> trainingDays;
  final String sessionTime;
  final RestTimerPrefs restTimer;
  final StepKg stepKg;
  final String weekStart;
  final String createdAt;
  final Goal? goal;
  final Experience? experience;
  final int? sessionMin;

  /// Available gym equipment ids; null = full gym (older profiles).
  final List<String>? equipment;
  final String? planSource; // generated | template | blank | ai
  final String? dietSource;

  factory Profile.fromJson(Map<String, Object?> j) => Profile(
        name: (j['name'] ?? '') as String,
        sex: Sex.parse(j['sex']),
        birthYear: _int(j['birthYear']) ?? 1990,
        heightCm: _num(j['heightCm']) ?? 170,
        startWeightKg: _num(j['startWeightKg']) ?? 70,
        goalWeightKg: _num(j['goalWeightKg']) ?? 70,
        targetDate: j['targetDate'] as String?,
        units: (j['units'] ?? 'kg') as String,
        theme: (j['theme'] ?? 'dark') as String,
        dietType: DietType.parse(j['dietType']),
        intolerances: _strings(j['intolerances']),
        kcalTarget: _int(j['kcalTarget']) ?? 0,
        proteinTargetG: _int(j['proteinTargetG']) ?? 0,
        trainingDays: _strings(j['trainingDays']).map(Weekday.parse).toList(),
        sessionTime: (j['sessionTime'] ?? '09:15') as String,
        restTimer: j['restTimer'] is Map ? RestTimerPrefs.fromJson((j['restTimer'] as Map).cast()) : const RestTimerPrefs(),
        stepKg: j['stepKg'] is Map ? StepKg.fromJson((j['stepKg'] as Map).cast()) : const StepKg(),
        weekStart: (j['weekStart'] ?? 'mon') as String,
        createdAt: (j['createdAt'] ?? '') as String,
        goal: j['goal'] == null ? null : Goal.parse(j['goal']),
        experience: j['experience'] == null ? null : Experience.parse(j['experience']),
        sessionMin: _int(j['sessionMin']),
        equipment: _stringsOrNull(j['equipment']),
        planSource: j['planSource'] as String?,
        dietSource: j['dietSource'] as String?,
      );

  Map<String, Object?> toJson() => _clean({
        'id': id,
        'name': name,
        'sex': sex.wire,
        'birthYear': birthYear,
        'heightCm': heightCm,
        'startWeightKg': startWeightKg,
        'goalWeightKg': goalWeightKg,
        'targetDate': targetDate,
        'units': units,
        'theme': theme,
        'dietType': dietType.wire,
        'intolerances': intolerances,
        'kcalTarget': kcalTarget,
        'proteinTargetG': proteinTargetG,
        'trainingDays': trainingDays.map((w) => w.wire).toList(),
        'sessionTime': sessionTime,
        'restTimer': restTimer.toJson(),
        'stepKg': stepKg.toJson(),
        'weekStart': weekStart,
        'createdAt': createdAt,
        'goal': goal?.wire,
        'experience': experience?.wire,
        'sessionMin': sessionMin,
        'equipment': equipment,
        'planSource': planSource,
        'dietSource': dietSource,
      });

  Profile copyWith({
    String? name,
    Sex? sex,
    int? birthYear,
    double? heightCm,
    double? startWeightKg,
    double? goalWeightKg,
    String? units,
    String? theme,
    DietType? dietType,
    List<String>? intolerances,
    int? kcalTarget,
    int? proteinTargetG,
    List<Weekday>? trainingDays,
    String? sessionTime,
    RestTimerPrefs? restTimer,
    StepKg? stepKg,
    Goal? goal,
    Experience? experience,
    int? sessionMin,
    List<String>? equipment,
    String? planSource,
    String? dietSource,
  }) =>
      Profile(
        name: name ?? this.name,
        sex: sex ?? this.sex,
        birthYear: birthYear ?? this.birthYear,
        heightCm: heightCm ?? this.heightCm,
        startWeightKg: startWeightKg ?? this.startWeightKg,
        goalWeightKg: goalWeightKg ?? this.goalWeightKg,
        targetDate: targetDate,
        units: units ?? this.units,
        theme: theme ?? this.theme,
        dietType: dietType ?? this.dietType,
        intolerances: intolerances ?? this.intolerances,
        kcalTarget: kcalTarget ?? this.kcalTarget,
        proteinTargetG: proteinTargetG ?? this.proteinTargetG,
        trainingDays: trainingDays ?? this.trainingDays,
        sessionTime: sessionTime ?? this.sessionTime,
        restTimer: restTimer ?? this.restTimer,
        stepKg: stepKg ?? this.stepKg,
        weekStart: weekStart,
        createdAt: createdAt,
        goal: goal ?? this.goal,
        experience: experience ?? this.experience,
        sessionMin: sessionMin ?? this.sessionMin,
        equipment: equipment ?? this.equipment,
        planSource: planSource ?? this.planSource,
        dietSource: dietSource ?? this.dietSource,
      );
}

/* ---------------------------------------------------------------- exercise */

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    this.freeDbId,
    this.primaryMuscles = const [],
    this.equipment = const [],
    this.category = Category.strength,
    this.cue,
    this.instructions,
    this.youtubeQuery,
    this.custom = false,
    this.isBodyweight,
    this.defaultUnit = Unit.reps,
    this.pattern,
    this.level,
    this.alternates,
    this.secondaryMuscles,
    this.bodyPart,
    this.demoId,
    this.source,
  });

  final String id;
  final String name;
  final String? freeDbId;
  final List<String> primaryMuscles;
  final List<String> equipment;
  final Category category;
  final String? cue;
  final List<String>? instructions;
  final String? youtubeQuery;
  final bool custom;
  final bool? isBodyweight;
  final Unit defaultUnit;

  /// Movement pattern (squat, hinge, horizontal push…).
  final String? pattern;

  /// 1 (easiest) … 5 (hardest).
  final int? level;

  /// Ranked alternates (exercise ids), easier → harder.
  final List<String>? alternates;
  final List<String>? secondaryMuscles;
  final String? bodyPart;

  /// Animated 3D demo id (`assets/media/demos/<id>.webp`).
  final String? demoId;

  /// 'curated' | 'dataset'
  final String? source;

  factory Exercise.fromJson(Map<String, Object?> j) => Exercise(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        freeDbId: j['freeDbId'] as String?,
        primaryMuscles: _strings(j['primaryMuscles']),
        equipment: _strings(j['equipment']),
        category: Category.parse(j['category']),
        cue: j['cue'] as String?,
        instructions: _stringsOrNull(j['instructions']),
        youtubeQuery: j['youtubeQuery'] as String?,
        custom: j['custom'] == true,
        isBodyweight: j['isBodyweight'] as bool?,
        defaultUnit: Unit.parse(j['defaultUnit']),
        pattern: j['pattern'] as String?,
        level: _int(j['level']),
        alternates: _stringsOrNull(j['alternates']),
        secondaryMuscles: _stringsOrNull(j['secondaryMuscles']),
        bodyPart: j['bodyPart'] as String?,
        demoId: j['demoId'] as String?,
        source: j['source'] as String?,
      );

  Map<String, Object?> toJson() => _clean({
        'id': id,
        'name': name,
        'freeDbId': freeDbId,
        'primaryMuscles': primaryMuscles,
        'equipment': equipment,
        'category': category.wire,
        'cue': cue,
        'instructions': instructions,
        'youtubeQuery': youtubeQuery,
        'custom': custom,
        'isBodyweight': isBodyweight,
        'defaultUnit': defaultUnit.wire,
        'pattern': pattern,
        'level': level,
        'alternates': alternates,
        'secondaryMuscles': secondaryMuscles,
        'bodyPart': bodyPart,
        'demoId': demoId,
        'source': source,
      });

  Exercise copyWith({
    String? name,
    String? cue,
    List<String>? instructions,
    bool? isBodyweight,
    String? pattern,
    int? level,
    List<String>? alternates,
    List<String>? primaryMuscles,
    List<String>? secondaryMuscles,
    String? bodyPart,
    String? demoId,
    String? source,
  }) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        freeDbId: freeDbId,
        primaryMuscles: primaryMuscles ?? this.primaryMuscles,
        equipment: equipment,
        category: category,
        cue: cue ?? this.cue,
        instructions: instructions ?? this.instructions,
        youtubeQuery: youtubeQuery,
        custom: custom,
        isBodyweight: isBodyweight ?? this.isBodyweight,
        defaultUnit: defaultUnit,
        pattern: pattern ?? this.pattern,
        level: level ?? this.level,
        alternates: alternates ?? this.alternates,
        secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
        bodyPart: bodyPart ?? this.bodyPart,
        demoId: demoId ?? this.demoId,
        source: source ?? this.source,
      );
}

/* ---------------------------------------------------------------- program */

class CycleEntry {
  const CycleEntry({required this.weeks, required this.rir, this.deload = false, this.note});
  final List<int> weeks;
  final int rir;
  final bool deload;
  final String? note;
  factory CycleEntry.fromJson(Map<String, Object?> j) => CycleEntry(
        weeks: (j['weeks'] as List? ?? const []).map((e) => _int(e) ?? 0).toList(),
        rir: _int(j['rir']) ?? 2,
        deload: j['deload'] == true,
        note: j['note'] as String?,
      );
  Map<String, Object?> toJson() => _clean({'weeks': weeks, 'rir': rir, 'deload': deload ? true : null, 'note': note});
}

class WeekFocus {
  const WeekFocus({
    required this.week,
    required this.rirMain,
    required this.rirAccessory,
    required this.focus,
    required this.note,
    this.setsDelta = 0,
    this.deload = false,
  });
  final int week;
  final int rirMain;
  final int rirAccessory;
  final String focus;
  final String note;
  final int setsDelta;
  final bool deload;
  factory WeekFocus.fromJson(Map<String, Object?> j) => WeekFocus(
        week: _int(j['week']) ?? 1,
        rirMain: _int(j['rirMain']) ?? 2,
        rirAccessory: _int(j['rirAccessory']) ?? 2,
        focus: (j['focus'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        setsDelta: _int(j['setsDelta']) ?? 0,
        deload: j['deload'] == true,
      );
  Map<String, Object?> toJson() =>
      {'week': week, 'rirMain': rirMain, 'rirAccessory': rirAccessory, 'focus': focus, 'note': note, 'setsDelta': setsDelta, 'deload': deload};
}

class ProgressionCfg {
  const ProgressionCfg({
    this.model = 'double_progression',
    this.dumbbellIncrementKg = 2,
    this.barIncrementKg = 5,
    this.cycle = const [],
    this.weeks,
  });
  final String model;
  final double dumbbellIncrementKg;
  final double barIncrementKg;
  final List<CycleEntry> cycle;
  final List<WeekFocus>? weeks;
  factory ProgressionCfg.fromJson(Map<String, Object?> j) => ProgressionCfg(
        model: (j['model'] ?? 'double_progression') as String,
        dumbbellIncrementKg: _num(j['dumbbellIncrementKg']) ?? 2,
        barIncrementKg: _num(j['barIncrementKg']) ?? 5,
        cycle: (j['cycle'] as List? ?? const []).map((e) => CycleEntry.fromJson((e as Map).cast())).toList(),
        weeks: (j['weeks'] as List?)?.map((e) => WeekFocus.fromJson((e as Map).cast())).toList(),
      );
  Map<String, Object?> toJson() => _clean({
        'model': model,
        'dumbbellIncrementKg': dumbbellIncrementKg,
        'barIncrementKg': barIncrementKg,
        'cycle': cycle.map((c) => c.toJson()).toList(),
        'weeks': weeks?.map((w) => w.toJson()).toList(),
      });
}

class WarmupItem {
  const WarmupItem({required this.name, this.minutes, this.reps, this.exerciseId});
  final String name;
  final double? minutes;
  final String? reps;
  final String? exerciseId;
  factory WarmupItem.fromJson(Map<String, Object?> j) =>
      WarmupItem(name: (j['name'] ?? '') as String, minutes: _num(j['minutes']), reps: j['reps'] as String?, exerciseId: j['exerciseId'] as String?);
  Map<String, Object?> toJson() => _clean({'name': name, 'minutes': minutes, 'reps': reps, 'exerciseId': exerciseId});
}

class Program {
  const Program({
    required this.id,
    required this.name,
    required this.active,
    required this.startedOn,
    this.warmup = const [],
    this.cooldown = '',
    this.rules = const [],
    this.progression = const ProgressionCfg(),
    this.templateId,
  });
  final String id;
  final String name;
  final bool active;

  /// yyyy-MM-dd (Monday of the start week).
  final String startedOn;
  final List<WarmupItem> warmup;
  final String cooldown;
  final List<String> rules;
  final ProgressionCfg progression;
  final String? templateId;
  factory Program.fromJson(Map<String, Object?> j) => Program(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        active: j['active'] == true,
        startedOn: (j['startedOn'] ?? '') as String,
        warmup: (j['warmup'] as List? ?? const []).map((e) => WarmupItem.fromJson((e as Map).cast())).toList(),
        cooldown: (j['cooldown'] ?? '') as String,
        rules: _strings(j['rules']),
        progression: j['progression'] is Map ? ProgressionCfg.fromJson((j['progression'] as Map).cast()) : const ProgressionCfg(),
        templateId: j['templateId'] as String?,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'name': name,
        'active': active,
        'startedOn': startedOn,
        'warmup': warmup.map((w) => w.toJson()).toList(),
        'cooldown': cooldown,
        'rules': rules,
        'progression': progression.toJson(),
        'templateId': templateId,
      });
  Program copyWith({bool? active, String? name, String? startedOn}) => Program(
        id: id,
        name: name ?? this.name,
        active: active ?? this.active,
        startedOn: startedOn ?? this.startedOn,
        warmup: warmup,
        cooldown: cooldown,
        rules: rules,
        progression: progression,
        templateId: templateId,
      );
}

class ProgramDay {
  const ProgramDay({
    required this.id,
    required this.programId,
    required this.weekday,
    required this.type,
    required this.title,
    this.durationMin,
    this.notes,
    required this.order,
  });
  final String id;
  final String programId;
  final Weekday weekday;
  final DayType type;
  final String title;
  final int? durationMin;
  final String? notes;
  final int order;
  factory ProgramDay.fromJson(Map<String, Object?> j) => ProgramDay(
        id: j['id'] as String,
        programId: j['programId'] as String,
        weekday: Weekday.parse(j['weekday']),
        type: DayType.parse(j['type']),
        title: (j['title'] ?? '') as String,
        durationMin: _int(j['durationMin']),
        notes: j['notes'] as String?,
        order: _int(j['order']) ?? 0,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'programId': programId,
        'weekday': weekday.wire,
        'type': type.wire,
        'title': title,
        'durationMin': durationMin,
        'notes': notes,
        'order': order,
      });
  ProgramDay copyWith({Weekday? weekday, DayType? type, String? title, int? durationMin, String? notes, int? order}) => ProgramDay(
        id: id,
        programId: programId,
        weekday: weekday ?? this.weekday,
        type: type ?? this.type,
        title: title ?? this.title,
        durationMin: durationMin ?? this.durationMin,
        notes: notes ?? this.notes,
        order: order ?? this.order,
      );
}

class PlannedExercise {
  const PlannedExercise({
    required this.id,
    required this.dayId,
    required this.order,
    required this.slot,
    required this.exerciseId,
    this.swapExerciseId,
    this.supersetGroup,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.unit,
    required this.perSide,
    required this.restSec,
    this.cue,
  });
  final String id;
  final String dayId;
  final int order;
  final String slot;
  final String exerciseId;
  final String? swapExerciseId;
  final String? supersetGroup;
  final int sets;
  final int repsMin;
  final int repsMax;
  final Unit unit;
  final bool perSide;
  final int restSec;
  final String? cue;
  factory PlannedExercise.fromJson(Map<String, Object?> j) => PlannedExercise(
        id: j['id'] as String,
        dayId: j['dayId'] as String,
        order: _int(j['order']) ?? 0,
        slot: (j['slot'] ?? '') as String,
        exerciseId: j['exerciseId'] as String,
        swapExerciseId: j['swapExerciseId'] as String?,
        supersetGroup: j['supersetGroup'] as String?,
        sets: _int(j['sets']) ?? 3,
        repsMin: _int(j['repsMin']) ?? 8,
        repsMax: _int(j['repsMax']) ?? 12,
        unit: Unit.parse(j['unit']),
        perSide: j['perSide'] == true,
        restSec: _int(j['restSec']) ?? 60,
        cue: j['cue'] as String?,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'dayId': dayId,
        'order': order,
        'slot': slot,
        'exerciseId': exerciseId,
        'swapExerciseId': swapExerciseId,
        'supersetGroup': supersetGroup,
        'sets': sets,
        'repsMin': repsMin,
        'repsMax': repsMax,
        'unit': unit.wire,
        'perSide': perSide,
        'restSec': restSec,
        'cue': cue,
      });
  PlannedExercise copyWith({
    int? order,
    String? slot,
    String? exerciseId,
    String? Function()? swapExerciseId,
    String? Function()? supersetGroup,
    int? sets,
    int? repsMin,
    int? repsMax,
    Unit? unit,
    bool? perSide,
    int? restSec,
    String? cue,
  }) =>
      PlannedExercise(
        id: id,
        dayId: dayId,
        order: order ?? this.order,
        slot: slot ?? this.slot,
        exerciseId: exerciseId ?? this.exerciseId,
        swapExerciseId: swapExerciseId != null ? swapExerciseId() : this.swapExerciseId,
        supersetGroup: supersetGroup != null ? supersetGroup() : this.supersetGroup,
        sets: sets ?? this.sets,
        repsMin: repsMin ?? this.repsMin,
        repsMax: repsMax ?? this.repsMax,
        unit: unit ?? this.unit,
        perSide: perSide ?? this.perSide,
        restSec: restSec ?? this.restSec,
        cue: cue ?? this.cue,
      );
}

/* ---------------------------------------------------------------- sessions */

class SessionFeedback {
  const SessionFeedback({
    required this.rpe,
    required this.feel,
    this.pain = const [],
    this.disliked = const [],
    this.ranOutOfTime = false,
    this.energy,
    this.note,
  });
  final int rpe;
  final Feel feel;

  /// Exercise ids that caused joint pain.
  final List<String> pain;

  /// Exercise ids the user didn't enjoy.
  final List<String> disliked;
  final bool ranOutOfTime;
  final String? energy; // low | ok | high
  final String? note;
  factory SessionFeedback.fromJson(Map<String, Object?> j) => SessionFeedback(
        rpe: _int(j['rpe']) ?? 7,
        feel: Feel.parse(j['feel']),
        pain: _strings(j['pain']),
        disliked: _strings(j['disliked']),
        ranOutOfTime: j['ranOutOfTime'] == true,
        energy: j['energy'] as String?,
        note: j['note'] as String?,
      );
  Map<String, Object?> toJson() => _clean({
        'rpe': rpe,
        'feel': feel.wire,
        'pain': pain,
        'disliked': disliked,
        'ranOutOfTime': ranOutOfTime,
        'energy': energy,
        'note': note,
      });
}

class Session {
  const Session({
    required this.id,
    required this.dayKey,
    this.programDayId,
    required this.title,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.rpe,
    this.notes,
    required this.cycleWeek,
    required this.deload,
    this.mode,
    this.feedback,
  });
  final String id;
  final String dayKey;
  final String? programDayId;
  final String title;
  final String startedAt;
  final String? endedAt;
  final String status; // active | done | abandoned
  final int? rpe;
  final String? notes;
  final int cycleWeek;
  final bool deload;
  final SessionMode? mode;
  final SessionFeedback? feedback;
  factory Session.fromJson(Map<String, Object?> j) => Session(
        id: j['id'] as String,
        dayKey: (j['dayKey'] ?? '') as String,
        programDayId: j['programDayId'] as String?,
        title: (j['title'] ?? '') as String,
        startedAt: (j['startedAt'] ?? '') as String,
        endedAt: j['endedAt'] as String?,
        status: (j['status'] ?? 'done') as String,
        rpe: _int(j['rpe']),
        notes: j['notes'] as String?,
        cycleWeek: _int(j['cycleWeek']) ?? 1,
        deload: j['deload'] == true,
        mode: j['mode'] == null ? null : SessionMode.parse(j['mode']),
        feedback: j['feedback'] is Map ? SessionFeedback.fromJson((j['feedback'] as Map).cast()) : null,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'dayKey': dayKey,
        'programDayId': programDayId,
        'title': title,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'status': status,
        'rpe': rpe,
        'notes': notes,
        'cycleWeek': cycleWeek,
        'deload': deload,
        'mode': mode?.wire,
        'feedback': feedback?.toJson(),
      });
}

/// One exercise as it will be performed in a session (snapshot at start).
class SessionExercise {
  const SessionExercise({
    required this.plannedExerciseId,
    required this.exerciseId,
    required this.originalExerciseId,
    required this.slot,
    this.supersetGroup,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.unit,
    required this.perSide,
    required this.restSec,
    this.rir,
    required this.isMain,
    this.cue,
    this.note,
  });
  final String plannedExerciseId;
  final String exerciseId;
  final String originalExerciseId;
  final String slot;
  final String? supersetGroup;
  final int sets;
  final int repsMin;
  final int repsMax;
  final Unit unit;
  final bool perSide;
  final int restSec;
  final int? rir;
  final bool isMain;
  final String? cue;
  final String? note;
  factory SessionExercise.fromJson(Map<String, Object?> j) => SessionExercise(
        plannedExerciseId: j['plannedExerciseId'] as String,
        exerciseId: j['exerciseId'] as String,
        originalExerciseId: (j['originalExerciseId'] ?? j['exerciseId']) as String,
        slot: (j['slot'] ?? '') as String,
        supersetGroup: j['supersetGroup'] as String?,
        sets: _int(j['sets']) ?? 3,
        repsMin: _int(j['repsMin']) ?? 8,
        repsMax: _int(j['repsMax']) ?? 12,
        unit: Unit.parse(j['unit']),
        perSide: j['perSide'] == true,
        restSec: _int(j['restSec']) ?? 60,
        rir: _int(j['rir']),
        isMain: j['isMain'] == true,
        cue: j['cue'] as String?,
        note: j['note'] as String?,
      );
  Map<String, Object?> toJson() => _clean({
        'plannedExerciseId': plannedExerciseId,
        'exerciseId': exerciseId,
        'originalExerciseId': originalExerciseId,
        'slot': slot,
        'supersetGroup': supersetGroup,
        'sets': sets,
        'repsMin': repsMin,
        'repsMax': repsMax,
        'unit': unit.wire,
        'perSide': perSide,
        'restSec': restSec,
        'rir': rir,
        'isMain': isMain,
        'cue': cue,
        'note': note,
      });
  SessionExercise copyWith({String? exerciseId, int? sets, int? repsMin, int? repsMax, int? restSec, int? rir, String? note, String? supersetGroup}) =>
      SessionExercise(
        plannedExerciseId: plannedExerciseId,
        exerciseId: exerciseId ?? this.exerciseId,
        originalExerciseId: originalExerciseId,
        slot: slot,
        supersetGroup: supersetGroup ?? this.supersetGroup,
        sets: sets ?? this.sets,
        repsMin: repsMin ?? this.repsMin,
        repsMax: repsMax ?? this.repsMax,
        unit: unit,
        perSide: perSide,
        restSec: restSec ?? this.restSec,
        rir: rir ?? this.rir,
        isMain: isMain,
        cue: cue,
        note: note ?? this.note,
      );
}

class SetLog {
  const SetLog({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    this.plannedExerciseId,
    this.swappedFromExerciseId,
    required this.setIndex,
    this.weightKg,
    this.reps,
    this.seconds,
    this.meters,
    this.rir,
    required this.completedAt,
    this.isWarmup = false,
  });
  final String id;
  final String sessionId;
  final String exerciseId;
  final String? plannedExerciseId;
  final String? swappedFromExerciseId;
  final int setIndex;
  final double? weightKg;
  final int? reps;
  final int? seconds;
  final double? meters;
  final int? rir;
  final String completedAt;
  final bool isWarmup;
  factory SetLog.fromJson(Map<String, Object?> j) => SetLog(
        id: j['id'] as String,
        sessionId: j['sessionId'] as String,
        exerciseId: j['exerciseId'] as String,
        plannedExerciseId: j['plannedExerciseId'] as String?,
        swappedFromExerciseId: j['swappedFromExerciseId'] as String?,
        setIndex: _int(j['setIndex']) ?? 0,
        weightKg: _num(j['weightKg']),
        reps: _int(j['reps']),
        seconds: _int(j['seconds']),
        meters: _num(j['meters']),
        rir: _int(j['rir']),
        completedAt: (j['completedAt'] ?? '') as String,
        isWarmup: j['isWarmup'] == true,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'sessionId': sessionId,
        'exerciseId': exerciseId,
        'plannedExerciseId': plannedExerciseId,
        'swappedFromExerciseId': swappedFromExerciseId,
        'setIndex': setIndex,
        'weightKg': weightKg,
        'reps': reps,
        'seconds': seconds,
        'meters': meters,
        'rir': rir,
        'completedAt': completedAt,
        'isWarmup': isWarmup,
      });
}

class ActiveSessionState {
  const ActiveSessionState({
    required this.sessionId,
    this.exerciseIdx = 0,
    this.setIdx = 0,
    this.restEndsAt,
    this.restTotalSec,
    this.swaps = const {},
    this.extraSets,
    this.plan,
    this.prShown,
    this.hold,
    this.pain,
  });
  static const id = 'current';
  final String sessionId;
  final int exerciseIdx;
  final int setIdx;
  final String? restEndsAt;
  final int? restTotalSec;
  final Map<String, String> swaps;
  final Map<String, int>? extraSets;
  final List<SessionExercise>? plan;
  final List<String>? prShown;

  /// Hold weight increases this session (feedback said too hard).
  final bool? hold;

  /// Exercise ids that hurt last time.
  final List<String>? pain;
  factory ActiveSessionState.fromJson(Map<String, Object?> j) => ActiveSessionState(
        sessionId: j['sessionId'] as String,
        exerciseIdx: _int(j['exerciseIdx']) ?? 0,
        setIdx: _int(j['setIdx']) ?? 0,
        restEndsAt: j['restEndsAt'] as String?,
        restTotalSec: _int(j['restTotalSec']),
        swaps: (j['swaps'] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        extraSets: (j['extraSets'] as Map?)?.map((k, v) => MapEntry(k.toString(), _int(v) ?? 0)),
        plan: (j['plan'] as List?)?.map((e) => SessionExercise.fromJson((e as Map).cast())).toList(),
        prShown: _stringsOrNull(j['prShown']),
        hold: j['hold'] as bool?,
        pain: _stringsOrNull(j['pain']),
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'sessionId': sessionId,
        'exerciseIdx': exerciseIdx,
        'setIdx': setIdx,
        'restEndsAt': restEndsAt,
        'restTotalSec': restTotalSec,
        'swaps': swaps,
        'extraSets': extraSets,
        'plan': plan?.map((p) => p.toJson()).toList(),
        'prShown': prShown,
        'hold': hold,
        'pain': pain,
      });
}

/* ---------------------------------------------------------------- diet */

class DietPlan {
  const DietPlan({required this.id, required this.name, required this.active, required this.kcalTarget, required this.proteinTargetG});
  final String id;
  final String name;
  final bool active;
  final int kcalTarget;
  final int proteinTargetG;
  factory DietPlan.fromJson(Map<String, Object?> j) => DietPlan(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        active: j['active'] == true,
        kcalTarget: _int(j['kcalTarget']) ?? 2000,
        proteinTargetG: _int(j['proteinTargetG']) ?? 120,
      );
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'active': active, 'kcalTarget': kcalTarget, 'proteinTargetG': proteinTargetG};
  DietPlan copyWith({bool? active, String? name, int? kcalTarget, int? proteinTargetG}) => DietPlan(
        id: id,
        name: name ?? this.name,
        active: active ?? this.active,
        kcalTarget: kcalTarget ?? this.kcalTarget,
        proteinTargetG: proteinTargetG ?? this.proteinTargetG,
      );
}

class PlannedMeal {
  const PlannedMeal({
    required this.id,
    required this.dietPlanId,
    required this.order,
    required this.time,
    required this.meal,
    required this.items,
    this.rotate,
    required this.proteinG,
    required this.kcal,
    this.optional,
    this.skipOnRestDay,
  });
  final String id;
  final String dietPlanId;
  final int order;
  final String time; // HH:mm
  final String meal;
  final List<String> items;
  final List<String>? rotate;
  final double proteinG;
  final double kcal;
  final bool? optional;
  final bool? skipOnRestDay;
  factory PlannedMeal.fromJson(Map<String, Object?> j) => PlannedMeal(
        id: j['id'] as String,
        dietPlanId: j['dietPlanId'] as String,
        order: _int(j['order']) ?? 0,
        time: (j['time'] ?? '12:00') as String,
        meal: (j['meal'] ?? '') as String,
        items: _strings(j['items']),
        rotate: _stringsOrNull(j['rotate']),
        proteinG: _num(j['proteinG']) ?? 0,
        kcal: _num(j['kcal']) ?? 0,
        optional: j['optional'] as bool?,
        skipOnRestDay: j['skipOnRestDay'] as bool?,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'dietPlanId': dietPlanId,
        'order': order,
        'time': time,
        'meal': meal,
        'items': items,
        'rotate': rotate,
        'proteinG': proteinG,
        'kcal': kcal,
        'optional': optional,
        'skipOnRestDay': skipOnRestDay,
      });
}

class MealLog {
  const MealLog({
    required this.id,
    required this.dayKey,
    this.plannedMealId,
    required this.state,
    this.label,
    required this.proteinG,
    required this.kcal,
    this.chosenRotation,
    required this.loggedAt,
  });
  final String id;
  final String dayKey;
  final String? plannedMealId;
  final String state; // eaten | swapped | skipped
  final String? label;
  final double proteinG;
  final double kcal;
  final String? chosenRotation;
  final String loggedAt;
  factory MealLog.fromJson(Map<String, Object?> j) => MealLog(
        id: j['id'] as String,
        dayKey: (j['dayKey'] ?? '') as String,
        plannedMealId: j['plannedMealId'] as String?,
        state: (j['state'] ?? 'eaten') as String,
        label: j['label'] as String?,
        proteinG: _num(j['proteinG']) ?? 0,
        kcal: _num(j['kcal']) ?? 0,
        chosenRotation: j['chosenRotation'] as String?,
        loggedAt: (j['loggedAt'] ?? '') as String,
      );
  Map<String, Object?> toJson() => _clean({
        'id': id,
        'dayKey': dayKey,
        'plannedMealId': plannedMealId,
        'state': state,
        'label': label,
        'proteinG': proteinG,
        'kcal': kcal,
        'chosenRotation': chosenRotation,
        'loggedAt': loggedAt,
      });
}

class HabitDef {
  const HabitDef({required this.id, required this.label, required this.kind, this.target, this.unit, required this.order});
  final String id;
  final String label;
  final String kind; // check | number
  final double? target;
  final String? unit;
  final int order;
  factory HabitDef.fromJson(Map<String, Object?> j) => HabitDef(
        id: j['id'] as String,
        label: (j['label'] ?? '') as String,
        kind: (j['kind'] ?? 'check') as String,
        target: _num(j['target']),
        unit: j['unit'] as String?,
        order: _int(j['order']) ?? 0,
      );
  Map<String, Object?> toJson() => _clean({'id': id, 'label': label, 'kind': kind, 'target': target, 'unit': unit, 'order': order});
}

class HabitLog {
  const HabitLog({required this.id, required this.dayKey, required this.habitId, required this.value});
  final String id;
  final String dayKey;
  final String habitId;
  final double value;
  factory HabitLog.fromJson(Map<String, Object?> j) =>
      HabitLog(id: j['id'] as String, dayKey: (j['dayKey'] ?? '') as String, habitId: (j['habitId'] ?? '') as String, value: _num(j['value']) ?? 0);
  Map<String, Object?> toJson() => {'id': id, 'dayKey': dayKey, 'habitId': habitId, 'value': value};
}

/* ---------------------------------------------------------------- body & media */

class BodyLog {
  const BodyLog({required this.id, required this.dayKey, this.weightKg, this.waistCm, this.note});
  final String id;
  final String dayKey;
  final double? weightKg;
  final double? waistCm;
  final String? note;
  factory BodyLog.fromJson(Map<String, Object?> j) =>
      BodyLog(id: j['id'] as String, dayKey: (j['dayKey'] ?? '') as String, weightKg: _num(j['weightKg']), waistCm: _num(j['waistCm']), note: j['note'] as String?);
  Map<String, Object?> toJson() => _clean({'id': id, 'dayKey': dayKey, 'weightKg': weightKg, 'waistCm': waistCm, 'note': note});
}

class Photo {
  const Photo({required this.id, required this.dayKey, required this.pose, required this.blobId});
  final String id;
  final String dayKey;
  final String pose; // front | side | back
  final String blobId;
  factory Photo.fromJson(Map<String, Object?> j) =>
      Photo(id: j['id'] as String, dayKey: (j['dayKey'] ?? '') as String, pose: (j['pose'] ?? 'front') as String, blobId: (j['blobId'] ?? '') as String);
  Map<String, Object?> toJson() => {'id': id, 'dayKey': dayKey, 'pose': pose, 'blobId': blobId};
}

/// Media is stored as a file in the app's documents directory; the row keeps the metadata.
class MediaBlob {
  const MediaBlob({required this.id, required this.kind, required this.mime, required this.bytes, required this.path, required this.createdAt});
  final String id;
  final String kind; // clip | photo
  final String mime;
  final int bytes;

  /// File name relative to the app's media directory.
  final String path;
  final String createdAt;
  factory MediaBlob.fromJson(Map<String, Object?> j) => MediaBlob(
        id: j['id'] as String,
        kind: (j['kind'] ?? 'photo') as String,
        mime: (j['mime'] ?? '') as String,
        bytes: _int(j['bytes']) ?? 0,
        path: (j['path'] ?? '') as String,
        createdAt: (j['createdAt'] ?? '') as String,
      );
  Map<String, Object?> toJson() => {'id': id, 'kind': kind, 'mime': mime, 'bytes': bytes, 'path': path, 'createdAt': createdAt};
}

class ExerciseClip {
  const ExerciseClip({required this.exerciseId, required this.blobId, required this.durationSec, this.thumb});
  final String exerciseId;
  final String blobId;
  final double durationSec;
  final String? thumb;
  factory ExerciseClip.fromJson(Map<String, Object?> j) => ExerciseClip(
        exerciseId: j['exerciseId'] as String,
        blobId: (j['blobId'] ?? '') as String,
        durationSec: _num(j['durationSec']) ?? 0,
        thumb: j['thumb'] as String?,
      );
  Map<String, Object?> toJson() => _clean({'exerciseId': exerciseId, 'blobId': blobId, 'durationSec': durationSec, 'thumb': thumb});
}
