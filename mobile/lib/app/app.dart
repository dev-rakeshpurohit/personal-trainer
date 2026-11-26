import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../state/providers.dart';
import '../ui/theme.dart';
import 'router.dart';

/// When true the whole app uses the dark, high-contrast Gym mode (set while a workout runs).
final gymModeProvider = NotifierProvider<GymMode, bool>(GymMode.new);

class GymMode extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool on) => state = on;
}

/// One-time startup: load seeds and merge any newly bundled exercises into the local library.
final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(seedDataProvider.future);
  final lib = await ref.watch(libraryServiceProvider.future);
  await lib.upgradeLibraryIfNeeded();
});

/// Bridges the profile stream to go_router so it re-evaluates redirects when onboarding completes.
class _ProfileListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

class RepfellowApp extends ConsumerStatefulWidget {
  const RepfellowApp({super.key, this.initialLocation = '/today'});
  final String initialLocation;
  @override
  ConsumerState<RepfellowApp> createState() => _RepfellowAppState();
}

class _RepfellowAppState extends ConsumerState<RepfellowApp> {
  final _refresh = _ProfileListenable();
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
    refresh: _refresh,
    redirect: (context, state) {
      final profile = ref.read(profileProvider);
      if (profile.isLoading) return null;
      final has = profile.value != null;
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!has && !atOnboarding) return '/onboarding';
      if (has && atOnboarding && state.uri.queryParameters['fresh'] != '1') return '/today';
      return null;
    },
  );

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profileProvider, (_, _) => _refresh.ping());
    final gym = ref.watch(gymModeProvider);
    final startup = ref.watch(appStartupProvider);
    final profile = ref.watch(profileProvider);
    final ready = startup.hasValue && !profile.isLoading;
    return MaterialApp.router(
      title: 'Repfellow',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: gym ? ThemeMode.dark : ThemeMode.system,
      routerConfig: _router,
      builder: (context, child) => ready ? child! : _Splash(error: startup.error),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.error});
  final Object? error;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Scaffold(
      body: Center(
        child: error != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text('Could not start: $error', textAlign: TextAlign.center))
            : Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(colors: [c.accent, c.accentInk], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
              ),
      ),
    );
  }
}
