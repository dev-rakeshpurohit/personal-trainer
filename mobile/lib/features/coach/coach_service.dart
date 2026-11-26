// Coach tab state over the local DB: the thread (meta 'coachThread'), the invite code (meta
// 'accessCode'), the free-edit meter (meta 'coachUsage') and approve / undo of proposals.
//
// Beta stub: Pro = meta 'proBeta' == true, or an invite code is saved (TestFlight testers are Pro).
// meta 'proBeta' == false forces the free tier (3 AI edits per calendar month).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/store.dart';
import '../../data/services/common.dart';
import '../../data/services/plan_builder.dart';
import '../../domain/ai_plan.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import 'coach_models.dart';

const kFreeEditsPerMonth = 3;

class CoachMeta {
  static const thread = 'coachThread';
  static const accessCode = 'accessCode';
  static const proBeta = 'proBeta';
  static const usage = 'coachUsage';
}

/// Everything the Coach tab shows that lives in the DB.
class CoachState {
  const CoachState({required this.thread, this.accessCode, required this.pro, required this.usedThisMonth, this.activeProgramId, this.activeDietId});
  final List<CoachMessage> thread;
  final String? accessCode;
  final bool pro;
  final int usedThisMonth;
  final String? activeProgramId;
  final String? activeDietId;

  int get freeLeft => (kFreeEditsPerMonth - usedThisMonth).clamp(0, kFreeEditsPerMonth);
  bool get canAsk => pro || freeLeft > 0;
  bool get hasCode => accessCode != null && accessCode!.isNotEmpty;

  Iterable<CoachProposal> get proposals => thread.where((m) => m.proposal != null).map((m) => m.proposal!);

  /// Undo is possible while the plans this proposal wrote are still the active ones.
  bool canUndo(CoachProposal p) =>
      p.status == ProposalStatus.approved &&
      (p.appliedProgramId == null || p.appliedProgramId == activeProgramId) &&
      (p.appliedDietId == null || p.appliedDietId == activeDietId);
}

