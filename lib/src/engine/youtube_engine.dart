import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../capabilities/engine_capabilities.dart';
import '../models/player_tracks.dart';
import '../source/youtube_video_id.dart';
import '../source/zv_media_source.dart';
import '../state/zv_player_state.dart';
import 'playback_engine.dart';
import 'youtube_page.dart';

/// Plays YouTube URLs through YouTube's official IFrame Player API.
///
/// The provider's own controls are switched off (`controls: 0`) and the web
/// view takes no touches: the viewer only ever sees and uses ZV Player's
/// controls, which drive the embed through the API. Media is never extracted
/// from YouTube; the embed plays it, as YouTube's terms require.
///
/// Capabilities are only what the IFrame API really offers: play/pause, seek,
/// volume/mute, speed and a buffered fraction. Quality, captions, audio
/// tracks, picture-in-picture, casting and fit/fill are provider-owned and are
/// not claimed.
class YouTubeEngine implements PlaybackEngine {
  /// [origin] is the page origin the embed is served from. YouTube refuses to
  /// play embeds without a valid referrer (error 152/153), so hosts should
  /// pass their own https origin (for example their website).
  YouTubeEngine({Uri? origin})
      : origin = origin ?? Uri.parse('https://localhost');

  final Uri origin;

  /// The JavaScript handler the page reports on.
  static const String channel = 'ZvPlayerEvents';

  /// The rates YouTube's player accepts.
  static const List<double> speeds = <double>[0.25, 0.5, 1.0, 1.5, 2.0];

