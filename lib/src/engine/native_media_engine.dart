import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../controller/zv_native_controller.dart';
import '../source/zv_media_source.dart';
import '../models/player_tracks.dart';
import '../state/zv_player_state.dart';
import '../platform/zv_native_view.dart';
import '../capabilities/device_capabilities.dart';
import '../capabilities/engine_capabilities.dart';
import 'playback_engine.dart';

/// The native media pipeline (Media3 / AVPlayer) behind the engine contract.
///
/// A thin adapter over the existing [ZvNativeController]: it owns no playback
/// logic of its own, so resume rules, retry policy and track handling continue
/// to live in one place and keep working exactly as before.
class NativeMediaEngine implements PlaybackEngine {
  NativeMediaEngine({ZvNativeController? controller})
      : _controller = controller ?? ZvNativeController();

  final ZvNativeController _controller;

  bool _initialized = false;
  bool _disposed = false;
  EngineCapabilities _capabilities = const EngineCapabilities.nativeMedia();

  /// Exposed so existing callers can keep using the controller directly during
  /// migration; the universal layer should talk to the engine instead.
  ZvNativeController get controller => _controller;

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.native;

  @override
  ValueListenable<ZvPlayerState> get state => _controller;

  @override
  EngineCapabilities get capabilities => _capabilities;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isDisposed => _disposed;

  /// What the native pipeline can do for [source].
  ///
  /// Selection is always possible; whether tracks *exist* is reported through
  /// the track lists. Adaptive sources additionally get a meaningful `Auto`.
  static EngineCapabilities capabilitiesFor(ZvMediaSource source) {
    const EngineCapabilities base = EngineCapabilities.nativeMedia();
    if (source.isAdaptive) return base;

    // A progressive file has no manifest: quality switching is only possible
    // when the backend supplied more than one URL for the same content.
    return base.copyWith(canSelectQuality: source.hasManualVariants);
  }

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) return;
    await _controller.initialise();
    _initialized = true;
  }

  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {
    if (_disposed) return;
    if (!_initialized) await initialize();
    _capabilities = capabilitiesFor(source);
    _controller.addListener(_syncDeviceCapabilities);
    await _controller.load(source, autoPlay: autoPlay);
  }

  /// The device probe lands after playback starts. Picture in Picture is the
  /// one capability it can take away: plenty of Android hardware ships without
  /// the system feature at all, and a button that cannot do anything is worse
  /// than no button.
  void _syncDeviceCapabilities() {
    if (_disposed) return;
    final DeviceCapabilities device = _controller.capabilities;
    if (!device.probed) return;
    final bool pip = _capabilities.supportsPictureInPicture;
    if (pip == device.supportsPip) return;
    _capabilities =
        _capabilities.copyWith(supportsPictureInPicture: device.supportsPip);
    // The controller is already notifying its own listeners; capabilities are
    // read from it on the same rebuild.
  }

  @override
  Future<void> play() => _guard(() => _controller.play());

  @override
  Future<void> pause() => _guard(() => _controller.pause());

  @override
  Future<void> seekTo(Duration position) =>
      _guard(() => _controller.seekTo(position));

  @override
  Future<void> setSpeed(double speed) =>
      _guard(() => _controller.setSpeed(speed));

  @override
  Future<void> setVolume(double volume) =>
      _guard(() => _controller.setVolume(volume));

  @override
  Future<void> setMuted(bool muted) =>
      _guard(() => _controller.setMuted(muted));

  @override
  Future<void> selectQuality(VideoQualityTrack track) {
    if (!_capabilities.canSelectQuality) return Future<void>.value();
    return _guard(() => _controller.selectQuality(track));
  }

  @override
  Future<void> selectAudioTrack(AudioTrackOption track) {
    if (!_capabilities.canSelectAudioTrack) return Future<void>.value();
    return _guard(() => _controller.selectAudioTrack(track));
  }

  @override
  Future<void> selectSubtitle(SubtitleTrackOption? track) {
    if (!_capabilities.canSelectSubtitle) return Future<void>.value();
    return _guard(() => _controller.selectSubtitle(track));
  }

  @override
  Future<bool> enterPictureInPicture() async {
    if (_disposed || !_capabilities.supportsPictureInPicture) return false;
    return _controller.enterPictureInPicture();
  }

  @override
  Future<void> setVideoFit(VideoFitMode fit) async {
    if (_disposed || !_capabilities.canChangeVideoFit) return;
    await _controller.setVideoFit(fit);
  }

  @override
  void setFullscreen(bool fullscreen) {
    if (_disposed) return;
    _controller.setFullscreen(fullscreen);
  }

  @override
  Widget buildSurface(BuildContext context) {
    final int? playerId = _controller.playerId;
    if (playerId == null) {
      // Not initialised yet: a black box, never a broken surface.
      return const ColoredBox(color: Color(0xFF000000));
    }
    return ZvNativeView(playerId: playerId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    _controller.removeListener(_syncDeviceCapabilities);
    await _controller.dispose();
  }

  Future<void> _guard(Future<void> Function() action) {
    if (_disposed || !_initialized) return Future<void>.value();
    return action();
  }
}
