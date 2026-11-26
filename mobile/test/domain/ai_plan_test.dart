import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/ai_plan.dart';
import 'package:repmate/domain/models.dart';

Matcher _throwsMsg(String re) => throwsA(isA<AiPlanException>().having((e) => e.message, 'message', matches(RegExp(re))));

void main() {
  const allowed = {
    'dumbbell-goblet-squat': 'Dumbbell goblet squat',
    'dumbbell-bench-press': 'Dumbbell bench press',
    'lat-pulldown': 'Lat pulldown',
    'dumbbell-biceps-curl': 'Dumbbell biceps curl',
    'rope-triceps-pushdown': 'Rope triceps pushdown',
  };

  final req = CoachRequest(
    code: 'RPM-AAAA-BBBB',
    mode: CoachMode.newPlan,
    want: const CoachWant(workout: true, diet: true),
    profile: const CoachProfile(
      sex: Sex.male,
      age: 35,
      heightCm: 175,
      weightKg: 82,
      goalWeightKg: 75,
      goal: Goal.lean,
      experience: Experience.beginner,
      trainingDays: [Weekday.tue, Weekday.thu, Weekday.sat],
      sessionMin: 60,
      equipment: ['dumbbells', 'cable'],
      dietType: DietType.vegEgg,
      intolerances: ['peanuts'],
    ),
    notes: 'Bad left knee, no jumping. Love paneer.',
    exercises: [for (final e in allowed.entries) CoachExercise(id: e.key, name: e.value, pattern: 'x', unit: 'reps')],
  );

  group('AI coach prompt', () {
    test('carries the person, notes and only the allowed exercises', () {
      final p = buildPrompt(req);
      expect(p.system, matches(RegExp('ONLY exercise ids')));
      expect(p.user, contains('Bad left knee'));
      expect(p.user, contains('avoid peanuts'));
      expect(p.user, contains('dumbbell-goblet-squat | Dumbbell goblet squat'));
      expect(p.user, contains('trains TUE, THU, SAT'));
    });
    test('omits the exercise list for diet-only requests', () {
      expect(buildPrompt(req.copyWith(want: const CoachWant(workout: false, diet: true))).user, isNot(contains('EXERCISES')));
    });
  });

  group('CoachRequest', () {
    test('serialises exactly like JSON.stringify of the TS request', () {
      expect(
        req.toJsonString(),
        '{"code":"RPM-AAAA-BBBB","mode":"new","want":{"workout":true,"diet":true},'
        '"profile":{"sex":"male","age":35,"heightCm":175,"weightKg":82,"goalWeightKg":75,"goal":"lean","experience":"beginner",'
        '"trainingDays":["TUE","THU","SAT"],"sessionMin":60,"equipment":["dumbbells","cable"],"dietType":"veg_egg","intolerances":["peanuts"]},'
        '"notes":"Bad left knee, no jumping. Love paneer.",'
        '"exercises":[{"id":"dumbbell-goblet-squat","name":"Dumbbell goblet squat","pattern":"x","unit":"reps"},'
        '{"id":"dumbbell-bench-press","name":"Dumbbell bench press","pattern":"x","unit":"reps"},'
        '{"id":"lat-pulldown","name":"Lat pulldown","pattern":"x","unit":"reps"},'
        '{"id":"dumbbell-biceps-curl","name":"Dumbbell biceps curl","pattern":"x","unit":"reps"},'
        '{"id":"rope-triceps-pushdown","name":"Rope triceps pushdown","pattern":"x","unit":"reps"}]}',
      );
      expect(req.isValid, isTrue);
      expect(CoachRequest.parse(req.toJson()).toJsonString(), req.toJsonString());
    });
    test('rejects what the server schema rejects', () {
      expect(req.copyWith(notes: 'x' * 2000).isValid, isTrue);
      expect(req.copyWith(notes: 'x' * 2001).isValid, isFalse);
      expect(() => req.copyWith(notes: 'x' * 2001).validate(), throwsFormatException);
      final j = req.toJson();
      (j['profile'] as Map)['age'] = 35.5;
      expect(() => CoachRequest.parse(j), throwsFormatException);
      (j['profile'] as Map)['age'] = 12;
      expect(() => CoachRequest.parse(j), throwsFormatException);
      (j['profile'] as Map)['age'] = 35;
      (j['profile'] as Map)['sessionTime'] = null; // optional means absent, not null
      expect(() => CoachRequest.parse(j), throwsFormatException);
    });
  });

  group('extractJson', () {
    test('handles fences and stray text', () {
      expect(extractJson('Sure!\n```json\n{"a":1}\n```'), {'a': 1});
      expect(() => extractJson('no plan here'), _throwsMsg('did not return'));
    });
  });

  group('normaliseAiPlan', () {
    final raw = {
      'summary': 'Three full-body days.',
      'workout': {
        'name': 'Lean 3-day',
        'days': [
          {
            'weekday': 'TUE', 'type': 'strength', 'title': 'Full body A', 'durationMin': 60, //
            'exercises': [
              {'id': 'dumbbell-goblet-squat', 'sets': 3, 'repsMin': 12, 'repsMax': 8, 'unit': 'reps', 'restSec': 92},
              {'id': 'box-jump-made-up', 'sets': 3, 'repsMin': 5, 'repsMax': 5, 'unit': 'reps', 'restSec': 60},
              {'id': 'dumbbell-biceps-curl', 'sets': 2, 'repsMin': 10, 'repsMax': 12, 'unit': 'reps', 'restSec': 45, 'superset': 'a'},
              {'id': 'rope-triceps-pushdown', 'sets': 2, 'repsMin': 10, 'repsMax': 12, 'unit': 'reps', 'restSec': 45, 'superset': 'a'},
              {'id': 'dumbbell-goblet-squat', 'sets': 3, 'repsMin': 8, 'repsMax': 10, 'unit': 'reps', 'restSec': 90},
            ],
          },
          {
            'weekday': 'THU', 'type': 'strength', 'title': 'Full body B', //
            'exercises': [
              {'id': 'nope', 'sets': 3, 'repsMin': 8, 'repsMax': 10, 'unit': 'reps', 'restSec': 60},
            ],
          },
          {
            'weekday': 'SAT', 'type': 'strength', 'title': 'Full body C', //
            'exercises': [
              {'id': 'lat-pulldown', 'sets': 99, 'repsMin': 10, 'repsMax': 12, 'unit': 'reps', 'restSec': 60},
            ],
          },
        ],
      },
      'diet': {
        'kcalTarget': 2000,
        'proteinTargetG': 150,
        'meals': [
          {
            'time': '13:00', 'meal': 'Lunch', 'items': ['Paneer bhurji 150 g', '2 roti'], 'kcal': 700, 'proteinG': 45, //
          },
          {
            'time': '7:30', 'meal': 'Breakfast', 'items': ['4 egg whites + 1 egg'], 'kcal': 600, 'proteinG': 40, //
          },
        ],
      },
    };

    test('drops unknown ids, dedupes, fixes rep order, rounds rest and fills the week', () {
      final n = normaliseAiPlan(raw, allowed);
      expect(n.workout!.days, hasLength(7));
      final tue = n.workout!.days.firstWhere((d) => d.weekday == Weekday.tue);
      expect(tue.exercises.map((e) => e.exerciseId).toList(), ['dumbbell-goblet-squat', 'dumbbell-biceps-curl', 'rope-triceps-pushdown']);
      final e0 = tue.exercises[0];
      expect([e0.repsMin, e0.repsMax, e0.restSec, e0.slot], [8, 12, 90, 'A']);
      expect([tue.exercises[1].slot, tue.exercises[1].supersetGroup], ['B1', 'B']);
      expect([tue.exercises[2].slot, tue.exercises[2].supersetGroup], ['B2', 'B']);
      // a training day with nothing valid becomes rest
      final thu = n.workout!.days.firstWhere((d) => d.weekday == Weekday.thu);
      expect(thu.type, DayType.rest);
      expect(thu.exercises, isEmpty);
      expect(n.workout!.days.firstWhere((d) => d.weekday == Weekday.mon).type, DayType.rest);
      expect(n.warnings.any((w) => w.contains('box-jump-made-up')), isTrue);
    });

    test('clamps silly numbers instead of failing', () {
      final sat = normaliseAiPlan(raw, allowed).workout!.days.firstWhere((d) => d.weekday == Weekday.sat);
      expect(sat.exercises[0].sets, lessThanOrEqualTo(8));
    });

    test('sorts meals by time and warns when totals miss the target', () {
      final n = normaliseAiPlan(raw, allowed);
      expect(n.diet!.meals[0].meal, 'Breakfast');
      expect(n.warnings.any((w) => RegExp('1300 kcal').hasMatch(w)), isTrue);
    });

    test('rejects replies with no usable plan', () {
      expect(() => normaliseAiPlan({'summary': 'x'}, allowed), _throwsMsg('empty plan'));
      expect(
        () => normaliseAiPlan({
          'summary': 'x',
          'workout': {
            'name': 'w',
            'days': [
              {
                'weekday': 'MON', 'type': 'strength', 'title': 'A', //
                'exercises': [
                  {'id': 'nope', 'sets': 3, 'repsMin': 5, 'repsMax': 5, 'unit': 'reps', 'restSec': 60},
                ],
              },
            ],
          },
        }, allowed),
        _throwsMsg('without exercises'),
      );
      expect(() => normaliseAiPlan('garbage', allowed), _throwsMsg('unexpected format'));
    });
  });
}
