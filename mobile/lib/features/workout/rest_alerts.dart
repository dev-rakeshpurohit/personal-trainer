// Rest-timer surfaces outside the app UI (local notification now; Live Activity / Android ongoing
// notification later) plus the screen-awake switch. Every surface reads the same stored end
// timestamp, so nothing here ticks. Tests override the providers with fakes.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

/// What a rest surface shows: the end timestamp is the single source of truth.
@immutable
class RestTimerInfo {
  const RestTimerInfo({required this.endsAt, required this.totalSec, required this.exerciseName, required this.nextLabel, required this.sessionStartedAt});
  final DateTime endsAt;
  final int totalSec;

  /// Exercise of the next set ("Bench press").
  final String exerciseName;

  /// "Set 3 · 80 kg × 8".
  final String nextLabel;
  final DateTime sessionStartedAt;
}

/// A place the rest countdown is mirrored: local notification today, a Live Activity later
/// (add an implementation and list it in [restSurfacesProvider]).
abstract interface class RestTimerSurface {
  /// Start or update the countdown (called again after −15 / +15).
  Future<void> show(RestTimerInfo info);

  /// Rest skipped, finished or the workout ended.
  Future<void> clear();
}

/// Permission for rest-over alerts. Asked only from a button tap, never at launch.
abstract interface class RestAlertPermission {
  Future<bool> granted();
  Future<bool> request();
}

/// Keeps the screen on while the logger is open.
abstract interface class ScreenAwake {
  Future<void> set(bool on);
}

/* ------------------------------------------------------------------ local notification */

/// Schedules one local notification at the rest end; re-scheduling replaces it.
class LocalNotificationRest implements RestTimerSurface, RestAlertPermission {
  LocalNotificationRest([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  static const _id = 4201;
  Future<bool>? _init;

  Future<bool> _ready() => _init ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              // Never prompt here: permission is requested from the "Alert me" button.
              iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            ),
          );
          return true;
        } catch (e) {
          debugPrint('Rest notifications unavailable: $e');
          return false;
        }
      }();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> granted() async {
    if (!await _ready()) return false;
    try {
      final ios = _ios;
      if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
      final android = _android;
      if (android != null) return await android.areNotificationsEnabled() ?? false;
    } catch (_) {}
    return false;
  }

  @override
  Future<bool> request() async {
    if (!await _ready()) return false;
    try {
      final ios = _ios;
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
      final android = _android;
      if (android != null) return await android.requestNotificationsPermission() ?? false;
    } catch (_) {}
    return false;
  }

  @override
  Future<void> show(RestTimerInfo info) async {
    if (!await granted()) return;
    if (!info.endsAt.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: _id,
        title: 'Rest over',
        body: 'Next: ${info.exerciseName} · ${info.nextLabel}',
        scheduledDate: tz.TZDateTime.from(info.endsAt.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true, interruptionLevel: InterruptionLevel.active),
          android: AndroidNotificationDetails('rest', 'Rest timer', channelDescription: 'Tells you when rest is over', importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Could not schedule rest alert: $e');
    }
  }

  @override
  Future<void> clear() async {
    if (!await _ready()) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}

class _Wakelock implements ScreenAwake {
  @override
  Future<void> set(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      debugPrint('Wakelock unavailable: $e');
    }
  }
}

/* ------------------------------------------------------------------ providers */

final _localNotificationRest = Provider<LocalNotificationRest>((ref) => LocalNotificationRest());

/// Every surface that mirrors the rest countdown. A Live Activity surface is added here later.
final restSurfacesProvider = Provider<List<RestTimerSurface>>((ref) => [ref.watch(_localNotificationRest)]);

final restAlertPermissionProvider = Provider<RestAlertPermission>((ref) => ref.watch(_localNotificationRest));

final screenAwakeProvider = Provider<ScreenAwake>((ref) => _Wakelock());

/// Fan-out helpers that never throw (the logger must keep working if a surface fails).
extension RestSurfaces on List<RestTimerSurface> {
  Future<void> showAll(RestTimerInfo info) => Future.wait(map((s) => s.show(info).catchError((Object _) {}))).then((_) {});
  Future<void> clearAll() => Future.wait(map((s) => s.clear().catchError((Object _) {}))).then((_) {});
}
