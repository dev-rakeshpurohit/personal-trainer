// Coach thread models: messages (you, the AI coach, a trainer) and proposals, persisted as JSON in
// meta 'coachThread'. Proposals keep a snapshot of the plan they were compared against ("before"),
// so the diff in Plan history still reads correctly after the plan has changed.
import '../../domain/ai_plan.dart';
import '../../domain/models.dart';

/// Who wrote a thread message. Violet = AI coach, teal = trainer (trainer messages are a later feature).
enum CoachVoice { user, coach, trainer, proposal }

enum ProposalStatus { pending, approved, discarded, undone }

class CoachMessage {
  const CoachMessage({required this.id, required this.voice, required this.createdAt, this.text = '', this.author, this.proposal});

  final String id;
  final CoachVoice voice;

  /// ISO-8601 UTC.
  final String createdAt;
  final String text;

  /// Trainer name (trainer messages).
  final String? author;
  final CoachProposal? proposal;

  CoachMessage copyWith({CoachProposal? proposal}) =>
      CoachMessage(id: id, voice: voice, createdAt: createdAt, text: text, author: author, proposal: proposal ?? this.proposal);

  Map<String, Object?> toJson() => {
        'id': id,
        'voice': voice.name,
        'createdAt': createdAt,
        if (text.isNotEmpty) 'text': text,
        if (author != null) 'author': author,
        if (proposal != null) 'proposal': proposal!.toJson(),
      };

  /// Returns null for rows it can't read (a newer app version, corrupted data) instead of throwing.
  static CoachMessage? tryParse(Object? json) {
    try {
      if (json is! Map) return null;
      final m = json.cast<String, Object?>();
      final voice = CoachVoice.values.firstWhere((v) => v.name == m['voice'], orElse: () => CoachVoice.coach);
      final p = m['proposal'];
      final proposal = p is Map ? CoachProposal.fromJson(p.cast()) : null;
      if (voice == CoachVoice.proposal && proposal == null) return null;
      return CoachMessage(
        id: m['id'] as String,
        voice: voice,
        createdAt: (m['createdAt'] ?? '') as String,
        text: (m['text'] ?? '') as String,
        author: m['author'] as String?,
        proposal: proposal,
      );
    } catch (_) {
      return null;
    }
  }
}

class CoachProposal {
  const CoachProposal({
    required this.title,
    required this.request,
    required this.mode,
    required this.want,
    required this.before,
    required this.after,
    this.status = ProposalStatus.pending,
    this.adjusted = false,
    this.decidedAt,
    this.appliedProgramId,
    this.appliedDietId,
    this.prevProgramId,
    this.prevDietId,
    this.prevProfile,
    this.model,
  });

  final String title;

  /// What the person asked, as typed.
  final String request;
  final CoachMode mode;
  final CoachWant want;

  /// The active plan when the proposal arrived (workout and/or diet; either can be null).
  final NormPlan before;

  /// The coach's plan, including any Adjust edits.
  final NormPlan after;
  final ProposalStatus status;
  final bool adjusted;
  final String? decidedAt;
  final String? appliedProgramId;
  final String? appliedDietId;
  final String? prevProgramId;
  final String? prevDietId;

  /// Profile fields changed on approve (planSource, dietSource, kcalTarget, proteinTargetG), for Undo.
  final Map<String, Object?>? prevProfile;
  final String? model;

  bool get touchesWorkout => after.workout != null;
  bool get touchesDiet => after.diet != null;

  CoachProposal copyWith({
    NormPlan? after,
    ProposalStatus? status,
    bool? adjusted,
    String? decidedAt,
    String? appliedProgramId,
    String? appliedDietId,
    String? prevProgramId,
    String? prevDietId,
    Map<String, Object?>? prevProfile,
  }) =>
      CoachProposal(
        title: title,
        request: request,
        mode: mode,
        want: want,
        before: before,
        after: after ?? this.after,
        status: status ?? this.status,
        adjusted: adjusted ?? this.adjusted,
        decidedAt: decidedAt ?? this.decidedAt,
        appliedProgramId: appliedProgramId ?? this.appliedProgramId,
        appliedDietId: appliedDietId ?? this.appliedDietId,
        prevProgramId: prevProgramId ?? this.prevProgramId,
        prevDietId: prevDietId ?? this.prevDietId,
        prevProfile: prevProfile ?? this.prevProfile,
        model: model,
      );

  Map<String, Object?> toJson() => {
        'title': title,
        'request': request,
        'mode': mode.wire,
        'want': want.toJson(),
        'before': before.toJson(),
        'after': after.toJson(),
        'status': status.name,
        if (adjusted) 'adjusted': true,
        'decidedAt': ?decidedAt,
        'appliedProgramId': ?appliedProgramId,
        'appliedDietId': ?appliedDietId,
        'prevProgramId': ?prevProgramId,
        'prevDietId': ?prevDietId,
        'prevProfile': ?prevProfile,
        'model': ?model,
      };

