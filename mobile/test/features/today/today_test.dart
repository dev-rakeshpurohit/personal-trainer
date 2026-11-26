// Today tab widget tests over an in-memory DB with a controlled clock.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/common.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/today/today_logic.dart';
import 'package:repmate/features/today/today_screen.dart';
import 'package:repmate/state/providers.dart';
import 'package:repmate/ui/theme.dart';

import '../../data/harness.dart';

final seed = loadSeed();

Widget app(Stores s, DateTime now) {
  final router = GoRouter(initialLocation: '/today', routes: [
    GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
    for (final p in ['/workout', '/coach', '/eat', '/train', '/onboarding']) GoRoute(path: p, builder: (_, _) => Scaffold(body: Text('ROUTE $p'))),
  ]);
  return ProviderScope(
    overrides: [
      storesProvider.overrideWithValue(s),
      clockProvider.overrideWithValue(() => now),
      idGenProvider.overrideWithValue(counterIds()),
      seedDataProvider.overrideWith((ref) async => seed),
    ],
    child: MaterialApp.router(theme: buildTheme(Brightness.dark), routerConfig: router),
  );
}

Future<void> settle(WidgetTester t, [int ms = 800]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Scroll the lazily built Today list until [f] is on screen (down first, then back up).
Future<void> reveal(WidgetTester t, Finder f) async {
  final list = find.byType(Scrollable).first;
  for (final dy in [-200.0, 200.0]) {
    for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
      await t.drag(list, Offset(0, dy));
      await t.pump();
    }
  }
  await t.ensureVisible(f);
  await t.pump();
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await reveal(t, f);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

void main() {
  late Stores s;
  final wed = DateTime(2026, 12, 2, 9); // Wednesday; plan trains Mon · Wed · Fri

  setUp(() => s = memoryStores());

  /// A generated Mon/Wed/Fri plan with diet, onboarded at [onboardedAt].
  Future<void> onboard(DateTime now, DateTime onboardedAt) async {
    final b = PlanBuilder(s, seed, newId: counterIds('p'), now: () => now);
    final p = builderProfile().copyWith(name: 'Asha');
    await b.saveGeneratedProgram(p, today: onboardedAt);
    final d = await b.saveGeneratedDiet(p);
    await s.profile.put(p.copyWith(kcalTarget: d.kcalTarget, proteinTargetG: d.proteinTargetG));
    await s.setMeta('onboardedAt', isoString(onboardedAt));
  }

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets("shows today's workout; Start begins a session and opens the logger; meal quick-log", (t) async {
    await phone(t);
    await onboard(wed, wed);
    await t.pumpWidget(app(s, wed));
    await settle(t);

    expect(find.text('Good morning, Asha'), findsOneWidget);
    expect(find.byKey(const Key('today-phase')), findsOneWidget);
    expect(find.text('Week 1 of 8 · Learn'), findsOneWidget);
    expect(find.byKey(const Key('today-hero-training')), findsOneWidget);
    expect(find.byKey(const Key('today-replan')), findsNothing);
    final program = (await s.activeProgram())!;
    final wedDay = (await s.programDays.whereK1(program.id)).firstWhere((d) => d.weekday == Weekday.wed);
    expect(find.text(wedDay.title), findsWidgets);

    // Protein-first diet: "Ate as planned" logs the next meal.
    await tapKey(t, 'today-ate');
    expect(await s.mealLogs.whereK1('2026-12-02'), hasLength(1));
    ScaffoldMessenger.of(t.element(find.byType(TodayScreen))).removeCurrentSnackBar();
    await settle(t, 300);

    // Another day opens a read-only preview (only today can start).
    await tapKey(t, 'strip-5'); // Friday
    expect(find.textContaining('Preview · starts on Friday'), findsOneWidget);
    await t.tapAt(const Offset(195, 40));
    await settle(t);

    await tapKey(t, 'today-start');
    await settle(t, 1000);
    expect(find.text('ROUTE /workout'), findsOneWidget);
    final active = await s.activeSession.get(ActiveSessionState.id);
    expect(active, isNotNull);
    final session = (await s.sessions.get(active!.sessionId))!;
    expect(session.programDayId, wedDay.id);
    expect(session.status, 'active');

    await t.pumpWidget(const SizedBox());
    await s.db.close();
  });

  testWidgets('a missed Monday shows the re-plan card; "Skip it" keeps the week; life status pauses the goal', (t) async {
    await phone(t);
    final monday = DateTime(2026, 11, 30, 7);
    await onboard(wed, monday);
    await t.pumpWidget(app(s, wed));
    await settle(t);

    expect(find.byKey(const Key('today-replan')), findsOneWidget);
    expect(find.textContaining("Missed Monday's"), findsOneWidget);
    // The automatic re-plan moves Monday's session to today.
    expect(find.textContaining('Moved from Mon'), findsOneWidget);

    await tapKey(t, 'replan-skip');
    await reveal(t, find.byKey(const Key('today-replan-done')));
    expect(find.byKey(const Key('today-replan')), findsNothing);
    expect(await s.getMeta<Object?>(replanOffKey(DateTime(2026, 12, 2))), true);
    expect(await s.getMeta<String>(replanChoiceKey(DateTime(2026, 12, 2))), 'skip');
    await reveal(t, find.byKey(const Key('today-hero-training')));
    expect(find.textContaining('Moved from Mon'), findsNothing);

    await tapKey(t, 'life-travelling');
    expect(LifeStatus.parse(await s.getMeta<Object?>(kLifeStatusMeta)), LifeStatus.travelling);
    await reveal(t, find.textContaining('Paused while you'));
    await reveal(t, find.byKey(const Key('today-life-banner')));

    await t.pumpWidget(const SizedBox());
    await s.db.close();
  });

  test('phase label and weekly goal words', () {
    expect(greeting(7), 'Good morning');
    expect(weeklyGoalWords(4, 4), startsWith('Weekly goal hit'));
    expect(weeklyGoalWords(1, 3), startsWith('2 more'));
    expect(shortTitle('Strength A – Lower'), 'Strength A');
  });
}
