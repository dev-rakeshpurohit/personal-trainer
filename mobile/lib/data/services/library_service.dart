// Port of ensureLibrary / upgradeLibraryIfNeeded from src/data/plan-builder.ts.
import '../../domain/models.dart';
import '../db/store.dart';
import '../seed/library_builder.dart';

class LibraryService {
  LibraryService(this.s, this.seed);
  final Stores s;
  final SeedData seed;

  /// Make sure every library exercise exists and carries current metadata.
  /// Keeps custom exercises and user-edited fields (cue, Track weight, alternates) untouched.
  Future<({int added, int updated})> ensureLibrary() async {
    final lib = staticLibrary(seed);
    final existing = {for (final e in await s.exercises.all()) e.id: e};
    final up = planLibraryUpgrade(lib, existing);
    await s.transaction(() async {
      if (up.missing.isNotEmpty) await s.exercises.addMissing(up.missing);
      if (up.updates.isNotEmpty) await s.exercises.putAll(up.updates);
      await s.setMeta('libraryVersion', kLibraryVersion);
    });
    return (added: up.missing.length, updated: up.updates.length);
  }

  /// Run once per library version on existing installs (call lazily from the app shell).
  Future<bool> upgradeLibraryIfNeeded() async {
    final v = await s.getMeta<num>('libraryVersion');
    if ((v ?? 0) >= kLibraryVersion) return false;
    if (await s.profile.get(Profile.id) == null) return false;
    await ensureLibrary();
    return true;
  }
}
