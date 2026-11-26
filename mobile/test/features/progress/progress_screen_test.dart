// Progress tab over an onboarded in-memory DB with ~30 days of demo data.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/features/progress/history.dart';
import 'package:repmate/features/progress/lift_charts.dart';
import 'package:repmate/features/progress/progress_screen.dart';

import '../eat/feature_env.dart';

void main() {
  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;
  Finder scrollable() => find.byType(Scrollable).first;

  testWidgets('renders the weekly card and a lift chart from demo data', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const ProgressScreen());

    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Top sets'), findsOneWidget);
    expect(find.text('Trend weight'), findsWidgets);
    expect(find.text('Protein days'), findsOneWidget);
    expect(text(tester, 'weekly-trend'), matches(RegExp(r'^\d+\.\d kg$')));
    expect(text(tester, 'weekly-sentence'), contains('protein days'));

    await tester.scrollUntilVisible(find.byType(LineChart).first, 200, scrollable: scrollable());
    expect(find.byType(LiftChartCard), findsOneWidget);
    expect(find.text('Dumbbell goblet squat'), findsWidgets, reason: 'main lift chip from the plan’s A slot');
    expect(find.textContaining('Estimated 1-rep max'), findsOneWidget);
    expect(find.text('1M'), findsOneWidget);
    expect(find.text('1Y'), findsOneWidget);
    await tester.tap(find.text('1M'));
    await tester.pump();

    await tester.scrollUntilVisible(find.byType(StrengthCard), 200, scrollable: scrollable());
    expect(find.textContaining('body weight)'), findsWidgets, reason: 'strength level rows explain the ratio');
    await tearDownFeature(tester, env);
  });

  testWidgets('logging weight with the stepper sheet updates the weekly card', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const ProgressScreen());
    final before = text(tester, 'weekly-trend');

    await tester.scrollUntilVisible(find.text('Log weight'), 200, scrollable: scrollable());
    await tester.tap(find.text('Log weight'));
    await settle(tester);
    expect(find.text('Same time each morning, after the bathroom, before food. The 7-day average is what counts.'), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.bySemanticsLabel('Decrease Body weight'));
      await tester.pump();
    }
    await tester.tap(find.text('Save'));
    await settle(tester);

    final today = (await tester.runAsync(() => env.s.bodyLogs.whereK1('2026-12-03')))!;
    expect(today, hasLength(1));
    expect(today.single.weightKg, isNotNull);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('weekly-trend')), -200, scrollable: scrollable());
    expect(text(tester, 'weekly-trend'), isNot(before), reason: 'a 3 kg lighter weigh-in moves the 7-day trend');
    await tearDownFeature(tester, env);
  });

  testWidgets('workout history opens a session with its sets', (tester) async {
    final env = await setUpFeature(tester);
    await pumpFeature(tester, env, const ProgressScreen());
    await tester.scrollUntilVisible(find.text('WORKOUT HISTORY'), 300, scrollable: scrollable());
    await tester.scrollUntilVisible(find.byType(HistoryList), 200, scrollable: scrollable());
    final first = find.textContaining('workout #').first;
    await tester.ensureVisible(first);
    await tester.pump();
    await tester.tap(first);
    await settle(tester);
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.textContaining('Set 1'), findsWidgets);
    expect(find.textContaining('reps'), findsWidgets);
    await tearDownFeature(tester, env);
  });
}
