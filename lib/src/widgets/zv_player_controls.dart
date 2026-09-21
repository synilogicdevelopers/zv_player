import 'package:flutter/material.dart';

import '../services/player_command_sink.dart';
import '../state/zv_player_state.dart';
import '../capabilities/engine_capabilities.dart';
import '../ui/zv_player_theme.dart';
import 'zv_progress_bar.dart';
import 'zv_settings_sheet.dart';

/// The transport chrome for a player whose surface Flutter may draw over.
///
/// Layout:
///
/// - top: back, title / metadata, then cast, mini player, captions, settings
/// - left: brightness, where the platform supports it
/// - centre: back 10s, one play/pause, forward 10s
/// - bottom: elapsed, full-width timeline, duration, fullscreen
/// - secondary row: lock, episodes, speed, audio & subtitles, next
///
/// Every button is opt-in: it appears only when the host supplies a handler or
/// the engine reports the capability *and* the media has something to choose.
/// Stays interactive while buffering - a viewer who wants to seek out of a
/// stall should not have to wait for the stall to end.
class ZvPlayerControls extends StatelessWidget {
  const ZvPlayerControls({
    super.key,
    required this.sink,
    required this.capabilities,
    required this.state,
    required this.visible,
    required this.onInteraction,
    this.onBack,
    this.onToggleFullscreen,
    this.onEnterPip,
    this.onToggleMiniPlayer,
    this.onCast,
    this.title = '',
    this.subtitleText = '',
    this.onSetBrightness,
    this.brightness,
    this.onLock,
    this.onEpisodes,
    this.onNext,
    this.onSettingsSession,
    this.onSetVideoFit,
  });

  /// Receives commands. Either controller satisfies this.
  final PlayerCommandSink sink;

  /// What the active engine can honour. Controls it cannot honour are hidden
  /// rather than shown and ignored.
  final EngineCapabilities capabilities;
  final ZvPlayerState state;
  final bool visible;

  /// Called on any touch, to restart the auto-hide countdown.
  final VoidCallback onInteraction;
  final VoidCallback? onBack;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onEnterPip;
  final VoidCallback? onToggleMiniPlayer;
  final VoidCallback? onCast;
  final String title;
  final String subtitleText;

  /// Null hides the brightness slider (and the sheet's brightness row).
  final ValueChanged<double>? onSetBrightness;
  final double? brightness;
  final VoidCallback? onLock;

  /// Supplied only by a host that has an episode list / a next item.
  final VoidCallback? onEpisodes;
  final VoidCallback? onNext;

  /// Lets the host suspend auto-hide for as long as the sheet is open.
  final Future<void> Function(Future<void> Function())? onSettingsSession;

  /// Supplied only when the engine can crop without distorting.
  final ValueChanged<VideoFitMode>? onSetVideoFit;

  bool get _hasSubtitles =>
      capabilities.canSelectSubtitle && state.tracks.hasSubtitles;

  bool get _hasAudioChoice =>
      capabilities.canSelectAudioTrack && state.tracks.hasAudioChoice;

  bool get _hasSpeed =>
      capabilities.canSetSpeed && capabilities.speeds.length > 1;

