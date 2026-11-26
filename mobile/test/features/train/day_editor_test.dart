// Day editor: steppers write through, remove has Undo, add goes through the picker.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/features/train/day_editor_screen.dart';
import 'package:repmate/ui/widgets.dart' show BigStepper;

import 'train_harness.dart';

void main() {
  testWidgets('edit sets with a stepper, remove with Undo, add from the picker', (tester) async {
    phoneSize(tester);
    final s = await seededStores(tester);
    final days = (await tester.runAsync(() => s.programDays.all()))!;
    final thu = days.firstWhere((d) => d.title.startsWith('Strength B'));
    await tester.pumpWidget(testApp(s, DayEditorScreen(dayId: thu.id)));
    final legPressRow = find.textContaining('Leg press', findRichText: true);
    await pumpUntil(tester, legPressRow);
    expect(find.text('Edit Thursday'), findsOneWidget);

    // sets stepper
    await tapVisible(tester, legPressRow);
    await pumpUntil(tester, find.text('Remove from this day'));
    await tapVisible(tester, find.descendant(of: find.byType(BigStepper).first, matching: find.byIcon(CupertinoIcons.plus))); // the Sets stepper comes first
    await settle(tester);
    var legPress = (await tester.runAsync(() => s.plannedExercises.whereK1(thu.id)))!.firstWhere((p) => p.exerciseId == 'leg-press');
    expect(legPress.sets, 4);

    // remove + undo
    await tapVisible(tester, find.text('Remove from this day'));
    await pumpUntil(tester, find.text('Leg press removed'));
    expect((await tester.runAsync(() => s.plannedExercises.whereK1(thu.id)))!.any((p) => p.exerciseId == 'leg-press'), isFalse);
    await tapVisible(tester, find.text('Undo'));
    await settle(tester);
    legPress = (await tester.runAsync(() => s.plannedExercises.whereK1(thu.id)))!.firstWhere((p) => p.exerciseId == 'leg-press');
    expect(legPress.sets, 4);

    // add from the picker
    await scrollTo(tester, find.text('Add exercise'), find.byType(Scrollable).first);
    await tapVisible(tester, find.text('Add exercise'));
    await pumpUntil(tester, find.textContaining('matches'));
    await tester.enterText(find.byType(TextField), 'seated calf raise');
    await pumpUntil(tester, find.text('Machine seated calf raise'));
    await tapVisible(tester, find.text('Machine seated calf raise'));
    await pumpUntil(tester, find.textContaining('Machine seated calf raise added'));
    expect((await tester.runAsync(() => s.plannedExercises.whereK1(thu.id)))!.any((p) => p.exerciseId == 'machine-seated-calf-raise'), isTrue);

    await teardownApp(tester, s);
  });
}
