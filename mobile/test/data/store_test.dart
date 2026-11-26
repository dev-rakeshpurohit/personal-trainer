import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/app_db.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/domain/models.dart';

void main() {
  late AppDb db;
  late Stores s;
  setUp(() {
    db = AppDb(NativeDatabase.memory());
    s = Stores(db);
  });
  tearDown(() => db.close());

  SetLog set(String id, String session, String ex, int i) =>
      SetLog(id: id, sessionId: session, exerciseId: ex, setIndex: i, weightKg: 20, reps: 10, completedAt: '2026-12-01T09:30:00Z');

  test('put/get round-trips the PWA JSON shape', () async {
    const ex = Exercise(id: 'push-up', name: 'Push-up', primaryMuscles: ['chest'], defaultUnit: Unit.reps, demoId: '0662', source: 'curated');
    await s.exercises.put(ex);
    final back = await s.exercises.get('push-up');
    expect(back!.toJson(), ex.toJson());
    expect(await s.exercises.count(), 1);
  });

  test('indexed lookups by k1/k2 and ranges', () async {
    await s.sets.putAll([set('a', 's1', 'squat', 0), set('b', 's1', 'bench', 0), set('c', 's2', 'squat', 0)]);
    expect((await s.sets.whereK1('s1')).map((x) => x.id), unorderedEquals(['a', 'b']));
    expect((await s.sets.whereK2('squat')).map((x) => x.id), unorderedEquals(['a', 'c']));
    await s.sessions.putAll([
      const Session(id: 's1', dayKey: '2026-12-01', title: 'A', startedAt: '', status: 'done', cycleWeek: 1, deload: false),
      const Session(id: 's2', dayKey: '2026-12-09', title: 'B', startedAt: '', status: 'done', cycleWeek: 2, deload: false),
    ]);
    expect((await s.sessions.k1Between('2026-11-30', '2026-12-06')).map((x) => x.id), ['s1']);
  });

  test('watch streams emit on writes; addMissing keeps existing rows', () async {
    final emitted = <int>[];
    final sub = s.sets.watchK1('s1').listen((l) => emitted.add(l.length));
    await pumpEventQueue();
    await s.sets.put(set('a', 's1', 'squat', 0));
    await pumpEventQueue();
    await s.sets.put(set('b', 's1', 'squat', 1));
    await pumpEventQueue();
    await sub.cancel();
    expect(emitted.last, 2);

    await s.exercises.put(const Exercise(id: 'x', name: 'Mine', cue: 'keep'));
    await s.exercises.addMissing([const Exercise(id: 'x', name: 'Seed'), const Exercise(id: 'y', name: 'New')]);
    expect((await s.exercises.get('x'))!.cue, 'keep');
    expect(await s.exercises.count(), 2);
  });

  test('meta and active program helpers', () async {
    await s.setMeta('libraryVersion', 2);
    expect(await s.getMeta<int>('libraryVersion'), 2);
    await s.programs.putAll([
      const Program(id: 'p1', name: 'Old', active: false, startedOn: '2026-01-05'),
      const Program(id: 'p2', name: 'Now', active: true, startedOn: '2026-11-30'),
    ]);
    expect((await s.activeProgram())!.id, 'p2');
  });
}
