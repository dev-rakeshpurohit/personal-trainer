import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../dev/demo_bootstrap.dart';
import '../domain/models.dart';
import '../features/workout/start.dart';
import '../state/providers.dart';
import '../state/ui_state.dart';
import '../ui/theme.dart';
import 'router.dart';

export '../state/ui_state.dart' show gymModeProvider, GymMode;

/// One-time startup: load seeds and merge any newly bundled exercises into the local library.
final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(seedDataProvider.future);
  final lib = await ref.watch(libraryServiceProvider.future);
  await lib.upgradeLibraryIfNeeded();
  if (kDemoMode) await runDemoBootstrap(ref.read(storesProvider), await ref.watch(planBuilderProvider.future));
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

  Timer? _tour;

  void _startTour() {
    if (_tour != null || kDemoTour.isEmpty) return;
    final steps = kDemoTour.split(',');
    var i = 0;
    _tour = Timer.periodic(const Duration(seconds: kTourStepSeconds), (t) async {
      if (i >= steps.length) return t.cancel();
      final step = steps[i++].trim();
      if (step == 'start') {
        final bundle = await ref.read(programBundleProvider.future);
        final today = Weekday.ofDate(DateTime.now());
        final day = bundle?.days.where((d) => d.weekday == today).firstOrNull;
        final ctx = rootNavigatorKey.currentContext;
        if (day != null && ctx != null && ctx.mounted) await startWorkout(ref, ctx, dayId: day.id);
      } else {
        _router.go(step);
      }
    });
  }

  @override
  void dispose() {
    _tour?.cancel();
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
    if (kDemoMode && ready) _startTour();
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