  /// What the IFrame API can actually be driven to do.
  static const EngineCapabilities kCapabilities = EngineCapabilities(
    canPlayPause: true,
    canSeek: true,
    canSetSpeed: true,
    speeds: speeds,
    canSetVolume: true,
    canMute: true,
    supportsFullscreen: true,
    reportsBufferedPosition: true,
  );

  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());

  InAppWebViewController? _webViewController;
  ZvMediaSource? _source;
  String? _html;
  bool _initialized = false;
  bool _disposed = false;

  /// Where we last asked the provider to seek to, and when. The provider's
  /// clock lags a seek request (for seconds while paused), and without this
  /// the next progress tick snaps the scrubber back.
  Duration? _pendingSeekTarget;
  DateTime? _pendingSeekAt;
  static const Duration _seekSettleWindow = Duration(seconds: 4);
  static const Duration _seekSettleTolerance = Duration(seconds: 2);

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.embedded;

  @override
  ValueListenable<ZvPlayerState> get state => _state;

  @override
  EngineCapabilities get capabilities => kCapabilities;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isDisposed => _disposed;

  /// The source currently loaded, for diagnostics.
  ZvMediaSource? get currentSource => _source;

  @override
  Future<void> initialize() async {
    if (_disposed || _initialized) return;
    // The web view is created when the surface mounts; nothing to acquire.
    _initialized = true;
  }

  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {
    if (_disposed) return;
    if (!_initialized) await initialize();

    _pendingSeekTarget = null;
    _pendingSeekAt = null;
    _source = source;
    final String? videoId = youTubeVideoId(source.uri);
    if (videoId == null) {
      _html = null;
      _emit(_state.value.copyWith(
        status: PlayerStatus.error,
        source: source,
        error: const PlayerErrorInfo(
          type: PlayerErrorType.sourceUnavailable,
          code: 'youtube_invalid_url',
          message: 'This video link is not valid.',
        ),
      ));
      return;
    }
    _html = youTubePage(
      videoId,
      autoplay: autoPlay,
      mute: _state.value.isMuted,
      startAt: source.startPosition,
    );

    _emit(_state.value.copyWith(
      status: PlayerStatus.loading,
      source: source,
      position: source.startPosition ?? Duration.zero,
      duration: source.duration ?? Duration.zero,
      tracks: const PlayerTracks(),
      clearError: true,
    ));

    // A mounted surface swaps the page in place (reconnect, next item).
    final InAppWebViewController? controller = _webViewController;
    if (controller != null) await _loadHtml(controller, _html!);
  }

  Future<void> _loadHtml(InAppWebViewController controller, String html) {
    return controller.loadData(
      data: html,
      baseUrl: WebUri(origin.toString()),
      mimeType: 'text/html',
      encoding: 'utf-8',
    );
  }

  @override
  Future<void> play() => _js('playVideo();');

  @override
  Future<void> pause() => _js('pauseVideo();');

  @override
  Future<void> seekTo(Duration position) async {
    _pendingSeekTarget = position;
    _pendingSeekAt = DateTime.now();
    _emit(_state.value.copyWith(position: position, isSeeking: false));
    await _js('seekTo(${position.inMilliseconds / 1000});');
  }

  bool _shouldIgnoreReportedPosition(Duration reported) {
    final Duration? target = _pendingSeekTarget;
    final DateTime? at = _pendingSeekAt;
    if (target == null || at == null) return false;
    if ((reported - target).abs() <= _seekSettleTolerance ||
        DateTime.now().difference(at) >= _seekSettleWindow) {
      _pendingSeekTarget = null;
      _pendingSeekAt = null;
      return false;
    }
    return true;
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _js('setPlaybackRate($speed);');
    _emit(_state.value.copyWith(speed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    final double clamped = volume.clamp(0.0, 1.0);
    await _js('setVolume($clamped);');
    _emit(_state.value.copyWith(volume: clamped, isMuted: clamped == 0));
  }

  /// Audio only: unmuting never starts playback.
  @override
  Future<void> setMuted(bool muted) async {
    await _js(muted ? 'mute();' : 'unMute();');
    _emit(_state.value.copyWith(isMuted: muted));
  }

  @override
  Future<void> selectQuality(VideoQualityTrack track) async {}

  @override
  Future<void> selectAudioTrack(AudioTrackOption track) async {}

  @override
  Future<void> selectSubtitle(SubtitleTrackOption? track) async {}

  @override
  Future<bool> enterPictureInPicture() async => false;

  @override
  Future<void> setVideoFit(VideoFitMode fit) async {}

  @override
  void setFullscreen(bool fullscreen) {
    _emit(_state.value.copyWith(isFullscreen: fullscreen));
  }

  @override
  Widget buildSurface(BuildContext context) {
    final String? html = _html;
    if (_disposed || html == null) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    // No touches reach the embed: ZV Player's controls are the only UI.
    return IgnorePointer(
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: html,
          baseUrl: WebUri(origin.toString()),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          supportZoom: false,
          disableContextMenu: true,
          disableHorizontalScroll: true,
          disableVerticalScroll: true,
        ),
        onWebViewCreated: (InAppWebViewController controller) {
          _webViewController = controller;
          controller.addJavaScriptHandler(
            handlerName: channel,
            callback: (List<dynamic> args) {
              if (args.isNotEmpty) _onWebMessage(args.first);
              return null;
            },
          );
        },
      ),
    );
  }

  /// Feeds a page message through the same path the web view uses.
  @visibleForTesting
  void debugHandleWebMessage(Object? message) => _onWebMessage(message);

  void _onWebMessage(Object? message) {
    if (_disposed || message == null) return;
    final String raw = '$message';

    switch (raw) {
      case 'playing':
        _emit(_state.value
            .copyWith(status: PlayerStatus.playing, clearError: true));
        return;
      case 'paused':
        _emit(_state.value.copyWith(status: PlayerStatus.paused));
        return;
      case 'buffering':
        _emit(_state.value.copyWith(status: PlayerStatus.buffering));
        return;
      // Loaded but not playing (autoplay declined): a ready state, so the
      // chrome shows a play control rather than a spinner.
      case 'cued':
        _emit(_state.value
            .copyWith(status: PlayerStatus.ready, clearError: true));
        return;
      case 'ended':
        _emit(_state.value.copyWith(status: PlayerStatus.completed));
        return;
    }

    if (!raw.startsWith('{')) return;
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['event'] == 'error') {
        _emit(_state.value.copyWith(
          status: PlayerStatus.error,
          error: PlayerErrorInfo(
            type: PlayerErrorType.sourceUnavailable,
            code: 'youtube_${data['code']}',
            message:
                'This video could not be loaded. Check your connection and retry.',
            isRecoverable: true,
          ),
        ));
        return;
      }
      if (data['event'] != 'timeUpdate') return;
      final double current = (data['currentTime'] as num?)?.toDouble() ?? 0;
      final double total = (data['duration'] as num?)?.toDouble() ?? 0;
      final double? bufferedFraction = (data['buffered'] as num?)?.toDouble();
      final Duration reported =
          Duration(milliseconds: (current * 1000).round());
      final Duration duration = total > 0
          ? Duration(milliseconds: (total * 1000).round())
          : _state.value.duration;

      _emit(_state.value.copyWith(
        position:
            _state.value.isSeeking || _shouldIgnoreReportedPosition(reported)
                ? _state.value.position
                : reported,
        duration: duration,
        bufferedPosition: bufferedFraction == null
            ? _state.value.bufferedPosition
            : Duration(
                milliseconds:
                    (duration.inMilliseconds * bufferedFraction).round()),
        volume: (data['volume'] as num?)?.toDouble() ?? _state.value.volume,
        isMuted: data['muted'] as bool? ?? _state.value.isMuted,
        speed: (data['rate'] as num?)?.toDouble() ?? _state.value.speed,
        // A progress tick while loading means metadata has arrived.
        status: _state.value.status == PlayerStatus.loading
            ? PlayerStatus.ready
            : _state.value.status,
      ));
    } catch (_) {
      // A malformed message must never take playback down.
    }
  }

  Future<void> _js(String source) async {
    if (_disposed) return;
    final InAppWebViewController? controller = _webViewController;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: source);
    } catch (error) {
      if (kDebugMode) debugPrint('[zv_player] YouTube JS failed: $error');
    }
  }

  void _emit(ZvPlayerState next) {
    if (_disposed) return;
    _state.value = next;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;
    try {
      _webViewController?.dispose();
    } catch (_) {
      // Web view teardown must not throw.
    }
    _webViewController = null;
    _source = null;
    _html = null;
    _state.dispose();
  }
}
