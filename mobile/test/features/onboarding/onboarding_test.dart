// Onboarding widget tests over an in-memory DB: organic flow (paywall shown once) and the
// trainer/promo branch (no paywall, Pro via code, start Workout 1 now).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/onboarding/draft.dart';
import 'package:repmate/features/onboarding/ob_widgets.dart';
import 'package:repmate/features/onboarding/onboarding_screen.dart';
import 'package:repmate/features/today/today_screen.dart';
import 'package:repmate/state/providers.dart';
import 'package:repmate/ui/theme.dart';
import 'package:repmate/ui/widgets.dart';

import '../../data/harness.dart';

final seed = loadSeed();

Widget app(Stores s, DateTime now, {List<bool>? permissionAsks}) {
  final router = GoRouter(initialLocation: '/onboarding', routes: [
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
    for (final p in ['/workout', '/coach', '/eat', '/train']) GoRoute(path: p, builder: (_, _) => Scaffold(body: Text('ROUTE $p'))),
  ]);
  return ProviderScope(
    overrides: [
      storesProvider.overrideWithValue(s),
      clockProvider.overrideWithValue(() => now),
      idGenProvider.overrideWithValue(counterIds()),
      seedDataProvider.overrideWith((ref) async => seed),
      notificationPermissionProvider.overrideWithValue(() async {
        permissionAsks?.add(true);
        return true;
      }),
    ],
    child: MaterialApp.router(theme: buildTheme(Brightness.light), routerConfig: router),
  );
}

Future<void> settle(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).first;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

/// Wait for the real build step (library import + plan + diet) and open the reveal.
Future<void> waitForPlan(WidgetTester t) async {
  for (var i = 0; i < 200; i++) {
    await t.pump(const Duration(milliseconds: 200));
    final b = find.byKey(const Key('ob-see-plan'));
    if (b.evaluate().isNotEmpty && t.widget<RfButton>(b).onPressed != null) break;
  }
  await tapKey(t, 'ob-see-plan');
}

