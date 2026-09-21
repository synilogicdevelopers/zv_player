import 'package:flutter/foundation.dart';

import '../source/zv_media_source.dart';
import '../models/player_tracks.dart';

/// The player's lifecycle, as a single value rather than a spread of booleans.
enum PlayerStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  completed,
  error,
  disposed,
}

/// Error categories the UI can react to differently.
enum PlayerErrorType {
  sourceUnavailable,
  network,
  bufferingTimeout,
  unsupportedFormat,
  decoder,
  drm,
  audio,
  subtitle,
  casting,
  lifecycle,
  unknown,
}

/// A playback failure, in two registers: one for the viewer, one for the log.
@immutable
class PlayerErrorInfo {
  const PlayerErrorInfo({
    required this.type,
    required this.message,
    this.code,
    this.technicalDetail,
    this.isRecoverable = false,
    this.retryAttempt = 0,
  });

  final PlayerErrorType type;

  /// Shown to the viewer. Never a stack trace.
  final String message;

  /// Native error code, for logs.
  final String? code;

  /// Full native detail, for logs and crash reporting only.
  final String? technicalDetail;
  final bool isRecoverable;
  final int retryAttempt;

  PlayerErrorInfo copyWith({int? retryAttempt}) => PlayerErrorInfo(
        type: type,
        message: message,
        code: code,
        technicalDetail: technicalDetail,
        isRecoverable: isRecoverable,
        retryAttempt: retryAttempt ?? this.retryAttempt,
      );

  @override
  String toString() =>
      'PlayerErrorInfo(${type.name}, code: $code, recoverable: $isRecoverable)';
}

/// Where the video is actually rendering.
enum PlaybackRoute { local, cast }

/// How the video is scaled inside the player area.
///
/// Presentation decides
/// how much screen the player gets, fit decides what happens to the picture
/// inside it. Neither ever stretches - `fill` crops the overflow instead.
enum VideoFitMode {
  /// The whole frame is visible; letterboxing where aspect ratios differ.
  fit,

  /// The player area is filled, cropping only the excess edges.
  fill,
}

@immutable
class ZvPlayerState {
  const ZvPlayerState({
    this.status = PlayerStatus.idle,
    this.source,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.isFullscreen = false,
    this.videoFit = VideoFitMode.fit,
    this.isPip = false,
    this.isMiniPlayer = false,
    this.route = PlaybackRoute.local,
    this.tracks = const PlayerTracks(),
    this.videoWidth,
    this.videoHeight,
    this.isLive = false,
    this.hasNextEpisode = false,
    this.error,
    this.isSeeking = false,
  });

  final PlayerStatus status;
  final ZvMediaSource? source;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final double speed;
  final double volume;
  final bool isMuted;
  final bool isFullscreen;

  /// Picture scaling, independent of fullscreen.
  final VideoFitMode videoFit;
  final bool isPip;
  final bool isMiniPlayer;
  final PlaybackRoute route;
  final PlayerTracks tracks;
  final int? videoWidth;
  final int? videoHeight;
  final bool isLive;
  final bool hasNextEpisode;
  final PlayerErrorInfo? error;
  final bool isSeeking;

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isBuffering => status == PlayerStatus.buffering;
  bool get isCasting => route == PlaybackRoute.cast;
  bool get hasError => status == PlayerStatus.error;

  /// True once the native player has media ready; controls stay interactive
  /// through buffering, which is why buffering counts as initialised.
  bool get isInitialised =>
      status == PlayerStatus.ready ||
      status == PlayerStatus.playing ||
      status == PlayerStatus.paused ||
      status == PlayerStatus.buffering ||
      status == PlayerStatus.completed;

  /// Live streams and zero-duration sources cannot be scrubbed.
  bool get canSeek => !isLive && duration > Duration.zero && isInitialised;

  double get aspectRatio {
    final int? width = videoWidth;
    final int? height = videoHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  /// Fraction watched, clamped; safe to hand straight to a progress bar.
  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  double get bufferedProgress {
    if (duration.inMilliseconds <= 0) return 0;
    return (bufferedPosition.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  ZvPlayerState copyWith({
    PlayerStatus? status,
    ZvMediaSource? source,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? speed,
    double? volume,
    bool? isMuted,
    bool? isFullscreen,
    VideoFitMode? videoFit,
    bool? isPip,
    bool? isMiniPlayer,
    PlaybackRoute? route,
    PlayerTracks? tracks,
    int? videoWidth,
    int? videoHeight,
    bool? isLive,
    bool? hasNextEpisode,
    PlayerErrorInfo? error,
    bool clearError = false,
    bool? isSeeking,
  }) {
    return ZvPlayerState(
      status: status ?? this.status,
      source: source ?? this.source,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      videoFit: videoFit ?? this.videoFit,
      isPip: isPip ?? this.isPip,
      isMiniPlayer: isMiniPlayer ?? this.isMiniPlayer,
      route: route ?? this.route,
      tracks: tracks ?? this.tracks,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      isLive: isLive ?? this.isLive,
      hasNextEpisode: hasNextEpisode ?? this.hasNextEpisode,
      error: clearError ? null : (error ?? this.error),
      isSeeking: isSeeking ?? this.isSeeking,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZvPlayerState &&
        other.status == status &&
        other.source == source &&
        other.position == position &&
        other.duration == duration &&
        other.bufferedPosition == bufferedPosition &&
        other.speed == speed &&
        other.volume == volume &&
        other.isMuted == isMuted &&
        other.isFullscreen == isFullscreen &&
        other.videoFit == videoFit &&
        other.isPip == isPip &&
        other.isMiniPlayer == isMiniPlayer &&
        other.route == route &&
        other.tracks == tracks &&
        other.videoWidth == videoWidth &&
        other.videoHeight == videoHeight &&
        other.isLive == isLive &&
        other.hasNextEpisode == hasNextEpisode &&
        other.error == error &&
        other.isSeeking == isSeeking;
  }

  @override
  // hashAll rather than hash: the state has more fields than Object.hash
  // accepts positionally.
  int get hashCode => Object.hashAll(<Object?>[
        status,
        source,
        position,
        duration,
        bufferedPosition,
        speed,
        volume,
        isMuted,
        isFullscreen,
        videoFit,
        isPip,
        isMiniPlayer,
        route,
        tracks,
        videoWidth,
        videoHeight,
        isLive,
        hasNextEpisode,
        error,
        isSeeking,
      ]);
}
