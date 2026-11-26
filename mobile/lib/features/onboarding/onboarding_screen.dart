import 'package:material_ui/material_ui.dart';

import '../../ui/widgets.dart';

/// Placeholder — replaced by the Welcome feature build (UX spec).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: CustomScrollView(slivers: [SliverToBoxAdapter(child: PageHeader(title: 'Welcome'))]));
}
