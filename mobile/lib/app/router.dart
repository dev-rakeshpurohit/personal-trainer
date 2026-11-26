// Routes. Tabs live in a StatefulShellRoute (each keeps its own stack); onboarding and the
// gym-floor logger are full-screen routes above the tab bar.
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/coach/coach_screen.dart';
import '../features/eat/eat_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/today/today_screen.dart';
import '../features/train/train_screen.dart';
import '../features/workout/workout_screen.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter({String initialLocation = '/today', Listenable? refresh, GoRouterRedirect? redirect}) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: initialLocation,
      refreshListenable: refresh,
      redirect: redirect,
      routes: [
        GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
        GoRoute(path: '/workout', builder: (_, _) => const WorkoutScreen()),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (_, _) => const TodayScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/train', builder: (_, _) => const TrainScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/eat', builder: (_, _) => const EatScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/coach', builder: (_, _) => const CoachScreen())]),
          ],
        ),
      ],
    );
