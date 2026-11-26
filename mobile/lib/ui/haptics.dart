// Haptic language (UX spec): one function per event so feel stays consistent app-wide.
import 'dart:async';

import 'package:flutter/services.dart';

abstract final class Haptics {
  /// Stepper tick, picker change.
  static Future<void> tick() => HapticFeedback.selectionClick();

  /// A set marked done.
  static Future<void> setDone() => HapticFeedback.lightImpact();

  /// 10 seconds of rest left: two soft taps.
  static Future<void> restSoon() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.lightImpact();
  }

  /// Rest over: strong 3-pulse pattern (felt in a pocket).
  static Future<void> restOver() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      if (i < 2) await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  /// Personal record: success then a rising pattern.
  static Future<void> pr() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }

  /// A proposal approved / important confirmation.
  static Future<void> approve() => HapticFeedback.mediumImpact();
}
