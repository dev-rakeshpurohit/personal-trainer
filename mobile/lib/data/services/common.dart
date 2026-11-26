// Shared helpers for the data services (ids, clock, JS-compatible formatting).
import 'package:uuid/uuid.dart';

import '../../domain/equipment.dart';
import '../../domain/models.dart';
import '../seed/library_builder.dart' show IdGen;

export '../seed/library_builder.dart' show IdGen;

/// Injectable "now" (the PWA used `new Date()`); tests pass a fixed clock.
typedef Clock = DateTime Function();

const _uuid = Uuid();

/// Random v4 uuid, like `crypto.randomUUID()` in the PWA.
String uuidV4() => _uuid.v4();

/// Default id generator.
const IdGen defaultIdGen = uuidV4;

DateTime systemNow() => DateTime.now();

/// JS `Date.toISOString()`: UTC, millisecond precision, trailing `Z`.
String isoString(DateTime d) => DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true).toIso8601String();

/// Parse an ISO timestamp to local time (JS `new Date(iso)` then local getters).
DateTime parseIsoLocal(String s) => DateTime.parse(s).toLocal();

/// Gym equipment for a profile (full gym for older profiles without the field).
List<String> equipmentOf(Profile p) => p.equipment ?? kPresets['full_gym']!;

/// JS `Math.round` (halves toward +∞).
int jsRound(num x) => (x + 0.5).floor();

/// JS `String(n)` for template literals: no trailing `.0` on whole numbers.
String jsNum(num n) => n is double && n.isFinite && n == n.truncateToDouble() ? n.toInt().toString() : n.toString();

/// `n.toLocaleString()` in en-US (thousands separators), e.g. 2000 → "2,000".
String thousands(num n) {
  final neg = n < 0;
  final s = jsNum(n.abs());
  final dot = s.indexOf('.');
  final intPart = dot < 0 ? s : s.substring(0, dot);
  final frac = dot < 0 ? '' : s.substring(dot);
  final b = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) b.write(',');
    b.write(intPart[i]);
  }
  return '${neg ? '-' : ''}$b$frac';
}
