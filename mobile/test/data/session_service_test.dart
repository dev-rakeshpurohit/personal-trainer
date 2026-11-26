// Session lifecycle (src/features/workout/session.ts + Player/Summary data logic), mirroring
// tests/e2e/workout.spec.ts: Tuesday 2026-12-01 09:15, Lean & Athletic template, Strength A.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/common.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/data/services/progression_data.dart';
import 'package:repmate/data/services/session_service.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/domain/progression.dart';

import 'harness.dart';

void main() {
  final seed = loadSeed();
  late Stores s;
  late SessionService svc;
  late TestClock clock;
  late ProgramDay tue;
  final profile = backupProfile(trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat]);
  final tuesday = DateTime(2026, 12, 1, 9, 15);

  setUp(() async {
    s = memoryStores();
    clock = TestClock(tuesday);
    final ids = counterIds();
    final b = PlanBuilder(s, seed, newId: ids, now: clock.call);
    await b.importProgramTemplate(trainingDays: profile.trainingDays);
    await s.profile.put(profile);
    svc = SessionService(s, newId: counterIds('x'), now: clock.call);
    tue = (await s.programDays.all()).firstWhere((d) => d.weekday == Weekday.tue);
  });
  tearDown(() => s.db.close());

  Future<String> start({SessionMode mode = SessionMode.full}) async {
    final p = (await svc.prepareSession(tue.id, mode, date: clock()))!;
    return svc.startSession(p, mode, date: clock());
  }

  /// Log every planned set of an exercise at [kg] × [reps] (rir 3), following the flow.
  Future<void> logAll(int idx, double kg, int reps) async {
    final st = (await svc.resume())!;
    for (var i = 0; i < st.totalSets(idx); i++) {
      await svc.logAndAdvance(idx, i, SetValues(weightKg: kg, reps: reps, rir: 3));
      clock.advance(const Duration(minutes: 2));
    }
  }

  group('prepare & start', () {
    test('Strength A from the template: superset A1/A2, week-1 RIR, resume state', () async {
      final p = (await svc.prepareSession(tue.id, SessionMode.full, date: tuesday))!;
      expect(p.day.title, contains('Strength A'));
      expect(p.plan.map((e) => e.exerciseId).take(2), ['dumbbell-goblet-squat', 'dumbbell-bench-press']);
      expect(p.plan[0].supersetGroup, 'A');
      expect(p.plan[0].isMain, isTrue);
      expect(p.plan[0].rir, 3);
      expect(p.cycleWeek, 1);
      expect(p.deload, isFalse);
      expect(p.adaptation.reasons, isEmpty);
      expect(p.estMin, greaterThan(30));

      final id = await svc.startSession(p, SessionMode.full, date: tuesday);
      final session = (await s.sessions.get(id))!;
      expect(session.status, 'active');
      expect(session.dayKey, '2026-12-01');
      expect(session.startedAt, isoString(tuesday));
      expect(session.mode, SessionMode.full);
      final v = (await svc.activeSession())!;
      expect(v.session.id, id);
      expect(v.active.plan, hasLength(6));
      expect(v.active.hold, isFalse);
      // starting again returns the running session
      expect(await svc.startSession(p, SessionMode.full), id);
      expect(await s.sessions.count(), 1);
    });

    test('express trims Strength A to the 4 A/B lifts at 2 sets', () async {
      final p = (await svc.prepareSession(tue.id, SessionMode.express, date: tuesday))!;
      expect(p.plan, hasLength(4));
      expect(p.plan.every((e) => e.sets <= 2), isTrue);
    });

    test('unknown day → null', () async {
      expect(await svc.prepareSession('nope', SessionMode.full), isNull);
    });
  });

  group('logging', () {
    test('superset flow, rest timer and resume after a kill', () async {
      final id = await start();
      final r1 = await svc.logAndAdvance(0, 0, const SetValues(weightKg: 16, reps: 8));
      expect(r1.row.sessionId, id);
      expect(r1.row.exerciseId, 'dumbbell-goblet-squat');
      expect(r1.row.swappedFromExerciseId, isNull);
      expect(r1.row.completedAt, isoString(tuesday));
      expect(r1.next, (ex: 1, set: 0)); // A2
      expect(r1.restSec, 60);
      expect(r1.restEndsAt, tuesday.add(const Duration(seconds: 60)));
      expect(r1.prs, isEmpty); // first time ever

      await svc.skipRest();
      expect((await s.activeSession.get('current'))!.restEndsAt, isNull);

      final r2 = await svc.logAndAdvance(1, 0, const SetValues(weightKg: 14, reps: 8));
      expect(r2.next, (ex: 0, set: 1)); // back to A1 set 2
      expect(await s.sets.count(), 2);

      // "kill the app": a fresh service resumes on the same exercise and set
      final st = (await SessionService(s).resume())!;
      expect(st.idx, 0);
      expect(st.current!.exerciseId, 'dumbbell-goblet-squat');
      expect(st.nextSetIdx, 1);
      expect(st.setsFor(0).map((x) => x.setIndex), [0]);
      expect(st.doneKeys, {'0:0', '1:0'});
      expect(st.allDone, isFalse);
      expect(st.restEndsAt, tuesday.add(const Duration(seconds: 90)));
    });

    test('reps are required for a reps set; bodyweight drops the weight', () async {
      await start();
      expect(() => svc.logAndAdvance(0, 0, const SetValues(weightKg: 16)), throwsArgumentError);
      await svc.swapExercise(0, 'bodyweight-squat');
      final r = await svc.logAndAdvance(0, 0, const SetValues(weightKg: 16, reps: 12));
      expect(r.row.weightKg, isNull);
      expect(r.row.exerciseId, 'bodyweight-squat');
    });

    test('extra set extends the flow; undo restores a deleted set', () async {
      await start();
      final st0 = (await svc.resume())!;
      final pe = st0.plan[5]; // D front plank, 3 sets
      expect(st0.totalSets(5), 3);
      await svc.addExtraSet(pe.plannedExerciseId);
      final st = (await svc.resume())!;
      expect(st.totalSets(5), 4);
      expect(st.flow.length, st0.flow.length + 1);

      final r = await svc.logAndAdvance(5, 0, const SetValues(seconds: 40));
      expect(await s.sets.count(), 1);
      final undo = await svc.deleteSet(r.row.id);
      expect(await s.sets.count(), 0);
      await undo();
      expect((await s.sets.get(r.row.id))!.seconds, 40);
      await svc.updateSet(r.row.id, {'rir': 2});
      expect((await s.sets.get(r.row.id))!.rir, 2);
    });

    test('rest timer adjust never ends in the past', () async {
      await start();
      await svc.logAndAdvance(0, 0, const SetValues(weightKg: 16, reps: 8));
      await svc.adjustRest(15);
      var a = (await s.activeSession.get('current'))!;
      expect(a.restEndsAt, isoString(tuesday.add(const Duration(seconds: 75))));
      expect(a.restTotalSec, 75);
      await svc.adjustRest(-600);
      a = (await s.activeSession.get('current'))!;
      expect(a.restEndsAt, isoString(tuesday));
      expect(a.restTotalSec, 1);
    });

    test('PR detected against earlier sessions, toast once per exercise per session', () async {
      await s.sessions.put(const Session(id: 'old', dayKey: '2026-11-24', title: 'A', startedAt: '2026-11-24T03:45:00.000Z', status: 'done', cycleWeek: 1, deload: false));
      await s.sets.put(const SetLog(id: 'o1', sessionId: 'old', exerciseId: 'dumbbell-goblet-squat', setIndex: 0, weightKg: 20, reps: 10, completedAt: '2026-11-24T03:50:00.000Z'));
      await start();
      final r = await svc.logAndAdvance(0, 0, const SetValues(weightKg: 22, reps: 8));
      expect(r.prs, containsAll([PRType.weight, PRType.e1rm]));
      expect(r.showPr, isTrue);
      final r2 = await svc.logAndAdvance(0, 1, const SetValues(weightKg: 24, reps: 8));
      expect(r2.prs, contains(PRType.weight));
      expect(r2.showPr, isFalse);
      expect((await s.activeSession.get('current'))!.prShown, ['dumbbell-goblet-squat']);
    });
  });

  group('swaps', () {
    test('just today: separate history, swappedFrom recorded, plan untouched; back restores', () async {
      await start();
      await svc.swapExercise(1, 'dumbbell-floor-press');
      var a = (await s.activeSession.get('current'))!;
      expect(a.plan![1].exerciseId, 'dumbbell-floor-press');
      expect(a.plan![1].originalExerciseId, 'dumbbell-bench-press');
      expect(a.swaps, {a.plan![1].plannedExerciseId: 'dumbbell-floor-press'});
      final r = await svc.logAndAdvance(1, 0, const SetValues(weightKg: 14, reps: 8));
      expect(r.row.exerciseId, 'dumbbell-floor-press');
      expect(r.row.swappedFromExerciseId, 'dumbbell-bench-press');
      expect((await s.plannedExercises.get(a.plan![1].plannedExerciseId))!.exerciseId, 'dumbbell-bench-press');

      await svc.swapExercise(1, 'dumbbell-bench-press');
      a = (await s.activeSession.get('current'))!;
      expect(a.plan![1].exerciseId, 'dumbbell-bench-press');
      expect(a.swaps, isEmpty);
    });

    test('always: rewrites the planned exercise and keeps the old one reachable', () async {
      await start();
      final a0 = (await s.activeSession.get('current'))!;
      final peId = a0.plan![0].plannedExerciseId;
      final before = (await s.plannedExercises.get(peId))!;
      await svc.swapExercise(0, 'bodyweight-squat', always: true);
      final pe = (await s.plannedExercises.get(peId))!;
      expect(pe.exerciseId, 'bodyweight-squat');
      expect(pe.swapExerciseId, before.swapExerciseId);
      final bw = (await s.exercises.get('bodyweight-squat'))!;
      expect(bw.alternates, isNotNull);
      expect(bw.alternates!.first, 'dumbbell-goblet-squat');
      expect(bw.alternates, isNot(contains('bodyweight-squat')));
      // next session starts with the new exercise
      await svc.discardSession(a0.sessionId);
      final p = (await svc.prepareSession(tue.id, SessionMode.full, date: tuesday))!;
      expect(p.plan[0].exerciseId, 'bodyweight-squat');
    });

    test('making the planned swap permanent swaps the two around', () async {
      final pes = (await s.plannedExercises.whereK1(tue.id))..sort((a, b) => a.order - b.order);
      final bench = pes[1];
      expect(bench.swapExerciseId, 'dumbbell-floor-press');
      await svc.makePermanentSwap(bench.id, 'dumbbell-floor-press');
      final after = (await s.plannedExercises.get(bench.id))!;
      expect(after.exerciseId, 'dumbbell-floor-press');
      expect(after.swapExerciseId, 'dumbbell-bench-press');
    });
  });

  group('finish & feedback → next session adapts', () {
    Future<String> doSession({required SessionFeedback fb}) async {
      final id = await start();
      await logAll(0, 20, 10);
      await svc.finishSession(id, notes: 'good', feedback: fb);
      return id;
    }

    test('finish marks the session done, clears the active state and saves feedback', () async {
      final id = await doSession(fb: const SessionFeedback(rpe: 7, feel: Feel.justRight, note: 'felt fine'));
      final ss = (await s.sessions.get(id))!;
      expect(ss.status, 'done');
      expect(ss.endedAt, isNotNull);
      expect(ss.rpe, 7);
      expect(ss.notes, 'felt fine'); // feedback note replaces the session note, as in the PWA
      expect(ss.feedback!.feel, Feel.justRight);
      expect(await svc.activeSession(), isNull);
      expect(await s.activeSession.count(), 0);

      final sum = (await svc.summary(id))!;
      expect(sum.count, 4);
      expect(sum.volume, 4 * 20 * 10);
      expect(sum.durationSec, greaterThan(0));
      expect(sum.prs, isEmpty); // nothing earlier to beat
      expect(sum.exercises, ['dumbbell-goblet-squat']);
      expect(sum.planned, hasLength(6));
    });

    test('too hard: hold weights + trim an accessory set next time', () async {
      final nextTue = tuesday.add(const Duration(days: 7));
      final baseline = (await svc.prepareSession(tue.id, SessionMode.full, date: nextTue))!;
      await doSession(fb: const SessionFeedback(rpe: 9, feel: Feel.tooHard));
      clock.t = nextTue;

      // without the hold the goblet squat would go up (all sets at the top of the range)
      final pe = (await s.plannedExercises.whereK1(tue.id)).firstWhere((p) => p.exerciseId == 'dumbbell-goblet-squat');
      final program = (await s.activeProgram())!;
      final plain = await ProgressionData(s).suggestionFor(pe, pe.exerciseId, await s.exercises.get(pe.exerciseId), profile, program, nextTue);
      expect(plain.kind, SuggestionKind.increase);
      expect(plain.weightKg, 22);

      final p = (await svc.prepareSession(tue.id, SessionMode.full, date: nextTue))!;
      expect(p.adaptation.holdProgression, isTrue);
      expect(p.adaptation.reasons.first, contains('very hard'));
      final accessory = p.plan.indexWhere((e) => !e.isMain && e.unit == Unit.reps);
      expect(p.plan[accessory].sets, baseline.plan[accessory].sets - 1);
      expect(p.plan[0].sets, baseline.plan[0].sets); // main lifts keep their sets

      await svc.startSession(p, SessionMode.full, date: nextTue);
      final a = (await s.activeSession.get('current'))!;
      expect(a.hold, isTrue);
      final sug = await svc.suggestionForActive(a, 0, profile);
      expect(sug.suggestion.kind, SuggestionKind.hold);
      expect(sug.suggestion.weightKg, 20);
      expect(sug.suggestion.message, 'Holding weight today: last session felt very hard');
      expect(sug.suggestion.prefill.every((x) => x.weightKg == 20), isTrue);
      expect(sug.last, '20 kg × 10, 20 kg × 10, 20 kg × 10, 20 kg × 10');
      final draft = draftFor(a.plan![0], sug.suggestion, const [], 0);
      expect(draft, const SetValues(weightKg: 20, reps: 8));
    });

    test('pain: keep the weight on that exercise only', () async {
      await doSession(fb: const SessionFeedback(rpe: 7, feel: Feel.justRight, pain: ['dumbbell-goblet-squat']));
      clock.t = tuesday.add(const Duration(days: 7));
      final p = (await svc.prepareSession(tue.id, SessionMode.full))!;
      expect(p.adaptation.holdProgression, isFalse);
      expect(p.adaptation.pain, ['dumbbell-goblet-squat']);
      await svc.startSession(p, SessionMode.full);
      final a = (await s.activeSession.get('current'))!;
      expect(a.pain, ['dumbbell-goblet-squat']);
      final sug = await svc.suggestionForActive(a, 0, profile);
      expect(sug.suggestion.kind, SuggestionKind.hold);
      expect(sug.suggestion.message, 'Pain last time: keep the weight, move carefully');
    });

    test('ran out of time: Express is suggested next time', () async {
      await doSession(fb: const SessionFeedback(rpe: 7, feel: Feel.justRight, ranOutOfTime: true));
      final p = (await svc.prepareSession(tue.id, SessionMode.full, date: tuesday.add(const Duration(days: 7))))!;
      expect(p.adaptation.preferExpress, isTrue);
      expect(p.adaptation.holdProgression, isFalse);
    });

    test('two easy sessions: +1 accessory set', () async {
      final nextNext = tuesday.add(const Duration(days: 14));
      final baseline = (await svc.prepareSession(tue.id, SessionMode.full, date: nextNext))!;
      await doSession(fb: const SessionFeedback(rpe: 5, feel: Feel.tooEasy));
      clock.t = tuesday.add(const Duration(days: 7));
      await doSession(fb: const SessionFeedback(rpe: 5, feel: Feel.tooEasy));
      final p = (await svc.prepareSession(tue.id, SessionMode.full, date: nextNext))!;
      expect(p.adaptation.accessorySetsDelta, 1);
      final accessory = p.plan.indexWhere((e) => !e.isMain && e.unit == Unit.reps);
      expect(p.plan[accessory].sets, baseline.plan[accessory].sets + 1);
      // and the summary of the second session shows the earlier one as history
      final ids = (await s.sessions.all()).map((x) => x.id).toList();
      expect(ids, hasLength(2));
    });

    test('discard removes the session and its sets', () async {
      final id = await start();
      await svc.logAndAdvance(0, 0, const SetValues(weightKg: 16, reps: 8));
      await svc.discardSession(id);
      expect(await s.sessions.count(), 0);
      expect(await s.sets.count(), 0);
      expect(await svc.activeSession(), isNull);
    });
  });
}
