// AI coach client (src/lib/coach.ts) against a mocked /api/coach.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/coach_client.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/ai_plan.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

void main() {
  final seed = loadSeed();
  late Stores s;
  final now = DateTime(2026, 12, 1, 9);

  setUp(() async {
    s = memoryStores();
    final b = PlanBuilder(s, seed, newId: counterIds(), now: () => now);
    await b.ensureLibrary();
    await b.importProgramTemplate(trainingDays: const [Weekday.tue, Weekday.thu]);
    await b.importDietTemplate();
    await s.profile.put(builderProfile());
    await s.bodyLogs.put(const BodyLog(id: 'b1', dayKey: '2026-11-20', weightKg: 67.5));
    await s.bodyLogs.put(const BodyLog(id: 'b2', dayKey: '2026-11-28', waistCm: 80));
  });
  tearDown(() => s.db.close());

  test('coachExercises only offers what fits the gym and the level', () async {
    final lib = await s.exercises.all();
    final allowed = coachExercises(lib, builderProfile());
    expect(allowed, isNotEmpty);
    expect(allowed.every((e) => isAvailable(e, kPresets['dumbbells_only']!)), isTrue);
    expect(allowed.where((e) => e.source == 'dataset').every((e) => (e.level ?? 2) <= 3 && e.pattern != null), isTrue);
  });

  test('builds the request, posts it and normalises the reply', () async {
    late Map<String, Object?> sent;
    late Uri url;
    final client = MockClient((req) async {
      url = req.url;
      sent = (jsonDecode(req.body) as Map).cast();
      return http.Response(
        jsonEncode({
          'plan': {
            'summary': 'Upper/lower',
            'workout': {
              'name': 'AI · 2 days',
              'days': [
                {
                  'weekday': 'TUE',
                  'type': 'strength',
                  'title': 'Upper',
                  'exercises': [
                    {'id': 'dumbbell-bench-press', 'sets': 3, 'repsMin': 8, 'repsMax': 12, 'unit': 'reps', 'restSec': 90},
                    {'id': 'not-a-real-id', 'sets': 3, 'repsMin': 8, 'repsMax': 12, 'unit': 'reps', 'restSec': 90},
                  ],
                },
              ],
            },
          },
          'costUsd': 0.009,
          'model': 'anthropic/claude-haiku-5.5',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final c = CoachClient(s, client: client, baseUrl: 'https://example.test/', now: () => now);
    final r = await c.askCoach(mode: CoachMode.change, want: const CoachWant(workout: true, diet: false), notes: 'more upper body', code: 'RPM-TEST-CODE');
    expect(url.toString(), 'https://example.test/api/coach');
    expect(sent['code'], 'RPM-TEST-CODE');
    expect(sent['mode'], 'change');
    final prof = (sent['profile'] as Map).cast<String, Object?>();
    expect(prof['age'], 31);
    expect(prof['weightKg'], 67.5); // latest weigh-in, not the start weight
    expect(prof.containsKey('kcalTarget'), isFalse); // 0 → omitted
    expect(prof['equipment'], kPresets['dumbbells_only']);
    expect((sent['exercises'] as List), isNotEmpty);
    final current = sent['current'] as String;
    expect(current, contains('TUE strength'));
    expect(current, contains('DIET 2000 kcal'));
    expect(current, isNot(contains('.0 kcal')));
    expect(CoachRequest.parse(sent).mode, CoachMode.change); // the server would accept it

    expect(r.model, 'anthropic/claude-haiku-5.5');
    expect(r.costUsd, 0.009);
    expect(r.plan.workout!.days.firstWhere((d) => d.weekday == Weekday.tue).exercises.map((e) => e.exerciseId), ['dumbbell-bench-press']);
    expect(r.plan.warnings.join(' '), contains('not-a-real-id'));
  });

  test('errors: no code, server error, offline', () async {
    final c0 = CoachClient(s, client: MockClient((_) async => http.Response('{}', 200)));
    await expectLater(c0.askCoach(mode: CoachMode.newPlan, want: const CoachWant(workout: true, diet: true), notes: ''),
        throwsA(isA<CoachError>().having((e) => e.status, 'status', 401)));

    final c1 = CoachClient(s, client: MockClient((_) async => http.Response(jsonEncode({'error': 'Too many requests'}), 429)));
    await expectLater(c1.askCoach(mode: CoachMode.newPlan, want: const CoachWant(workout: false, diet: true), notes: '', code: 'X'),
        throwsA(isA<CoachError>().having((e) => e.message, 'message', 'Too many requests').having((e) => e.status, 'status', 429)));

    final c2 = CoachClient(s, client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(c2.askCoach(mode: CoachMode.newPlan, want: const CoachWant(workout: true, diet: false), notes: '', code: 'X'),
        throwsA(isA<CoachError>().having((e) => e.message, 'message', startsWith('No connection'))));

    await s.profile.delete(Profile.id);
    await expectLater(c1.askCoach(mode: CoachMode.newPlan, want: const CoachWant(workout: true, diet: false), notes: '', code: 'X'),
        throwsA(isA<CoachError>().having((e) => e.message, 'message', 'Set up your profile first.')));
  });
}
