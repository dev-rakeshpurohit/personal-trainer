import 'package:material_ui/material_ui.dart';

import '../../ui/widgets.dart';

/// Placeholder — replaced by the Workout feature build (UX spec).
class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: CustomScrollView(slivers: [SliverToBoxAdapter(child: PageHeader(title: 'Workout'))]));
}
