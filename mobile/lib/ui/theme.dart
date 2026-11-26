// Repfellow design tokens (UX spec §Visual language). Light / dark follow the system;
// "Gym mode" is the dark theme forced on during a workout (see GymMode in app shell).
// Rule: one accent per screen; red ONLY for destructive actions, never for misses.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class RfColors extends ThemeExtension<RfColors> {
  const RfColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.done,
    required this.pr,
    required this.coach,
    required this.trainer,
    required this.caution,
    required this.destructive,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;

  /// Marigold: "do this now" (Start, Done, primary buttons). Fill colour.
  final Color accent;

  /// Accent used as text/icon on the background (contrast-safe).
  final Color accentInk;
  final Color onAccent;

  /// Leaf: logged sets, completed days.
  final Color done;

  /// Gold: PRs and milestones (always with a trophy glyph).
  final Color pr;

  /// Violet "coach ink": anything authored or changed by the AI.
  final Color coach;

  /// Teal: anything authored or approved by the human trainer.
  final Color trainer;

  /// Amber: gentle warnings, "above range". Never used for misses.
  final Color caution;

  /// The only red in the app: delete, cancel subscription.
  final Color destructive;

  static const dark = RfColors(
    bg: Color(0xFF0B0B0F),
    surface: Color(0xFF16161D),
    surface2: Color(0xFF20202A),
    line: Color(0xFF2E2E3B),
    text: Color(0xFFF4F4F7),
    muted: Color(0xFFA3A3B5),
    accent: Color(0xFFFF8A00),
    accentInk: Color(0xFFFFA33D),
    onAccent: Color(0xFF14100B),
    done: Color(0xFF2FBF71),
    pr: Color(0xFFFFD23F),
    coach: Color(0xFF9A8CFF),
    trainer: Color(0xFF25C2B0),
    caution: Color(0xFFF2A93B),
    destructive: Color(0xFFFF453A),
  );

  static const light = RfColors(
    bg: Color(0xFFF5F5F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFECECF1),
    line: Color(0xFFDADAE2),
    text: Color(0xFF111117),
    muted: Color(0xFF5C5C6C),
    accent: Color(0xFFFF8A00),
    accentInk: Color(0xFFA84F00),
    onAccent: Color(0xFF14100B),
    done: Color(0xFF17844A),
    pr: Color(0xFF8A6A00),
    coach: Color(0xFF5848D2),
    trainer: Color(0xFF0B7F72),
    caution: Color(0xFF9A6100),
    destructive: Color(0xFFD70015),
  );

  @override
  RfColors copyWith() => this;

  @override
  RfColors lerp(ThemeExtension<RfColors>? other, double t) {
    if (other is! RfColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RfColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      accentInk: l(accentInk, other.accentInk),
      onAccent: l(onAccent, other.onAccent),
      done: l(done, other.done),
      pr: l(pr, other.pr),
      coach: l(coach, other.coach),
      trainer: l(trainer, other.trainer),
      caution: l(caution, other.caution),
      destructive: l(destructive, other.destructive),
    );
  }
}

/// Spacing, radii and control sizes.
abstract final class Rf {
  static const gutter = 16.0;
  static const cardRadius = 20.0;
  static const btnRadius = 14.0;
  static const chipRadius = 999.0;

  /// Platform minimum is 44pt; Repfellow's primary gym controls are larger.
  static const tap = 48.0;
  static const gymTap = 56.0;
  static const doneBar = 64.0;
}

/// Type scale (pt): Timer 56 · Set numerals 40 · Title 28 · Headline 20 · Body 17 · Caption 13.
/// Numerals always use tabular figures so values don't jitter as they change.
abstract final class RfType {
  static const _tab = [FontFeature.tabularFigures()];
  static const timer = TextStyle(fontSize: 56, fontWeight: FontWeight.w700, height: 1.0, fontFeatures: _tab, letterSpacing: -1);
  static const setNumeral = TextStyle(fontSize: 40, fontWeight: FontWeight.w700, height: 1.05, fontFeatures: _tab, letterSpacing: -0.5);
  static const title = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.4);
  static const headline = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.2);
  static const body = TextStyle(fontSize: 17, height: 1.35);
  static const bodyStrong = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.35);
  static const callout = TextStyle(fontSize: 15, height: 1.35);
  static const caption = TextStyle(fontSize: 13, height: 1.3);
  static const captionStrong = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3);
  static const overline = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, height: 1.2);
  static const numeral = TextStyle(fontFeatures: _tab);
}

extension RfContext on BuildContext {
  RfColors get rf => Theme.of(this).extension<RfColors>()!;
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? RfColors.dark : RfColors.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.coach,
    onSecondary: Colors.white,
    tertiary: c.trainer,
    error: c.destructive,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.text,
    surfaceContainerHighest: c.surface2,
    outline: c.line,
  );
  final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: scheme, platform: TargetPlatform.iOS);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: c.line,
    dividerTheme: DividerThemeData(color: c.line, thickness: 0.5, space: 0.5),
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    iconTheme: IconThemeData(color: c.text, size: 24),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: b == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: RfType.headline.copyWith(color: c.text),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: true,
      dragHandleColor: c.line,
      dragHandleSize: const Size(40, 5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface2,
      contentTextStyle: RfType.callout.copyWith(color: c.text, fontWeight: FontWeight.w500),
      actionTextColor: c.accentInk,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rf.btnRadius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rf.btnRadius), borderSide: BorderSide(color: c.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rf.btnRadius), borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rf.btnRadius), borderSide: BorderSide(color: c.accent, width: 1.5)),
      hintStyle: RfType.body.copyWith(color: c.muted),
      labelStyle: RfType.callout.copyWith(color: c.muted),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.accent, selectionHandleColor: c.accent),
  );
}
