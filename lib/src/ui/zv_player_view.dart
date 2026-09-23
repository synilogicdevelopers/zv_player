import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/zv_player_controller.dart';
import '../state/zv_player_state.dart';
import '../capabilities/engine_capabilities.dart';
import '../platform/player_brightness.dart';
import 'zv_player_theme.dart';
import 'fullscreen_presenter.dart';
import '../widgets/zv_error_view.dart';
import '../widgets/zv_player_controls.dart';
import '../widgets/zv_player_gestures.dart';

/// The one player surface, whatever engine is behind it.
///
/// Renders the engine's own surface plus the shared chrome. There is no
/// engine branching here: which controls appear is decided by the capabilities
/// the active engine reports, so a web embed simply shows fewer of them.
class ZvPlayer extends StatefulWidget {
  const ZvPlayer({
    super.key,
    required this.controller,
    this.title = '',
    this.subtitleText = '',
    this.onBack,
    this.onCast,
    this.theme = ZvPlayerTheme.standard,
    this.pauseOnBackground = true,
    this.pauseWhenRouteObscured = true,
    this.autoEnterFullscreen = true,
    this.baseOrientations = const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ],
  });

  final ZvPlayerController controller;
  final String title;
  final String subtitleText;
  final VoidCallback? onBack;

  /// Supplied by the host only when casting is genuinely available for the
  /// current source; null hides the button.
  final VoidCallback? onCast;
  final ZvPlayerTheme theme;
  final bool pauseOnBackground;

  /// Stops playback the moment another page is pushed over the player's route.
  ///
  /// A pushed route does not dispose the page beneath it, so without this an
  /// autoplaying trailer keeps running - and keeps making sound - behind the
  /// screen the viewer moved on to. Popping back leaves the player paused
  /// where it was rather than resuming behind the viewer's back.
  ///
  /// Only full page pushes count. A bottom sheet, dialog or any other
  /// non-opaque overlay (the player's own settings sheet included) leaves
  /// playback alone, and a player already in Picture in Picture is exempt:
  /// a floating window is meant to outlive its page.
  final bool pauseWhenRouteObscured;

  /// Opens straight into landscape theater presentation, as an OTT player
  /// should. Presentation belongs to this layer, never to an engine, so it
  /// behaves identically for a YouTube embed and a native stream.
  final bool autoEnterFullscreen;

  /// Restored exactly when fullscreen exits, so the app never ends up
  /// rotatable everywhere after a video has been watched.
  final List<DeviceOrientation> baseOrientations;

  @override
  State<ZvPlayer> createState() => _ZvPlayerState();
}

class _ZvPlayerState extends State<ZvPlayer> with WidgetsBindingObserver {
  bool _controlsVisible = true;
  bool _locked = false;
  bool _wasPlaying = false;
  bool _togglingFullscreen = false;
  Timer? _hideTimer;

  late final FullscreenPresenter _fullscreen = FullscreenPresenter(
    baseOrientations: widget.baseOrientations,
  );

  final PlayerBrightness _brightness = PlayerBrightness();

  bool _autoEntered = false;

  /// True while the settings sheet is up. Auto-hide pauses, so the controls
  /// are still there when the sheet is dismissed.
  bool _settingsOpen = false;

  /// Null until the platform answers, which is also how the brightness row
  /// stays hidden on a platform that cannot change it.
  double? _brightnessValue;

  /// The route this player sits on, watched so playback can stop when another
  /// page covers it.
  ModalRoute<dynamic>? _route;

