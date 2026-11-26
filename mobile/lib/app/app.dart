import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/theme.dart';
import 'router.dart';

/// When true the whole app uses the dark, high-contrast Gym mode (set while a workout runs).
final gymModeProvider = NotifierProvider<GymMode, bool>(GymMode.new);

class GymMode extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool on) => state = on;
}

class RepfellowApp extends ConsumerStatefulWidget {
  const RepfellowApp({super.key, this.initialLocation = '/today'});
  final String initialLocation;
  @override
  ConsumerState<RepfellowApp> createState() => _RepfellowAppState();
}

class _RepfellowAppState extends ConsumerState<RepfellowApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(gymModeProvider);
    return MaterialApp.router(
      title: 'Repfellow',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: gym ? ThemeMode.dark : ThemeMode.system,
      routerConfig: _router,
    );
  }
}
