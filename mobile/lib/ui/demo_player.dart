// Animated 3D exercise demo (bundled animated WebP; © Gym visual, personal use) with
// fallbacks: free-exercise-db photo → icon. Respects Reduce Motion (still frame + play).
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';

import '../data/seed/seed_loader.dart';
import '../domain/models.dart';
import 'theme.dart';

class DemoPlayer extends StatefulWidget {
  const DemoPlayer({super.key, required this.exercise, this.height = 220, this.still = false, this.borderRadius = Rf.cardRadius});
  final Exercise? exercise;
  final double height;

  /// Force the still thumbnail (lists, off-screen pages).
  final bool still;
  final double borderRadius;

  @override
  State<DemoPlayer> createState() => _DemoPlayerState();
}

class _DemoPlayerState extends State<DemoPlayer> {
  bool? _playing;

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final reduce = context.reduceMotion;
    final playing = !widget.still && (_playing ?? !reduce);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget img;
    if (ex?.demoId != null) {
      img = Image.asset(
        playing ? SeedAssets.demoAnim(ex!.demoId!) : SeedAssets.demoThumb(ex!.demoId!),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheHeight: (widget.height * dpr).round(),
        errorBuilder: (_, _, _) => _fallback(context, ex),
      );
    } else {
      img = _fallback(context, ex);
    }
    return Semantics(
      label: ex == null ? 'Exercise demo' : '${ex.name} demonstration',
      image: true,
      child: GestureDetector(
        onTap: widget.still ? null : () => setState(() => _playing = !playing),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Container(
            height: widget.height,
            width: double.infinity,
            // The demos are drawn on white; keep a white card in both themes.
            color: Colors.white,
            child: Stack(fit: StackFit.expand, children: [
              img,
              if (!playing && !widget.still)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                    child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 24),
                  ),
                ),
              if (ex?.demoId != null && widget.height >= 120)
                const Positioned(
                  right: 8,
                  top: 6,
                  child: Text('© Gym visual', style: TextStyle(fontSize: 10, color: Color(0x66000000), fontWeight: FontWeight.w500)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context, Exercise? ex) {
    if (ex?.freeDbId != null) {
      return Image.asset(SeedAssets.photo(ex!.freeDbId!), fit: BoxFit.contain, errorBuilder: (_, _, _) => _icon(context));
    }
    return _icon(context);
  }

  Widget _icon(BuildContext context) => Container(
        color: context.rf.surface2,
        alignment: Alignment.center,
        child: Icon(Icons.fitness_center, size: 36, color: context.rf.muted),
      );
}

/// Square still thumbnail for lists.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({super.key, required this.exercise, this.size = 56});
  final Exercise? exercise;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: DemoPlayer(exercise: exercise, height: size, still: true, borderRadius: 12),
      );
}
