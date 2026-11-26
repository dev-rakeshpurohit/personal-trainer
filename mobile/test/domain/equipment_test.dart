// Port of src/domain/equipment.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:repmate/domain/equipment.dart';
import 'package:repmate/domain/models.dart';

Exercise ex(String id, String name, List<String> equipment, {int level = 3, List<String>? alternates}) => Exercise(
      id: id,
      name: name,
      equipment: equipment,
      category: Category.strength,
      defaultUnit: Unit.reps,
      level: level,
      alternates: alternates,
    );

void main() {
  group('required equipment', () {
    test('maps free-exercise-db equipment and names', () {
      expect(requiredEquipment(ex('a', 'Dumbbell goblet squat', ['dumbbell'])), ['dumbbells']);
      expect(requiredEquipment(ex('b', 'Trap-bar deadlift', ['other'])), ['trap_bar']);
      expect(requiredEquipment(ex('c', 'Lat pulldown', ['cable'])), containsAll(['cable', 'machines']));
      expect(requiredEquipment(ex('d', 'Leg press', ['machine'])), ['machines']);
      expect(requiredEquipment(ex('e', 'Bike intervals', ['machine'])), ['cardio_machines']);
      expect(requiredEquipment(ex('f', 'Front plank', ['body only'])), isEmpty);
      expect(requiredEquipment(ex('g', 'Incline dumbbell press', ['dumbbell'])), ['dumbbells', 'bench']);
      expect(requiredEquipment(ex('h', 'Hanging knee raise', ['body only'])), ['pullup_bar']);
      expect(requiredEquipment(ex('i', 'Band face pull', ['bands'])), ['bands']);
      expect(requiredEquipment(ex('j', 'Low box jump (30–45 cm)', ['body only'])), ['box']);
      expect(requiredEquipment(ex('k', "Farmer's carry", ['other'])), ['dumbbells']);
    });
    test('checks availability; bodyweight is always available', () {
      expect(isAvailable(ex('f', 'Push-ups', ['body only']), []), isTrue);
      expect(isAvailable(ex('a', 'Dumbbell row', ['dumbbell']), kPresets['home']!), isFalse);
      expect(isAvailable(ex('a', 'Dumbbell row', ['dumbbell']), kPresets['dumbbells_only']!), isTrue);
    });
  });

  group('plan substitution', () {
    final lat = ex('lat', 'Lat pulldown', ['cable'], level: 2, alternates: ['band', 'pull', 'row']);
    final band = ex('band', 'Band-assisted pull-up', ['bands'], level: 2);
    final pull = ex('pull', 'Pull-up', ['body only'], level: 4);
    final row = ex('row', 'One-arm dumbbell row', ['dumbbell'], level: 2);
    final map = {for (final e in [lat, band, pull, row]) e.id: e};
    const pe = PlannedExercise(
      id: 'p1',
      dayId: 'd',
      order: 0,
      slot: 'B1',
      exerciseId: 'lat',
      swapExerciseId: 'row',
      sets: 3,
      repsMin: 10,
      repsMax: 12,
      unit: Unit.reps,
      perSide: false,
      restSec: 60,
    );

    test('prefers the closest difficulty that is available', () {
      expect(bestReplacement(lat, [row, band, pull], ['dumbbells', 'bands'])?.id, 'row');
      expect(bestReplacement(lat, [band, pull], ['bands', 'pullup_bar'])?.id, 'band');
      expect(bestReplacement(lat, [band, pull], ['bands']), isNull); // band-assisted pull-ups still need a bar
    });
    test('never keeps an unavailable exercise: replace main, then fix the swap', () {
      final c = adaptToEquipment([pe], map, ['bands', 'pullup_bar']);
      expect(c, const [
        PlanChange(plannedExerciseId: 'p1', from: 'lat', to: 'band', kind: PlanChangeKind.replaced),
        PlanChange(plannedExerciseId: 'p1', from: 'row', to: 'pull', kind: PlanChangeKind.swapReplaced),
      ]);
    });
    test('removes when nothing fits', () {
      final lonely = ex('lonely', 'Leg press', ['machine'], level: 2, alternates: []);
      final c = adaptToEquipment([pe.copyWith(exerciseId: 'lonely', swapExerciseId: () => null)], {'lonely': lonely}, []);
      expect(c[0].kind, PlanChangeKind.removed);
    });
    test('keeps everything with a full gym', () {
      expect(adaptToEquipment([pe], map, kPresets['full_gym']!), isEmpty);
    });
  });

  group('JS sort helpers', () {
    test('jsLocaleCompare orders like String.prototype.localeCompare', () {
      final names = ['dumbbell fly', 'Dumbbell Fly', 'Cable crunch', 'cable-crunch', '3/4 sit-up', 'band pull-apart', 'Band face pull'];
      expect(stableSorted(names, jsLocaleCompare),
          ['3/4 sit-up', 'Band face pull', 'band pull-apart', 'Cable crunch', 'cable-crunch', 'dumbbell fly', 'Dumbbell Fly']);
    });
    test('stableSorted keeps input order on ties', () {
      final xs = [(k: 1, v: 'a'), (k: 0, v: 'b'), (k: 1, v: 'c'), (k: 0, v: 'd')];
      expect(stableSorted(xs, (a, b) => a.k - b.k).map((x) => x.v), ['b', 'd', 'a', 'c']);
    });
  });
}