  void _openSheet(BuildContext context, {SettingsPanel? panel}) {
    onInteraction();
    Future<void> open() => ZvSettingsSheet.show(
          context,
          sink,
          state,
          capabilities,
          initialPanel: panel,
          onSetBrightness: onSetBrightness,
          brightness: brightness,
          onSetVideoFit: panel == null ? onSetVideoFit : null,
        );
    if (onSettingsSession != null) {
      onSettingsSession!(open);
    } else {
      open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);

    final List<Widget> secondary = <Widget>[
      if (onLock != null)
        _ActionChip(
          icon: Icons.lock_outline_rounded,
          label: 'Lock',
          tooltip: 'Lock player',
          onPressed: onLock!,
          theme: theme,
        ),
      if (onEpisodes != null)
        _ActionChip(
          icon: Icons.format_list_bulleted_rounded,
          label: 'Episodes',
          tooltip: 'Episodes',
          onPressed: () {
            onInteraction();
            onEpisodes!();
          },
          theme: theme,
        ),
      if (_hasSpeed)
        _ActionChip(
          icon: Icons.speed_rounded,
          label: 'Speed (${_speedLabel(state.speed)})',
          tooltip: 'Playback speed',
          onPressed: () => _openSheet(context, panel: SettingsPanel.speed),
          theme: theme,
        ),
      if (_hasSubtitles || _hasAudioChoice)
        _ActionChip(
          icon: Icons.subtitles_outlined,
          label: 'Audio & Subtitles',
          tooltip: 'Audio & Subtitles',
          onPressed: () => _openSheet(context,
              panel: _hasSubtitles
                  ? SettingsPanel.captions
                  : SettingsPanel.audioTrack),
          theme: theme,
        ),
      if (onNext != null)
        _ActionChip(
          icon: Icons.skip_next_rounded,
          label: 'Next',
          tooltip: 'Next',
          onPressed: () {
            onInteraction();
            onNext!();
          },
          theme: theme,
        ),
    ];

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: theme.controlsFade,
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            IgnorePointer(child: _Scrim(theme: theme)),
            SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // A small inline player keeps the essentials only; the side
                  // slider and the secondary row need a real stage.
                  final bool roomy = constraints.maxHeight >= 260;
                  final bool showBrightness =
                      roomy && onSetBrightness != null && brightness != null;
                  return Column(
                    children: <Widget>[
                      _TopBar(
                        theme: theme,
                        title: title,
                        subtitleText: subtitleText,
                        state: state,
                        onBack: onBack,
                        onCast: onCast,
                        onToggleMiniPlayer: onToggleMiniPlayer,
                        onEnterPip: onEnterPip,
                        onCaptions: _hasSubtitles
                            ? () => _openSheet(context,
                                panel: SettingsPanel.captions)
                            : null,
                        onSettings: () => _openSheet(context),
                      ),
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: showBrightness ? 48 : 0,
                              child: showBrightness
                                  ? _BrightnessSlider(
                                      theme: theme,
                                      value: brightness!,
                                      onChanged: (double value) {
                                        onInteraction();
                                        onSetBrightness!(value);
                                      },
                                    )
                                  : null,
                            ),
                            Expanded(
                              child: _CentreTransport(
                                theme: theme,
                                state: state,
                                sink: sink,
                                capabilities: capabilities,
                                onInteraction: onInteraction,
                              ),
                            ),
                            // Mirrors the slider so the transport stays centred.
                            SizedBox(width: showBrightness ? 48 : 0),
                          ],
                        ),
                      ),
                      _BottomBar(
                        theme: theme,
                        state: state,
                        sink: sink,
                        capabilities: capabilities,
                        onInteraction: onInteraction,
                        onToggleFullscreen: onToggleFullscreen,
                      ),
                      if (roomy && secondary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          // Scales down rather than overflowing on a narrow
                          // portrait stage.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                for (final Widget chip in secondary)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: chip,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _speedLabel(double speed) {
  final String value = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '${value}x';
}

