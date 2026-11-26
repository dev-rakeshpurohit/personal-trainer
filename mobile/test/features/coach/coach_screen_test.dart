// Coach tab end to end over an in-memory DB and a mocked /api/coach.
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:repmate/data/db/store.dart';
import 'package:repmate/data/services/coach_client.dart';
import 'package:repmate/data/services/plan_builder.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';
import 'package:repmate/features/coach/coach_screen.dart';
import 'package:repmate/features/coach/proposal_diff.dart';
import 'package:repmate/state/providers.dart';
import 'package:repmate/ui/theme.dart';

import '../../data/harness.dart';

void main() {
  final seed = loadSeed();
  final now = DateTime(2026, 11, 26, 9);
  late Stores s;
  late String prevProgramId;
  late PlannedExercise changed; // first exercise of the first training day: its dose changes
  late String addedId; // an exercise the coach adds
  late String addedName;
  late Map<String, Object?> reply;
  var status = 200;
  var calls = 0;

  setUp(() async {
    status = 200;
    calls = 0;
    s = memoryStores();
    final b = PlanBuilder(s, seed, newId: counterIds('seed'), now: () => now);
    await b.ensureLibrary();
    await b.importProgramTemplate(trainingDays: const [Weekday.tue, Weekday.thu]);
    await b.importDietTemplate();
    await s.profile.put(builderProfile(equipment: kPresets['full_gym']!));
    await s.setMeta('accessCode', 'RPM-TEST-CODE');

    final bundle = (await loadProgramBundle(s))!;
    prevProgramId = bundle.program.id;
    final lib = await s.exercises.all();
    final allowed = coachExercises(lib, builderProfile(equipment: kPresets['full_gym']!)).map((e) => e.id).toSet();
    final training = bundle.days.where((d) => d.type == DayType.strength && bundle.plannedFor(d.id).isNotEmpty).toList();
    final first = training.first;
    final planned = bundle.plannedFor(first.id).where((p) => allowed.contains(p.exerciseId)).toList();
    changed = planned.first;
    final inPlan = bundle.planned.map((p) => p.exerciseId).toSet();
    final add = lib.firstWhere((e) => allowed.contains(e.id) && !inPlan.contains(e.id) && e.pattern == 'calves');
    addedId = add.id;
    addedName = add.name;

    Map<String, Object?> exJson(PlannedExercise p, {int? sets, int? lo, int? hi}) => {
          'id': p.exerciseId,
          'sets': sets ?? p.sets,
          'repsMin': lo ?? p.repsMin,
          'repsMax': hi ?? p.repsMax,
          'unit': p.unit.wire,
          'restSec': p.restSec,
        };
    reply = {
      'plan': {
        'summary': 'Kept your heavy work and added calves; volume stays in range.',
        'workout': {
          'name': 'AI · knee-friendly',
          'days': [
            for (final d in training)
              {
                'weekday': d.weekday.wire,
                'type': 'strength',
                'title': d.title,
                'exercises': [
                  for (final p in bundle.plannedFor(d.id).where((p) => allowed.contains(p.exerciseId)))
                    p.id == changed.id ? exJson(p, sets: p.sets + 1, lo: 10, hi: 10) : exJson(p),
                  if (d.id == first.id) {'id': addedId, 'sets': 3, 'repsMin': 12, 'repsMax': 15, 'unit': 'reps', 'restSec': 60},
                ],
              },
          ],
        },
      },
      'costUsd': 0.01,
      'model': 'test-model',
    };
  });
  tearDown(() => s.db.close());

  Future<void> pumpCoach(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = MockClient((req) async {
      calls++;
      if (status != 200) return http.Response(jsonEncode({'error': 'Invalid code'}), status);
      return http.Response(jsonEncode(reply), 200, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storesProvider.overrideWithValue(s),
        clockProvider.overrideWithValue(() => now),
        idGenProvider.overrideWithValue(counterIds('t')),
        seedDataProvider.overrideWith((ref) async => seed),
        coachClientProvider.overrideWithValue(CoachClient(s, client: client, now: () => now)),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const CoachScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('coach-input')), text);
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up));
    await tester.pump();
    // wait for the coach to answer (the "working on it" card disappears)
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (i > 2 && find.text('Coach is working on it').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<Program?> active(WidgetTester tester) => tester.runAsync<Program?>(() => s.activeProgram());

  testWidgets('a request shows a proposal card with diff, impact and safety note', (tester) async {
    await pumpCoach(tester);
    expect(find.text('Coach can be wrong — review before approving'), findsOneWidget);
    await ask(tester, 'Knee hurts, go easy');
    expect(calls, 1);
    expect(find.text('Knee-friendly week'), findsOneWidget);
    expect(find.text('Knee hurts, go easy'), findsOneWidget); // the user's bubble
    // diff: the changed dose and the added exercise
    final from = doseLabel(changed.sets, changed.repsMin, changed.repsMax, changed.unit);
    final to = doseLabel(changed.sets + 1, 10, 10, changed.unit);
    expect(find.text('$from → $to'), findsOneWidget);
    expect(find.text(addedName), findsOneWidget);
    // impact strip + why + safety
    expect(find.textContaining('Plan check:'), findsOneWidget);
    expect(find.textContaining('Calves'), findsWidgets);
    expect(find.textContaining('Session'), findsWidgets);
    expect(find.textContaining('Based on your plan and last sessions'), findsOneWidget);
    expect(find.text('If pain is sharp or lasts more than a few days, see a doctor or physio.'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    // the composer is cleared after a proposal arrives
    expect(find.widgetWithText(TextField, 'Knee hurts, go easy'), findsNothing);
  });

  testWidgets('Approve activates the AI program; Undo restores the previous one', (tester) async {
    await pumpCoach(tester);
    await ask(tester, 'Add some calf work');
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    final p = await active(tester);
    expect(p!.id, isNot(prevProgramId));
    expect(p.templateId, 'ai-coach');
    expect(find.text('Plan updated'), findsOneWidget);
    expect(find.textContaining('Approved'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect((await active(tester))!.id, prevProgramId);
    expect(find.textContaining('Undone'), findsWidgets);
    expect(find.text('Undone. Your previous plan is back.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('Discard leaves the plan as it is', (tester) async {
    await pumpCoach(tester);
    await ask(tester, 'Add some calf work');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect((await active(tester))!.id, prevProgramId);
    expect(find.text('Discarded. Your plan didn’t change.'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('Plan history lists proposals with date and outcome', (tester) async {
    await pumpCoach(tester);
    await ask(tester, 'Add some calf work');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.clock));
    await tester.pumpAndSettle();
    expect(find.text('Plan history'), findsOneWidget);
    expect(find.text('Your plan, adjusted'), findsOneWidget);
    expect(find.text('Discarded'), findsOneWidget);
    expect(find.textContaining('Thu 26 Nov'), findsOneWidget);
  });

  testWidgets('Adjust removes a line before approving', (tester) async {
    await pumpCoach(tester);
    await ask(tester, 'Add some calf work');
    expect(find.text(addedName), findsOneWidget);
    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    // the added exercise is the second line; "×" keeps the current plan for it
    expect(find.bySemanticsLabel('Keep current plan for this line'), findsWidgets);
    await tester.tap(find.byKey(ValueKey('keep-line-$addedId')));
    await tester.pumpAndSettle();
    expect(find.text(addedName), findsNothing);
    expect(find.textContaining('adjusted by you'), findsOneWidget);
  });

  testWidgets('401 shows the invite-code message and keeps the request text', (tester) async {
    status = 401;
    await pumpCoach(tester);
    await ask(tester, 'Vrat on Thursday please');
    expect(find.textContaining('needs your invite code'), findsOneWidget);
    expect(find.byKey(const Key('coach-code')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Vrat on Thursday please'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('free tier: the edit meter counts down', (tester) async {
    await s.setMeta('proBeta', false);
    await pumpCoach(tester);
    expect(find.text('3 of 3 free edits left this month'), findsOneWidget);
    await ask(tester, 'Make it harder');
    expect(find.text('2 of 3 free edits left this month'), findsOneWidget);
  });

  testWidgets('Pro beta (invite code saved) shows unlimited edits', (tester) async {
    await pumpCoach(tester);
    expect(find.text('Pro beta · unlimited edits'), findsOneWidget);
  });
}
