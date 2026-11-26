import 'package:material_ui/material_ui.dart';

import '../../ui/widgets.dart';

/// Placeholder — replaced by the Eat feature build (UX spec).
class EatScreen extends StatelessWidget {
  const EatScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: CustomScrollView(slivers: [SliverToBoxAdapter(child: PageHeader(title: 'Eat'))]));
}
