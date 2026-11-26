// Port of src/data/backup.ts (JSON backups). Files are interchangeable with the PWA:
// { app: 'repmate', schemaVersion: 1, exportedAt, tables: { <dexie table>: rows[] }, media }.
// Media (clips, photos) is not exported yet: files are always written with media 'omitted'.
// A PWA zip backup can be read (its backup.json is restored; the media files in it are skipped).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/schedule.dart';
import '../db/store.dart';
import 'common.dart';

const int kBackupSchemaVersion = 1;

/// Tables exported in a backup, in restore order (TS DATA_TABLES).
const List<String> kDataTables = [
  'profile', 'exercises', 'programs', 'programDays', 'plannedExercises', 'sessions', 'sets', 'activeSession', //
  'dietPlans', 'plannedMeals', 'mealLogs', 'habitDefs', 'habitLogs', 'bodyLogs', 'photos', 'clips', 'meta',
];

enum RestoreMode { replace, merge }

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A validated backup file (TS ParsedBackup without the media map).
class ParsedBackup {
  const ParsedBackup(this.data);

  /// The decoded backup JSON.
  final Map<String, Object?> data;
  int get schemaVersion => (data['schemaVersion'] as num).toInt();
  String get exportedAt => data['exportedAt'] as String;
  Map<String, List<Map<String, Object?>>> get tables => {
        for (final e in (data['tables'] as Map).entries)
          e.key as String: [for (final r in e.value as List) (r as Map).cast<String, Object?>()],
      };
}

class ExportedBackup {
  const ExportedBackup({required this.json, required this.filename, required this.exportedAt});
  final String json;
  final String filename;
  final String exportedAt;
  Uint8List get bytes => Uint8List.fromList(utf8.encode(json));
}

/// Typed access to one store for dump / load (closures keep the collection's real type).
class _Table {
  _Table(this.dump, this.load, this.clear);
  final Future<List<Map<String, Object?>>> Function() dump;
  final Future<void> Function(List<Map<String, Object?>> rows) load;
  final Future<void> Function() clear;

  static _Table of<T>(Collection<T> c) => _Table(
        () async {
          final rows = await c.all();
          rows.sort((a, b) => c.idOf(a).compareTo(c.idOf(b))); // IndexedDB primary-key order
          return [for (final r in rows) c.toJson(r)];
        },
        (rows) => c.putAll([for (final r in rows) c.fromJson(r)]),
        c.clear,
      );
}

class BackupService {
  BackupService(this.s, {Clock? now}) : now = now ?? systemNow;
  final Stores s;
  final Clock now;

  Map<String, _Table> get _tables => {
        'profile': _Table.of(s.profile),
        'exercises': _Table.of(s.exercises),
        'programs': _Table.of(s.programs),
        'programDays': _Table.of(s.programDays),
        'plannedExercises': _Table.of(s.plannedExercises),
        'sessions': _Table.of(s.sessions),
        'sets': _Table.of(s.sets),
        'activeSession': _Table.of(s.activeSession),
        'dietPlans': _Table.of(s.dietPlans),
        'plannedMeals': _Table.of(s.plannedMeals),
        'mealLogs': _Table.of(s.mealLogs),
        'habitDefs': _Table.of(s.habitDefs),
        'habitLogs': _Table.of(s.habitLogs),
        'bodyLogs': _Table.of(s.bodyLogs),
        'photos': _Table.of(s.photos),
        'clips': _Table.of(s.clips),
        'meta': _Table.of(s.meta),
      };

  /// The backup object (TS buildBackup(false)). Stamps `lastBackupAt` = export time inside the file.
  Future<Map<String, Object?>> buildBackup({DateTime? at}) async {
    final exportedAt = isoString(at ?? now());
    final io = _tables;
    final tables = <String, Object?>{};
    for (final t in kDataTables) {
      tables[t] = await io[t]!.dump();
    }
    tables['meta'] = [
      ...(tables['meta'] as List<Map<String, Object?>>).where((m) => m['key'] != 'lastBackupAt'),
      {'key': 'lastBackupAt', 'value': exportedAt},
    ];
    return {'app': 'repmate', 'schemaVersion': kBackupSchemaVersion, 'exportedAt': exportedAt, 'tables': tables, 'media': 'omitted'};
  }

  /// JSON file contents and name (`repmate-backup-yyyy-MM-dd.json`, local date).
  Future<ExportedBackup> exportJson({DateTime? at}) async {
    final when = at ?? now();
    final data = await buildBackup(at: when);
    return ExportedBackup(json: jsonEncode(data), filename: 'repmate-backup-${dayKey(when)}.json', exportedAt: data['exportedAt'] as String);
  }

  /// Validate a backup file (JSON, or a PWA zip with backup.json).
  ParsedBackup parse(List<int> bytes) {
    String text;
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      final zip = ZipDecoder().decodeBytes(bytes);
      final f = zip.findFile('backup.json');
      if (f == null) throw const BackupException('This zip has no backup.json');
      text = utf8.decode(f.content);
    } else {
      text = utf8.decode(bytes, allowMalformed: true);
    }
    return parseJson(text);
  }

  ParsedBackup parseJson(String text) {
    Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const BackupException('That file is not a Repmate backup (invalid JSON).');
    }
    if (!_valid(raw)) throw const BackupException('That file is not a Repmate backup.');
    final p = ParsedBackup((raw as Map).cast<String, Object?>());
    if (p.schemaVersion > kBackupSchemaVersion) {
      throw const BackupException('This backup is from a newer version of Repmate. Update the app first.');
    }
    return p;
  }

  static bool _valid(Object? raw) {
    if (raw is! Map) return false;
    if (raw['app'] != 'repmate') return false;
    final v = raw['schemaVersion'];
    if (v is! num || v != v.truncate() || v < 1) return false;
    if (raw['exportedAt'] is! String) return false;
    final t = raw['tables'];
    if (t is! Map) return false;
    for (final rows in t.values) {
      if (rows is! List || rows.any((r) => r is! Map)) return false;
    }
    return raw['media'] == 'omitted' || raw['media'] == 'included-in-zip';
  }

  /// Restore: replace wipes every store first (media too); merge upserts rows over existing ones.
  Future<void> restore(ParsedBackup p, RestoreMode mode) async {
    final io = _tables;
    final tables = p.tables;
    await s.transaction(() async {
      if (mode == RestoreMode.replace) {
        for (final t in io.values) {
          await t.clear();
        }
        await s.media.clear();
      }
      for (final name in kDataTables) {
        final rows = tables[name];
        if (rows != null && rows.isNotEmpty) await io[name]!.load(rows);
      }
    });
  }

  Future<void> markBackedUp([String? at]) => s.setMeta('lastBackupAt', at ?? isoString(now()));
}
