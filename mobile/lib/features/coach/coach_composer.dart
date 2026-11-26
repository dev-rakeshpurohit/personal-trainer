// Coach composer: "life happened" context chips, mode (change / new plan), what to change
// (workout / diet), the text field (Hinglish welcome) and a voice button marked coming soon.
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../domain/ai_plan.dart';
import '../../ui/haptics.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Context chips (UX spec, Signature 3). [text] is what the chip adds to the request.
const kCoachChips = <({String label, String text, IconData icon, bool diet})>[
  (label: 'I only have 30 min', text: 'I only have 30 min per session this week.', icon: CupertinoIcons.timer, diet: false),
  (label: 'Knee hurts', text: 'My knee hurts — go easy on it.', icon: CupertinoIcons.bandage, diet: false),
  (label: 'Move legs to Saturday', text: 'Move legs to Saturday.', icon: CupertinoIcons.calendar, diet: false),
  (label: 'Travel next week', text: 'I’m travelling next week, hotel gym or dumbbells only.', icon: CupertinoIcons.airplane, diet: false),
  (label: 'Vrat on Thursday', text: 'I have a vrat (fast) on Thursday.', icon: CupertinoIcons.moon_stars, diet: true),
  (label: 'Make it harder', text: 'Make it harder — I’m ready for more.', icon: CupertinoIcons.flame, diet: false),
];

class CoachComposer extends StatelessWidget {
  const CoachComposer({
    super.key,
    required this.controller,
    required this.mode,
    required this.workout,
    required this.diet,
    required this.busy,
    required this.onMode,
    required this.onWorkout,
    required this.onDiet,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final CoachMode mode;
  final bool workout;
  final bool diet;
  final bool busy;
  final ValueChanged<CoachMode> onMode;
  final ValueChanged<bool> onWorkout;
  final ValueChanged<bool> onDiet;
  final VoidCallback onSend;
  final VoidCallback onStop;

  void _addChip(({String label, String text, IconData icon, bool diet}) chip) {
    final cur = controller.text.trim();
    if (cur.contains(chip.text)) return;
    controller.text = cur.isEmpty ? chip.text : '$cur ${chip.text}';
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    if (chip.diet && !diet) onDiet(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    return Container(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line, width: 0.5))),
      padding: const EdgeInsets.only(top: 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 4),
            itemCount: kCoachChips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final chip = kCoachChips[i];
              return RfChip(label: chip.label, icon: chip.icon, tone: c.coach, onTap: busy ? null : () => _addChip(chip));
            },
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Rf.gutter, vertical: 2),
            children: [
              RfChip(label: 'Change my plan', selected: mode == CoachMode.change, tone: c.coach, onTap: busy ? null : () => onMode(CoachMode.change)),
              const SizedBox(width: 6),
              RfChip(label: 'New plan', selected: mode == CoachMode.newPlan, tone: c.coach, onTap: busy ? null : () => onMode(CoachMode.newPlan)),
              Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), color: c.line),
              RfChip(
                label: 'Workout',
                icon: workout ? CupertinoIcons.checkmark_alt : Icons.fitness_center,
                selected: workout,
                tone: c.coach,
                onTap: busy || (workout && !diet) ? null : () => onWorkout(!workout),
              ),
              const SizedBox(width: 6),
              RfChip(
                label: 'Diet',
                icon: diet ? CupertinoIcons.checkmark_alt : Icons.restaurant,
                selected: diet,
                tone: c.coach,
                onTap: busy || (diet && !workout) ? null : () => onDiet(!diet),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Rf.gutter - 4, 6, Rf.gutter, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Semantics(
              button: true,
              label: 'Voice input, coming soon',
              excludeSemantics: true,
              child: Pressable(
                onTap: () {
                  Haptics.tick();
                  showRfToast(context, 'Voice input is coming soon. Type for now — Hinglish is fine.', icon: CupertinoIcons.mic);
                },
                child: SizedBox(
                  width: Rf.tap,
                  height: Rf.tap,
                  child: Stack(alignment: Alignment.center, children: [
                    Icon(CupertinoIcons.mic, color: c.muted),
                    Positioned(
                      right: 2,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(6)),
                        child: Text('Soon', style: RfType.caption.copyWith(fontSize: 9, color: c.muted, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                key: const Key('coach-input'),
                controller: controller,
                enabled: !busy,
                minLines: 1,
                maxLines: 4,
                maxLength: 1500,
                textCapitalization: TextCapitalization.sentences,
                style: RfType.body.copyWith(color: c.text),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: mode == CoachMode.newPlan ? 'Anything the new plan should know? (optional)' : 'What changed? e.g. “aaj sirf 30 min hai”',
                  hintStyle: RfType.callout.copyWith(color: c.muted),
                  filled: true,
                  fillColor: c.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.coach, width: 1.4)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, v, _) {
                final ready = busy || mode == CoachMode.newPlan || v.text.trim().isNotEmpty;
                return Semantics(
                  button: true,
                  enabled: ready,
                  label: busy ? 'Stop' : 'Send to coach',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: !ready ? null : (busy ? onStop : onSend),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: context.reduceMotion ? 0 : 150),
                      width: Rf.tap,
                      height: Rf.tap,
                      decoration: BoxDecoration(color: ready ? c.coach : c.surface2, shape: BoxShape.circle),
                      child: Icon(busy ? CupertinoIcons.stop_fill : CupertinoIcons.arrow_up, color: ready ? c.onAccent : c.muted, size: 22),
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
