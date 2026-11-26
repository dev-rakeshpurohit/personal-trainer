// Shared entry point to begin a workout (Today, Train, notifications all call this).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';

/// Prepare and start today's session for [dayId], then open the full-screen logger.
/// If a session is already active, just reopens the logger.
Future<void> startWorkout(WidgetRef ref, BuildContext context, {required String dayId, SessionMode mode = SessionMode.full}) async {
  final svc = ref.read(sessionServiceProvider);
  final active = await svc.activeSession();
  if (active != null) {
    if (context.mounted) context.push('/workout');
    return;
  }
  final now = ref.read(clockProvider)();
  final prepared = await svc.prepareSession(dayId, mode, date: now);
  if (prepared == null || prepared.plan.isEmpty) {
    if (context.mounted) showRfToast(context, 'Nothing planned for this session yet.');
    return;
  }
  await svc.startSession(prepared, mode, date: now);
  if (context.mounted) context.push('/workout');
}

/// Reopen the logger for an in-progress session.
void resumeWorkout(BuildContext context) => context.push('/workout');
