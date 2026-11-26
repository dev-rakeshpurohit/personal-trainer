// Widget-test setup for Train and Library: in-memory DB seeded with the template plan, a fixed
// clock (Thursday 3 Dec 2026), and helpers that let drift's real async work finish between pumps.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/state/providers.dart';
import 'package:repmate/ui/theme.dart';

import '../../data/harness.dart';

final kNow = DateTime(2026, 12, 3, 8); // Thursday, week 1 of the block

const kTueSat = [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat];

/// Fresh stores with the full library, the Tue–Sat template plan and an onboarded profile.
Future<Stores> seededStores(WidgetTester tester) async {
  final s = memoryStores();
  await tester.runAsync(() async {
    final b = PlanBuilder(s, loadSeed(), newId: counterIds('p'), now: () => kNow);
    await b.importProgramTemplate(trainingDays: kTueSat);
    await b.ensureLibrary();
    await s.profile.put(backupProfile(trainingDays: kTueSat));
    await s.setMeta('onboardedAt', DateTime(2026, 12, 3, 7).toUtc().toIso8601String());
  });
  return s;
}

/// A done session with working sets (for history / progression).
Future<void> addSession(WidgetTester tester, Stores s, {required String id, required DateTime at, required String exerciseId, required List<(double, int)> sets, String? dayId}) =>
    tester.runAsync(() async {
      await s.sessions.put(Session(
        id: id,
        dayKey: '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}',
        programDayId: dayId,
        title: 'Earlier session',
        startedAt: at.toUtc().toIso8601String(),
        endedAt: at.add(const Duration(hours: 1)).toUtc().toIso8601String(),
        status: 'done',
        cycleWeek: 1,
        deload: false,
      ));
      await s.sets.putAll([
        for (var i = 0; i < sets.length; i++)
          SetLog(id: '$id-$i', sessionId: id, exerciseId: exerciseId, setIndex: i, weightKg: sets[i].$1, reps: sets[i].$2, rir: 3, completedAt: at.toUtc().toIso8601String()),
      ]);
    });

Widget testApp(Stores s, Widget home) => ProviderScope(
      overrides: [
        storesProvider.overrideWithValue(s),
        clockProvider.overrideWithValue(() => kNow),
        idGenProvider.overrideWithValue(counterIds('t')),
        seedDataProvider.overrideWith((ref) async => loadSeed()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    );

/// iPhone 13 logical size.
void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Let DB futures run (real async), then pump frames, until [finder] matches (or give up).
Future<void> pumpUntil(WidgetTester tester, Finder finder, {int tries = 60}) async {
  for (var i = 0; i < tries; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// A few rounds of real async + frames (after a write).
Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Settle, scroll [finder] into view and tap it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await settle(tester, 4);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
}

/// Jump [scrollable] down in small steps (no fling) until [finder] is built, then show it.
Future<void> scrollTo(WidgetTester tester, Finder finder, Finder scrollable) async {
  final pos = tester.state<ScrollableState>(scrollable).position;
  for (var i = 0; i < 60 && finder.evaluate().isEmpty && pos.pixels < pos.maxScrollExtent; i++) {
    pos.jumpTo((pos.pixels + 200).clamp(0, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Unmount and close the DB.
Future<void> teardownApp(WidgetTester tester, Stores s) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => s.db.close());
}
