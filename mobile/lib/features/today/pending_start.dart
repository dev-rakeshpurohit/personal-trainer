// One-shot hand-off: onboarding's "Start Workout 1 now" sets a program day id, then navigates to
// Today, which starts the workout once it is on screen (so the logger opens above the tab shell).
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pendingStartProvider = NotifierProvider<PendingStart, String?>(PendingStart.new);

class PendingStart extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? dayId) => state = dayId;

  /// Returns the pending day id and clears it.
  String? take() {
    final v = state;
    state = null;
    return v;
  }
}
