// App-wide UI state that features may read without importing the app/router.
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When true the whole app uses the dark, high-contrast Gym mode (set while a workout runs).
final gymModeProvider = NotifierProvider<GymMode, bool>(GymMode.new);

class GymMode extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool on) => state = on;
}