  factory CoachProposal.fromJson(Map<String, Object?> j) {
    final want = (j['want'] as Map?)?.cast<String, Object?>() ?? const {};
    return CoachProposal(
      title: (j['title'] ?? 'Plan change') as String,
      request: (j['request'] ?? '') as String,
      mode: j['mode'] == 'new' ? CoachMode.newPlan : CoachMode.change,
      want: CoachWant(workout: want['workout'] == true, diet: want['diet'] == true),
      before: normPlanFromJson(j['before']),
      after: normPlanFromJson(j['after']),
      status: ProposalStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => ProposalStatus.pending),
      adjusted: j['adjusted'] == true,
      decidedAt: j['decidedAt'] as String?,
      appliedProgramId: j['appliedProgramId'] as String?,
      appliedDietId: j['appliedDietId'] as String?,
      prevProgramId: j['prevProgramId'] as String?,
      prevDietId: j['prevDietId'] as String?,
      prevProfile: (j['prevProfile'] as Map?)?.cast<String, Object?>(),
      model: j['model'] as String?,
    );
  }
}

/* ------------------------------------------------------------ NormPlan JSON (the inverse of NormPlan.toJson) */

int _i(Object? v, int fallback) => v is num ? v.round() : fallback;
double _d(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
List<String> _strs(Object? v) => v is List ? [for (final x in v) '$x'] : const [];

NormExercise normExerciseFromJson(Map<String, Object?> m) => NormExercise(
      slot: (m['slot'] ?? '') as String,
      exerciseId: m['exerciseId'] as String,
      supersetGroup: m['supersetGroup'] as String?,
      sets: _i(m['sets'], 3),
      repsMin: _i(m['repsMin'], 8),
      repsMax: _i(m['repsMax'], 12),
      unit: Unit.parse(m['unit']),
      perSide: m['perSide'] == true,
      restSec: _i(m['restSec'], 90),
      cue: m['cue'] as String?,
    );

NormDay normDayFromJson(Map<String, Object?> m) => NormDay(
      weekday: Weekday.parse(m['weekday']),
      type: DayType.parse(m['type']),
      title: (m['title'] ?? '') as String,
      durationMin: m['durationMin'] is num ? (m['durationMin'] as num).round() : null,
      notes: m['notes'] as String?,
      exercises: [for (final e in (m['exercises'] as List? ?? const [])) normExerciseFromJson((e as Map).cast())],
    );

AiDiet aiDietFromJson(Map<String, Object?> m) => AiDiet(
      kcalTarget: _d(m['kcalTarget'], 0),
      proteinTargetG: _d(m['proteinTargetG'], 0),
      meals: [
        for (final x in (m['meals'] as List? ?? const []))
          () {
            final meal = (x as Map).cast<String, Object?>();
            return AiMeal(
              time: (meal['time'] ?? '') as String,
              meal: (meal['meal'] ?? '') as String,
              items: _strs(meal['items']),
              rotate: meal['rotate'] == null ? null : _strs(meal['rotate']),
              kcal: _d(meal['kcal'], 0),
              proteinG: _d(meal['proteinG'], 0),
              optional: meal['optional'] as bool?,
            );
          }(),
      ],
      tips: m['tips'] == null ? null : _strs(m['tips']),
    );

NormPlan normPlanFromJson(Object? json) {
  final m = json is Map ? json.cast<String, Object?>() : const <String, Object?>{};
  final w = m['workout'];
  final d = m['diet'];
  return NormPlan(
    summary: (m['summary'] ?? '') as String,
    workout: w is Map
        ? NormWorkout(
            name: (w['name'] ?? '') as String,
            days: [for (final day in (w['days'] as List? ?? const [])) normDayFromJson((day as Map).cast())],
          )
        : null,
    diet: d is Map ? aiDietFromJson(d.cast()) : null,
    warnings: _strs(m['warnings']),
  );
}

/* ------------------------------------------------------------ snapshots of the active plan */

/// The active program as a [NormWorkout] (days in week order).
NormWorkout workoutSnapshot(Program program, List<ProgramDay> days, List<PlannedExercise> planned) {
  final sorted = [...days]..sort((a, b) => a.weekday.index - b.weekday.index);
  return NormWorkout(name: program.name, days: [
    for (final d in sorted)
      NormDay(
        weekday: d.weekday,
        type: d.type,
        title: d.title,
        durationMin: d.durationMin,
        notes: d.notes,
        exercises: [
          for (final p in (planned.where((p) => p.dayId == d.id).toList()..sort((a, b) => a.order - b.order)))
            NormExercise(
              slot: p.slot,
              exerciseId: p.exerciseId,
              supersetGroup: p.supersetGroup,
              sets: p.sets,
              repsMin: p.repsMin,
              repsMax: p.repsMax,
              unit: p.unit,
              perSide: p.perSide,
              restSec: p.restSec,
              cue: p.cue,
            ),
        ],
      ),
  ]);
}

/// The active diet as an [AiDiet].
AiDiet dietSnapshot(DietPlan plan, List<PlannedMeal> meals) => AiDiet(
      kcalTarget: plan.kcalTarget.toDouble(),
      proteinTargetG: plan.proteinTargetG.toDouble(),
      meals: [
        for (final m in meals)
          AiMeal(time: m.time, meal: m.meal, items: m.items, rotate: m.rotate, kcal: m.kcal, proteinG: m.proteinG, optional: m.optional),
      ],
    );
