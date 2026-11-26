// Design tokens: identical to the PWA (src/styles/index.css), dark by default.
// Uses the platform font (SF Pro on iOS) for a native feel.
import 'package:material_ui/material_ui.dart';

@immutable
class RmColors extends ThemeExtension<RmColors> {
  const RmColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.primary,
    required this.primaryInk,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color muted;
  final Color primary;
  final Color primaryInk;
  final Color onPrimary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  static const dark = RmColors(
    bg: Color(0xFF0B0F14),
    surface: Color(0xFF141A22),
    surface2: Color(0xFF1C2430),
    line: Color(0xFF283240),
    text: Color(0xFFF2F5F8),
    muted: Color(0xFF9AA7B4),
    primary: Color(0xFFFF7A1A),
    primaryInk: Color(0xFFFF9142),
    onPrimary: Color(0xFF0B0F14),
    success: Color(0xFF2BD47D),
    warning: Color(0xFFFFC14D),
    danger: Color(0xFFFF5C5C),
    info: Color(0xFF4DA3FF),
  );

  static const light = RmColors(
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFECEFF3),
    line: Color(0xFFDADFE6),
    text: Color(0xFF0F141A),
    muted: Color(0xFF54606E),
    primary: Color(0xFFFF7A1A),
    primaryInk: Color(0xFFB44708),
    onPrimary: Color(0xFF0B0F14),
    success: Color(0xFF128048),
    warning: Color(0xFFA06200),
    danger: Color(0xFFC82828),
    info: Color(0xFF1464C8),
  );

  @override
  RmColors copyWith() => this;

  @override
  RmColors lerp(ThemeExtension<RmColors>? other, double t) {
    if (other is! RmColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RmColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      primary: l(primary, other.primary),
      primaryInk: l(primaryInk, other.primaryInk),
      onPrimary: l(onPrimary, other.onPrimary),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
    );
  }
}

/// Radii and sizes from the PWA design system.
abstract final class Rm {
  static const cardRadius = 16.0;
  static const btnRadius = 12.0;
  static const tap = 48.0;
  static const gutter = 16.0;
}

extension RmTheme on BuildContext {
  RmColors get rm => Theme.of(this).extension<RmColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? RmColors.dark : RmColors.light;
  final scheme = ColorScheme(
    brightness: b,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.info,
    onSecondary: c.onPrimary,
    error: c.danger,
    onError: c.onPrimary,
    surface: c.surface,
    onSurface: c.text,
  );
  final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text).copyWith(
        // Display / title / body scale from the PWA (Tailwind config).
        displayLarge: const TextStyle(fontSize: 72, fontWeight: FontWeight.w700, height: 1),
        displayMedium: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, height: 1.2),
        headlineMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.3),
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.27),
        titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
        bodyLarge: const TextStyle(fontSize: 17, height: 1.4),
        bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
        bodySmall: const TextStyle(fontSize: 13, height: 1.35),
        labelLarge: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ).apply(bodyColor: c.text, displayColor: c.text);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    textTheme: text,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: c.line,
    appBarTheme: AppBarTheme(backgroundColor: c.bg, foregroundColor: c.text, elevation: 0, scrolledUnderElevation: 0),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      showDragHandle: true,
      dragHandleColor: c.line,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface2,
      contentTextStyle: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rm.btnRadius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rm.btnRadius), borderSide: BorderSide(color: c.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rm.btnRadius), borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rm.btnRadius), borderSide: BorderSide(color: c.primary, width: 1.5)),
      hintStyle: TextStyle(color: c.muted, fontSize: 17),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg.withValues(alpha: 0.96),
      indicatorColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.contains(WidgetState.selected) ? c.primaryInk : c.muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 26, color: s.contains(WidgetState.selected) ? c.primaryInk : c.muted)),
    ),
  );
}
