// Widget-test setup shared by the Eat and Progress tests: an onboarded in-memory DB with ~30 days
// of demo data, a fixed clock, and helpers to let drift streams settle under the test binding.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/dev_seed.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/state/providers.dart';
import 'package:repmate/ui/theme.dart';

import '../../data/harness.dart';

/// Thursday 3 Dec 2026, 13:00 (lunch time).
final kTestNow = DateTime(2026, 12, 3, 13);

class FeatureEnv {
  FeatureEnv(this.s, this.now);
  final Stores s;
  DateTime now;

  List<Override> get overrides => [
        storesProvider.overrideWithValue(s),
        clockProvider.overrideWithValue(() => now),
        idGenProvider.overrideWithValue(counterIds('t')),
        seedDataProvider.overrideWith((ref) async => loadSeed()),
      ];
}

/// Onboards (program Tue–Sat + diet template + profile) and seeds demo data, outside fake async.
Future<FeatureEnv> setUpFeature(WidgetTester tester, {bool demo = true}) async {
  final s = memoryStores();
  final env = FeatureEnv(s, kTestNow);
  await tester.runAsync(() async {
    final b = PlanBuilder(s, loadSeed(), newId: counterIds('p'), now: () => env.now);
    await b.importProgramTemplate(trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat], today: env.now);
    await b.importDietTemplate();
    await s.profile.put(backupProfile());
    await s.setMeta('onboardedAt', '2026-11-01T09:00:00.000Z');
    if (demo) await seedDemoData(s, today: env.now, newId: counterIds('demo'));
  });
  return env;
}

/// Pumps [child] inside the app theme with the env's provider overrides.
Future<void> pumpFeature(WidgetTester tester, FeatureEnv env, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: env.overrides,
    child: MaterialApp(theme: buildTheme(Brightness.dark), home: child),
  ));
  await settle(tester);
  for (var i = 0; i < 100 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  await settle(tester);
}

/// Lets real-async DB work and stream updates land, then pumps frames.
Future<void> settle(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Unmounts the tree (cancelling streams) and closes the DB.
Future<void> tearDownFeature(WidgetTester tester, FeatureEnv env) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester, rounds: 2);
  await tester.runAsync(() => env.s.db.close());
}