/// Top and bottom gradients so white glyphs stay legible over bright frames.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.theme});

  final ZvPlayerTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const <double>[0, 0.3, 0.62, 1],
          colors: <Color>[
            theme.scrimTop,
            Colors.transparent,
            Colors.transparent,
            theme.scrimBottom,
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.theme,
    required this.title,
    required this.subtitleText,
    required this.state,
    required this.onSettings,
    this.onBack,
    this.onCast,
    this.onToggleMiniPlayer,
    this.onEnterPip,
    this.onCaptions,
  });

  final ZvPlayerTheme theme;
  final String title;
  final String subtitleText;
  final ZvPlayerState state;
  final VoidCallback onSettings;
  final VoidCallback? onBack;
  final VoidCallback? onCast;
  final VoidCallback? onToggleMiniPlayer;
  final VoidCallback? onEnterPip;
  final VoidCallback? onCaptions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: <Widget>[
          if (onBack != null)
            _IconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'Back',
              onPressed: onBack!,
              theme: theme,
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: onBack == null ? 12 : 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (subtitleText.isNotEmpty)
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (state.isLive) _LiveBadge(theme: theme),
          if (onCast != null)
            _IconButton(
              icon: state.isCasting
                  ? Icons.cast_connected_rounded
                  : Icons.cast_rounded,
              tooltip: 'Cast',
              onPressed: onCast!,
              theme: theme,
            ),
          if (onToggleMiniPlayer != null)
            _IconButton(
              icon: Icons.picture_in_picture_alt_outlined,
              tooltip: 'Mini player',
              onPressed: onToggleMiniPlayer!,
              theme: theme,
            ),
          if (onEnterPip != null)
            _IconButton(
              icon: Icons.picture_in_picture_alt_outlined,
              tooltip: 'Picture in picture',
              onPressed: onEnterPip!,
              theme: theme,
            ),
          if (onCaptions != null)
            _IconButton(
              icon: state.tracks.selectedSubtitle != null
                  ? Icons.closed_caption_rounded
                  : Icons.closed_caption_off_outlined,
              tooltip: 'Captions',
              onPressed: onCaptions!,
              theme: theme,
            ),
          _IconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: onSettings,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.theme});

  final ZvPlayerTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Vertical brightness track on the left edge, as in the reference.
class _BrightnessSlider extends StatelessWidget {
  const _BrightnessSlider({
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  final ZvPlayerTheme theme;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.wb_sunny_outlined, color: theme.onSurface, size: 18),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: Semantics(
              label: 'Brightness',
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: theme.onSurface,
                    inactiveTrackColor: theme.trackInactive,
                    thumbColor: theme.onSurface,
                    overlayColor: theme.onSurface.withValues(alpha: 0.12),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: value.clamp(0.0, 1.0),
                    // Thumb drags only: a stray tap near the left edge (say, a
                    // double-tap-to-rewind) must never jump the brightness.
                    allowedInteraction: SliderInteraction.slideThumb,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
        ),
        Icon(Icons.brightness_low_rounded,
            color: theme.onSurfaceMuted, size: 16),
      ],
    );
  }
}

class _CentreTransport extends StatelessWidget {
  const _CentreTransport({
    required this.theme,
    required this.state,
    required this.sink,
    required this.capabilities,
    required this.onInteraction,
  });

  final ZvPlayerTheme theme;
  final ZvPlayerState state;
  final PlayerCommandSink sink;
  final EngineCapabilities capabilities;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    // While buffering the spinner replaces the play glyph, but seek stays live.
    final bool showSpinner =
        state.isBuffering || state.status == PlayerStatus.loading;

