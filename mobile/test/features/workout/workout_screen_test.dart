// Gym-floor logger over an in-memory DB: Tuesday 2026-12-01 09:15, Lean & Athletic template,
// Strength A (A1 goblet squat / A2 dumbbell bench superset).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/state/ui_state.dart' show gymModeProvider;
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/data/services/session_service.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/workout/rest_alerts.dart';
import 'package:repmate/features/workout/rest_band.dart';
import 'package:repmate/features/workout/summary_screen.dart';
import 'package:repmate/features/workout/workout_screen.dart';
import 'package:repmate/state/providers.dart';
import 'package:repmate/ui/theme.dart';

import '../../data/harness.dart';

class FakeSurface implements RestTimerSurface {
  final shown = <RestTimerInfo>[];
  var clears = 0;
  @override
  Future<void> show(RestTimerInfo info) async => shown.add(info);
  @override
  Future<void> clear() async => clears++;
}

class FakePermission implements RestAlertPermission {
  var granted_ = false;
  var requests = 0;
  @override
  Future<bool> granted() async => granted_;
  @override
  Future<bool> request() async {
    requests++;
    return granted_ = true;
  }
}

class FakeAwake implements ScreenAwake {
  final calls = <bool>[];
  @override
  Future<void> set(bool on) async => calls.add(on);
}

