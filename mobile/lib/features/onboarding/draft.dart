// Onboarding answers (port of src/features/onboarding/draft.ts, extended for the Repfellow flow).
// Pure Dart apart from models: no widgets here, so the mapping to a Profile is easy to test.
import '../../domain/equipment.dart';
import '../../domain/models.dart';

/// Meta keys written by onboarding (and read by Today / Coach / settings).
abstract final class ObMeta {
  static const onboardedAt = 'onboardedAt';
  static const setupChangedAt = 'setupChangedAt';

  /// Trainer / promo / invite code. Also the invite code the AI coach server needs during TestFlight.
  static const accessCode = 'accessCode';

  /// Pro unlocked by a trainer or promo code (the code string).
  static const proViaCode = 'proViaCode';

  /// BETA stub: Pro "trial" started from the paywall while StoreKit isn't wired. No payment is taken.
  static const proBeta = 'proBeta';

  /// The paywall is shown once: ISO time it was seen.
  static const paywallSeenAt = 'paywallSeenAt';

  /// 'en' | 'hinglish' (the coach replies in this style; the UI stays English).
  static const coachLanguage = 'coachLanguage';

  /// Body-check answers: list of area ids (empty = none).
  static const painAreas = 'painAreas';

  /// Experience detail: knows working weights (skip calibration later).
  static const knowsWeights = 'knowsWeights';

  /// Whey preference: 'yes' | 'no' | 'unsure'.
  static const whey = 'whey';

  /// Usual training window id (see [kTrainTimes]).
  static const trainWindow = 'trainWindow';

  /// Training-day reminders: {enabled: bool, time: 'HH:mm'}.
  static const reminders = 'trainingReminders';
}

class Choice<T> {
  const Choice(this.id, this.label, [this.sub = '']);
  final T id;
  final String label;
  final String sub;
}

const List<Choice<Experience>> kExperience = [
  Choice(Experience.beginner, 'New', 'Less than 6 months of regular training'),
  Choice(Experience.intermediate, 'Some', '6 months to 2 years'),
  Choice(Experience.advanced, 'Experienced', 'More than 2 years'),
];

const List<int> kSessionLengths = [30, 45, 60, 75];

/// When you train → default reminder / session time.
const List<Choice<String>> kTrainTimes = [
  Choice('early', 'Early morning', '06:30'),
  Choice('morning', 'Morning', '09:15'),
  Choice('evening', 'Evening rush', '18:30'),
  Choice('night', 'Late evening', '20:30'),
];

/// Where you train → an equipment preset (the checklist stays editable).
class GymPreset {
  const GymPreset(this.id, this.label, this.sub, this.equipment);
  final String id;
  final String label;
  final String sub;
  final List<String> equipment;
}

final List<GymPreset> kGymPresets = [
  const GymPreset('local', 'Local gym', 'Dumbbells, barbell, cables, a few machines', [
    Equip.dumbbells, Equip.bench, Equip.barbell, Equip.cable, Equip.machines, Equip.pullupBar, Equip.cardioMachines, //
  ]),
  GymPreset('premium', 'Premium chain', 'Everything, including sleds and trap bars', kPresets['full_gym']!),
  GymPreset('home_db', 'Home with dumbbells', 'Dumbbells, a bench, bands', kPresets['dumbbells_only']!),
  const GymPreset('hotel', 'Hotel or office gym', 'Light dumbbells, a bench, cardio machines', [
    Equip.dumbbells, Equip.bench, Equip.cardioMachines, //
  ]),
  GymPreset('home_bw', 'Bodyweight and bands', 'No weights at all', kPresets['home']!),
];

const List<Choice<String>> kPainAreas = [
  Choice('neck', 'Neck'),
  Choice('shoulder', 'Shoulder'),
  Choice('elbow', 'Elbow or wrist'),
  Choice('upper_back', 'Upper back'),
  Choice('lower_back', 'Lower back'),
  Choice('hip', 'Hip'),
  Choice('knee', 'Knee'),
  Choice('ankle', 'Ankle or foot'),
];

const List<Choice<DietType>> kDietTypes = [
  Choice(DietType.veg, 'Veg', 'Dairy yes, no eggs, meat or fish'),
  Choice(DietType.vegEgg, 'Egg + veg', 'Veg plus eggs'),
  Choice(DietType.nonveg, 'Non-veg', 'Chicken, fish and eggs too'),
  Choice(DietType.vegan, 'Vegan', 'No dairy, eggs or meat'),
];

/// A protein food the person eats. Unticking one adds [blocks] to the profile's intolerances,
/// which the diet generator already honours.
class ProteinSource {
  const ProteinSource(this.id, this.label, {this.blocks, this.allowed = const {}});
  final String id;
  final String label;
  final String? blocks;

  /// Diet types that can eat it (empty = all).
  final Set<DietType> allowed;
  bool fits(DietType d) => allowed.isEmpty || allowed.contains(d);
}

const List<ProteinSource> kProteinSources = [
  ProteinSource('dal', 'Dal, chana, rajma'),
  ProteinSource('paneer', 'Paneer', blocks: 'paneer', allowed: {DietType.veg, DietType.vegEgg, DietType.nonveg}),
  ProteinSource('curd', 'Curd and milk', allowed: {DietType.veg, DietType.vegEgg, DietType.nonveg}),
  ProteinSource('soya', 'Soya chunks and tofu', blocks: 'soy'),
  ProteinSource('eggs', 'Eggs', blocks: 'egg', allowed: {DietType.vegEgg, DietType.nonveg}),
  ProteinSource('meat', 'Chicken and fish', allowed: {DietType.nonveg}),
];