void main() {
  late Stores s;
  final now = DateTime(2026, 12, 2, 9); // Wednesday

  setUp(() => s = memoryStores());

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('organic onboarding: plan saved, first edit falls back to Coach tab, paywall shown once', (t) async {
    await phone(t);
    final asks = <bool>[];
    await t.pumpWidget(app(s, now, permissionAsks: asks));
    await settle(t);

    expect(find.text('Your gym coach + Indian diet plan.'), findsOneWidget);
    await tapKey(t, 'ob-next'); // welcome
    await tapText(t, 'Build muscle');
    await tapKey(t, 'ob-next'); // goal
    await tapKey(t, 'ob-next'); // experience
    await tapKey(t, 'ob-next'); // schedule (Mon · Wed · Fri, 45 min)
    await tapKey(t, 'ob-next'); // gym
    await tapText(t, 'None');
    await tapKey(t, 'ob-next'); // body check
    await tapKey(t, 'ob-next'); // about you
    expect(find.text('Your coach shows its working'), findsOneWidget);
    await tapKey(t, 'ob-next'); // interlude
    await tapKey(t, 'ob-next'); // diet
    await tapKey(t, 'ob-next'); // protein
    await tapText(t, 'Hinglish');
    await tapKey(t, 'ob-next'); // language → build

    await waitForPlan(t);
    expect(find.text('Week 1'), findsOneWidget);
    await tapKey(t, 'ob-reveal-next');
    expect(find.text('Plan check'), findsOneWidget);
    await tapKey(t, 'ob-reveal-next');
    expect(find.text('A day of eating'), findsOneWidget);
    await tapKey(t, 'ob-reveal-next');

    // First edit without a code: shown as available in the Coach tab, then continue.
    await t.enterText(find.byKey(const Key('ob-edit-field')), 'no squats, knee is sensitive');
    await settle(t, 200);
    await tapKey(t, 'ob-edit-ask');
    expect(find.byKey(const Key('ob-edit-unavailable')), findsOneWidget);
    await tapKey(t, 'ob-edit-skip');

    expect(find.text('Your plan is saved on this phone'), findsOneWidget);
    await tapKey(t, 'ob-save-next');
    await tapKey(t, 'ob-notify-yes');
    expect(asks, [true]);

    expect(find.text('Keep your plan coaching itself'), findsOneWidget);
    expect(find.byKey(const Key('ob-paywall-close')), findsOneWidget);
    await tapKey(t, 'ob-paywall-free');

    expect(find.byKey(const Key('ob-start-now')), findsOneWidget);
    await tapKey(t, 'ob-later');
    await settle(t, 1000);
    expect(find.textContaining('Good morning'), findsOneWidget);

    final p = (await s.profile.get(Profile.id))!;
    expect(p.goal, Goal.muscle);
    expect(p.trainingDays, [Weekday.mon, Weekday.wed, Weekday.fri]);
    expect(p.proteinTargetG, greaterThan(0));
    expect(await s.activeProgram(), isNotNull);
    expect(await s.activeDiet(), isNotNull);
    expect(await s.getMeta<String>(ObMeta.onboardedAt), isNotNull);
    expect(await s.getMeta<String>(ObMeta.paywallSeenAt), isNotNull);
    expect(await s.getMeta<Object?>(ObMeta.proBeta), isNull);
    expect(await s.getMeta<String>(ObMeta.coachLanguage), 'hinglish');
    expect(await s.getMeta<List<Object?>>(ObMeta.painAreas), isEmpty);
    expect((await s.getMeta<Map<Object?, Object?>>(ObMeta.reminders))!['enabled'], true);
    expect((await s.bodyLogs.all()).single.weightKg, 75);

    await t.pumpWidget(const SizedBox());
    await s.db.close();
  });

  testWidgets('trainer/promo code: shorter flow, Pro via code, no paywall, Workout 1 starts now', (t) async {
    await phone(t);
    await t.pumpWidget(app(s, now));
    await settle(t);

    await tapKey(t, 'ob-have-code');
    await t.enterText(find.byKey(const Key('ob-code-field')), 'SANDEEP30');
    await tapKey(t, 'ob-code-apply');
    await settle(t, 400);
    expect(find.textContaining('Code SANDEEP30 applied'), findsOneWidget);
    expect(find.byKey(const Key('ob-have-code')), findsNothing);

    await tapKey(t, 'ob-next'); // welcome
    await tapText(t, 'Lose fat');
    await tapKey(t, 'ob-next'); // goal
    await tapKey(t, 'ob-next'); // experience
    await tapKey(t, 'ob-next'); // schedule
    await tapKey(t, 'ob-next'); // gym
    await tapText(t, 'Knee');
    await tapKey(t, 'ob-next'); // body check
    await tapKey(t, 'ob-next'); // about
    expect(find.text('Your coach shows its working'), findsNothing); // no interlude on this branch
    await tapKey(t, 'ob-next'); // diet
    await tapKey(t, 'ob-next'); // protein → build

    await waitForPlan(t);
    for (var i = 0; i < 3; i++) {
      await tapKey(t, 'ob-reveal-next');
    }
    await tapKey(t, 'ob-save-next');
    await tapKey(t, 'ob-notify-no');

    expect(find.text('Keep your plan coaching itself'), findsNothing);
    await tapKey(t, 'ob-start-now');
    await settle(t, 1500);
    expect(find.text('ROUTE /workout'), findsOneWidget);

    expect(await s.getMeta<String>(ObMeta.accessCode), 'SANDEEP30');
    expect(await s.getMeta<String>(ObMeta.proViaCode), 'SANDEEP30');
    expect(await s.getMeta<String>(ObMeta.paywallSeenAt), isNull);
    expect(await s.getMeta<List<Object?>>(ObMeta.painAreas), ['knee']);
    expect((await s.profile.get(Profile.id))!.goal, Goal.fatLoss);
    final active = await s.activeSession.get(ActiveSessionState.id);
    expect(active, isNotNull);
    expect((await s.sessions.get(active!.sessionId))!.dayKey, '2026-12-02');

    await t.pumpWidget(const SizedBox());
    await s.db.close();
  });

  test('draft → profile: unticked foods and avoid list become intolerances', () {
    final d = OnboardingDraft()
      ..diet = DietType.vegEgg
      ..proteinSources = {'dal', 'curd', 'eggs'}
      ..avoid = {'gluten'};
    expect(d.intolerances, ['paneer', 'soy', 'gluten']);
    final p = d.toProfile(now: now, createdAt: 'x');
    expect(p.birthYear, 1996);
    expect(p.sessionTime, '18:30');
    final back = OnboardingDraft.fromProfile(p, year: 2026);
    expect(back.proteinSources.containsAll({'dal', 'curd', 'eggs'}), isTrue);
    expect(back.proteinSources.contains('paneer'), isFalse);
    expect(back.avoid, {'gluten'});
  });
}
