import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/player_command_sink.dart';
import '../source/zv_media_source.dart';
import '../models/player_tracks.dart';
import '../state/zv_player_state.dart';
import '../capabilities/engine_capabilities.dart';
import '../engine/playback_engine.dart';
import '../source/source_router.dart';

/// Log tags emitted on the way through the player, for device verification.
class ZvPlayerLog {
  const ZvPlayerLog._();

  static const String open = 'ZV_PLAYER_OPEN';
  static const String sourceClassified = 'SOURCE_CLASSIFIED';
  static const String engineSelected = 'ENGINE_SELECTED';
  static const String engineInitialized = 'ENGINE_INITIALIZED';
  static const String firstFrame = 'FIRST_FRAME';
  static const String error = 'ZV_PLAYER_ERROR';
  static const String close = 'ZV_PLAYER_CLOSE';
}

/// One playback session, whatever plays it.
///
/// Routes the source to an engine, owns that engine's lifecycle, and mirrors
/// its state so the UI listens to exactly one object. Contains no engine
/// branching: the router picks the engine, and the engine reports what it can
/// do through [capabilities].
class ZvPlayerController extends ValueNotifier<ZvPlayerState>
    implements PlayerCommandSink {
  ZvPlayerController({
    SourceRouter? router,
    this.logger = _defaultLogger,
  })  : _router = router ?? SourceRouter.standard(),
        super(const ZvPlayerState());

  final SourceRouter _router;

  /// Where the structured log lines go. Replaceable for tests.
  final void Function(String tag, Map<String, Object?> fields) logger;

  PlaybackEngine? _engine;
  EngineSelection? _selection;
  bool _disposed = false;
  bool _firstFrameReported = false;

  /// Bumped by every [open]. An open that is superseded while awaiting its
  /// engine (a newer [open], or [dispose]) stops rather than touching state.
  int _openGeneration = 0;
  ZvMediaSource? _source;
  bool _wantsPlayback = true;
  bool _networkAvailable = true;
  bool _recovering = false;
  bool _recoveryFailed = false;
  Duration? _checkpoint;
  Timer? _recoveryTimer;
  int _recoveryAttempt = 0;
  int _recoveryGeneration = 0;

  bool get isOffline => !_networkAvailable;
  bool get isRecovering => _recovering;
  bool get recoveryFailed => _recoveryFailed;

  /// Connectivity changes keep the same engine and surface alive.
  Future<void> setNetworkAvailable(bool available) async {
    if (_disposed || _networkAvailable == available) return;
    _networkAvailable = available;
    if (_source?.type == ZvSourceType.local) return;
    _recoveryTimer?.cancel();
    ++_recoveryGeneration;
    if (!available) {
      _checkpoint ??= value.position;
      _recovering = false;
      _recoveryFailed = false;
      notifyListeners();
      await _engine?.pause();
    } else if (_checkpoint != null) {
      _recoveryAttempt = 0;
      await _recover();
    } else {
      notifyListeners();
    }
  }

  Future<void> _recover() async {
    final PlaybackEngine? engine = _engine;
    final ZvMediaSource? source = _source;
    if (_disposed || !_networkAvailable || engine == null || source == null) {
      return;
    }
    final int generation = ++_recoveryGeneration;
    _recovering = true;
    _recoveryFailed = false;
    ++_recoveryAttempt;
    notifyListeners();
    logger('PLAYER_RECOVERY', <String, Object?>{
      'attempt': _recoveryAttempt,
      'positionMs': (_checkpoint ?? value.position).inMilliseconds,
      'autoPlay': _wantsPlayback,
    });
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(seconds: 12), () {
      if (_disposed || generation != _recoveryGeneration || !_recovering) {
        return;
      }
      if (_recoveryAttempt >= 3) {
        _recovering = false;
        _recoveryFailed = true;
        notifyListeners();
      } else {
        _recoveryTimer =
            Timer(Duration(seconds: _recoveryAttempt * 2), _recover);
      }
    });
    try {
      await engine.load(
          source.copyWith(startPosition: _checkpoint ?? value.position),
          autoPlay: _wantsPlayback);
    } catch (error) {
      // The watchdog owns the bounded retry sequence, including thrown loads.
      logger('PLAYER_RECOVERY_ERROR', <String, Object?>{'error': '$error'});
    }
  }

  VoidCallback? _engineListener;

  /// The engine chosen for the current source, or null before [open].
  PlaybackEngine? get engine => _engine;

  EngineSelection? get selection => _selection;

  PlaybackEngineKind get engineKind =>
      _selection?.kind ?? PlaybackEngineKind.unsupported;

  /// What the active engine can do. Before an engine exists, nothing is
  /// claimed, so the chrome renders no controls it cannot honour.
  EngineCapabilities get capabilities =>
      _engine?.capabilities ?? const EngineCapabilities(canPlayPause: false);

  bool get isDisposed => _disposed;

  /// Classifies, routes, creates, initialises and loads - in that order.
  ///
  /// Nothing is constructed until routing has produced a playable selection,
  /// so an unsupported source never builds an engine.
  ///
  /// Opening a new source first releases the previous engine - its listener,
  /// its native player or web view - so a controller never holds two engines.
  Future<void> open(ZvMediaSource source, {bool autoPlay = true}) async {
    if (_disposed) return;
    final int generation = ++_openGeneration;
    final bool reopening = _source != null;

    // Anything tied to the previous session ends here.
    ++_recoveryGeneration;
    _recoveryTimer?.cancel();
    _recovering = false;
    _recoveryFailed = false;
    _checkpoint = null;
    _firstFrameReported = false;
    final PlaybackEngine? previous = _detachEngine();
    if (reopening) {
      // Fresh playback state for the new source; presentation carries over.
      value = ZvPlayerState(
          isFullscreen: value.isFullscreen, videoFit: value.videoFit);
    }
    if (previous != null) {
      await previous.dispose();
      if (_disposed || generation != _openGeneration) return;
    }

    _source = source;
    _wantsPlayback = autoPlay;
    logger(ZvPlayerLog.open, <String, Object?>{
      'contentId': source.contentId,
      'sourceType': source.type.name,
    });
    logger(ZvPlayerLog.sourceClassified, <String, Object?>{
      'sourceType': source.type.name,
      'isNativePlayable': source.type.isNativePlayable,
      'isEmbedded': source.type.isEmbedded,
    });

    final EngineSelection selection = _router.select(source);
    _selection = selection;
    logger(ZvPlayerLog.engineSelected, <String, Object?>{
      'engine': selection.kind.name,
      'sourceType': selection.sourceType.name,
      'reason': selection.reason,
    });

    if (!selection.isPlayable) {
      _fail(
        code: 'unsupported_source',
        message: 'This video source is not supported.',
        detail: selection.reason,
      );
      return;
    }

    final PlaybackEngine? engine = _router.createEngine(source);
    if (engine == null) {
      _fail(
        code: 'engine_unavailable',
        message: 'This video cannot be played in this build.',
        detail: 'no engine registered for ${selection.kind.name}',
      );
      return;
    }

    _engine = engine;
    _attachEngine(engine);

    try {
      await engine.initialize();
      logger(ZvPlayerLog.engineInitialized, <String, Object?>{
        'engine': selection.kind.name,
      });
      if (_disposed || generation != _openGeneration) return;
      await engine.load(source, autoPlay: autoPlay);
    } catch (error, stack) {
      if (_disposed || generation != _openGeneration) return;
      _fail(
        code: 'engine_start_failed',
        message: 'The video player could not start.',
        detail: '$error\n$stack',
      );
    }
  }

  /// Stops listening to the current engine and forgets it. The caller owns
  /// disposing the returned engine.
  PlaybackEngine? _detachEngine() {
    final PlaybackEngine? engine = _engine;
    final VoidCallback? listener = _engineListener;
    if (engine != null && listener != null) {
      engine.state.removeListener(listener);
    }
    _engineListener = null;
    _engine = null;
    _selection = null;
    return engine;
  }

  void _attachEngine(PlaybackEngine engine) {
    void listener() {
      // A replaced engine can still emit while it winds down; only the
      // current one may write state.
      if (_disposed || !identical(engine, _engine)) return;
      final ZvPlayerState next = engine.state.value;
      if (_networkAvailable && !_recovering && _checkpoint == null) {
        if (next.status == PlayerStatus.playing) _wantsPlayback = true;
        if (next.status == PlayerStatus.paused ||
            next.status == PlayerStatus.completed) {
          _wantsPlayback = false;
        }
      }
      if (_recovering &&
          ((_wantsPlayback &&
                  next.isPlaying &&
                  next.position > (_checkpoint ?? Duration.zero)) ||
              (!_wantsPlayback &&
                  (next.position - (_checkpoint ?? next.position)).abs() <=
                      const Duration(seconds: 2) &&
                  (next.status == PlayerStatus.ready ||
                      next.status == PlayerStatus.paused)))) {
        _recoveryTimer?.cancel();
        _recovering = false;
        _recoveryFailed = false;
        _checkpoint = null;
      }
      if (!_firstFrameReported &&
          (next.status == PlayerStatus.playing ||
              next.status == PlayerStatus.ready)) {
        _firstFrameReported = true;
        logger(ZvPlayerLog.firstFrame, <String, Object?>{
          'engine': engineKind.name,
          'status': next.status.name,
        });
      }
      if (next.hasError && next.error != null) {
        logger(ZvPlayerLog.error, <String, Object?>{
          'engine': engineKind.name,
          'type': next.error!.type.name,
          'code': next.error!.code,
        });
      }
      value = next.copyWith(
        position:
            value.isSeeking ? value.position : (_checkpoint ?? next.position),
        isSeeking: value.isSeeking,
        isFullscreen: value.isFullscreen,
        videoFit: value.videoFit,
      );
      // Recovery flags can change even when the engine value is unchanged.
      notifyListeners();
    }

    _engineListener = listener;
    engine.state.addListener(listener);
    // Adopt whatever the engine already holds.
    listener();
  }

  void _fail({
    required String code,
    required String message,
    String? detail,
  }) {
    logger(ZvPlayerLog.error, <String, Object?>{
      'code': code,
      'engine': engineKind.name,
    });
    if (_disposed) return;
    value = value.copyWith(
      status: PlayerStatus.error,
      error: PlayerErrorInfo(
        type: PlayerErrorType.unsupportedFormat,
        code: code,
        message: message,
        technicalDetail: detail,
      ),
    );
  }

  // --- Commands: delegated, and gated by what the engine supports ----------

  @override
  Future<void> play() async {
    if (!capabilities.canPlayPause) return;
    _wantsPlayback = true;
    if (!_networkAvailable) return;
    await _engine?.play();
  }

  @override
  Future<void> pause() async {
    if (!capabilities.canPlayPause) return;
    _wantsPlayback = false;
    await _engine?.pause();
  }

  @override
  Future<void> togglePlayPause() => value.isPlaying ? pause() : play();

  @override
  Future<void> seekTo(Duration position) async {
    if (!capabilities.canSeek) {
      if (value.isSeeking) value = value.copyWith(isSeeking: false);
      return;
    }
    value = value.copyWith(isSeeking: false);
    if (_checkpoint != null) _checkpoint = _clamp(position);
    await _engine?.seekTo(_clamp(position));
  }

  @override
  Future<void> seekBy(Duration delta) => seekTo(value.position + delta);

  @override
  void previewSeek(Duration position) {
    if (_disposed || !capabilities.canSeek) return;
    value = value.copyWith(position: _clamp(position), isSeeking: true);
  }

  Duration _clamp(Duration position) {
    if (position < Duration.zero) return Duration.zero;
    if (value.duration > Duration.zero && position > value.duration) {
      return value.duration;
    }
    return position;
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!capabilities.canSetSpeed) return;
    await _engine?.setSpeed(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!capabilities.canSetVolume) return;
    await _engine?.setVolume(volume);
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (!capabilities.canMute) return;
    await _engine?.setMuted(muted);
  }

  @override
  Future<void> toggleMute() => setMuted(!value.isMuted);

  @override
  Future<void> selectQuality(VideoQualityTrack track) async {
    if (!capabilities.canSelectQuality) return;
    await _engine?.selectQuality(track);
  }

  @override
  Future<void> selectAudioTrack(AudioTrackOption track) async {
    if (!capabilities.canSelectAudioTrack) return;
    await _engine?.selectAudioTrack(track);
  }

  @override
  Future<void> selectSubtitle(SubtitleTrackOption? track) async {
    if (!capabilities.canSelectSubtitle) return;
    await _engine?.selectSubtitle(track);
  }

  @override
  Future<void> retry() async {
    if (_disposed || !_networkAvailable || _recovering) return;
    _checkpoint ??= value.position;
    _recoveryAttempt = 0;
    await _recover();
  }

  Future<bool> enterPictureInPicture() async {
    if (!capabilities.supportsPictureInPicture) return false;
    return await _engine?.enterPictureInPicture() ?? false;
  }

  void setFullscreen(bool fullscreen) {
    if (_disposed) return;
    _engine?.setFullscreen(fullscreen);
    value = value.copyWith(
      isFullscreen: fullscreen,
    );
  }

  /// Switches the picture between whole-frame and crop-to-fill.
  ///
  /// Ignored when the engine cannot do it without distorting, which is why the
  /// row is hidden for web embeds rather than shown and ignored.
  Future<void> setVideoFit(VideoFitMode fit) async {
    if (_disposed || !capabilities.canChangeVideoFit) return;
    await _engine?.setVideoFit(fit);
    value = value.copyWith(videoFit: fit);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_recoveryGeneration;
    _recoveryTimer?.cancel();
    logger(ZvPlayerLog.close, <String, Object?>{
      'engine': engineKind.name,
      'positionMs': value.position.inMilliseconds,
    });

    final PlaybackEngine? engine = _detachEngine();
    if (engine != null) await engine.dispose();
    super.dispose();
  }

  static void _defaultLogger(String tag, Map<String, Object?> fields) {
    if (!kDebugMode) return;
    final String body = fields.entries
        .map((MapEntry<String, Object?> e) => '${e.key}=${e.value}')
        .join(' ');
    debugPrint('$tag  $body');
  }
}