  /// True while a pushed page covers this one. Kept as state, not read on
  /// demand, because an engine that finishes initialising *after* the push
  /// would otherwise start playing behind the new screen.
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onPlaybackChanged);
    _scheduleHide();
    if (widget.autoEnterFullscreen) {
      // Issued here rather than after the first frame so the rotation starts
      // as the route does, avoiding a visible portrait-then-landscape flip.
      // Presentation never waits on the engine, so a slow or failing load
      // cannot leave the screen half-presented.
      unawaited(_enterFullscreenOnEntry());
    }
    unawaited(_readBrightness());
  }

  /// Runs once per player. The presenter is itself idempotent, and this flag
  /// keeps a rebuild from re-issuing orientation calls.
  Future<void> _enterFullscreenOnEntry() async {
    if (_autoEntered) return;
    _autoEntered = true;
    final bool entered = await _fullscreen.enter();
    if (entered && mounted) widget.controller.setFullscreen(true);
  }

  Future<void> _readBrightness() async {
    final double? value = await _brightness.read();
    if (!mounted || value == null) return;
    setState(() => _brightnessValue = value);
  }

  Future<void> _setBrightness(double value) async {
    final bool applied = await _brightness.set(value);
    if (!mounted || !applied) return;
    setState(() => _brightnessValue = value);
  }

  /// Whether this route is still the one on top is the signal used to detect
  /// that the viewer has moved on.
  ///
  /// Reading it through [ModalRoute.of] subscribes this element to the route's
  /// status, so Flutter calls this again the moment a push or pop flips it.
  /// A route's transition animation would be a more precise signal but is not
  /// a reliable one: whether it runs at all depends on the navigator's route
  /// types (GetX, for one, drives it only for Cupertino parallax), and the
  /// player cannot know what stack it was dropped into.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.pauseWhenRouteObscured) return;
    _route = ModalRoute.of(context);
    final ModalRoute<dynamic>? route = _route;
    // No route at all (a bare widget test, an overlay) means nothing can
    // cover this player, so there is nothing to watch for.
    _setObscured(route != null && !route.isCurrent);
  }

  void _detachRoute() => _route = null;

  void _setObscured(bool obscured) {
    if (_obscured == obscured) return;
    _obscured = obscured;
    if (obscured) _stopForObscuredRoute();
  }

  /// Pausing the controller also pauses the engine behind it - the Media3
  /// session, the AVPlayer, or the YouTube web view - so no audio survives
  /// the push.
  void _stopForObscuredRoute() {
    if (widget.controller.isDisposed) return;
    // A floating PiP window is exactly the case where playback *should*
    // outlive the page it came from.
    if (widget.controller.value.isPip) return;
    // The player's own settings sheet sits on top of this route as well, and
    // changing quality is not leaving the video.
    if (_settingsOpen) return;
    unawaited(widget.controller.pause());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _detachRoute();
    widget.controller.removeListener(_onPlaybackChanged);
    WidgetsBinding.instance.removeObserver(this);
    _fullscreen.restoreSynchronously();
    // Brightness always goes back to the system when the player closes.
    unawaited(_brightness.restore());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState != AppLifecycleState.paused) return;
    // Backgrounding hands brightness back too; the player must not dim a
    // device the viewer has moved on from.
    unawaited(_brightness.restore());
    final ZvPlayerState state = widget.controller.value;
    if (widget.pauseOnBackground && !state.isPip) {
      unawaited(widget.controller.pause());
    }
  }

  void _onPlaybackChanged() {
    final playing = widget.controller.value.isPlaying;
    // An open() that was still loading when the page was covered reaches
    // `playing` only now. Autoplay must not win a race against the viewer
    // having already left.
    if (playing && _obscured) {
      _stopForObscuredRoute();
      return;
    }
    if (!mounted || playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (playing) {
      _scheduleHide();
    } else if (!_locked && !_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.theme.autoHideDelay, () {
      if (!mounted || _settingsOpen) return;
      // Paused playback keeps its chrome: a still frame with no controls
      // looks broken rather than immersive.
      if (widget.controller.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Wraps the settings sheet so auto-hide is suspended for its lifetime.
  Future<void> _withSettingsOpen(Future<void> Function() show) async {
    _settingsOpen = true;
    _hideTimer?.cancel();
    try {
      await show();
    } finally {
      _settingsOpen = false;
      if (mounted) _showControls();
    }
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    if (_togglingFullscreen) return;
    _togglingFullscreen = true;
    try {
      if (widget.controller.value.isFullscreen) {
        await exitFullscreen();
      } else {
        final bool entered = await _fullscreen.enter();
        if (entered && mounted) widget.controller.setFullscreen(true);
      }
      _showControls();
    } finally {
      _togglingFullscreen = false;
    }
  }

  /// Leaves fullscreen and restores the app's orientation baseline.
  Future<void> exitFullscreen() async {
    final bool exited = await _fullscreen.exit();
    if (exited && mounted) widget.controller.setFullscreen(false);
  }

  Widget _unlock() => SafeArea(
        child: Align(
            alignment: Alignment.centerRight,
            child: IconButton.filledTonal(
              tooltip: 'Unlock player',
              icon: const Icon(Icons.lock_rounded),
              onPressed: () => setState(() {
                _locked = false;
                _controlsVisible = true;
              }),
            )),
      );

  Widget _controls(ZvPlayerState state, EngineCapabilities capabilities) =>
      ZvPlayerControls(
        sink: widget.controller,
        capabilities: capabilities,
        state: state,
        visible: _controlsVisible && !state.hasError,
        onInteraction: _showControls,
        onBack: widget.onBack,
        title: widget.title,
        subtitleText: widget.subtitleText,
        onLock: () => setState(() {
          _locked = true;
          _controlsVisible = false;
        }),
        onSetBrightness: _brightnessValue == null ? null : _setBrightness,
        brightness: _brightnessValue,
        onSetVideoFit: capabilities.canChangeVideoFit
            ? widget.controller.setVideoFit
            : null,
        onSettingsSession: _withSettingsOpen,
        onCast: widget.onCast,
        onToggleFullscreen:
            capabilities.supportsFullscreen ? _toggleFullscreen : null,
        onEnterPip: capabilities.supportsPictureInPicture
            ? () => widget.controller.enterPictureInPicture()
            : null,
      );

  Widget _connectionStatus() {
    final controller = widget.controller;
    final String? message = controller.isOffline
        ? 'You’re offline. Playback will reconnect when you’re online.'
        : controller.isRecovering
            ? 'Reconnecting…'
            : controller.recoveryFailed
                ? 'Could not reconnect. Tap Retry.'
                : null;
    if (message == null) return const SizedBox.shrink();
    return Material(
        color: const Color(0xFF232323),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: const TextStyle(color: Colors.white, fontSize: 12))),
            if (controller.recoveryFailed && !_locked)
              TextButton(
                  onPressed: controller.retry, child: const Text('Retry')),
          ]),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return ZvPlayerThemeScope(
      theme: widget.theme,
      child: ValueListenableBuilder<ZvPlayerState>(
        valueListenable: widget.controller,
        builder: (BuildContext context, ZvPlayerState state, _) {
          final capabilities = widget.controller.capabilities;
          final Widget surface =
              widget.controller.engine?.buildSurface(context) ??
                  // No engine: still starting, or nothing can play this source
                  // - in which case the error view says so over plain black.
                  (state.hasError
                      ? const SizedBox.expand()
                      : const Center(child: CircularProgressIndicator()));
          return PopScope(
            canPop: !state.isFullscreen,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (!didPop) unawaited(exitFullscreen());
            },
            child: ColoredBox(
              color: widget.theme.background,
              child: DefaultTextStyle.merge(
                style: ZvPlayerTheme.textStyle,
                child: Builder(builder: (context) {
                  return Stack(fit: StackFit.expand, children: [
                    surface,
                    if (!state.isPip && !_locked) ...[
                      ZvPlayerGestureLayer(
                        onTap: _toggleControls,
                        seekStep: widget.theme.seekStep,
                        enabled: capabilities.canSeek && state.canSeek,
                        onSeek: (side) {
                          widget.controller.seekBy(side == SeekSide.forward
                              ? widget.theme.seekStep
                              : -widget.theme.seekStep);
                          _showControls();
                        },
                      ),
                      _controls(state, capabilities),
                    ],
                    if (_locked) ...[
                      const Positioned.fill(
                          child: AbsorbPointer(
                              child: ColoredBox(color: Colors.transparent))),
                      _unlock(),
                    ],
                    if (!_locked &&
                        state.hasError &&
                        state.error != null &&
                        !widget.controller.isOffline &&
                        !widget.controller.isRecovering)
                      ZvErrorView(
                          error: state.error!,
                          onRetry: widget.controller.retry,
                          onBack: widget.onBack),
                    Align(
                        alignment: Alignment.topCenter,
                        child: SafeArea(child: _connectionStatus())),
                  ]);
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}
