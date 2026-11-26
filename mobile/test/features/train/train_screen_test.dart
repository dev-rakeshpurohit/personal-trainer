// Train tab over an in-memory DB seeded with the Tue–Sat template plan (today = Thu 3 Dec 2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/domain/balance.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/train/body_map.dart';
import 'package:repmate/features/train/plan_history_screen.dart';
import 'package:repmate/features/train/train_data.dart';
import 'package:repmate/features/train/train_screen.dart';

import 'train_harness.dart';

void main() {
  Finder scrollable() => find.byType(Scrollable).first;

  testWidgets('shows the template week: block strip, today startable, other days preview-only', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await tester.pumpWidget(testApp(s, const TrainScreen()));
    await pumpUntil(tester, find.text('You are here'));

    expect(find.textContaining('Week 1 of 8'), findsWidgets);
    expect(find.text('You are here'), findsOneWidget);
    expect(find.textContaining('Learn'), findsWidgets); // week 1 focus

    await tester.scrollUntilVisible(find.text('Strength A – full body'), 300, scrollable: scrollable());
    expect(find.textContaining('Was planned for Tuesday 1 Dec'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Leg press'), 300, scrollable: scrollable());
    expect(find.text('Strength B – full body'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Start session'), 300, scrollable: scrollable());
    expect(find.text('Start session'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Starts on Friday 4 Dec'), 300, scrollable: scrollable());
    expect(find.textContaining('Starts on Friday 4 Dec'), findsOneWidget);

    await teardownApp(tester, s);
  });

  testWidgets('a progressed lift gets a coach dot and the Why sheet explains it with the data used', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await addSession(tester, s, id: 'old1', at: DateTime(2026, 11, 26, 9), exerciseId: 'leg-press', sets: const [(60, 12), (60, 12), (60, 12)]);
    await tester.pumpWidget(testApp(s, const TrainScreen()));
    await pumpUntil(tester, find.text('You are here'));

    final legPress = find.text('Leg press');
    await tester.scrollUntilVisible(legPress, 300, scrollable: scrollable());
    await pumpUntil(tester, find.textContaining('65 kg'));
    expect(find.textContaining('65 kg'), findsWidgets);

    await tapVisible(tester, legPress);
    await pumpUntil(tester, find.text('WHAT CHANGED THIS WEEK'));
    expect(find.text('WHAT CHANGED THIS WEEK'), findsOneWidget);
    expect(find.textContaining('Weight up to 65 kg'), findsOneWidget);
    expect(find.text('BASED ON YOUR LAST 3 SESSIONS'), findsOneWidget);
    await pumpUntil(tester, find.text('Last time'));
    expect(find.text('Last time'), findsOneWidget);
    expect(find.text('Change this'), findsOneWidget);

    await teardownApp(tester, s);
  });

  testWidgets('an unchanged exercise still answers "why" in one tap', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await tester.pumpWidget(testApp(s, const TrainScreen()));
    await pumpUntil(tester, find.text('PLAN CHECK'));
    final ex = find.text('Seated cable row');
    await tester.scrollUntilVisible(ex, 300, scrollable: scrollable());
    await tapVisible(tester, ex);
    await pumpUntil(tester, find.text('WHY THIS TARGET'));
    expect(find.text('WHY THIS TARGET'), findsOneWidget);
    expect(find.textContaining('First time on this one'), findsOneWidget);
    await teardownApp(tester, s);
  });

  testWidgets('Plan check flags calves (no calf work in the template) and Add fixes it, with Undo', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await tester.pumpWidget(testApp(s, const TrainScreen()));
    await pumpUntil(tester, find.text('PLAN CHECK'));
    expect(find.byType(BodyMap), findsOneWidget);
    expect(find.textContaining('Calves need more work'), findsOneWidget); // the summary sentence names the gap

    await tester.tap(find.text('Details'));
    await pumpUntil(tester, find.text('Every muscle'.toUpperCase()));
    final calvesFix = find.byKey(const ValueKey('fixall-calves'));
    await tester.scrollUntilVisible(calvesFix, 300, scrollable: scrollable());
    expect(find.descendant(of: calvesFix, matching: find.textContaining('Calves 0 sets — aim 4–16')), findsOneWidget);

    final add = find.descendant(of: calvesFix, matching: find.textContaining('Add to '));
    await tapVisible(tester, add);
    await settle(tester);
    await pumpUntil(tester, find.textContaining('Added '));
    expect(find.textContaining('Added '), findsOneWidget);
    expect(calvesFix, findsNothing); // gap closed

    final planned = await tester.runAsync(() => s.plannedExercises.all());
    final exMap = {for (final e in (await tester.runAsync(() => s.exercises.all()))!) e.id: e};
    expect(planned!.any((p) => exMap[p.exerciseId]!.primaryMuscles.contains('calves')), isTrue);

    await tapVisible(tester, find.text('Undo'));
    await settle(tester);
    await pumpUntil(tester, calvesFix);
    expect(calvesFix, findsOneWidget);

    await teardownApp(tester, s);
  });

  testWidgets('plan history lists the template plan as active', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await tester.pumpWidget(testApp(s, const PlanHistoryScreen()));
    await pumpUntil(tester, find.text('Active'));
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Repfellow template'), findsOneWidget);
    await teardownApp(tester, s);
  });

  test('block phases group the 8-week wave and keep the deload calm', () {
    const p = Program(
      id: 'x',
      name: 'x',
      active: true,
      startedOn: '2026-11-30',
      progression: ProgressionCfg(weeks: [
        WeekFocus(week: 1, rirMain: 3, rirAccessory: 3, focus: 'Learn', note: ''),
        WeekFocus(week: 2, rirMain: 3, rirAccessory: 3, focus: 'Build baseline', note: ''),
        WeekFocus(week: 3, rirMain: 2, rirAccessory: 2, focus: 'Accumulate', note: ''),
        WeekFocus(week: 4, rirMain: 2, rirAccessory: 2, focus: 'Accumulate', note: ''),
        WeekFocus(week: 5, rirMain: 1, rirAccessory: 2, focus: 'Intensify', note: ''),
        WeekFocus(week: 6, rirMain: 1, rirAccessory: 2, focus: 'Intensify', note: ''),
        WeekFocus(week: 7, rirMain: 1, rirAccessory: 2, focus: 'Peak', note: ''),
        WeekFocus(week: 8, rirMain: 3, rirAccessory: 3, focus: 'Deload', note: '', deload: true),
      ]),
    );
    final phases = blockPhases(p);
    expect(phases.map((x) => '${x.label} ${x.range}'), ['Base wk 1–2', 'Build wk 3–4', 'Peak wk 5–7', 'Recovery wk 8']);
    expect(phases.last.deload, isTrue);
    expect(volumeState(MuscleGroup.chest, 3, 6), VolumeState.below);
    expect(volumeState(MuscleGroup.chest, 8, 6), VolumeState.inRange);
    expect(volumeState(MuscleGroup.biceps, 18, 6), VolumeState.above);
    expect(hitRegion(const Offset(50, 105), const Size(100, 210), back: true), MuscleGroup.glutes);
    expect(authorOf(const Program(id: 'a', name: 'a', active: false, startedOn: '', templateId: 'ai-coach')), PlanAuthor.coach);
    expect(authorOf(const Program(id: 'a', name: 'a', active: false, startedOn: '', templateId: 'generated:muscle')), PlanAuthor.generated);
  });
}
