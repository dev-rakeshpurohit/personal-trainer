// Demo data generator (src/data/devSeed.ts).
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/dev_seed.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

void main() {
  final seed = loadSeed();
  late Stores s;
  final today = DateTime(2026, 12, 1, 9);

  setUp(() async {
    s = memoryStores();
    final b = PlanBuilder(s, seed, newId: counterIds(), now: () => today);
    await b.importProgramTemplate(trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat]);
    await b.importDietTemplate();
    await s.profile.put(backupProfile());
  });
  tearDown(() => s.db.close());

  test('same RNG sequence as the PWA', () {
    final r = demoRng(42);
    // first values of the JS LCG: (s * 1664525 + 1013904223) % 2^32 / 2^32, s0 = 42
    var x = 42;
    for (var i = 0; i < 5; i++) {
      x = (x * 1664525 + 1013904223) % 4294967296;
      expect(r(), x / 4294967296);
    }
  });

  test('fills ~30 days of logs and is deterministic', () async {
    await s.sessions.put(const Session(id: 'keep?', dayKey: '2026-01-01', title: 'x', startedAt: '', status: 'done', cycleWeek: 1, deload: false));
    final r = await seedDemoData(s, today: today, newId: counterIds('d'));
    expect(r.sessions, inInclusiveRange(15, 22)); // 5 training days/week × ~4.3 weeks × 90 %
    expect(r.sets, greaterThan(r.sessions * 10));
    expect(r.weighIns, inInclusiveRange(18, 30));
    expect(await s.sessions.get('keep?'), isNull); // logs are replaced
    expect((await s.activeProgram())!.startedOn, '2026-10-26');
    expect(await s.getMeta<String>('onboardedAt'), isNotNull);
    expect(await s.mealLogs.count(), greaterThan(100));
    expect(await s.habitLogs.count(), greaterThanOrEqualTo(90));

    final again = memoryStores();
    addTearDown(again.db.close);
    final b = PlanBuilder(again, seed, newId: counterIds(), now: () => today);
    await b.importProgramTemplate(trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat]);
    await b.importDietTemplate();
    await again.profile.put(backupProfile());
    final r2 = await seedDemoData(again, today: today, newId: counterIds('d'));
    expect(r2, r);
  });

  test('needs onboarding first', () async {
    await s.profile.delete(Profile.id);
    expect(() => seedDemoData(s, today: today), throwsStateError);
  });
}
