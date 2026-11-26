// Tab shell: Today · Train · Eat · Progress · Coach (separated trailing slot).
// Translucent blurred bar now; the native iOS Liquid Glass bar replaces it in F8 (UX spec).
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/haptics.dart';
import '../ui/theme.dart';

class TabSpec {
  const TabSpec(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const kTabs = [
  TabSpec('Today', CupertinoIcons.sun_max, CupertinoIcons.sun_max_fill),
  TabSpec('Train', Icons.fitness_center_outlined, Icons.fitness_center),
  TabSpec('Eat', Icons.restaurant_outlined, Icons.restaurant),
  TabSpec('Progress', CupertinoIcons.chart_bar, CupertinoIcons.chart_bar_fill),
  TabSpec('Coach', Icons.auto_awesome_outlined, Icons.auto_awesome),
];

/// Height of the tab bar content (excluding the home-indicator inset). Screens pad by this.
const double kTabBarHeight = 62;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: _GlassTabBar(
        index: shell.currentIndex,
        onTap: (i) {
          Haptics.tick();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget item(int i, {bool coach = false}) {
      final t = kTabs[i];
      final on = i == index;
      final color = on ? (coach ? c.coach : c.accentInk) : c.muted;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          label: '${t.label} tab',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(on ? t.activeIcon : t.icon, size: 25, color: color),
              const SizedBox(height: 3),
              Text(t.label, style: RfType.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ]),
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: kTabBarHeight + bottom,
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: c.bg.withValues(alpha: 0.82),
            border: Border(top: BorderSide(color: c.line.withValues(alpha: 0.7), width: 0.5)),
          ),
          child: Row(children: [
            for (var i = 0; i < 4; i++) item(i),
            // Coach sits in a visually separated trailing slot.
            Container(width: 0.5, height: 30, color: c.line),
            item(4, coach: true),
          ]),
        ),
      ),
    );
  }
}
