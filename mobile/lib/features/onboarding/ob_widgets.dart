// Building blocks of the onboarding screens (kept in the feature folder per UI-CONVENTIONS).
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Asks the OS for notification permission. Must be called from a button tap (never on load).
/// Tests override this provider.
final notificationPermissionProvider = Provider<Future<bool> Function()>((ref) => requestNotificationPermission);

Future<bool> requestNotificationPermission() async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    final ios = plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
  } catch (_) {
    // No plugin on this platform: treat as "not granted".
  }
  return false;
}

/// Title + optional subtitle at the top of a question.
class StepHeading extends StatelessWidget {
  const StepHeading(this.title, {super.key, this.sub});
  final String title;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(title, style: RfType.title.copyWith(color: c.text))),
        if (sub != null) ...[const SizedBox(height: 8), Text(sub!, style: RfType.body.copyWith(color: c.muted))],
      ]),
    );
  }
}

/// Large single- or multi-select card with a check circle.
class OptionCard extends StatelessWidget {
  const OptionCard({super.key, required this.title, this.sub, required this.selected, required this.onTap, this.icon, this.multi = false});
  final String title;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool multi;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        label: sub == null || sub!.isEmpty ? title : '$title. $sub',
        excludeSemantics: true,
        child: Pressable(
          onTap: () {
            Haptics.tick();
            onTap();
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: context.reduceMotion ? 0 : 160),
            constraints: const BoxConstraints(minHeight: Rf.gymTap + 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? c.accent.withValues(alpha: 0.12) : c.surface,
              borderRadius: BorderRadius.circular(Rf.cardRadius),
              border: Border.all(color: selected ? c.accent : c.line, width: selected ? 1.6 : 0.8),
            ),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 26, color: selected ? c.accentInk : c.muted), const SizedBox(width: 14)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: RfType.bodyStrong.copyWith(color: c.text)),
                  if (sub != null && sub!.isNotEmpty) ...[const SizedBox(height: 2), Text(sub!, style: RfType.callout.copyWith(color: c.muted))],
                ]),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? (multi ? CupertinoIcons.checkmark_square_fill : CupertinoIcons.checkmark_circle_fill)
                    : (multi ? CupertinoIcons.square : CupertinoIcons.circle),
                size: 24,
                color: selected ? c.accentInk : c.line,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A labelled group (e.g. "Session length") with chips below.
class ChipGroup extends StatelessWidget {
  const ChipGroup({super.key, required this.label, required this.children, this.hint});
  final String label;
  final String? hint;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: RfType.overline.copyWith(color: c.muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: children),
        if (hint != null) ...[const SizedBox(height: 8), Text(hint!, style: RfType.caption.copyWith(color: c.muted))],
      ]),
    );
  }
}

/// One measurement with a compact stepper and a one-line explanation.
class MeasureRow extends StatelessWidget {
  const MeasureRow({
    super.key,
    required this.label,
    required this.why,
    required this.value,
    required this.onChanged,
    required this.step,
    required this.min,
    required this.max,
    required this.unit,
  });
  final String label;
  final String why;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RfCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: RfType.bodyStrong.copyWith(color: c.text)),
          Text(why, style: RfType.caption.copyWith(color: c.muted)),
          const SizedBox(height: 8),
          BigStepper(value: value, onChanged: onChanged, step: step, min: min, max: max, label: label, unit: unit, compact: true),
        ]),
      ),
    );
  }
}

/// A line that appears while the plan is built: a check plus genuine text.
class BuildLine extends StatelessWidget {
  const BuildLine(this.text, {super.key, this.done = true});
  final String text;
  final bool done;
  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(done ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 22, color: done ? c.done : c.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: RfType.body.copyWith(color: done ? c.text : c.muted))),
      ]),
    );
  }
}

/// Small coloured badge, e.g. "BETA".
class TagBadge extends StatelessWidget {
  const TagBadge(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = color ?? context.rf.caution;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: t.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(Rf.chipRadius)),
      child: Text(text, style: RfType.overline.copyWith(color: t, fontSize: 11)),
    );
  }
}
