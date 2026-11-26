import 'package:material_ui/material_ui.dart';

import '../../ui/widgets.dart';

/// Placeholder — replaced by the Today feature build (UX spec).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: CustomScrollView(slivers: [SliverToBoxAdapter(child: PageHeader(title: 'Today'))]));
}
