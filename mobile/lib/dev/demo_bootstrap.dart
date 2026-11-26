// Screenshot/demo mode. Compiled out unless built with --dart-define=DEMO=1 (never in releases).
import 'dart:io' show Platform;

import '../data/services/common.dart';
import '../data/services/dev_seed.dart';
import '../data/services/plan_builder.dart';
import '../data/db/store.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';

const kDemoMode = bool.fromEnvironment('DEMO');
/// Start route in demo mode: launch env ROUTE (simctl: SIMCTL_CHILD_ROUTE=/train) or /today.
String get kDemoRoute => Platform.environment['ROUTE'] ?? const String.fromEnvironment('ROUTE', defaultValue: '/today');

/// Creates a demo profile with the template plan + diet and 30 days of history, once.
Future<void> runDemoBootstrap(Stores s, PlanBuilder builder) async {
  if (!kDemoMode || await s.profile.get(Profile.id) != null) return;
  final now = DateTime.now();
  final profile = Profile(
    name: 'Rakesh',
    sex: Sex.male,
    birthYear: 1990,
    heightCm: 175,
    startWeightKg: 84,
    goalWeightKg: 76,
    dietType: DietType.vegEgg,
    kcalTarget: 2100,
    proteinTargetG: 140,
    trainingDays: const [Weekday.tue, Weekday.wed, Weekday.thu, Weekday.fri, Weekday.sat],
    createdAt: isoString(now),
    goal: Goal.lean,
    experience: Experience.beginner,
    sessionMin: 75,
    planSource: 'template',
    dietSource: 'template',
  );
  await builder.ensureLibrary();
  await builder.importProgramTemplate(trainingDays: profile.trainingDays, today: addDays(now, -30));
  await builder.importDietTemplate();
  await s.profile.put(profile);
  await s.setMeta('onboardedAt', isoString(addDays(now, -30)));
  await s.setMeta('accessCode', 'DEMO');
  await seedDemoData(s, days: 30, today: now);
}

/// Demo tour: comma-separated steps, each shown for [kTourStepSeconds]. "start" begins today's workout.
const kDemoTour = String.fromEnvironment('TOUR');
const kTourStepSeconds = int.fromEnvironment('TOUR_STEP', defaultValue: 8);
