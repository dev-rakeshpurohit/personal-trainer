// Port of src/lib/coach.ts: builds the AI coach request from local data, POSTs it to /api/coach
// and normalises the reply with normaliseAiPlan. The invite code is passed in by the caller
// (kept in secure storage by the app).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../domain/ai_plan.dart';
import '../../domain/equipment.dart';
import '../../domain/models.dart';
import '../db/store.dart';
import 'common.dart';

const String kCoachBaseUrl = 'https://repmate-test.vercel.app';

final _odd = RegExp(
  r'exercise ball|stability ball|bosu|\(v\d\)|arm blaster|stork|throw down|pov|on knees|towel|self assisted|pirate|side lying|with leg raised|with bicep curl|kipping|planche|maltese|flag|elevator|impossible|korean|skin the cat',
  caseSensitive: false,
);
const _maxLevel = {Experience.beginner: 3, Experience.intermediate: 4, Experience.advanced: 5};

/// Exercises the coach may choose from: what fits the gym, without odd variants, sensible for the level.
List<Exercise> coachExercises(List<Exercise> lib, Profile p) {
  final eq = equipmentOf(p);
  final max = _maxLevel[p.experience ?? Experience.beginner]!;
  return lib
      .where((e) =>
          isAvailable(e, eq) &&
          (e.source != 'dataset' || (e.pattern != null && e.pattern!.isNotEmpty && !_odd.hasMatch(e.name) && (e.level ?? 2) <= max)))
      .toList();
}

