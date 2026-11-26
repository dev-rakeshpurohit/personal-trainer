import 'package:material_ui/material_ui.dart';

import '../../ui/widgets.dart';

/// Placeholder — replaced by the Progress feature build (UX spec).
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: CustomScrollView(slivers: [SliverToBoxAdapter(child: PageHeader(title: 'Progress'))]));
}
