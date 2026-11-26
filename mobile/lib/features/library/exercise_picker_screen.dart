// Pick an exercise for the plan (day editor): same browser as the Library, returns the id.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../ui/theme.dart';
import 'exercise_browser.dart';
import 'exercise_detail_screen.dart';

class ExercisePickerScreen extends StatelessWidget {
  const ExercisePickerScreen({super.key, this.title = 'Add exercise'});
  final String title;

  /// Push the picker; resolves to the chosen exercise id (null when dismissed).
  static Future<String?> pick(BuildContext context, {String title = 'Add exercise'}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ExercisePickerScreen(title: title), fullscreenDialog: true));

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ExerciseBrowser(
        bottomPadding: MediaQuery.paddingOf(context).bottom + 16,
        onTap: (e) => Navigator.of(context).pop(e.id),
        trailingFor: (e) => IconButton(
          tooltip: 'About ${e.name}',
          icon: Icon(CupertinoIcons.info_circle, color: c.muted),
          onPressed: () => ExerciseDetailScreen.open(context, e.id, showAddToPlan: false),
        ),
      ),
    );
  }
}
