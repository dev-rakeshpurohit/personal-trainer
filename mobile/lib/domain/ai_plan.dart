// Port of src/domain/aiPlan.ts. Pure Dart: no Flutter imports.
//
// AI coach contract, shared with the /api/coach function (which validates the request with the
// TS zod schema and builds the real prompt server-side).
//
// The model only ever chooses exercises by id from a list the app sends (already filtered to the
// user's equipment); `normaliseAiPlan` drops anything else, clamps numbers and fills the week.
//
// zod is replaced by explicit validation that mirrors the zod v3 schemas:
//   - request: `CoachRequest.validate()` / `CoachRequest.parse()` = `coachRequestSchema.parse`.
//   - response: `normaliseAiPlan` parses with the same rules as `aiPlanSchema` (coercion, `.catch`
//     fallbacks, optional vs missing keys) before repairing the plan.
import 'dart:convert';

import 'models.dart';

/// Week order, same as `WEEK` in the TS module.
const List<Weekday> kAiWeek = Weekday.values;

/// Errors with the user-facing messages of the TS module.
class AiPlanException implements Exception {
  const AiPlanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/* ===================================================================== JS helpers */

/// JS `Math.round`: halves round toward +∞.
double _jsRound(double x) {
  final f = x.floorToDouble();
  return x - f >= 0.5 ? f + 1 : f;
}

/// JS `String(number)` (template-literal formatting).
String _jsNum(num v) {
  final d = v.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
  if (d == d.truncateToDouble() && d.abs() < 1e21) return BigInt.from(d).toString();
  return d.toString();
}

const _jsSpace = {
  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, //
  0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
};

/// JS `String.prototype.trim`.
String _jsTrim(String s) {
  var a = 0, b = s.length;
  while (a < b && _jsSpace.contains(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && _jsSpace.contains(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

final _decimal = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');
final _radix = RegExp(r'^0([xXoObB])([0-9a-zA-Z]+)$');

double _jsStringToNumber(String s) {
  final t = _jsTrim(s);
  if (t.isEmpty) return 0;
  if (t == 'Infinity' || t == '+Infinity') return double.infinity;
  if (t == '-Infinity') return double.negativeInfinity;
  if (_decimal.hasMatch(t)) return double.parse(t);
  final m = _radix.firstMatch(t);
  if (m != null) {
    final radix = switch (m.group(1)!.toLowerCase()) { 'x' => 16, 'o' => 8, _ => 2 };
    final v = BigInt.tryParse(m.group(2)!, radix: radix);
    return v == null ? double.nan : v.toDouble();
  }
  return double.nan;
}

/// JS `String(value)` for JSON values (used by array → number coercion).
String _jsString(Object? v) => switch (v) {
      null => 'null',
      String s => s,
      bool b => b ? 'true' : 'false',
      num n => _jsNum(n),
      List l => l.map((e) => e == null ? '' : _jsString(e)).join(','),
      _ => '[object Object]',
    };

/// JS `Number(value)` (what `z.coerce.number()` does).
double _jsToNumber(Object? v) => switch (v) {
      _Undefined() => double.nan,
      null => 0,
      bool b => b ? 1 : 0,
      num n => n.toDouble(),
      String s => _jsStringToNumber(s),
      List l => _jsStringToNumber(_jsString(l)),
      _ => double.nan,
    };

/* ===================================================================== zod-like parsing */

/// A key that is absent from its object (JS `undefined`), as opposed to JSON `null`.
class _Undefined {
  const _Undefined();
}

const _undefined = _Undefined();

/// Any schema failure (zod "invalid" or "dirty").
class _Fail implements Exception {
  const _Fail();
}

Object? _get(Map m, String key) => m.containsKey(key) ? m[key] : _undefined;

Map _obj(Object? v) => v is Map ? v : throw const _Fail();

List _arr(Object? v, {int? min, int? max}) {
  if (v is! List) throw const _Fail();
  if (min != null && v.length < min) throw const _Fail();
  if (max != null && v.length > max) throw const _Fail();
  return v;
}

String _str(Object? v, {int? max}) {
  if (v is! String) throw const _Fail();
  if (max != null && v.length > max) throw const _Fail();
  return v;
}

bool _bool(Object? v) => v is bool ? v : throw const _Fail();

T _enum<T extends Wire>(List<T> values, Object? v) {
  if (v is String) {
    for (final x in values) {
      if (x.wire == v) return x;
    }
  }
  throw const _Fail();
}

/// `.catch(fallback)`.
T _catch<T>(T Function() f, T fallback) {
  try {
    return f();
  } on _Fail {
    return fallback;
  }
}

/// `.optional()`: an absent key → null; anything else (including JSON null) goes to [f].
T? _opt<T>(Object? v, T Function(Object? v) f) => v is _Undefined ? null : f(v);

/// `num(min, max)` = `z.coerce.number().min(min).max(max).catch(min)`.
double _numCatch(Object? v, double min, double max) {
  final n = _jsToNumber(v);
  if (n.isNaN || n < min || n > max) return min;
  return n;
}

/// `z.number()` (+ `.int()`) with a range, strict (no coercion). Used for the request.
double _numStrict(Object? v, double min, double max, {bool integer = false}) {
  if (v is! num) throw const _Fail();
  final d = v.toDouble();
  if (d.isNaN || d < min || d > max) throw const _Fail();
  if (integer && d != d.truncateToDouble()) throw const _Fail();
  return d;
}

/// JSON number the way `JSON.stringify` writes it (no trailing `.0` on whole numbers).
num _jsonNum(num v) => v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 9007199254740992 ? v.toInt() : v;

/* ===================================================================== request (app → function) */

enum CoachMode with Wire {
  newPlan('new'),
  change('change');

  const CoachMode(this.wire);
  @override
  final String wire;
}

class CoachWant {
  const CoachWant({required this.workout, required this.diet});
  final bool workout;
  final bool diet;
  Map<String, Object?> toJson() => {'workout': workout, 'diet': diet};
}

class CoachProfile {
  const CoachProfile({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.goalWeightKg,
    required this.goal,
    required this.experience,
    required this.trainingDays,
    required this.sessionMin,
    this.sessionTime,
    required this.equipment,
    required this.dietType,
    required this.intolerances,
    this.kcalTarget,
    this.proteinTargetG,
  });
  final Sex sex;
  final int age; // 13..100
  final double heightCm; // 120..230
  final double weightKg; // 30..300
  final double goalWeightKg; // 30..300
  final Goal goal;
  final Experience experience;
  final List<Weekday> trainingDays; // ≤ 7
  final int sessionMin; // 20..120
  final String? sessionTime; // ≤ 10 chars
  final List<String> equipment; // ≤ 20, each ≤ 30 chars
  final DietType dietType;
  final List<String> intolerances; // ≤ 12, each ≤ 40 chars
  final int? kcalTarget; // 1000..5000
  final int? proteinTargetG; // 40..350

  /// Same keys, order and values as `JSON.stringify` of the TS object (undefined keys dropped).
  Map<String, Object?> toJson() => {
        'sex': sex.wire,
        'age': age,
        'heightCm': _jsonNum(heightCm),
        'weightKg': _jsonNum(weightKg),
        'goalWeightKg': _jsonNum(goalWeightKg),
        'goal': goal.wire,
        'experience': experience.wire,
        'trainingDays': trainingDays.map((d) => d.wire).toList(),
        'sessionMin': sessionMin,
        if (sessionTime != null) 'sessionTime': sessionTime,
        'equipment': equipment,
        'dietType': dietType.wire,
        'intolerances': intolerances,
        if (kcalTarget != null) 'kcalTarget': kcalTarget,
        if (proteinTargetG != null) 'proteinTargetG': proteinTargetG,
      };

  /// `coachProfileSchema.parse` (throws [FormatException] on invalid input; unknown keys are dropped).
  factory CoachProfile.fromJson(Object? json) => _guard(() => _parseProfile(json));
}

class CoachExercise {
  const CoachExercise({required this.id, required this.name, this.pattern, required this.unit});
  final String id; // ≤ 80
  final String name; // ≤ 90
  final String? pattern; // ≤ 30
  final String unit; // ≤ 8
  Map<String, Object?> toJson() => {'id': id, 'name': name, if (pattern != null) 'pattern': pattern, 'unit': unit};
}

class CoachRequest {
  const CoachRequest({
    required this.code,
    required this.mode,
    required this.want,
    required this.profile,
    required this.notes,
    required this.exercises,
    this.current,
  });
  final String code; // ≤ 20
  final CoachMode mode;
  final CoachWant want;
  final CoachProfile profile;
  final String notes; // ≤ 2000
  final List<CoachExercise> exercises; // ≤ 1500
  /// Compact text of the current plan, for "change my plan" (≤ 12000).
  final String? current;

  CoachRequest copyWith({CoachMode? mode, CoachWant? want, String? notes, List<CoachExercise>? exercises, String? current}) => CoachRequest(
        code: code,
        mode: mode ?? this.mode,
        want: want ?? this.want,
        profile: profile,
        notes: notes ?? this.notes,
        exercises: exercises ?? this.exercises,
        current: current ?? this.current,
      );

  /// The body POSTed to /api/coach: identical to `JSON.stringify(body)` in src/lib/coach.ts.
  Map<String, Object?> toJson() => {
        'code': code,
        'mode': mode.wire,
        'want': want.toJson(),
        'profile': profile.toJson(),
        'notes': notes,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        if (current != null) 'current': current,
      };

  String toJsonString() => jsonEncode(toJson());

  /// True when the server's `coachRequestSchema.parse` would accept [toJson].
  bool get isValid {
    try {
      _parseRequest(jsonDecode(toJsonString()));
      return true;
    } on _Fail {
      return false;
    }
  }

  /// Throws [FormatException] ('Invalid request.') when the server would reject this request.
  void validate() => CoachRequest.parse(toJson());

  /// `coachRequestSchema.parse` on decoded JSON. Throws [FormatException] ('Invalid request.').
  static CoachRequest parse(Object? json) => _guard(() => _parseRequest(json));
}

T _guard<T>(T Function() f) {
  try {
    return f();
  } on _Fail {
    throw const FormatException('Invalid request.');
  }
}

List<String> _strList(Object? v, {required int max, required int itemMax}) => [for (final x in _arr(v, max: max)) _str(x, max: itemMax)];

CoachProfile _parseProfile(Object? json) {
  final m = _obj(json);
  return CoachProfile(
    sex: _enum(Sex.values, _get(m, 'sex')),
    age: _numStrict(_get(m, 'age'), 13, 100, integer: true).toInt(),
    heightCm: _numStrict(_get(m, 'heightCm'), 120, 230),
    weightKg: _numStrict(_get(m, 'weightKg'), 30, 300),
    goalWeightKg: _numStrict(_get(m, 'goalWeightKg'), 30, 300),
    goal: _enum(Goal.values, _get(m, 'goal')),
    experience: _enum(Experience.values, _get(m, 'experience')),
    trainingDays: [for (final d in _arr(_get(m, 'trainingDays'), max: 7)) _enum(Weekday.values, d)],
    sessionMin: _numStrict(_get(m, 'sessionMin'), 20, 120, integer: true).toInt(),
    sessionTime: _opt(_get(m, 'sessionTime'), (v) => _str(v, max: 10)),
    equipment: _strList(_get(m, 'equipment'), max: 20, itemMax: 30),
    dietType: _enum(DietType.values, _get(m, 'dietType')),
    intolerances: _strList(_get(m, 'intolerances'), max: 12, itemMax: 40),
    kcalTarget: _opt(_get(m, 'kcalTarget'), (v) => _numStrict(v, 1000, 5000, integer: true).toInt()),
    proteinTargetG: _opt(_get(m, 'proteinTargetG'), (v) => _numStrict(v, 40, 350, integer: true).toInt()),
  );
}

CoachRequest _parseRequest(Object? json) {
  final m = _obj(json);
  final want = _obj(_get(m, 'want'));
  return CoachRequest(
    code: _str(_get(m, 'code'), max: 20),
    mode: _enum(CoachMode.values, _get(m, 'mode')),
    want: CoachWant(workout: _bool(_get(want, 'workout')), diet: _bool(_get(want, 'diet'))),
    profile: _parseProfile(_get(m, 'profile')),
    notes: _str(_get(m, 'notes'), max: 2000),
    exercises: [
      for (final x in _arr(_get(m, 'exercises'), max: 1500))
        (() {
          final e = _obj(x);
          return CoachExercise(
            id: _str(_get(e, 'id'), max: 80),
            name: _str(_get(e, 'name'), max: 90),
            pattern: _opt(_get(e, 'pattern'), (v) => _str(v, max: 30)),
            unit: _str(_get(e, 'unit'), max: 8),
          );
        })(),
    ],
    current: _opt(_get(m, 'current'), (v) => _str(v, max: 12000)),
  );
}

/* ===================================================================== response (model → app) */

class AiMeal {
  const AiMeal({required this.time, required this.meal, required this.items, this.rotate, required this.kcal, required this.proteinG, this.optional});
  final String time; // H:MM or HH:MM
  final String meal;
  final List<String> items;
  final List<String>? rotate;
  final double kcal; // 0..2000
  final double proteinG; // 0..150
  final bool? optional;
  Map<String, Object?> toJson() => {
        'time': time,
        'meal': meal,
        'items': items,
        if (rotate != null) 'rotate': rotate,
        'kcal': _jsonNum(kcal),
        'proteinG': _jsonNum(proteinG),
        if (optional != null) 'optional': optional,
      };
}

class AiDiet {
  const AiDiet({required this.kcalTarget, required this.proteinTargetG, required this.meals, this.tips});
  final double kcalTarget; // 1000..5000
  final double proteinTargetG; // 40..350
  final List<AiMeal> meals;
  final List<String>? tips;
  Map<String, Object?> toJson() => {
        'kcalTarget': _jsonNum(kcalTarget),
        'proteinTargetG': _jsonNum(proteinTargetG),
        'meals': meals.map((m) => m.toJson()).toList(),
        if (tips != null) 'tips': tips,
      };
}

class _AiExercise {
  const _AiExercise(this.id, this.sets, this.repsMin, this.repsMax, this.unit, this.restSec, this.perSide, this.superset, this.cue);
  final String id;
  final double sets, repsMin, repsMax, restSec;
  final Unit unit;
  final bool? perSide;
  final String? superset;
  final String? cue;
}

class _AiDay {
  const _AiDay(this.weekday, this.type, this.title, this.durationMin, this.notes, this.exercises);
  final Weekday weekday;
  final DayType type;
  final String title;
  final double? durationMin;
  final String? notes;
  final List<_AiExercise> exercises;
}

class _AiPlan {
  const _AiPlan(this.summary, this.workoutName, this.days, this.diet);
  final String summary;
  final String? workoutName; // non-null iff workout present
  final List<_AiDay> days;
  final AiDiet? diet;
}

_AiExercise _parseExercise(Object? json) {
  final m = _obj(json);
  return _AiExercise(
    _str(_get(m, 'id')),
    _numCatch(_get(m, 'sets'), 1, 8),
    _numCatch(_get(m, 'repsMin'), 1, 120),
    _numCatch(_get(m, 'repsMax'), 1, 120),
    _catch(() => _enum(Unit.values, _get(m, 'unit')), Unit.reps),
    _numCatch(_get(m, 'restSec'), 0, 300),
    _catch(() => _opt(_get(m, 'perSide'), _bool), null),
    _catch(() => _opt(_get(m, 'superset'), (v) => _str(v, max: 2)), null),
    _catch(() => _opt(_get(m, 'cue'), (v) => _str(v, max: 140)), null),
  );
}

_AiDay _parseDay(Object? json) {
  final m = _obj(json);
  return _AiDay(
    _enum(Weekday.values, _get(m, 'weekday')),
    _catch(() => _enum(DayType.values, _get(m, 'type')), DayType.strength),
    _catch(() => _str(_get(m, 'title'), max: 60), 'Session'),
    _opt(_get(m, 'durationMin'), (v) => _numCatch(v, 10, 150)),
    _catch(() => _opt(_get(m, 'notes'), (v) => _str(v, max: 200)), null),
    _catch(() => [for (final e in _arr(_get(m, 'exercises'), max: 14)) _parseExercise(e)], const []),
  );
}

final _timeRe = RegExp(r'^\d{1,2}:\d{2}$');

AiMeal _parseMeal(Object? json) {
  final m = _obj(json);
  return AiMeal(
    time: _catch(() {
      final s = _str(_get(m, 'time'));
      return _timeRe.hasMatch(s) ? s : throw const _Fail();
    }, '12:00'),
    meal: _str(_get(m, 'meal'), max: 40),
    items: [for (final x in _arr(_get(m, 'items'), min: 1, max: 8)) _str(x, max: 120)],
    rotate: _catch(() => _opt(_get(m, 'rotate'), (v) => [for (final x in _arr(v, max: 4)) _str(x, max: 160)]), null),
    kcal: _numCatch(_get(m, 'kcal'), 0, 2000),
    proteinG: _numCatch(_get(m, 'proteinG'), 0, 150),
    optional: _catch(() => _opt(_get(m, 'optional'), _bool), null),
  );
}

_AiPlan _parsePlan(Object? json) {
  final m = _obj(json);
  final summary = _catch(() => _str(_get(m, 'summary'), max: 900), '');
  String? workoutName;
  var days = <_AiDay>[];
  final w = _get(m, 'workout');
  if (w is! _Undefined) {
    final wm = _obj(w);
    workoutName = _catch(() => _str(_get(wm, 'name'), max: 60), 'AI coach plan');
    days = [for (final d in _arr(_get(wm, 'days'), max: 7)) _parseDay(d)];
  }
  final diet = _opt(_get(m, 'diet'), (v) {
    final dm = _obj(v);
    return AiDiet(
      kcalTarget: _numCatch(_get(dm, 'kcalTarget'), 1000, 5000),
      proteinTargetG: _numCatch(_get(dm, 'proteinTargetG'), 40, 350),
      meals: [for (final x in _arr(_get(dm, 'meals'), min: 2, max: 8)) _parseMeal(x)],
      tips: _catch(() => _opt(_get(dm, 'tips'), (t) => [for (final x in _arr(t, max: 6)) _str(x, max: 200)]), null),
    );
  });
  return _AiPlan(summary, workoutName, days, diet);
}

/* ===================================================================== prompt */

const Map<Goal, String> _goalText = {
  Goal.fatLoss: 'lose fat while keeping muscle',
  Goal.lean: 'get leaner, stronger and more athletic',
  Goal.muscle: 'build muscle (small calorie surplus)',
  Goal.strength: 'get stronger on the main lifts',
  Goal.general: 'general fitness and feeling good',
};
const Map<DietType, String> _dietText = {
  DietType.veg: 'vegetarian (no eggs, no meat, no fish)',
  DietType.vegEgg: 'vegetarian plus eggs',
  DietType.nonveg: 'eats meat, fish and eggs',
  DietType.vegan: 'vegan',
};

/// Verbatim port of the TS `buildPrompt` (the server builds the real prompt; this is for parity/tests).
({String system, String user}) buildPrompt(CoachRequest r) {
  final p = r.profile;
  final system = [
    'You are an experienced strength & conditioning coach and sports nutritionist building a plan for a gym app.',
    'Reply with ONE JSON object only, no prose, no markdown fences. Schema:',
    '{"summary": string (2-4 friendly sentences: what you built and why),',
    ' "workout"?: {"name": string, "days": [{"weekday": "MON".."SUN", "type": "strength"|"cardio"|"conditioning"|"rest"|"active_recovery", "title": string, "durationMin": number, "notes"?: string,',
    '   "exercises": [{"id": string (MUST be an id from the EXERCISES list), "sets": int, "repsMin": int, "repsMax": int, "unit": "reps"|"seconds"|"minutes"|"meters", "restSec": int, "perSide"?: bool, "superset"?: "A"|"B"|"C", "cue"?: string (one short coaching cue)}]}]},',
    ' "diet"?: {"kcalTarget": int, "proteinTargetG": int, "meals": [{"time": "HH:MM", "meal": string, "items": [string with quantity], "rotate"?: [string alternatives], "kcal": int, "proteinG": int, "optional"?: bool}], "tips"?: [string]}}',
    'Rules:',
    '- Use ONLY exercise ids from EXERCISES (they already match the gym equipment). Never invent ids.',
    '- Include all 7 weekdays in workout.days; non-training days are "rest" or "active_recovery" with no exercises.',
    '- Train only on the given training days. Respect session length: roughly 5-8 exercises for 60-75 min incl. warm-up, fewer for shorter sessions.',
    '- Balance the week: squat, hinge, single-leg, horizontal & vertical push and pull, core; add calves/arms/isolation only if time allows.',
    '- Beginners: 2-3 sets, moderate reps, conservative intervals. Use supersets (same letter) for accessories to save time.',
    '- Use unit "minutes" for steady cardio, "seconds" for holds/intervals.',
    '- Do NOT add warm-up, mobility-flow or cool-down items to training days: the app adds its own warm-up. A short cardio finisher is fine when it serves the goal.',
    '- Honour every injury, dislike, preference and schedule detail in the notes. Safety first: when in doubt choose the joint-friendlier option.',
    '- Diet: meals must fit the diet type and intolerances, use realistic everyday foods (Indian home food is a good default unless the notes say otherwise), give quantities, and make meal kcal/protein sum to within 5% of the targets.',
  ].join('\n');
  final days = p.trainingDays.map((d) => d.wire).join(', ');
  final sessionTime = p.sessionTime;
  final kcalTarget = p.kcalTarget;
  final proteinTargetG = p.proteinTargetG;
  final notes = _jsTrim(r.notes);
  final lines = [
    'MODE: ${r.mode == CoachMode.newPlan ? 'Build a new plan.' : 'Change the CURRENT plan as the notes ask; keep everything else the same.'}',
    'BUILD: ${[if (r.want.workout) 'workout', if (r.want.diet) 'diet'].join(' + ')}',
    'PERSON: ${p.sex.wire}, ${p.age} y, ${_jsNum(p.heightCm)} cm, ${_jsNum(p.weightKg)} kg → goal weight ${_jsNum(p.goalWeightKg)} kg. Goal: ${_goalText[p.goal]}. Experience: ${p.experience.wire}.',
    'SCHEDULE: trains ${days.isEmpty ? 'no fixed days' : days}; ${p.sessionMin} min per session${sessionTime != null && sessionTime.isNotEmpty ? ' at $sessionTime' : ''}.',
    'EQUIPMENT: ${p.equipment.isEmpty ? 'bodyweight only' : p.equipment.join(', ')}.',
    'FOOD: ${_dietText[p.dietType]}${p.intolerances.isNotEmpty ? '; avoid ${p.intolerances.join(', ')}' : ''}.'
        '${kcalTarget != null && kcalTarget != 0 ? ' Current targets $kcalTarget kcal, ${proteinTargetG ?? 'undefined'} g protein (adjust only if clearly wrong for the goal).' : ''}',
    'NOTES FROM THE PERSON: ${notes.isEmpty ? '(none)' : notes}',
  ];
  final current = r.current;
  if (current != null && current.isNotEmpty) lines.addAll(['CURRENT PLAN:', current]);
  if (r.want.workout) {
    lines.add('EXERCISES (id | name | pattern | unit):');
    lines.addAll(r.exercises.map((e) => '${e.id} | ${e.name} | ${e.pattern ?? '-'} | ${e.unit}'));
  }
  return (system: system, user: lines.join('\n'));
}

/// Pull the JSON object out of a model reply (tolerates code fences and stray text).
/// Throws [AiPlanException] when there is no object, or [FormatException] when it is not valid JSON.
Object? extractJson(String text) {
  final t = _jsTrim(text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), ''));
  final a = t.indexOf('{');
  final b = t.lastIndexOf('}');
  if (a < 0 || b <= a) throw const AiPlanException('The coach did not return a plan. Please try again.');
  return jsonDecode(t.substring(a, b + 1));
}

/* ===================================================================== normalise (app side) */

class NormExercise {
  NormExercise({
    required this.slot,
    required this.exerciseId,
    this.supersetGroup,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.unit,
    required this.perSide,
    required this.restSec,
    this.cue,
  });
  String slot;
  final String exerciseId;
  String? supersetGroup;
  final int sets;
  final int repsMin;
  final int repsMax;
  final Unit unit;
  final bool perSide;
  final int restSec;
  final String? cue;

  Map<String, Object?> toJson() => {
        'slot': slot,
        'exerciseId': exerciseId,
        if (supersetGroup != null) 'supersetGroup': supersetGroup,
        'sets': sets,
        'repsMin': repsMin,
        'repsMax': repsMax,
        'unit': unit.wire,
        'perSide': perSide,
        'restSec': restSec,
        if (cue != null) 'cue': cue,
      };
}

class NormDay {
  const NormDay({required this.weekday, required this.type, required this.title, this.durationMin, this.notes, required this.exercises});
  final Weekday weekday;
  final DayType type;
  final String title;
  final int? durationMin;
  final String? notes;
  final List<NormExercise> exercises;

  Map<String, Object?> toJson() => {
        'weekday': weekday.wire,
        'type': type.wire,
        'title': title,
        if (durationMin != null) 'durationMin': durationMin,
        if (notes != null) 'notes': notes,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}

class NormWorkout {
  const NormWorkout({required this.name, required this.days});
  final String name;
  final List<NormDay> days;
  Map<String, Object?> toJson() => {'name': name, 'days': days.map((d) => d.toJson()).toList()};
}

class NormPlan {
  const NormPlan({required this.summary, this.workout, this.diet, required this.warnings});
  final String summary;
  final NormWorkout? workout;
  final AiDiet? diet;
  final List<String> warnings;
  Map<String, Object?> toJson() => {
        'summary': summary,
        if (workout != null) 'workout': workout!.toJson(),
        if (diet != null) 'diet': diet!.toJson(),
        'warnings': warnings,
      };
}

/// Validate and repair a model reply. [allowed] = exercise ids the person can do (equipment-filtered),
/// mapped to their names. Unknown ids are dropped with a warning; empty training days become rest.
/// Throws [AiPlanException] with the same messages as the TS module.
NormPlan normaliseAiPlan(Object? raw, Map<String, String> allowed) {
  final _AiPlan plan;
  try {
    plan = _parsePlan(raw);
  } on _Fail {
    throw const AiPlanException('The coach replied in an unexpected format. Please try again.');
  }
  final warnings = <String>[];
  NormWorkout? workout;
  if (plan.workoutName != null) {
    final byDay = <Weekday, NormDay>{};
    for (final d in plan.days) {
      if (byDay.containsKey(d.weekday)) continue;
      final seen = <String>{};
      final exercises = <NormExercise>[];
      for (final e in d.exercises) {
        if (!allowed.containsKey(e.id)) {
          warnings.add("Skipped an exercise the coach suggested that isn't in your gym's list (${e.id}).");
          continue;
        }
        if (seen.contains(e.id)) continue;
        seen.add(e.id);
        final lo = _jsRound(e.repsMin < e.repsMax ? e.repsMin : e.repsMax).toInt();
        final hi = _jsRound(e.repsMin > e.repsMax ? e.repsMin : e.repsMax).toInt();
        final group = e.superset?.toUpperCase();
        exercises.add(NormExercise(
          slot: '',
          exerciseId: e.id,
          supersetGroup: group == null || group.isEmpty ? null : group,
          sets: _jsRound(e.sets).toInt(),
          repsMin: lo,
          repsMax: hi,
          unit: e.unit,
          perSide: e.perSide == true,
          restSec: (_jsRound(e.restSec / 5) * 5).toInt(),
          cue: e.cue,
        ));
      }
      // superset letters need two partners
      for (final x in exercises) {
        if (x.supersetGroup != null && exercises.where((y) => y.supersetGroup == x.supersetGroup).length < 2) x.supersetGroup = null;
      }
      // slots: A1/A2 for supersets, otherwise letters in order
      var letter = 0;
      final groupLetter = <String, String>{};
      final groupCount = <String, int>{};
      for (final x in exercises) {
        final g = x.supersetGroup;
        if (g != null) {
          final l = groupLetter.putIfAbsent(g, () => String.fromCharCode(65 + letter++));
          final n = (groupCount[l] ?? 0) + 1;
          groupCount[l] = n;
          x.slot = '$l$n';
          x.supersetGroup = l;
        } else {
          x.slot = String.fromCharCode(65 + letter++);
        }
      }
      final training = d.type.isTraining;
      final empty = training && exercises.isEmpty;
      final dur = d.durationMin;
      byDay[d.weekday] = NormDay(
        weekday: d.weekday,
        type: empty ? DayType.rest : d.type,
        title: empty ? 'Rest' : d.title,
        durationMin: dur != null && dur != 0 ? _jsRound(dur).toInt() : null,
        notes: d.notes,
        exercises: training ? exercises : const [],
      );
    }
    final days = [for (final w in kAiWeek) byDay[w] ?? NormDay(weekday: w, type: DayType.rest, title: 'Rest', exercises: const [])];
    if (!days.any((d) => d.exercises.isNotEmpty)) throw const AiPlanException('The coach returned a plan without exercises. Please try again.');
    workout = NormWorkout(name: plan.workoutName!, days: days);
  }
  var diet = plan.diet;
  if (diet != null) {
    final kcal = diet.meals.fold<double>(0, (s, m) => s + m.kcal);
    final protein = diet.meals.fold<double>(0, (s, m) => s + m.proteinG);
    if ((kcal - diet.kcalTarget).abs() > diet.kcalTarget * 0.1) {
      warnings.add('Meals add up to ${_jsNum(_jsRound(kcal))} kcal vs the ${_jsNum(diet.kcalTarget)} kcal target.');
    }
    if (protein < diet.proteinTargetG * 0.85) {
      warnings.add('Meals give ${_jsNum(_jsRound(protein))} g protein vs the ${_jsNum(diet.proteinTargetG)} g target.');
    }
    // stable sort by zero-padded time (Array.prototype.sort is stable)
    final indexed = [for (var i = 0; i < diet.meals.length; i++) (i, diet.meals[i])];
    indexed.sort((a, b) {
      final c = a.$2.time.padLeft(5, '0').compareTo(b.$2.time.padLeft(5, '0'));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    diet = AiDiet(kcalTarget: diet.kcalTarget, proteinTargetG: diet.proteinTargetG, meals: [for (final x in indexed) x.$2], tips: diet.tips);
  }
  if (workout == null && diet == null) throw const AiPlanException('The coach returned an empty plan. Please try again.');
  return NormPlan(summary: plan.summary, workout: workout, diet: diet, warnings: warnings.toSet().take(6).toList());
}