void main() {
  final seed = loadSeed();
  late Stores s;
  late TestClock clock;
  late SessionService svc;
  late FakeSurface surface;
  late FakePermission permission;
  late FakeAwake awake;
  late String sessionId;
  late Map<String, String> names;
  const days = [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat];

  setUp(() async {
    s = memoryStores();
    clock = TestClock(DateTime(2026, 12, 1, 9, 15));
    await PlanBuilder(s, seed, newId: counterIds(), now: clock.call).importProgramTemplate(trainingDays: days);
    await s.profile.put(backupProfile(trainingDays: days));
    svc = SessionService(s, newId: counterIds('x'), now: clock.call);
    final tue = (await s.programDays.all()).firstWhere((d) => d.weekday == Weekday.tue);
    final p = (await svc.prepareSession(tue.id, SessionMode.full, date: clock()))!;
    sessionId = await svc.startSession(p, SessionMode.full, date: clock());
    names = {for (final e in await s.exercises.all()) e.id: e.name};
    surface = FakeSurface();
    permission = FakePermission();
    awake = FakeAwake();
  });
  tearDown(() => s.db.close());

  Widget app() => ProviderScope(
        overrides: [
          storesProvider.overrideWithValue(s),
          clockProvider.overrideWithValue(clock.call),
          idGenProvider.overrideWithValue(counterIds('w')),
          seedDataProvider.overrideWith((ref) async => seed),
          restSurfacesProvider.overrideWithValue([surface]),
          restAlertPermissionProvider.overrideWithValue(permission),
          screenAwakeProvider.overrideWithValue(awake),
        ],
        child: MaterialApp.router(
          theme: buildTheme(Brightness.dark),
          routerConfig: GoRouter(initialLocation: '/workout', routes: [
            GoRoute(path: '/workout', builder: (_, _) => const WorkoutScreen()),
            GoRoute(path: '/today', builder: (_, _) => const Scaffold(body: Text('Today home'))),
          ]),
        ),
      );

  /// Let DB futures, streams and frames run (real async for sqlite, fake time for frames).
  Future<void> settle(WidgetTester t, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<T> db<T>(WidgetTester t, Future<T> Function() f) async => (await t.runAsync(f)) as T;

  Future<void> tapText(WidgetTester t, String text) async {
    final f = find.text(text);
    await t.ensureVisible(f.first);
    await t.pump();
    await t.tap(f.first);
    await settle(t);
  }

  /// Scroll the visible exercise page until [f] is built and on screen.
  Future<void> reveal(WidgetTester t, Finder f) async {
    final list = find.descendant(of: find.byType(PageView), matching: find.byType(Scrollable)).last;
    await t.scrollUntilVisible(f, 150, scrollable: list);
    await t.pump();
  }

  /// iPhone 13 viewport (390×844 @3x).
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t, rounds: 3);
  }

  testWidgets('Done set logs a row, rest band appears with effort chips, skip rest clears it', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);

    expect(find.text(names['dumbbell-goblet-squat']!), findsOneWidget);
    await reveal(t, find.text('SET 1 OF 4'));
    expect(find.text('SET 1 OF 4'), findsOneWidget);
    expect(find.text('Exercise 1 of 6'), findsOneWidget);
    expect(awake.calls, [true]);
    expect(ProviderScope.containerOf(t.element(find.byType(WorkoutScreen))).read(gymModeProvider), isTrue);
    // first time on this lift: calibration copy
    expect(find.textContaining('Find a weight you could do'), findsOneWidget);

    await tapText(t, 'Done set');

    final sets = await db(t, () => s.sets.whereK1(sessionId));
    expect(sets, hasLength(1));
    expect(sets.single.exerciseId, 'dumbbell-goblet-squat');
    expect(sets.single.setIndex, 0);
    expect(sets.single.reps, greaterThan(0));

    expect(find.byType(RestBand), findsOneWidget);
    expect(find.text('Skip rest'), findsOneWidget);
    expect(surface.shown, hasLength(1));
    expect(surface.shown.single.endsAt, clock().add(const Duration(seconds: 60)));
    // superset: the logger moves on to A2
    expect(find.text(names['dumbbell-bench-press']!), findsOneWidget);

    // effort during rest is stored as RIR on the logged set
    await tapText(t, '2 left');
    expect((await db(t, () => s.sets.get(sets.single.id)))!.rir, 2);

    // −15 moves the stored end timestamp and re-syncs the notification
    await tapText(t, '−15');
    final a = (await db(t, () => s.activeSession.get(ActiveSessionState.id)))!;
    expect(DateTime.parse(a.restEndsAt!).toLocal(), clock().add(const Duration(seconds: 45)));
    expect(surface.shown.last.endsAt, clock().add(const Duration(seconds: 45)));

    // permission is asked only from the button tap
    expect(permission.requests, 0);
    await tapText(t, 'Alert me when rest ends');
    expect(permission.requests, 1);

    final clearsBefore = surface.clears;
    await tapText(t, 'Skip rest');
    expect(find.byType(RestBand), findsNothing);
    expect(find.text('Done set'), findsOneWidget);
    expect((await db(t, () => s.activeSession.get(ActiveSessionState.id)))!.restEndsAt, isNull);
    expect(surface.clears, greaterThan(clearsBefore));
    await close(t);
  });

  testWidgets('rest ends on its own when the clock passes the end timestamp', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);
    await tapText(t, 'Done set');
    expect(find.byType(RestBand), findsOneWidget);
    clock.advance(const Duration(seconds: 61));
    await settle(t);
    expect(find.byType(RestBand), findsNothing);
    expect((await db(t, () => s.activeSession.get(ActiveSessionState.id)))!.restEndsAt, isNull);
    await close(t);
  });

  testWidgets('resume opens at the right exercise and set', (t) async {
    await svc.logAndAdvance(0, 0, const SetValues(weightKg: 16, reps: 10));
    await svc.logAndAdvance(1, 0, const SetValues(weightKg: 14, reps: 10));
    await svc.skipRest();
    phone(t);
    await t.pumpWidget(app());
    await settle(t);
    expect(find.text(names['dumbbell-goblet-squat']!), findsOneWidget);
    await reveal(t, find.text('SET 2 OF 4'));
    expect(find.text('SET 2 OF 4'), findsOneWidget);
    // the done set is listed with its values; next draft carries the weight over
    expect(find.text('16 kg × 10'), findsWidgets);
    await close(t);
  });

  testWidgets('swap just today changes the session plan, not the program', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);
    await tapText(t, 'Swap');
    expect(find.textContaining('Why swap'), findsOneWidget);
    await tapText(t, 'Busy');
    expect(find.text('Pick an alternative'), findsOneWidget);
    await tapText(t, 'Just today');

    final a = (await db(t, () => s.activeSession.get(ActiveSessionState.id)))!;
    final se = a.plan!.first;
    expect(se.exerciseId, isNot('dumbbell-goblet-squat'));
    expect(se.originalExerciseId, 'dumbbell-goblet-squat');
    expect(a.swaps[se.plannedExerciseId], se.exerciseId);
    expect((await db(t, () => s.plannedExercises.get(se.plannedExerciseId)))!.exerciseId, 'dumbbell-goblet-squat');
    expect(find.text(names[se.exerciseId]!), findsOneWidget);
    expect(find.text('Swapped today'), findsOneWidget);
    await close(t);
  });

  testWidgets('finish → narrated summary → feedback saved → Today', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);
    await tapText(t, 'Done set');
    await tapText(t, 'Skip rest');
    await tapText(t, 'Finish');
    expect(find.text('Finish now?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Finish'));
    await settle(t, rounds: 20);

    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('WORKOUT #1'), findsOneWidget);
    expect(find.text('Great start!'), findsOneWidget);
    expect(find.textContaining(names['dumbbell-goblet-squat']!), findsWidgets);
    expect(find.textContaining('Baseline'), findsOneWidget);
    expect(surface.clears, greaterThan(0));
    final session = (await db(t, () => s.sessions.get(sessionId)))!;
    expect(session.status, 'done');

    await tapText(t, 'Quick check-in');
    await tapText(t, 'Too hard');
    await tapText(t, 'Ran out of time');
    await tapText(t, 'Save & done');
    final saved = (await db(t, () => s.sessions.get(sessionId)))!;
    expect(saved.feedback?.feel, Feel.tooHard);
    expect(saved.feedback?.ranOutOfTime, isTrue);
    expect(saved.rpe, 9);
    expect(find.text('Today home'), findsOneWidget);
    await close(t);
    expect(awake.calls.last, isFalse);
  });

  testWidgets('finishing with nothing logged offers discard', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);
    await tapText(t, 'Finish');
    expect(find.text('Nothing logged yet'), findsOneWidget);
    await t.tap(find.text('Discard workout'));
    await settle(t);
    expect(find.text('Today home'), findsOneWidget);
    expect(await db(t, () => s.sessions.get(sessionId)), isNull);
    await close(t);
  });

  testWidgets('list overview jumps to an exercise', (t) async {
    phone(t);
    await t.pumpWidget(app());
    await settle(t);
    await tapText(t, 'Exercise 1 of 6');
    final third = (await db(t, () => s.activeSession.get(ActiveSessionState.id)))!.plan![2];
    await t.tap(find.textContaining(names[third.exerciseId]!).first);
    await settle(t);
    expect(find.text('Exercise 3 of 6'), findsOneWidget);
    expect((await db(t, () => s.activeSession.get(ActiveSessionState.id)))!.exerciseIdx, 2);
    await close(t);
  });
}

