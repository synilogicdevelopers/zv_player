import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ui/zv_player_theme.dart';

/// The transport scrubber: played, buffered and remaining across the **whole**
/// duration.
///
/// Two things this gets right that are easy to get wrong:
///
/// 1. **The track is always full width.** An earlier version put the track in a
///    `Center` with no width, so it shrink-wrapped its `FractionallySizedBox`
///    children - the "remaining" track ended where playback had reached, and a
///    four-hour film looked like a bar that stopped at the two-hour mark.
/// 2. **Dragging is relative.** Grabbing the bar does not jump to the finger;
///    movement is applied as a delta from where the thumb already was, so a
///    small drag on a long film is a small, predictable change. Tapping still
///    jumps, because that is what a tap means.
class ZvProgressBar extends StatefulWidget {
  const ZvProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeekPreview,
    required this.onSeekCommit,
    this.enabled = true,
    this.showBuffered = true,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekCommit;
  final bool enabled;

  /// False when the engine reports position but not buffering, so the bar
  /// omits the buffered range instead of drawing a misleading empty one.
  final bool showBuffered;

  @override
  State<ZvProgressBar> createState() => _ZvProgressBarState();
}

class _ZvProgressBarState extends State<ZvProgressBar> {
  bool _dragging = false;
  double _dragFraction = 0;

  int get _totalMs => widget.duration.inMilliseconds;

  /// Played fraction, clamped. Zero when the duration is not known yet, so the
  /// bar renders as an empty full-width track rather than something arbitrary.
  double get _fraction {
    if (_dragging) return _dragFraction.clamp(0.0, 1.0);
    if (_totalMs <= 0) return 0;
    return (widget.position.inMilliseconds / _totalMs).clamp(0.0, 1.0);
  }

  /// Buffered fraction, clamped to at least the played position: a buffer
  /// behind the playhead is meaningless and looks like a glitch.
  double get _bufferedFraction {
    if (_totalMs <= 0) return 0;
    final double buffered =
        (widget.buffered.inMilliseconds / _totalMs).clamp(0.0, 1.0);
    return buffered < _fraction ? _fraction : buffered;
  }

  Duration _durationAt(double fraction) =>
      Duration(milliseconds: (_totalMs * fraction.clamp(0.0, 1.0)).round());

  void _startDrag() {
    if (_totalMs <= 0) return;
    // Read the played fraction *before* flipping the flag: once _dragging is
    // true, _fraction returns _dragFraction, which would restart from zero.
    final double startFraction = _fraction;
    setState(() {
      _dragging = true;
      _dragFraction = startFraction;
    });
  }

  void _updateDrag(double deltaPixels, double width) {
    if (!_dragging || width <= 0) return;
    setState(() {
      _dragFraction = (_dragFraction + deltaPixels / width).clamp(0.0, 1.0);
    });
    widget.onSeekPreview(_durationAt(_dragFraction));
  }

  void _endDrag() {
    if (!_dragging) return;
    final Duration target = _durationAt(_dragFraction);
    setState(() => _dragging = false);
    widget.onSeekCommit(target);
  }

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Count movement from the touch down, not from where the recogniser
          // wins the arena. The default discards the first ~18px of every
          // drag, which on a long film is a silently lost chunk of seek.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart:
              widget.enabled ? (DragStartDetails _) => _startDrag() : null,
          onHorizontalDragUpdate: widget.enabled
              ? (DragUpdateDetails d) => _updateDrag(d.delta.dx, width)
              : null,
          onHorizontalDragEnd:
              widget.enabled ? (DragEndDetails _) => _endDrag() : null,
          onHorizontalDragCancel: widget.enabled ? _endDrag : null,
          onTapUp: widget.enabled && _totalMs > 0
              ? (TapUpDetails d) {
                  final double fraction =
                      (d.localPosition.dx / width).clamp(0.0, 1.0);
                  widget.onSeekCommit(_durationAt(fraction));
                }
              : null,
          child: SizedBox(
            // A comfortable touch target around a deliberately slim track.
            height: 32,
            width: double.infinity,
            child: Center(
              child: SizedBox(
                // Full width, always: the track represents the whole duration
                // whatever has been played.
                width: double.infinity,
                height: 16,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    // Remaining: the full-length background.
                    _Track(
                      color: theme.trackInactive,
                      height: _dragging ? 6 : 3,
                      widthFactor: 1,
                    ),
                    if (widget.showBuffered)
                      _Track(
                        color: theme.trackBuffered,
                        height: _dragging ? 6 : 3,
                        widthFactor: _bufferedFraction,
                      ),
                    _Track(
                      color:
                          widget.enabled ? theme.accent : theme.trackBuffered,
                      height: _dragging ? 6 : 3,
                      widthFactor: _fraction,
                    ),
                    if (widget.enabled)
                      Positioned(
                        left: (width * _fraction) - (_dragging ? 9 : 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          width: _dragging ? 18 : 12,
                          height: _dragging ? 18 : 12,
                          decoration: BoxDecoration(
                            color: theme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One horizontal band of the scrubber, laid out against the full width.
class _Track extends StatelessWidget {
  const _Track({
    required this.color,
    required this.height,
    required this.widthFactor,
  });

  final Color color;
  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor.clamp(0.0, 1.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
