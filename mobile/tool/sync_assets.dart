// Copies the web app's seeds and offline media into mobile/assets/.
//
//   cd mobile && dart run tool/sync_assets.dart
//
// - seed JSON                         → assets/seed/            (may be committed)
// - public/media/exercises/index.json → assets/seed/media-index.json
// - public/media/demos/*.webp         → assets/media/demos/     (Gym Visual licence: personal use only, git-ignored)
// - free-exercise-db fallback photos  → assets/media/exercises/<id>/{0,1}.webp (listed in demo-map.json `fallbackPhotos`)
//
// Only changed files are copied (size + modified time). Missing sources are skipped with a note.
import 'dart:convert';
import 'dart:io';

const _seedFiles = [
  'program.lean-athletic-v2.json',
  'diet.lean-veg-egg-2000.json',
  'alternates.research.json',
  'demo-map.json',
  'library.dataset.json',
  'library.curated-meta.json',
];

int _copied = 0;
int _skipped = 0;
int _bytes = 0;

String _p(List<String> parts) => parts.join(Platform.pathSeparator);

void _copy(File src, File dst) {
  final ss = src.statSync();
  if (dst.existsSync()) {
    final ds = dst.statSync();
    if (ds.size == ss.size && ds.modified.isAtSameMomentAs(ss.modified)) {
      _skipped++;
      return;
    }
  }
  dst.parent.createSync(recursive: true);
  src.copySync(dst.path);
  dst.setLastModifiedSync(ss.modified);
  _copied++;
  _bytes += ss.size;
}

String _mb(int b) => '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

void main() {
  // tool/ → mobile/ → repo root
  final mobile = File.fromUri(Platform.script).parent.parent;
  final root = mobile.parent;
  final assets = Directory(_p([mobile.path, 'assets']));

  // 1. Seeds
  for (final f in _seedFiles) {
    final src = File(_p([root.path, 'seed', f]));
    if (!src.existsSync()) {
      stderr.writeln('missing seed: ${src.path}');
      exitCode = 1;
      continue;
    }
    _copy(src, File(_p([assets.path, 'seed', f])));
  }
  final index = File(_p([root.path, 'public', 'media', 'exercises', 'index.json']));
  if (index.existsSync()) {
    _copy(index, File(_p([assets.path, 'seed', 'media-index.json'])));
  } else {
    stderr.writeln('missing media index: ${index.path} (run `pnpm fetch:media` in the web app)');
    exitCode = 1;
  }
  stdout.writeln('seed: ${_seedFiles.length + 1} files');

  // 2. 3D demos (licensed, personal use only; never committed)
  final demos = Directory(_p([root.path, 'public', 'media', 'demos']));
  var demoCount = 0;
  var demoBytes = 0;
  if (demos.existsSync()) {
    for (final e in demos.listSync()) {
      if (e is! File || !e.path.endsWith('.webp')) continue;
      demoCount++;
      demoBytes += e.lengthSync();
      _copy(e, File(_p([assets.path, 'media', 'demos', e.uri.pathSegments.last])));
    }
    stdout.writeln('demos: $demoCount files, ${_mb(demoBytes)}');
  } else {
    stdout.writeln('demos: skipped (${demos.path} not found; run `pnpm fetch:demos` in the web app)');
  }

  // 3. free-exercise-db fallback photos for exercises with no 3D demo
  final demoMap = File(_p([root.path, 'seed', 'demo-map.json']));
  final fallback = demoMap.existsSync()
      ? ((jsonDecode(demoMap.readAsStringSync()) as Map)['fallbackPhotos'] as List? ?? const []).cast<String>()
      : const <String>[];
  var photoCount = 0;
  for (final id in fallback) {
    for (final frame in const ['0.webp', '1.webp']) {
      final src = File(_p([root.path, 'public', 'media', 'exercises', id, frame]));
      if (!src.existsSync()) {
        stdout.writeln('photo missing, skipped: $id/$frame');
        continue;
      }
      photoCount++;
      _copy(src, File(_p([assets.path, 'media', 'exercises', id, frame])));
    }
  }
  stdout.writeln('fallback photos: ${fallback.length} exercises, $photoCount files');
  stdout.writeln('copied $_copied (${_mb(_bytes)}), unchanged $_skipped');
  if (fallback.isNotEmpty) {
    stdout.writeln('pubspec.yaml must list each photo folder under flutter/assets:');
    for (final id in fallback) {
      stdout.writeln('    - assets/media/exercises/$id/');
    }
  }
}
