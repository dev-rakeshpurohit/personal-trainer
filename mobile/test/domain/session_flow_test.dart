import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/session_flow.dart';

void main() {
  group('session flow', () {
    final flow = buildFlow([
      (sets: 4, supersetGroup: 'A'),
      (sets: 3, supersetGroup: 'A'),
      (sets: 2, supersetGroup: null),
    ]);

    test('alternates superset pairs and handles uneven set counts', () {
      expect(flow.map(stepKey).toList(), ['0:0', '1:0', '0:1', '1:1', '0:2', '1:2', '0:3', '2:0', '2:1']);
    });

    test('finds the next pending step and wraps around', () {
      final done = {'0:0'};
      expect(nextStep(flow, done, from: (ex: 0, set: 0)), (ex: 1, set: 0));
      final almost = flow.map(stepKey).where((k) => k != '0:1').toSet();
      expect(nextStep(flow, almost, from: (ex: 2, set: 1)), (ex: 0, set: 1));
      expect(nextStep(flow, flow.map(stepKey).toSet(), from: (ex: 2, set: 1)), isNull);
    });

    // Extra Dart-side checks of edge behaviour that mirrors the TS.
    test('without from starts at the first step; empty flow gives null', () {
      expect(nextStep(flow, {}), (ex: 0, set: 0));
      expect(nextStep(const [], {}), isNull);
    });

    test('empty superset group string is treated as no group', () {
      final f = buildFlow([(sets: 2, supersetGroup: ''), (sets: 1, supersetGroup: '')]);
      expect(f.map(stepKey).toList(), ['0:0', '0:1', '1:0']);
    });
  });
}
