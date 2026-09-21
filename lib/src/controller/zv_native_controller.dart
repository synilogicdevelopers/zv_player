import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/player_event.dart';
import '../services/cast_delegate.dart';
import '../services/player_command_sink.dart';
import '../services/playback_progress_store.dart';
import '../capabilities/device_capabilities.dart';
import '../source/zv_media_source.dart';
import '../models/player_tracks.dart';
import '../state/zv_player_state.dart';
import '../platform/zv_platform.dart';

/// Metadata for the item queued after the current one.
///
/// Supplied by the caller from real API data. The player never invents an
/// "up next" item, so the affordance simply does not appear when the backend
/// has not provided one.
@immutable
class UpNextItem {
  const UpNextItem({
    required this.title,
    required this.source,
    this.subtitleText = '',
    this.thumbnailUrl,
  });

  final String title;
  final String subtitleText;
  final ZvMediaSource source;
  final String? thumbnailUrl;
}

/// Playback speeds offered by the player.
const List<double> kPlaybackSpeeds = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
];

/// Owns one playback session: the native player, its state, and the rules
/// around it (resume, retry, analytics).
///
/// The UI listens to this and nothing else - no widget touches a platform
/// channel, and no widget polls native state.
class ZvNativeController extends ValueNotifier<ZvPlayerState>
    implements PlayerCommandSink {
  ZvNativeController({
    ZvPlatform? platform,
    PlaybackProgressStore? progressStore,
    PlayerAnalyticsSink analytics = const NoopAnalyticsSink(),
    CastDelegate cast = const NoCastDelegate(),
    ResumePolicy resumePolicy = const ResumePolicy(),
    this.maxRetries = 2,
    this.secureSurface = true,
  })  : _platform = platform ?? MethodChannelZvPlatform(),
        _progressStore = progressStore ?? InMemoryProgressStore(),
        _analytics = analytics,
        _cast = cast,
        _resumePolicy = resumePolicy,
        super(const ZvPlayerState());

  final ZvPlatform _platform;
  final PlaybackProgressStore _progressStore;
  final PlayerAnalyticsSink _analytics;
  final CastDelegate _cast;
  final ResumePolicy _resumePolicy;

  /// Bounded recovery: retries stop here rather than hammering a dead source.
  final int maxRetries;

  /// Whether to ask the platform to block screenshots while this player runs.
  final bool secureSurface;

  int? _playerId;
  Future<void>? _initialising;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _progressTimer;
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _disposed = false;
  bool _startupReported = false;
  DateTime? _loadStartedAt;
  DeviceCapabilities _capabilities = const DeviceCapabilities();
  UpNextItem? _upNext;
  bool _wasBuffering = false;

  /// Null until [initialise] completes. The view needs it to attach.
  int? get playerId => _playerId;

  DeviceCapabilities get capabilities => _capabilities;

  UpNextItem? get upNext => _upNext;

  CastDelegate get cast => _cast;

  bool get isReady => _playerId != null && !_disposed;

  /// Creates the native player and starts listening to it.
  ///
  /// Safe to call repeatedly and concurrently: callers racing here (a screen
  /// calling `initialise` while `load` does the same) share one in-flight
  /// creation rather than ending up with two decoders.
  Future<void> initialise() {
    if (_disposed || _playerId != null) return Future<void>.value();
    return _initialising ??= _create()
      ..whenComplete(() => _initialising = null);
  }

  Future<void> _create() async {
    try {
      await _createUnguarded();
    } catch (error, stack) {
      // A platform that cannot create a player must surface a player error,
      // not throw into whichever screen happened to call initialise().
      _emitError(
        PlayerErrorInfo(
          type: PlayerErrorType.lifecycle,
          code: 'player_create_failed',
          message: 'The video player could not start on this device.',
          technicalDetail: '$error\n$stack',
        ),
      );
    }
  }

  Future<void> _createUnguarded() async {
    final int id = await _platform.create();
    if (_disposed) {
      await _platform.dispose(id);
      return;
    }
    _playerId = id;
    _eventSub = _platform.events(id).listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stack) {
        _emitError(
          mapNativeError(
            code: 'event_channel',
            message: '$error',
            detail: '$stack',
          ),
        );
      },
    );

    if (secureSurface) {
      // Best effort: Android applies FLAG_SECURE, iOS has no equivalent.
      unawaited(_platform.setSecureSurface(id, true).catchError((_) {}));
    }

    // Capabilities are deliberately NOT probed here. This runs during the
    // navigation transition, and the probe enumerates every decoder on the
    // device. It is requested once playback is under way instead.
    notifyListeners();
  }

  Future<void> _loadCapabilities() async {
    try {
      _capabilities = await _platform.capabilities();
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Capability probing is advisory; failure must not break playback.
    }
  }

  /// Loads [source], resuming from stored progress when that still makes sense.
  Future<void> load(
    ZvMediaSource source, {
    bool autoPlay = true,
    UpNextItem? upNext,
    bool useStoredResume = true,
    bool resetRetryCount = true,
  }) async {
    if (_disposed) return;
    if (_playerId == null) await initialise();
    final int? id = _playerId;
    if (id == null) return;

    _upNext = upNext;
    // A retry reloads the same source deliberately; resetting the counter here
    // would make every failure look like the first and retry for ever.
    if (resetRetryCount) _retryCount = 0;
    _startupReported = false;
    _loadStartedAt = DateTime.now();

    Duration start = source.startPosition ?? Duration.zero;
    if (useStoredResume && start == Duration.zero && source.contentId != null) {
      final PlaybackProgress? stored =
          await _progressStore.load(source.contentId!);
      if (stored != null &&
          _resumePolicy.shouldResumeFrom(stored.position, stored.duration)) {
        start = stored.position;
      }
    }

    final ZvMediaSource resolved = source.copyWith(startPosition: start);

    // Refuse anything the native pipeline cannot play, before it reaches the
    // platform. Media3/AVPlayer would otherwise fail deep inside an extractor
    // with a container error that means nothing to a viewer. Embedded sources
    // belong to the web-view player and should have been routed there.
    if (!resolved.type.isNativePlayable) {
      value = value.copyWith(source: resolved, clearError: true);
      _emitError(
        PlayerErrorInfo(
          type: PlayerErrorType.unsupportedFormat,
          code: 'source_not_native',
          message: resolved.type.isEmbedded
              ? 'This title is hosted on ${resolved.type.displayName} and '
                  'cannot be played by the native player.'
              : 'This video source is not supported by the native player.',
          technicalDetail:
              'ZvSourceType.${resolved.type.name} is not native-playable; '
              'uri=${resolved.uri}',
        ),
      );
      return;
    }

    value = value.copyWith(
      status: PlayerStatus.loading,
      source: resolved,
      position: start,
      duration: source.duration ?? Duration.zero,
      bufferedPosition: Duration.zero,
      tracks: _tracksForSource(resolved),
      isLive: source.isLive,
      hasNextEpisode: upNext != null,
      clearError: true,
    );

    await _platform.load(id, resolved, autoPlay: autoPlay);
    _startProgressTimer();

    // Now that the heavy transition work is done, find out what this device
    // can do. Only affects optional affordances (PiP), so it can arrive late.
    if (!_capabilities.probed) unawaited(_loadCapabilities());
  }

  /// Quality entries that exist before the native player reports anything.
  ///
  /// For a set of separate per-quality URLs this is the whole list; for a
  /// manifest it stays empty until the native player parses the real tracks,
  /// so nothing is offered that does not exist.
  PlayerTracks _tracksForSource(ZvMediaSource source) {
    if (!source.hasManualVariants) return const PlayerTracks();

    final List<ZvSourceVariant> sorted =
        List<ZvSourceVariant>.from(source.variants)
          ..sort((ZvSourceVariant a, ZvSourceVariant b) =>
              (b.height ?? 0).compareTo(a.height ?? 0));

    return PlayerTracks(
      video: sorted.map((ZvSourceVariant variant) {
        return VideoQualityTrack(
          id: variant.id,
          label: variant.label,
          height: variant.height,
          isSelected: variant.uri == source.uri,
          isVariant: true,
        );
      }).toList(),
    );
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    switch (event['event']) {
      case 'status':
        _handleStatus('${event['status']}');
        break;
      case 'position':
        _handlePosition(event);
        break;
      case 'tracks':
        _handleTracks(event);
        break;
      case 'videoSize':
        value = value.copyWith(
          videoWidth: _asInt(event['width']),
          videoHeight: _asInt(event['height']),
        );
        break;
      case 'speed':
        value = value.copyWith(speed: _asDouble(event['speed']) ?? value.speed);
        break;
      case 'volume':
        value = value.copyWith(
          volume: _asDouble(event['volume']) ?? value.volume,
          isMuted: event['muted'] == true,
        );
        break;
      case 'pip':
        final bool inPip = event['isInPip'] == true;
        value = value.copyWith(isPip: inPip);
        _track(PlayerEventName.pip, <String, Object?>{'active': inPip});
        break;
      case 'isLive':
        value = value.copyWith(isLive: event['isLive'] == true);
        break;
      case 'completed':
        _handleCompleted();
        break;
      case 'error':
        _handleNativeError(event);
        break;
    }
  }

  void _handleStatus(String status) {
    switch (status) {
      case 'loading':
        value = value.copyWith(status: PlayerStatus.loading);
        break;
      case 'ready':
        _reportStartupOnce();
        _retryCount = 0;
        if (_wasBuffering) {
          _wasBuffering = false;
          _track(PlayerEventName.bufferEnd);
        }
        value = value.copyWith(status: PlayerStatus.ready, clearError: true);
        break;
      case 'playing':
        _reportStartupOnce();
        if (_wasBuffering) {
          _wasBuffering = false;
          _track(PlayerEventName.bufferEnd);
        }
        if (value.status != PlayerStatus.playing) {
          _track(PlayerEventName.play);
        }
        value = value.copyWith(status: PlayerStatus.playing, clearError: true);
        break;
      case 'paused':
        if (value.status == PlayerStatus.playing) {
          _track(PlayerEventName.pause);
        }
        value = value.copyWith(status: PlayerStatus.paused);
        break;
      case 'buffering':
        if (!_wasBuffering) {
          _wasBuffering = true;
          _track(PlayerEventName.bufferStart);
        }
        value = value.copyWith(status: PlayerStatus.buffering);
        break;
      case 'completed':
        _handleCompleted();
        break;
      case 'idle':
        value = value.copyWith(status: PlayerStatus.idle);
        break;
    }
  }

  void _reportStartupOnce() {
    if (_startupReported) return;
    _startupReported = true;
    final DateTime? started = _loadStartedAt;
    _track(PlayerEventName.startup, <String, Object?>{
      if (started != null)
        'startupTimeMs': DateTime.now().difference(started).inMilliseconds,
      'sourceType': value.source?.type.name,
    });
  }

  void _handlePosition(Map<String, dynamic> event) {
    final int? positionMs = _asInt(event['positionMs']);
    final int? durationMs = _asInt(event['durationMs']);
    final int? bufferedMs = _asInt(event['bufferedMs']);

    value = value.copyWith(
      position: value.isSeeking || positionMs == null
          ? value.position
          : Duration(milliseconds: positionMs),
      duration: (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : value.duration,
      bufferedPosition: bufferedMs != null
          ? Duration(milliseconds: bufferedMs)
          : value.bufferedPosition,
    );
  }

  void _handleTracks(Map<String, dynamic> event) {
    final List<VideoQualityTrack> native = _mapList(
      event['video'],
      VideoQualityTrack.fromMap,
    );
    final List<AudioTrackOption> audio = _mapList(
      event['audio'],
      AudioTrackOption.fromMap,
    );
    final List<SubtitleTrackOption> subtitles = _mapList(
      event['text'],
      SubtitleTrackOption.fromMap,
    );

    // Manual per-URL variants stay authoritative for progressive sources: the
    // native player only ever sees one of them at a time.
    final bool usingVariants = value.source?.hasManualVariants ?? false;
    List<VideoQualityTrack> video;
    if (usingVariants) {
      video = value.tracks.video;
    } else if (native.length > 1) {
      // A manifest with several representations: the native player can adapt,
      // so Auto is a real option rather than a label.
      final bool anySelected =
          native.any((VideoQualityTrack t) => t.isSelected);
      video = <VideoQualityTrack>[
        VideoQualityTrack.auto(isSelected: !anySelected),
        ...native,
      ];
    } else {
      video = native;
    }

    value = value.copyWith(
      tracks: PlayerTracks(video: video, audio: audio, subtitles: subtitles),
    );
  }

  void _handleCompleted() {
    _track(PlayerEventName.completed);
    value = value.copyWith(
      status: PlayerStatus.completed,
      position: value.duration,
    );
    final String? contentId = value.source?.contentId;
    if (contentId != null) {
      // A finished item should start from the beginning next time.
      unawaited(_progressStore.clear(contentId));
    }
  }

  void _handleNativeError(Map<String, dynamic> event) {
    final PlayerErrorInfo info = mapNativeError(
      code: event['code'] as String?,
      message: event['message'] as String?,
      detail: event['detail'] as String?,
    );
    // The native layer knows best whether a failure is transient. Only fall
    // back to the code-based guess when it did not say.
    final Object? nativeRecoverable = event['recoverable'];
    final bool recoverable =
        nativeRecoverable is bool ? nativeRecoverable : info.isRecoverable;

    if (recoverable && _retryCount < maxRetries) {
      _scheduleRetry(info);
      return;
    }
    _emitError(info.copyWith(retryAttempt: _retryCount));
  }

  /// Retries with a widening gap, at most [maxRetries] times, from the last
  /// known position. No infinite reconnect loops.
  void _scheduleRetry(PlayerErrorInfo info) {
    _retryCount++;
    final Duration delay = Duration(seconds: _retryCount * 2);
    value = value.copyWith(status: PlayerStatus.buffering);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      final ZvMediaSource? source = value.source;
      if (_disposed || source == null) return;
      unawaited(
        load(
          source.copyWith(startPosition: value.position),
          useStoredResume: false,
          upNext: _upNext,
          resetRetryCount: false,
        ).catchError((_) => _emitError(info)),
      );
    });
  }

  void _emitError(PlayerErrorInfo info) {
    _stopProgressTimer();
    _track(PlayerEventName.error, <String, Object?>{
      'type': info.type.name,
      'code': info.code,
      'retryAttempt': info.retryAttempt,
    });
    value = value.copyWith(status: PlayerStatus.error, error: info);
  }

  @override

  /// Retry after a failure the viewer chose to dismiss.
  Future<void> retry() async {
    final ZvMediaSource? source = value.source;
    if (source == null) return;
    _retryCount = 0;
    await load(
      source.copyWith(startPosition: value.position),
      useStoredResume: false,
      upNext: _upNext,
    );
  }

  // --- Transport -----------------------------------------------------------

  @override
  Future<void> play() async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.play(id);
  }

  @override
  Future<void> pause() async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.pause(id);
    await _saveProgress();
  }

  @override
  Future<void> togglePlayPause() => value.isPlaying ? pause() : play();

  @override
  Future<void> seekTo(Duration position) async {
    final int? id = _playerId;
    if (id == null || !value.canSeek) {
      // A refused seek must still end any drag, or the scrubber freezes at the
      // preview position while playback carries on underneath it.
      if (value.isSeeking) value = value.copyWith(isSeeking: false);
      return;
    }
    final Duration target = _clampPosition(position);
    _track(PlayerEventName.seek, <String, Object?>{
      'fromMs': value.position.inMilliseconds,
      'toMs': target.inMilliseconds,
    });
    value = value.copyWith(position: target, isSeeking: false);
    await _platform.seekTo(id, target);
  }

  @override

  /// Moves the scrubber without committing, so dragging stays smooth.
  void previewSeek(Duration position) {
    if (!value.canSeek) return;
    value = value.copyWith(position: _clampPosition(position), isSeeking: true);
  }

  @override
  Future<void> seekBy(Duration delta) => seekTo(value.position + delta);

  Duration _clampPosition(Duration position) {
    if (position < Duration.zero) return Duration.zero;
    if (value.duration > Duration.zero && position > value.duration) {
      return value.duration;
    }
    return position;
  }

  @override
  Future<void> setSpeed(double speed) async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.setSpeed(id, speed);
    value = value.copyWith(speed: speed);
    _track(PlayerEventName.speedChange, <String, Object?>{'speed': speed});
  }

  @override
  Future<void> setVolume(double volume) async {
    final int? id = _playerId;
    if (id == null) return;
    final double clamped = volume.clamp(0.0, 1.0);
    await _platform.setVolume(id, clamped);
    value = value.copyWith(volume: clamped, isMuted: clamped == 0);
  }

  @override
  Future<void> setMuted(bool muted) async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.setMuted(id, muted);
    value = value.copyWith(isMuted: muted);
  }

  @override
  Future<void> toggleMute() => setMuted(!value.isMuted);

  // --- Track selection -----------------------------------------------------

  @override

  /// Selects a quality. For manifest-based sources this is a native track
  /// override; for per-URL variants it reloads the chosen URL at the current
  /// position, which is the honest behaviour for a non-adaptive source.
  Future<void> selectQuality(VideoQualityTrack track) async {
    final int? id = _playerId;
    final ZvMediaSource? source = value.source;
    if (id == null || source == null) return;

    _track(PlayerEventName.qualityChange, <String, Object?>{
      'label': track.label,
      'adaptive': track.isAuto,
      'viaReload': track.isVariant,
    });

    if (track.isVariant) {
      final ZvSourceVariant variant = source.variants.firstWhere(
        (ZvSourceVariant v) => v.id == track.id,
        orElse: () => source.variants.first,
      );
      final Duration resumeAt = value.position;
      value = value.copyWith(
        tracks: value.tracks.copyWith(
          video: value.tracks.video
              .map((VideoQualityTrack t) =>
                  t.copyWith(isSelected: t.id == track.id))
              .toList(),
        ),
      );
      await load(
        source.copyWith(
          uri: variant.uri,
          type: variant.resolvedType,
          startPosition: resumeAt,
        ),
        useStoredResume: false,
        upNext: _upNext,
      );
      return;
    }

    await _platform.selectVideoTrack(id, track.isAuto ? null : track.id);
    value = value.copyWith(
      tracks: value.tracks.copyWith(
        video: value.tracks.video
            .map((VideoQualityTrack t) =>
                t.copyWith(isSelected: t.id == track.id))
            .toList(),
      ),
    );
  }

  @override
  Future<void> selectAudioTrack(AudioTrackOption track) async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.selectAudioTrack(id, track.id);
    value = value.copyWith(
      tracks: value.tracks.copyWith(
        audio: value.tracks.audio
            .map((AudioTrackOption t) =>
                t.copyWith(isSelected: t.id == track.id))
            .toList(),
      ),
    );
    _track(PlayerEventName.audioChange, <String, Object?>{
      'language': track.language,
    });
  }

  @override

  /// Passing null turns subtitles off.
  Future<void> selectSubtitle(SubtitleTrackOption? track) async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.selectSubtitleTrack(id, track?.id);
    value = value.copyWith(
      tracks: value.tracks.copyWith(
        subtitles: value.tracks.subtitles
            .map((SubtitleTrackOption t) =>
                t.copyWith(isSelected: track != null && t.id == track.id))
            .toList(),
      ),
    );
    _track(PlayerEventName.subtitleChange, <String, Object?>{
      'language': track?.language,
      'enabled': track != null,
    });
  }

  // --- Presentation flags --------------------------------------------------

  /// Applies crop-to-fill or whole-frame scaling on the native surface.
  Future<void> setVideoFit(VideoFitMode fit) async {
    final int? id = _playerId;
    if (id == null) return;
    await _platform.setVideoFit(id, fit);
    value = value.copyWith(videoFit: fit);
  }

  void setFullscreen(bool fullscreen) {
    if (value.isFullscreen == fullscreen) return;
    value = value.copyWith(isFullscreen: fullscreen);
    _track(PlayerEventName.fullscreen, <String, Object?>{'active': fullscreen});
  }

  void setMiniPlayer(bool mini) {
    if (value.isMiniPlayer == mini) return;
    value = value.copyWith(isMiniPlayer: mini);
  }

  /// Asks the platform for PiP. Returns false when it is unavailable, so the
  /// caller can tell the viewer instead of showing a fake overlay.
  Future<bool> enterPictureInPicture() async {
    final int? id = _playerId;
    if (id == null) return false;
    if (_capabilities.probed && !_capabilities.supportsPip) return false;
    return _platform.enterPictureInPicture(id);
  }

  // --- Up next -------------------------------------------------------------

  /// Plays the queued item. No-op when the caller supplied none.
  Future<void> playNext() async {
    final UpNextItem? next = _upNext;
    if (next == null) return;
    await load(next.source, upNext: null);
  }

  void setUpNext(UpNextItem? item) {
    _upNext = item;
    value = value.copyWith(hasNextEpisode: item != null);
  }

  // --- Progress ------------------------------------------------------------

  void _startProgressTimer() {
    _stopProgressTimer();
    _progressTimer = Timer.periodic(_resumePolicy.saveInterval, (Timer _) {
      if (value.isPlaying) {
        unawaited(_saveProgress());
        _track(PlayerEventName.progress, <String, Object?>{
          'positionMs': value.position.inMilliseconds,
          'durationMs': value.duration.inMilliseconds,
        });
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _saveProgress() async {
    final String? contentId = value.source?.contentId;
    if (contentId == null) return;
    if (!_resumePolicy.shouldSave(value.position, value.duration)) return;
    await _progressStore.save(
      PlaybackProgress(
        contentId: contentId,
        position: value.position,
        duration: value.duration,
      ),
    );
  }

  /// Persists progress immediately; call when the app goes to the background.
  Future<void> flushProgress() => _saveProgress();

  void _track(String name,
      [Map<String, Object?> properties = const <String, Object?>{}]) {
    _analytics.add(
      PlayerAnalyticsEvent(
        name: name,
        contentId: value.source?.contentId,
        properties: properties,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    // Persist before tearing down, or up to one save interval of watching is
    // lost whenever the viewer simply leaves the screen.
    try {
      await _saveProgress();
    } catch (_) {
      // Storage failures must never block teardown.
    }
    _disposed = true;
    _stopProgressTimer();
    _retryTimer?.cancel();
    await _eventSub?.cancel();
    _eventSub = null;
    final int? id = _playerId;
    _playerId = null;
    if (id != null) {
      await _platform.dispose(id);
    }
    super.dispose();
  }

  static List<T> _mapList<T>(
    Object? raw,
    T Function(Map<dynamic, dynamic>) mapper,
  ) {
    if (raw is! List) return <T>[];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(mapper)
        .toList(growable: false);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return null;
  }
}
