// The log bar pinned above the tab bar: Hinglish text in, review tray out. Mic, camera and barcode
// are visible but marked "coming soon" (no network parsing yet).
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../../ui/theme.dart';
import '../../ui/widgets.dart';

class LogBar extends StatefulWidget {
  const LogBar({super.key, required this.onSubmit, this.goTos = const []});
  final ValueChanged<String> onSubmit;

  /// Time-of-day go-tos ("poha + chai"), shown while the field has focus.
  final List<String> goTos;

  /// Height of the bar without go-to chips (for scroll padding).
  static const double height = 72;

  @override
  State<LogBar> createState() => _LogBarState();
}

class _LogBarState extends State<LogBar> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit([String? text]) {
    final t = (text ?? _ctl.text).trim();
    if (t.isEmpty) return;
    _ctl.clear();
    _focus.unfocus();
    widget.onSubmit(t);
  }

  void _soon(String what) => showRfToast(context, '$what logging is coming soon. Type it for now: Hinglish works.');

  @override
  Widget build(BuildContext context) {
    final c = context.rf;
    final typing = _ctl.text.trim().isNotEmpty;
    Widget soon(IconData icon, String what) => Semantics(
          button: true,
          label: '$what logging, coming soon',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _soon(what),
            child: SizedBox(
              width: 40,
              height: Rf.tap,
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, size: 22, color: c.muted.withValues(alpha: 0.7)),
                Positioned(
                  bottom: 6,
                  child: Text('soon', style: RfType.caption.copyWith(fontSize: 9, color: c.muted, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(color: c.bg.withValues(alpha: 0.86), border: Border(top: BorderSide(color: c.line, width: 0.5))),
          padding: const EdgeInsets.fromLTRB(Rf.gutter, 10, Rf.gutter, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_focus.hasFocus && widget.goTos.isNotEmpty && !typing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final g in widget.goTos) ...[
                      RfChip(label: g, icon: CupertinoIcons.arrow_counterclockwise, onTap: () => _submit(g)),
                      const SizedBox(width: 8),
                    ],
                  ]),
                ),
              ),
            Row(children: [
              Expanded(
                child: Semantics(
                  label: 'Log food',
                  textField: true,
                  child: TextField(
                    key: const ValueKey('eat-log-input'),
                    controller: _ctl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: RfType.body.copyWith(color: c.text),
                    decoration: InputDecoration(
                      hintText: 'e.g. 2 roti aur dal, thoda ghee',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      fillColor: c.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rf.chipRadius), borderSide: BorderSide(color: c.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rf.chipRadius), borderSide: BorderSide(color: c.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rf.chipRadius), borderSide: BorderSide(color: c.accent, width: 1.4)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (typing)
                Semantics(
                  button: true,
                  label: 'Review food',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: _submit,
                    child: Container(
                      width: Rf.tap,
                      height: Rf.tap,
                      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.arrow_up, color: c.onAccent, size: 22),
                    ),
                  ),
                )
              else ...[
                soon(CupertinoIcons.mic, 'Voice'),
                soon(CupertinoIcons.camera, 'Photo'),
                soon(CupertinoIcons.barcode_viewfinder, 'Barcode'),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
