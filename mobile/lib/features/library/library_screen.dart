// Exercise library (pushed from Train): every exercise with 3D demos, searchable and filterable.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../ui/theme.dart';
import 'exercise_browser.dart';
import 'exercise_detail_screen.dart';
import 'library_data.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(sortedExercisesProvider).value?.length;
    final c = context.rf;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Library'),
          if (n != null) Text('${_thousands(n)} exercises · 3D demos', style: RfType.caption.copyWith(color: c.muted)),
        ]),
      ),
      body: ExerciseBrowser(
        bottomPadding: MediaQuery.paddingOf(context).bottom + 16,
        onTap: (Exercise e) => ExerciseDetailScreen.open(context, e.id),
      ),
    );
  }
}

String _thousands(int n) => n >= 1000 ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}' : '$n';
