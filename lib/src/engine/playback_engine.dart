import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../source/zv_media_source.dart';
import '../models/player_tracks.dart';
import '../state/zv_player_state.dart';
import '../capabilities/engine_capabilities.dart';

/// Which implementation plays a source.
enum PlaybackEngineKind {
  /// Native media pipeline: Media3 on Android, AVPlayer on iOS.
  native,

  /// Web-view based playback for YouTube, Vimeo and other embeds.
  embedded,

  /// Nothing can play this source.
  unsupported,
}

/// One playback implementation behind a single contract.
///
/// The player UI talks to this and never to a concrete engine, so it contains
/// no `if (youtube)` / `if (media3)` branches. Engine-specific behaviour lives
/// inside the implementation; which implementation to use is decided by
/// `SourceRouter` before anything is created.
///
/// Lifecycle: construct → [initialize] → [load] → … → [dispose]. An engine must
/// not acquire decoders, web views or channels in its constructor; nothing is
/// initialised until routing has chosen it.
abstract class PlaybackEngine {
  PlaybackEngineKind get kind;

  /// Playback state, in the same shape for every engine.
  ValueListenable<ZvPlayerState> get state;

  /// What this engine can do for the currently loaded source. Read after
  /// [load], since capabilities can differ per source within one engine.
  EngineCapabilities get capabilities;

  bool get isInitialized;

  bool get isDisposed;

  /// Acquires whatever the engine needs. Safe to call more than once.
  Future<void> initialize();

  Future<void> load(ZvMediaSource source, {bool autoPlay = true});

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> setSpeed(double speed);

  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  /// Ignored when [EngineCapabilities.canSelectQuality] is false.
  Future<void> selectQuality(VideoQualityTrack track);

  /// Ignored when [EngineCapabilities.canSelectAudioTrack] is false.
  Future<void> selectAudioTrack(AudioTrackOption track);

  /// Null turns subtitles off. Ignored when the engine cannot select them.
  Future<void> selectSubtitle(SubtitleTrackOption? track);

  /// Returns false when the platform or engine cannot do it, so the caller can
  /// say so rather than pretending.
  Future<bool> enterPictureInPicture();

  /// Presentation only; the engine records it so state stays consistent.
  void setFullscreen(bool fullscreen);

  /// Switches between showing the whole frame and cropping to fill.
  /// Ignored when [EngineCapabilities.canChangeVideoFit] is false.
  Future<void> setVideoFit(VideoFitMode fit);

  /// The video surface: a platform view for native, a web view for embedded.
  Widget buildSurface(BuildContext context);

  /// Releases everything. Safe to call twice; later calls are no-ops.
  Future<void> dispose();
}
