// Safety routing for coach requests (UX spec, "AI coach edit"): pain → conservative swaps plus a
// see-a-professional line; diabetes / PCOS / pregnancy / GLP-1 → cautious mode with a non-medical
// disclaimer. English and common Hinglish words.

final _pain = RegExp(
  r'\b(pain|painful|hurts?|hurting|injur\w*|sprain\w*|strain\w*|ache|aching|achy|tweak\w*|niggle|dard|chot|sore (knee|back|shoulder|elbow|wrist|neck|hip))\b',
  caseSensitive: false,
);

final _medical = RegExp(
  r'(diabet\w*|\bsugar (hai|patient|problem)|\bpcos\b|\bpcod\b|pregnan\w*|\bexpecting\b|\bglp[- ]?1\b|ozempic|wegovy|mounjaro|zepbound|semaglutide|tirzepatide|liraglutide|insulin|metformin)',
  caseSensitive: false,
);

class CoachSafety {
  const CoachSafety({required this.pain, required this.medical});
  final bool pain;
  final bool medical;
  bool get any => pain || medical;

  static CoachSafety of(String text) => CoachSafety(pain: _pain.hasMatch(text), medical: _medical.hasMatch(text));

  /// Extra instructions sent to the coach with the request.
  String get promptNote => [
        if (pain) 'Safety: the person mentions pain. Prefer conservative, joint-friendly swaps and lower load on the affected area; never train through pain.',
        if (medical)
          'Safety: the person mentions a medical condition or medication. Be cautious and conservative, avoid aggressive calorie deficits, and give no medical advice.',
      ].join('\n');
}

const kPainNote = 'If pain is sharp or lasts more than a few days, see a doctor or physio.';
const kMedicalNote =
    'You mentioned a health condition or medication. The coach keeps changes gentle, but it isn’t medical advice: check big diet or training changes with your doctor.';
