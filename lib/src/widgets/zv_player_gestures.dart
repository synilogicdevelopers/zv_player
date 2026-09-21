import 'package:flutter/material.dart';

import '../ui/zv_player_theme.dart';

/// Which half of the surface a double tap landed on.
enum SeekSide { backward, forward }

/// Tap and double-tap handling over the video surface.
///
/// A single tap toggles the controls; a double tap on either half seeks. The
/// seek indicator is drawn here rather than in the controls layer so it still
/// appears when the controls are hidden.
class ZvPlayerGestureLayer extends StatefulWidget {
  const ZvPlayerGestureLayer({
    super.key,
    required this.onTap,
    required this.onSeek,
    required this.seekStep,
    this.enabled = true,
    this.onVerticalDragUpdate,
  });

  final VoidCallback onTap;
  final void Function(SeekSide side) onSeek;
  final Duration seekStep;
  final bool enabled;

  /// Hook for brightness/volume drags. Left unwired by default: a vertical
  /// gesture that fights the host app's scrolling is worse than none, and
  /// screen brightness needs a platform capability the player does not own yet.
  final void Function(DragUpdateDetails details, bool isLeftSide)?
      onVerticalDragUpdate;

  @override
  State<ZvPlayerGestureLayer> createState() => _ZvPlayerGestureLayerState();
}

class _ZvPlayerGestureLayerState extends State<ZvPlayerGestureLayer>
    with SingleTickerProviderStateMixin {
  SeekSide? _indicatorSide;
  int _accumulatedSeconds = 0;

  /// Created eagerly on purpose. As a lazy `late final` it would be built by
  /// the first read - which, if the viewer never double-tapped, is the read
  /// inside dispose(), and constructing a ticker against a deactivated element
  /// throws.
  late final AnimationController _indicatorController;

  @override
  void initState() {
    super.initState();
    _indicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  void _handleDoubleTap(SeekSide side) {
    if (!widget.enabled) return;
    widget.onSeek(side);
    setState(() {
      // Repeated taps on the same side accumulate, the way viewers expect.
      _accumulatedSeconds = _indicatorSide == side
          ? _accumulatedSeconds + widget.seekStep.inSeconds
          : widget.seekStep.inSeconds;
      _indicatorSide = side;
    });
    _indicatorController.forward(from: 0).then((_) {
      if (mounted && _indicatorController.status == AnimationStatus.completed) {
        setState(() {
          _indicatorSide = null;
          _accumulatedSeconds = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _half(SeekSide.backward)),
        Expanded(child: _half(SeekSide.forward)),
      ],
    );
  }

  Widget _half(SeekSide side) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: () => _handleDoubleTap(side),
      onVerticalDragUpdate: widget.onVerticalDragUpdate == null
          ? null
          : (DragUpdateDetails details) => widget.onVerticalDragUpdate!(
                details,
                side == SeekSide.backward,
              ),
      child: _indicatorSide == side
          ? _SeekIndicator(
              side: side,
              seconds: _accumulatedSeconds,
              animation: _indicatorController,
            )
          : const SizedBox.expand(),
    );
  }
}

class _SeekIndicator extends StatelessWidget {
  const _SeekIndicator({
    required this.side,
    required this.seconds,
    required this.animation,
  });

  final SeekSide side;
  final int seconds;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
    final bool forward = side == SeekSide.forward;

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        // Fade in fast, linger, fade out - no lingering chrome.
        final double opacity = animation.value < 0.25
            ? animation.value / 0.25
            : (1 - ((animation.value - 0.25) / 0.75)).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: forward ? Alignment.centerRight : Alignment.centerLeft,
                radius: 1.1,
                colors: <Color>[
                  Colors.white.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
          ),
        );
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: theme.onSurface,
              size: 34,
            ),
            const SizedBox(height: 6),
            Text(
              // Signed and unit-less, the way every OTT player labels it:
              // "+10" on the right, "-10" on the left, accumulating while the
              // taps keep coming.
              '${forward ? '+' : '-'}$seconds',
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
