// Eat tab over an onboarded in-memory DB with demo data.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/eat/eat_logic.dart';
import 'package:repmate/features/eat/eat_screen.dart';
import 'package:repmate/features/eat/meal_cards.dart';

import 'feature_env.dart';

void main() {
  Future<List<MealLog>> todayLogs(WidgetTester tester, FeatureEnv env) async =>
      (await tester.runAsync(() => env.s.mealLogs.whereK1('2026-12-03')))!;

  testWidgets('shows planned meals as ghost cards with the protein ring and hit days', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const EatScreen());

    expect(find.text('Eat'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('/ 150 g'), findsOneWidget, reason: 'protein ring shows the diet target');
    expect(find.textContaining('Protein-hit days'), findsOneWidget);
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('Ate as planned'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('10:45 · Breakfast'), 200, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('LUNCH'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('DINNER'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('Water'), 300, scrollable: find.byType(Scrollable).first);
    await tearDownFeature(tester, env);
  });

  testWidgets('"Ate as planned" logs the meal in one tap, with ✓ and Undo', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const EatScreen());

    // The first ghost card is the pre-gym snack (Thursday is a training day); log it.
    await tester.tap(find.text('Ate as planned').first);
    await settle(tester);
    var logs = await todayLogs(tester, env);
    expect(logs, hasLength(1));
    expect(logs.single.state, 'eaten');
    final cardUndo = find.descendant(of: find.byType(PlannedMealCard), matching: find.text('Undo'));
    expect(cardUndo, findsOneWidget, reason: 'logged card offers Undo');
    expect(find.descendant(of: find.byType(PlannedMealCard), matching: find.byIcon(CupertinoIcons.checkmark_circle_fill)), findsOneWidget);
    expect(find.textContaining('Pre-gym logged · +2 g protein'), findsOneWidget, reason: 'toast confirms');

    await tester.tap(cardUndo);
    await settle(tester);
    logs = await todayLogs(tester, env);
    expect(logs, isEmpty);
    await tearDownFeature(tester, env);
  });

  testWidgets('log bar parses "2 roti aur dal, thoda ghee" into a review tray and logs it', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const EatScreen());

    await tester.enterText(find.byKey(const ValueKey('eat-log-input')), '2 roti aur dal, thoda ghee');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Review food'));
    await settle(tester);

    expect(find.text('Review your plate'), findsOneWidget);
    expect(find.text('Roti'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('Dal'), findsOneWidget);
    expect(find.text('1 katori (M)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('½ tsp'), 120, scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
    expect(find.text('Ghee'), findsOneWidget);
    expect(find.text('Normal oil'), findsOneWidget, reason: 'oil chip on the cooked dal');
    final impact = tester.widget<Text>(find.byKey(const ValueKey('tray-impact'))).data!;
    expect(impact, startsWith('+15 g protein · 383 kcal · day 15/150 g'));

    // Bahar ka raises the oil of cooked dishes.
    final tray = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Bahar ka'), 120, scrollable: tray);
    await tester.tap(find.text('Bahar ka'));
    await tester.pump();
    expect(find.text('Zyada / dhaba'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await settle(tester);
    final logs = await todayLogs(tester, env);
    expect(logs, hasLength(1));
    expect(isExtraLog(logs.single), isTrue);
    expect(slotOfExtra(logs.single), MealSlot.lunch, reason: '13:00 lands in lunch');
    expect(logs.single.label, contains('Roti ×2'));
    expect(logs.single.proteinG, 15);
    await tester.scrollUntilVisible(find.textContaining('Roti ×2 · Dal'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byType(ExtraLogCard), findsOneWidget, reason: 'extra shows on the timeline');
    await tearDownFeature(tester, env);
  });

  testWidgets('vrat toggle swaps suggestions and eases the target', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const EatScreen());
    await tester.tap(find.text('Vrat day'));
    await settle(tester);
    expect(find.text('/ 113 g'), findsOneWidget, reason: '150 × 0.75, rounded');
    expect(find.textContaining('Sabudana'), findsWidgets);
    final vrat = await tester.runAsync(() => env.s.getMeta<Object?>(kVratDaysKey));
    expect(vrat, ['2026-12-03']);
    await tearDownFeature(tester, env);
  });

  testWidgets('Swap offers equal-protein options and logs the pick', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const EatScreen());
    final card = find.ancestor(of: find.textContaining('10:45 · Breakfast'), matching: find.byType(PlannedMealCard));
    await tester.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await settle(tester, rounds: 2);
    await tester.tap(find.descendant(of: card, matching: find.text('Swap')));
    await settle(tester);
    expect(find.text('Swap breakfast'), findsOneWidget);
    expect(find.textContaining('Instead of'), findsWidgets);
    await tester.tap(find.textContaining('Instead of').first);
    await settle(tester);
    final logs = await todayLogs(tester, env);
    expect(logs.single.state, 'swapped');
    expect(logs.single.plannedMealId, isNot(startsWith('extra:')));
    await tearDownFeature(tester, env);
  });

  testWidgets('an edited dish is remembered as "My dal" for the next parse', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const EatScreen());
    Future<void> openTray(String text) async {
      await tester.enterText(find.byKey(const ValueKey('eat-log-input')), text);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Review food'));
      await settle(tester);
    }

    await openTray('dal');
    await tester.tap(find.text('Normal oil')); // oil chip cycles normal → rich
    await tester.pump();
    expect(find.text('Zyada / dhaba'), findsOneWidget);
    await tester.tap(find.text('Log'));
    await settle(tester);
    final mine = await tester.runAsync(() => env.s.getMeta<Object?>(kMyDishesKey));
    expect((mine as Map)['dal'], containsPair('oil', 'rich'));
    expect(find.textContaining('saved as My dal'), findsOneWidget);

    await openTray('1 katori dal');
    expect(find.text('My dal'), findsOneWidget);
    expect(find.text('Zyada / dhaba'), findsOneWidget, reason: 'my dal keeps its oil');
    await tearDownFeature(tester, env);
  });
}
