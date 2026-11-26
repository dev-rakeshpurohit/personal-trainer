// Library: search the full exercise list, filters, detail with history and "Add to my plan".
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/library/exercise_detail_screen.dart';
import 'package:repmate/features/library/library_data.dart';
import 'package:repmate/features/library/library_screen.dart';

import '../train/train_harness.dart';

void main() {
  testWidgets('search finds "goblet" and the detail opens with demo, muscles and history', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await addSession(tester, s, id: 'g1', at: DateTime(2026, 11, 10, 9), exerciseId: 'dumbbell-goblet-squat', sets: const [(16, 10), (16, 10)]);
    await addSession(tester, s, id: 'g2', at: DateTime(2026, 11, 17, 9), exerciseId: 'dumbbell-goblet-squat', sets: const [(18, 10), (18, 9)]);
    await tester.pumpWidget(testApp(s, const LibraryScreen()));
    await pumpUntil(tester, find.textContaining('matches'));
    expect(find.textContaining('exercises · 3D demos'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'goblet');
    await pumpUntil(tester, find.text('Dumbbell goblet squat'));
    expect(find.text('Dumbbell goblet squat'), findsOneWidget);
    expect(find.text('In plan'), findsWidgets);

    await tapVisible(tester, find.text('Dumbbell goblet squat'));
    await pumpUntil(tester, find.text('Add to my plan'));
    expect(find.text('Add to my plan'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // page transition
    final detailScroll = find.descendant(of: find.byType(ExerciseDetailScreen), matching: find.byType(Scrollable)).first;
    await scrollTo(tester, find.text('MUSCLES'), detailScroll);
    expect(find.text('MUSCLES'), findsOneWidget);
    await scrollTo(tester, find.text('YOUR HISTORY'), detailScroll);
    await pumpUntil(tester, find.textContaining('Up '));
    expect(find.textContaining('Up '), findsOneWidget); // e1RM went up: words before numbers
    expect(find.textContaining('1 PR'), findsOneWidget);

    await teardownApp(tester, s);
  });

  testWidgets('"Add to my plan" adds the lift to the chosen day, with Undo', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    await tester.pumpWidget(testApp(s, const LibraryScreen()));
    await pumpUntil(tester, find.textContaining('matches'));
    await tester.enterText(find.byType(TextField), 'standing calf raise');
    await pumpUntil(tester, find.text('Bodyweight standing calf raise'));
    await tapVisible(tester, find.text('Bodyweight standing calf raise'));
    await pumpUntil(tester, find.text('Add to my plan'));
    await tapVisible(tester, find.text('Add to my plan'));
    await pumpUntil(tester, find.text('Strength C – heavier'));
    await tapVisible(tester, find.text('Strength C – heavier'));
    await pumpUntil(tester, find.textContaining('Added to Strength C'));
    expect(find.textContaining('Added to Strength C'), findsOneWidget);
    final planned = (await tester.runAsync(() => s.plannedExercises.all()))!;
    expect(planned.where((p) => p.exerciseId == 'bodyweight-standing-calf-raise'), hasLength(1));
    await teardownApp(tester, s);
  });

  test('filters: fits my gym, body area, bodyweight, search words', () {
    const a = Exercise(id: 'a', name: 'Machine leg press', primaryMuscles: ['quadriceps'], equipment: ['machine']);
    const b = Exercise(id: 'b', name: 'Bodyweight squat', primaryMuscles: ['quadriceps'], equipment: ['body only']);
    const c = Exercise(id: 'c', name: 'Dumbbell curl', primaryMuscles: ['biceps'], equipment: ['dumbbell']);
    final all = [a, b, c];
    expect(filterExercises(all, const LibraryFilter(), const ['dumbbells']).map((e) => e.id), ['b', 'c']);
    expect(filterExercises(all, const LibraryFilter(fitsGym: false), const ['dumbbells']).map((e) => e.id), ['a', 'b', 'c']);
    expect(filterExercises(all, const LibraryFilter(area: 'legs', fitsGym: false), const []).map((e) => e.id), ['a', 'b']);
    expect(filterExercises(all, const LibraryFilter(equipment: kBodyweight, fitsGym: false), const []).map((e) => e.id), ['b']);
    expect(filterExercises(all, const LibraryFilter(query: 'leg quad', fitsGym: false), const []).map((e) => e.id), ['a']);
    expect(prIndexes([50, 52, 51, 55]), [1, 3]);
  });
}