/// Things to avoid regardless of diet type (stored as intolerances).
const List<Choice<String>> kAvoid = [
  Choice('lactose', 'Lactose'),
  Choice('gluten', 'Gluten'),
  Choice('nuts', 'Nuts'),
];

class OnboardingDraft {
  OnboardingDraft();

  String name = '';
  Goal? goal;
  Experience experience = Experience.beginner;
  bool? knowsWeights;
  List<Weekday> days = [Weekday.mon, Weekday.wed, Weekday.fri];
  int sessionMin = 45;
  String trainWindow = 'evening';
  String gymPreset = 'local';
  List<String> equipment = List.of(kGymPresets.first.equipment);

  /// null = not answered yet; empty = "None".
  List<String>? pain;
  Sex sex = Sex.male;
  int age = 30;
  double heightCm = 170;
  double weightKg = 75;
  double goalWeightKg = 70;
  DietType diet = DietType.vegEgg;

  /// Protein sources the person eats (ids of [kProteinSources]).
  Set<String> proteinSources = {'dal', 'paneer', 'curd', 'soya', 'eggs', 'meat'};
  Set<String> avoid = {};
  String whey = 'unsure';
  String coachLanguage = 'en';

  String get sessionTime => kTrainTimes.firstWhere((t) => t.id == trainWindow, orElse: () => kTrainTimes[2]).sub;

  /// Intolerances derived from unticked protein sources and the avoid list.
  List<String> get intolerances => [
        for (final p in kProteinSources)
          if (p.blocks != null && p.fits(diet) && !proteinSources.contains(p.id)) p.blocks!,
        ...avoid,
      ];

  /// Prefill from an existing profile (redo setup with `?fresh=1`).
  static OnboardingDraft fromProfile(Profile p, {required int year}) {
    final d = OnboardingDraft()
      ..name = p.name == 'there' ? '' : p.name
      ..goal = p.goal
      ..experience = p.experience ?? Experience.beginner
      ..days = p.trainingDays.isEmpty ? [Weekday.mon, Weekday.wed, Weekday.fri] : List.of(p.trainingDays)
      ..sessionMin = kSessionLengths.contains(p.sessionMin) ? p.sessionMin! : 45
      ..equipment = List.of(p.equipment ?? kPresets['full_gym']!)
      ..sex = p.sex
      ..age = (year - p.birthYear).clamp(13, 90)
      ..heightCm = p.heightCm
      ..weightKg = p.startWeightKg
      ..goalWeightKg = p.goalWeightKg
      ..diet = p.dietType;
    d.gymPreset = kGymPresets.firstWhere((g) => _sameSet(g.equipment, d.equipment), orElse: () => const GymPreset('custom', '', '', [])).id;
    final intol = p.intolerances.map((x) => x.toLowerCase()).toSet();
    d.proteinSources = {
      for (final s in kProteinSources)
        if (s.blocks == null || !intol.contains(s.blocks)) s.id,
    };
    d.avoid = {for (final a in kAvoid) if (intol.contains(a.id)) a.id};
    final t = kTrainTimes.where((t) => t.sub == p.sessionTime);
    if (t.isNotEmpty) d.trainWindow = t.first.id;
    return d;
  }

  /// The profile to save. [base] keeps settings of an existing profile (units, rest timer…).
  Profile toProfile({required DateTime now, required String createdAt, Profile? base}) {
    final p = Profile(
      name: name.trim().isEmpty ? (base?.name ?? 'there') : name.trim(),
      sex: sex,
      birthYear: now.year - age,
      heightCm: heightCm,
      startWeightKg: weightKg,
      goalWeightKg: goalWeightKg,
      units: base?.units ?? 'kg',
      theme: base?.theme ?? 'system',
      dietType: diet,
      intolerances: intolerances,
      kcalTarget: base?.kcalTarget ?? 0,
      proteinTargetG: base?.proteinTargetG ?? 0,
      trainingDays: days.isEmpty ? [Weekday.mon, Weekday.wed, Weekday.fri] : (List.of(days)..sort((a, b) => a.index - b.index)),
      sessionTime: sessionTime,
      restTimer: base?.restTimer ?? const RestTimerPrefs(),
      stepKg: base?.stepKg ?? const StepKg(),
      weekStart: 'mon',
      createdAt: base?.createdAt ?? createdAt,
      goal: goal ?? Goal.lean,
      experience: experience,
      sessionMin: sessionMin,
      equipment: List.of(equipment),
      planSource: 'generated',
      dietSource: 'generated',
    );
    return p;
  }
}

bool _sameSet(List<String> a, List<String> b) => a.length == b.length && a.toSet().containsAll(b);

String painLabel(String id) => kPainAreas.firstWhere((p) => p.id == id, orElse: () => Choice(id, id)).label;

String goalLabel(Goal? g) => switch (g) {
      Goal.fatLoss => 'lose fat',
      Goal.lean => 'get lean and athletic',
      Goal.muscle => 'build muscle',
      Goal.strength => 'get stronger',
      Goal.general => 'stay fit',
      null => 'get fitter',
    };

String dietLabel(DietType d) => kDietTypes.firstWhere((x) => x.id == d).label;
