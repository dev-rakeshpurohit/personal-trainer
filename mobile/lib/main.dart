import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'dev/demo_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: RepfellowApp(initialLocation: kDemoMode ? kDemoRoute : '/today')));
}
