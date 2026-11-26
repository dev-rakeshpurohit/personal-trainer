// Loads the bundled seed JSON (copied into assets/seed/ by tool/sync_assets.dart).
import 'dart:convert';

import 'package:flutter/services.dart';

import 'library_builder.dart';

/// Asset paths of the bundled seeds.
abstract final class SeedAssets {
  static const program = 'assets/seed/program.lean-athletic-v2.json';
  static const diet = 'assets/seed/diet.lean-veg-egg-2000.json';
  static const mediaIndex = 'assets/seed/media-index.json';
  static const research = 'assets/seed/alternates.research.json';
  static const demoMap = 'assets/seed/demo-map.json';
  static const curatedMeta = 'assets/seed/library.curated-meta.json';
  static const dataset = 'assets/seed/library.dataset.json';

  /// 3D demo (animated) and its still thumbnail.
  static String demoAnim(String demoId) => 'assets/media/demos/$demoId.webp';
  static String demoThumb(String demoId) => 'assets/media/demos/$demoId-t.webp';

  /// free-exercise-db photo fallback (frame 0 or 1).
  static String photo(String freeDbId, [int frame = 0]) => 'assets/media/exercises/$freeDbId/$frame.webp';
}

/// Raw decoded seed JSON, keyed like [SeedData.fromJson].
class RawSeeds {
  const RawSeeds({
    required this.program,
    required this.diet,
    required this.mediaIndex,
    required this.research,
    required this.demoMap,
    required this.curatedMeta,
    required this.dataset,
  });
  final Map<String, Object?> program;
  final Map<String, Object?> diet;
  final List<Object?> mediaIndex;
  final Map<String, Object?> research;
  final Map<String, Object?> demoMap;
  final Map<String, Object?> curatedMeta;
  final Map<String, Object?> dataset;

  SeedData parse() => SeedData.fromJson(
        program: program,
        diet: diet,
        mediaIndex: mediaIndex,
        research: research,
        demoMap: demoMap,
        curatedMeta: curatedMeta,
        dataset: dataset,
      );
}

class SeedLoader {
  SeedLoader([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;

  Future<Object?> _json(String path) async => jsonDecode(await _bundle.loadString(path));

  /// Reads and decodes every seed asset.
  Future<RawSeeds> loadRaw() async {
    final r = await Future.wait([
      _json(SeedAssets.program),
      _json(SeedAssets.diet),
      _json(SeedAssets.mediaIndex),
      _json(SeedAssets.research),
      _json(SeedAssets.demoMap),
      _json(SeedAssets.curatedMeta),
      _json(SeedAssets.dataset),
    ]);
    return RawSeeds(
      program: (r[0] as Map).cast(),
      diet: (r[1] as Map).cast(),
      mediaIndex: (r[2] as List).cast(),
      research: (r[3] as Map).cast(),
      demoMap: (r[4] as Map).cast(),
      curatedMeta: (r[5] as Map).cast(),
      dataset: (r[6] as Map).cast(),
    );
  }

  /// Reads, decodes and validates every seed asset.
  Future<SeedData> load() async => (await loadRaw()).parse();
}
