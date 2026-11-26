// Port of src/domain/units.ts. Pure Dart.
const double kKgPerLb = 0.45359237;

double kgToLb(double kg) => kg / kKgPerLb;
double lbToKg(double lb) => lb * kKgPerLb;

double roundTo(double n, double step) => (n / step).round() * step;

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);
}

/// Display a kg value in the user's units, rounded sensibly.
String displayWeight(double? kg, String units) {
  if (kg == null) return '–';
  final v = units == 'kg' ? roundTo(kg, 0.25) : roundTo(kgToLb(kg), 0.5);
  return _fmt(v);
}

double toUserUnits(double kg, String units) => units == 'kg' ? roundTo(kg, 0.25) : roundTo(kgToLb(kg), 0.5);

double fromUserUnits(double v, String units) => units == 'kg' ? v : lbToKg(v);

/// Stepper increment in the user's display unit.
double stepFor(double stepKg, String units) {
  if (units == 'kg') return stepKg;
  return stepKg <= 2.5 ? 5 : 10;
}

({int ft, int inch}) cmToFtIn(double cm) {
  final totalIn = (cm / 2.54).round();
  return (ft: totalIn ~/ 12, inch: totalIn % 12);
}

String formatDuration(num sec) {
  final s = sec.round() < 0 ? 0 : sec.round();
  final m = s ~/ 60;
  final r = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (m >= 60) return '${m ~/ 60}:${two(m % 60)}:${two(r)}';
  return '$m:${two(r)}';
}
