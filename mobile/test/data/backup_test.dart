// Parity with src/data/backup.test.ts (JSON part): export → wipe → import → identical DB.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/backup_service.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/models.dart';

import 'harness.dart';

/// Every store as sorted JSON rows (like the TS snapshot helper).
Future<Map<String, List<Map<String, Object?>>>> snapshot(Stores s) async {
  Future<List<Map<String, Object?>>> dump<T>(Collection<T> c) async {
    final rows = await c.all();
    rows.sort((a, b) => c.idOf(a).compareTo(c.idOf(b)));
    return [for (final r in rows) c.toJson(r)];
  }

  return {
    'profile': await dump(s.profile),
    'exercises': await dump(s.exercises),
    'programs': await dump(s.programs),
    'programDays': await dump(s.programDays),
    'plannedExercises': await dump(s.plannedExercises),
    'sessions': await dump(s.sessions),
    'sets': await dump(s.sets),
    'activeSession': await dump(s.activeSession),
    'dietPlans': await dump(s.dietPlans),
    'plannedMeals': await dump(s.plannedMeals),
    'mealLogs': await dump(s.mealLogs),
    'habitDefs': await dump(s.habitDefs),
    'habitLogs': await dump(s.habitLogs),
    'bodyLogs': await dump(s.bodyLogs),
    'photos': await dump(s.photos),
    'media': await dump(s.media),
    'clips': await dump(s.clips),
    'meta': await dump(s.meta),
  };
}

void main() {
  final seed = loadSeed();
  late Stores s;
  late BackupService backup;
  final exportAt = DateTime(2026, 12, 1, 10, 30);

  Future<void> fill(Stores st) async {
    final b = PlanBuilder(st, seed, newId: counterIds(), now: () => DateTime(2026, 12, 1));
    await b.importProgramTemplate();
    await b.importDietTemplate();
    await st.profile.put(backupProfile());
    await st.bodyLogs.put(const BodyLog(id: 'b1', dayKey: '2026-12-01', weightKg: 79.2));
    await st.media.put(const MediaBlob(id: 'm1', kind: 'clip', mime: 'video/mp4', bytes: 3, path: 'media/m1.mp4', createdAt: 'x'));
    await st.clips.put(const ExerciseClip(exerciseId: 'front-plank', blobId: 'm1', durationSec: 5));
    await st.sessions.put(const Session(
        id: 's1', dayKey: '2026-12-01', programDayId: 'id2', title: 'Strength A', startedAt: '2026-12-01T03:45:00.000Z', status: 'done', cycleWeek: 1, deload: false,
        mode: SessionMode.full, feedback: SessionFeedback(rpe: 9, feel: Feel.tooHard, pain: ['dumbbell-goblet-squat'])));
    await st.sets.put(const SetLog(id: 'x1', sessionId: 's1', exerciseId: 'dumbbell-goblet-squat', setIndex: 0, weightKg: 20, reps: 10, rir: 2, completedAt: '2026-12-01T03:50:00.000Z'));
  }

  setUp(() async {
    s = memoryStores();
    backup = BackupService(s, now: () => exportAt);
    await fill(s);
  });
  tearDown(() => s.db.close());

  test('JSON round-trip restores an identical DB (media omitted)', () async {
    final e = await backup.exportJson();
    await backup.markBackedUp(e.exportedAt);
    final before = await snapshot(s);
    expect(e.filename, 'repmate-backup-2026-12-01.json');
    final data = jsonDecode(e.json) as Map;
    expect(data['app'], 'repmate');
    expect(data['schemaVersion'], 1);
    expect(data['media'], 'omitted');
    expect((data['tables'] as Map).keys, kDataTables);
    expect(((data['tables'] as Map)['meta'] as List).last, {'key': 'lastBackupAt', 'value': e.exportedAt});

    final fresh = memoryStores();
    addTearDown(fresh.db.close);
    final restoreInto = BackupService(fresh, now: () => exportAt);
    await restoreInto.restore(restoreInto.parse(e.bytes), RestoreMode.replace);
    final after = await snapshot(fresh);
    expect({...after}..remove('media'), {...before}..remove('media'));
    expect(after['media'], isEmpty);
    // and exporting again gives the very same file
    expect((await restoreInto.exportJson()).json, e.json);
  });

  test('replace wipes existing rows first (media too)', () async {
    final e = await backup.exportJson();
    await s.bodyLogs.put(const BodyLog(id: 'b9', dayKey: '2026-12-09', weightKg: 78));
    await backup.restore(backup.parseJson(e.json), RestoreMode.replace);
    expect((await s.bodyLogs.all()).map((b) => b.id), ['b1']);
    expect(await s.media.count(), 0);
  });

  test('rejects garbage', () {
    expect(() => backup.parseJson('{"hello":1}'), throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('not a Repmate backup'))));
    expect(() => backup.parseJson('nope'), throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('invalid JSON'))));
    expect(
      () => backup.parseJson(jsonEncode({'app': 'repmate', 'schemaVersion': 2, 'exportedAt': 'x', 'tables': {}, 'media': 'omitted'})),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('newer version'))),
    );
  });

  test('merge keeps existing rows and adds new ones', () async {
    final data = await backup.buildBackup();
    await s.bodyLogs.put(const BodyLog(id: 'b2', dayKey: '2026-12-02', weightKg: 79));
    await backup.restore(ParsedBackup(data), RestoreMode.merge);
    expect(await s.bodyLogs.count(), 2);
  });

  test('reads a PWA-written file (JS number formatting, zip with media)', () async {
    // a minimal file as the web app writes it: whole numbers without ".0", undefined keys absent
    final pwa = {
      'app': 'repmate',
      'schemaVersion': 1,
      'exportedAt': '2026-12-01T05:00:00.000Z',
      'media': 'included-in-zip',
      'tables': {
        'profile': [backupProfile().toJson()..['heightCm'] = 178],
        'bodyLogs': [
          {'id': 'b1', 'dayKey': '2026-12-01', 'weightKg': 79.2},
        ],
        'habitLogs': [
          {'id': 'h1', 'dayKey': '2026-12-01', 'habitId': 'water', 'value': 2500},
        ],
        'meta': [
          {'key': 'onboardedAt', 'value': '2026-11-30T08:00:00.000Z'},
        ],
        'media': [
          {'id': 'm1', 'kind': 'clip', 'mime': 'video/mp4', 'bytes': 3, 'createdAt': 'x'},
        ],
      },
    };
    final zip = Archive()
      ..addFile(ArchiveFile.bytes('backup.json', utf8.encode(jsonEncode(pwa))))
      ..addFile(ArchiveFile.bytes('media/m1.mp4', [1, 2, 3]));
    final bytes = ZipEncoder().encode(zip);
    final p = backup.parse(bytes);
    await backup.restore(p, RestoreMode.replace);
    expect((await s.profile.get(Profile.id))!.heightCm, 178);
    expect((await s.habitLogs.get('h1'))!.value, 2500);
    expect(await s.getMeta<String>('onboardedAt'), '2026-11-30T08:00:00.000Z');
    expect(await s.exercises.count(), 0);
    expect(await s.media.count(), 0); // media files are skipped for now
  });
}