    // Scales down rather than overflowing on a narrow stage (portrait, or
    // mid-rotation while the new constraints settle).
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (capabilities.canSeek)
            _IconButton(
              icon: Icons.replay_10_rounded,
              tooltip: 'Back 10 seconds',
              size: 36,
              onPressed: state.canSeek
                  ? () {
                      onInteraction();
                      sink.seekBy(-theme.seekStep);
                    }
                  : null,
              theme: theme,
            ),
          const SizedBox(width: 40),
          if (capabilities.canPlayPause)
            SizedBox(
              width: 72,
              height: 72,
              child: showSpinner
                  ? Center(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(theme.accent),
                        ),
                      ),
                    )
                  : _PlayPauseButton(
                      theme: theme,
                      state: state,
                      onPressed: () {
                        onInteraction();
                        if (state.status == PlayerStatus.completed) {
                          sink.seekTo(Duration.zero);
                          sink.play();
                        } else {
                          sink.togglePlayPause();
                        }
                      },
                    ),
            ),
          const SizedBox(width: 40),
          if (capabilities.canSeek)
            _IconButton(
              icon: Icons.forward_10_rounded,
              tooltip: 'Forward 10 seconds',
              size: 36,
              onPressed: state.canSeek
                  ? () {
                      onInteraction();
                      sink.seekBy(theme.seekStep);
                    }
                  : null,
              theme: theme,
            ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.theme,
    required this.state,
    required this.onPressed,
  });

  final ZvPlayerTheme theme;
  final ZvPlayerState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final IconData icon = state.status == PlayerStatus.completed
        ? Icons.replay_rounded
        : (state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded);

    // One glyph in a thin ring - the only play control on screen.
    return Semantics(
      button: true,
      label: state.isPlaying ? 'Pause' : 'Play',
      child: InkResponse(
        onTap: onPressed,
        radius: 38,
        containedInkWell: false,
        customBorder: const CircleBorder(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: theme.onSurface.withValues(alpha: 0.85), width: 2),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                icon,
                key: ValueKey<IconData>(icon),
                color: theme.onSurface,
                size: 44,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.theme,
    required this.state,
    required this.sink,
    required this.capabilities,
    required this.onInteraction,
    this.onToggleFullscreen,
  });

  final ZvPlayerTheme theme;
  final ZvPlayerState state;
  final PlayerCommandSink sink;
  final EngineCapabilities capabilities;
  final VoidCallback onInteraction;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    // Elapsed, the full-width track, then the total running time - so the
    // whole duration is legible without doing arithmetic.
    final TextStyle timeStyle = TextStyle(
      color: theme.onSurface,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    // Reserve the total-duration label width on both sides. Crossing a minute
    // or hour boundary (or bolding a drag preview) must not resize the track.
    final labelPainter = TextPainter(
      text: TextSpan(
          text: state.isLive ? 'Live' : formatPlayerDuration(state.duration),
          style: DefaultTextStyle.of(context)
              .style
              .merge(timeStyle.copyWith(fontWeight: FontWeight.w600))),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double timeWidth = labelPainter.width.ceilToDouble() + 2;
    labelPainter.dispose();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
              width: timeWidth,
              child: Text(
                state.isLive ? 'Live' : formatPlayerDuration(state.position),
                textAlign: TextAlign.right,
                style: timeStyle.copyWith(
                  // The elapsed time is emphasised while scrubbing, so the viewer
                  // can read the target position as they drag.
                  fontWeight:
                      state.isSeeking ? FontWeight.w600 : FontWeight.w500,
                ),
              )),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ZvProgressBar(
                position: state.position,
                duration: state.duration,
                buffered: state.bufferedPosition,
                enabled: state.canSeek && capabilities.canSeek,
                showBuffered: capabilities.reportsBufferedPosition,
                onSeekPreview: (Duration position) {
                  onInteraction();
                  sink.previewSeek(position);
                },
                onSeekCommit: (Duration position) {
                  onInteraction();
                  sink.seekTo(position);
                },
              ),
            ),
          ),
          if (!state.isLive)
            SizedBox(
                width: timeWidth,
                child: Text(formatPlayerDuration(state.duration),
                    style: timeStyle)),
          if (onToggleFullscreen != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _IconButton(
                icon: state.isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                tooltip: state.isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                size: 26,
                onPressed: () {
                  onInteraction();
                  onToggleFullscreen!();
                },
                theme: theme,
              ),
            ),
        ],
      ),
    );
  }
}

/// Icon over a label, as in the reference's secondary control row.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final ZvPlayerTheme theme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: theme.onSurface, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: theme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
    this.size = 24,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final ZvPlayerTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: size,
      // Keeps a 44pt touch target without drawing a large button.
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      splashRadius: 22,
      color: theme.onSurface,
      disabledColor: theme.onSurfaceMuted.withValues(alpha: 0.4),
      icon: Icon(icon),
    );
  }
}