String _month(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

class CoachService {
  CoachService(this.s, {required this.now, required this.newId});
  final Stores s;
  final Clock now;
  final IdGen newId;

  Future<List<CoachMessage>> thread() async {
    final raw = await s.getMeta<Object?>(CoachMeta.thread);
    if (raw is! List) return [];
    return raw.map(CoachMessage.tryParse).whereType<CoachMessage>().toList();
  }

  Future<CoachState> state() async {
    final code = await s.getMeta<Object?>(CoachMeta.accessCode);
    final pro = await s.getMeta<Object?>(CoachMeta.proBeta);
    final usage = await s.getMeta<Object?>(CoachMeta.usage);
    final used = usage is Map && usage['month'] == _month(now()) && usage['used'] is num ? (usage['used'] as num).toInt() : 0;
    final codeStr = code is String && code.trim().isNotEmpty ? code.trim() : null;
    return CoachState(
      thread: await thread(),
      accessCode: codeStr,
      pro: pro == true || (pro != false && codeStr != null),
      usedThisMonth: used,
      activeProgramId: (await s.activeProgram())?.id,
      activeDietId: (await s.activeDiet())?.id,
    );
  }

  Future<void> _save(List<CoachMessage> list) => s.setMeta(CoachMeta.thread, [for (final m in list) m.toJson()]);

  Future<void> append(List<CoachMessage> messages) async => _save([...await thread(), ...messages]);

  Future<CoachMessage> message(CoachVoice voice, {String text = '', CoachProposal? proposal}) async =>
      CoachMessage(id: newId(), voice: voice, createdAt: isoString(now()), text: text, proposal: proposal);

  Future<void> updateProposal(String messageId, CoachProposal p) async {
    final list = await thread();
    await _save([for (final m in list) m.id == messageId ? m.copyWith(proposal: p) : m]);
  }

  Future<void> setAccessCode(String code) => s.setMeta(CoachMeta.accessCode, code.trim().toUpperCase());

  /// Count one AI edit against this month's free allowance.
  Future<void> recordEdit() async {
    final st = await state();
    await s.setMeta(CoachMeta.usage, {'month': _month(now()), 'used': st.usedThisMonth + 1});
  }

  /// The active plan as the "before" side of a proposal.
  Future<NormPlan> snapshot() async {
    final bundle = await loadProgramBundle(s);
    final diet = await s.activeDiet();
    final meals = diet == null ? <PlannedMeal>[] : ((await s.plannedMeals.whereK1(diet.id))..sort((a, b) => a.order - b.order));
    return NormPlan(
      summary: '',
      workout: bundle == null ? null : workoutSnapshot(bundle.program, bundle.days, bundle.planned),
      diet: diet == null ? null : dietSnapshot(diet, meals),
      warnings: const [],
    );
  }

  /// Save the proposal's workout / diet as the active plans (the old ones stay in the DB for Undo).
  Future<CoachProposal> approve(CoachProposal p, PlanBuilder builder) async {
    final profile = await s.profile.get(Profile.id);
    if (profile == null) throw StateError('Set up your profile first.');
    final prevProgram = await s.activeProgram();
    final prevDiet = await s.activeDiet();
    final prevProfile = {
      'planSource': profile.planSource,
      'dietSource': profile.dietSource,
      'kcalTarget': profile.kcalTarget,
      'proteinTargetG': profile.proteinTargetG,
    };
    String? programId, dietId;
    final w = p.after.workout;
    final d = p.after.diet;
    if (w != null) programId = await builder.saveAiWorkout(profile, w, today: now());
    if (d != null) dietId = await builder.saveAiDiet(d);
    await s.profile.put(Profile.fromJson({
      ...profile.toJson(),
      if (w != null) 'planSource': 'ai',
      if (d != null) ...{'dietSource': 'ai', 'kcalTarget': jsRound(d.kcalTarget), 'proteinTargetG': jsRound(d.proteinTargetG)},
    }));
    await s.setMeta('setupChangedAt', isoString(now()));
    return p.copyWith(
      status: ProposalStatus.approved,
      decidedAt: isoString(now()),
      appliedProgramId: programId,
      appliedDietId: dietId,
      prevProgramId: prevProgram?.id,
      prevDietId: prevDiet?.id,
      prevProfile: prevProfile,
    );
  }

  /// Undo an approve: deactivate the plans it wrote and re-activate the previous ones.
  Future<CoachProposal> undo(CoachProposal p) async {
    await s.transaction(() async {
      if (p.appliedProgramId != null) {
        final active = await s.programs.whereK1('1');
        await s.programs.putAll(active.map((x) => x.copyWith(active: false)));
        if (p.prevProgramId != null) await s.programs.patch(p.prevProgramId!, {'active': true});
      }
      if (p.appliedDietId != null) {
        final active = await s.dietPlans.whereK1('1');
        await s.dietPlans.putAll(active.map((x) => x.copyWith(active: false)));
        if (p.prevDietId != null) await s.dietPlans.patch(p.prevDietId!, {'active': true});
      }
      final profile = await s.profile.get(Profile.id);
      if (profile != null && p.prevProfile != null) {
        final json = {...profile.toJson()};
        for (final e in p.prevProfile!.entries) {
          json[e.key] = e.value;
        }
        await s.profile.put(Profile.fromJson(json));
      }
    });
    await s.setMeta('setupChangedAt', isoString(now()));
    return p.copyWith(status: ProposalStatus.undone, decidedAt: isoString(now()));
  }
}

final coachServiceProvider = Provider<CoachService>(
  (ref) => CoachService(ref.watch(storesProvider), now: ref.watch(clockProvider), newId: ref.watch(idGenProvider)),
);

/// Live Coach tab state (re-reads when meta, programs or diets change).
final coachStateProvider = StreamProvider<CoachState>((ref) {
  final s = ref.watch(storesProvider);
  final svc = ref.watch(coachServiceProvider);
  return s.live({'meta', 'programs', 'dietPlans'}, svc.state);
});