class CoachError implements Exception {
  const CoachError(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class CoachResult {
  const CoachResult({required this.plan, this.costUsd, required this.model});
  final NormPlan plan;
  final double? costUsd;
  final String model;
}

class CoachClient {
  CoachClient(this.s, {http.Client? client, String baseUrl = kCoachBaseUrl, Clock? now, this.timeout = const Duration(minutes: 3)})
      : client = client ?? http.Client(),
        baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        now = now ?? systemNow;
  final Stores s;
  final http.Client client;
  final String baseUrl;
  final Clock now;
  final Duration timeout;

  /// Compact text of the current plan for "change my plan" requests.
  Future<String?> currentPlanText(Map<String, Exercise> byId) async {
    final program = await s.activeProgram();
    if (program == null) return null;
    final days = (await s.programDays.whereK1(program.id))..sort((a, b) => a.weekday.index - b.weekday.index);
    final planned = (await s.plannedExercises.whereK1In(days.map((d) => d.id)))..sort((a, b) => a.order - b.order);
    final diet = await s.activeDiet();
    final meals = diet == null ? <PlannedMeal>[] : ((await s.plannedMeals.whereK1(diet.id))..sort((a, b) => a.order - b.order));
    final lines = [
      for (final d in days)
        () {
          final ex = [
            for (final p in planned.where((p) => p.dayId == d.id))
              '${p.exerciseId} (${byId[p.exerciseId]?.name ?? ''}) ${p.sets}x${p.repsMin}-${p.repsMax}'
                  '${p.unit == Unit.reps ? '' : ' ${p.unit.wire}'}'
                  '${p.supersetGroup != null && p.supersetGroup!.isNotEmpty ? ' ss${p.supersetGroup}' : ''}',
          ];
          final dur = d.durationMin != null && d.durationMin != 0 ? ' ${d.durationMin}min' : '';
          return '${d.weekday.wire} ${d.type.wire} "${d.title}"$dur: ${ex.isEmpty ? '-' : ex.join('; ')}';
        }(),
      if (diet != null) ...[
        'DIET ${diet.kcalTarget} kcal / ${diet.proteinTargetG} g protein:',
        for (final m in meals) '${m.time} ${m.meal}: ${m.items.join(', ')} (${jsNum(m.kcal)} kcal, ${jsNum(m.proteinG)} g)',
      ],
    ];
    final text = lines.join('\n');
    return text.length > 12000 ? text.substring(0, 12000) : text;
  }

  /// Build the request body (exposed for tests and the coach screen's "what is sent" view).
  Future<CoachRequest> buildRequest({required CoachMode mode, required CoachWant want, required String notes, required String code}) async {
    final p = await s.profile.get(Profile.id);
    if (p == null) throw const CoachError('Set up your profile first.');
    final lib = (await s.exercises.all())..sort((a, b) => a.id.compareTo(b.id));
    final byId = {for (final e in lib) e.id: e};
    final allowed = coachExercises(lib, p);
    final bodies = (await s.bodyLogs.all()).where((b) => b.weightKg != null).toList()..sort((a, b) => b.dayKey.compareTo(a.dayKey));
    return CoachRequest(
      code: code,
      mode: mode,
      want: want,
      profile: CoachProfile(
        sex: p.sex,
        age: math.min(100, math.max(13, now().year - p.birthYear)),
        heightCm: p.heightCm,
        weightKg: bodies.isEmpty ? p.startWeightKg : bodies.first.weightKg!,
        goalWeightKg: p.goalWeightKg,
        goal: p.goal ?? Goal.lean,
        experience: p.experience ?? Experience.beginner,
        trainingDays: p.trainingDays,
        sessionMin: p.sessionMin ?? 60,
        sessionTime: p.sessionTime,
        equipment: equipmentOf(p),
        dietType: p.dietType,
        intolerances: p.intolerances,
        kcalTarget: p.kcalTarget == 0 ? null : p.kcalTarget,
        proteinTargetG: p.proteinTargetG == 0 ? null : p.proteinTargetG,
      ),
      notes: notes.length > 2000 ? notes.substring(0, 2000) : notes,
      exercises: want.workout
          ? [
              for (final e in allowed.take(1500))
                CoachExercise(id: e.id, name: e.name.length > 90 ? e.name.substring(0, 90) : e.name, pattern: e.pattern, unit: e.defaultUnit.wire),
            ]
          : const [],
      current: mode == CoachMode.change ? await currentPlanText(byId) : null,
    );
  }

  /// Ask the AI coach for a new plan or a change. [code] is the invite code (required by the server).
  /// Throws [CoachError] (network / server errors) or [AiPlanException] (unusable reply).
  Future<CoachResult> askCoach({required CoachMode mode, required CoachWant want, required String notes, String? code}) async {
    if (await s.profile.get(Profile.id) == null) throw const CoachError('Set up your profile first.');
    if (code == null || code.isEmpty) throw const CoachError('Enter your invite code to use the AI coach.', 401);
    final body = await buildRequest(mode: mode, want: want, notes: notes, code: code);
    final lib = (await s.exercises.all())..sort((a, b) => a.id.compareTo(b.id));
    final p = (await s.profile.get(Profile.id))!;
    final allowed = {for (final e in coachExercises(lib, p)) e.id: e.name};

    http.Response r;
    try {
      r = await client
          .post(Uri.parse('$baseUrl/api/coach'), headers: {'content-type': 'application/json'}, body: body.toJsonString())
          .timeout(timeout);
    } on TimeoutException {
      throw const CoachError('The coach took too long to answer. Please try again.');
    } catch (_) {
      throw const CoachError('No connection. The AI coach needs internet; your current plan still works offline.');
    }
    Map<String, Object?> data;
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      data = d is Map ? d.cast<String, Object?>() : {};
    } catch (_) {
      data = {};
    }
    if (r.statusCode < 200 || r.statusCode > 299) {
      throw CoachError(data['error'] is String ? data['error'] as String : 'The coach is unavailable right now.', r.statusCode);
    }
    final plan = normaliseAiPlan(data['plan'], allowed);
    final cost = data['costUsd'];
    return CoachResult(plan: plan, costUsd: cost is num ? cost.toDouble() : null, model: data['model'] is String ? data['model'] as String : '');
  }
}
