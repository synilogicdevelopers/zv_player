import 'package:flutter/foundation.dart';

import '../controller/zv_native_controller.dart';
import '../engine/native_media_engine.dart';
import '../engine/youtube_engine.dart';
import '../services/playback_progress_store.dart';

import 'zv_media_source.dart';
import '../engine/playback_engine.dart';

/// The routing decision for one source, with the reason it was made.
///
/// The reason is carried deliberately: a source that ends up unsupported must
/// be explainable in a log and in the UI, not silently dropped.
@immutable
class EngineSelection {
  const EngineSelection({
    required this.kind,
    required this.sourceType,
    required this.reason,
  });

  final PlaybackEngineKind kind;
  final ZvSourceType sourceType;
  final String reason;

  bool get isPlayable => kind != PlaybackEngineKind.unsupported;

  @override
  String toString() =>
      'EngineSelection(${kind.name} for ${sourceType.name}: $reason)';
}

/// Builds an engine on demand.
typedef PlaybackEngineBuilder = PlaybackEngine Function();

/// Chooses the engine for a source, and only then builds it.
///
/// This is the single place where a source type maps to an implementation.
/// Nothing downstream branches on YouTube or Media3 again.
///
/// - progressive / HLS / DASH / local: the native engine (Media3 / AVPlayer)
/// - YouTube: the YouTube engine (official IFrame API under ZV Player's UI)
/// - Vimeo and generic iframes: unsupported, with a reason
class SourceRouter {
  const SourceRouter({
    PlaybackEngineBuilder? nativeEngineBuilder,
    PlaybackEngineBuilder? youTubeEngineBuilder,
  })  : _nativeEngineBuilder = nativeEngineBuilder,
        _youTubeEngineBuilder = youTubeEngineBuilder;

  /// Both engines, with sensible defaults.
  ///
  /// [youTubeOrigin] is passed to [YouTubeEngine]; set it to your own https
  /// origin. [progressStore] persists resume positions for native playback.
  factory SourceRouter.standard({
    Uri? youTubeOrigin,
    PlaybackProgressStore? progressStore,
    bool secureSurface = false,
    int maxRetries = 0,
  }) {
    return SourceRouter(
      nativeEngineBuilder: () => NativeMediaEngine(
        controller: ZvNativeController(
          progressStore: progressStore,
          secureSurface: secureSurface,
          // ZvPlayerController owns connectivity recovery.
          maxRetries: maxRetries,
        ),
      ),
      youTubeEngineBuilder: () => YouTubeEngine(origin: youTubeOrigin),
    );
  }

  final PlaybackEngineBuilder? _nativeEngineBuilder;
  final PlaybackEngineBuilder? _youTubeEngineBuilder;

  bool get hasNativeEngine => _nativeEngineBuilder != null;

  bool get hasYouTubeEngine => _youTubeEngineBuilder != null;

  /// Decides which engine should play [source]. Pure: builds nothing.
  EngineSelection select(ZvMediaSource source) => selectForType(source.type);

  /// Decides from a classified type alone, for callers that have no full
  /// source yet (eligibility checks, logging, analytics).
  EngineSelection selectForType(ZvSourceType type) {
    if (type == ZvSourceType.youtube) {
      return EngineSelection(
        kind: PlaybackEngineKind.embedded,
        sourceType: type,
        reason: 'YouTube plays through the IFrame API under ZV Player controls',
      );
    }

    if (type.isNativePlayable) {
      return EngineSelection(
        kind: PlaybackEngineKind.native,
        sourceType: type,
        reason: '${type.name} is handled by the native media pipeline',
      );
    }

    return EngineSelection(
      kind: PlaybackEngineKind.unsupported,
      sourceType: type,
      reason: type.isEmbedded
          ? '${type.displayName} pages are not supported'
          : 'source could not be classified as playable media',
    );
  }

  /// Builds the engine for [source], or null when the source is unsupported or
  /// its engine has not been registered.
  ///
  /// The returned engine is **not** initialised: routing completes first, then
  /// the caller decides when to acquire resources.
  PlaybackEngine? createEngine(ZvMediaSource source) {
    switch (select(source).kind) {
      case PlaybackEngineKind.native:
        return _nativeEngineBuilder?.call();
      case PlaybackEngineKind.embedded:
        return _youTubeEngineBuilder?.call();
      case PlaybackEngineKind.unsupported:
        return null;
    }
  }
}
