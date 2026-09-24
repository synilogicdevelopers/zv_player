import 'package:flutter/foundation.dart';

/// What a playback engine can actually do for the source it is playing.
///
/// This exists so the player UI never has to ask "is this YouTube?". It asks
/// the engine what is possible and renders accordingly. Two rules:
///
/// 1. A capability is true only when the engine really implements it for the
///    current source. Reporting `canSetSpeed` for a web player whose page
///    exposes no rate control would put a control on screen that silently does
///    nothing.
/// 2. Capability is not availability. `canSelectQuality` means the engine can
///    switch renditions *if the media has any*; whether renditions exist is a
///    property of the source and is reported through the track lists.

/// Rates the native pipeline accepts. Embeds may accept a shorter list.
const List<double> kDefaultPlaybackSpeeds = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
];

@immutable
class EngineCapabilities {
  const EngineCapabilities({
    this.canPlayPause = true,
    this.canSeek = false,
    this.canSetSpeed = false,
    this.speeds = const <double>[],
    this.canSetVolume = false,
    this.canMute = false,
    this.canSelectQuality = false,
    this.supportsAdaptiveBitrate = false,
    this.canSelectAudioTrack = false,
    this.canSelectSubtitle = false,
    this.supportsPictureInPicture = false,
    this.supportsMiniPlayer = false,
    this.supportsFullscreen = true,
    this.supportsCast = false,
    this.reportsBufferedPosition = false,
    this.reportsTrackList = false,
    this.supportsDrm = false,
    this.canChangeVideoFit = false,
  });

  /// Everything a native media pipeline can drive. Track *availability* still
  /// comes from what the media contains.
  const EngineCapabilities.nativeMedia()
      : canPlayPause = true,
        canSeek = true,
        canSetSpeed = true,
        speeds = kDefaultPlaybackSpeeds,
        canSetVolume = true,
        canMute = true,
        canSelectQuality = true,
        supportsAdaptiveBitrate = true,
        canSelectAudioTrack = true,
        canSelectSubtitle = true,
        supportsPictureInPicture = true,
        supportsMiniPlayer = true,
        supportsFullscreen = true,
        supportsCast = true,
        reportsBufferedPosition = true,
        reportsTrackList = true,
        supportsDrm = false,
        canChangeVideoFit = true;

  final bool canPlayPause;
  final bool canSeek;
  final bool canSetSpeed;

  /// The rates this engine really accepts. Empty when speed is unsupported;
  /// the menu renders these rather than a hard-coded ladder.
  final List<double> speeds;
  final bool canSetVolume;
  final bool canMute;
  final bool canSelectQuality;

  /// Whether the engine itself adapts the rendition to the network, as a
  /// native player does for HLS/DASH. False for an engine that can only switch
  /// by reloading a different URL, and for a provider embed that decides for
  /// itself.
  final bool supportsAdaptiveBitrate;
  final bool canSelectAudioTrack;
  final bool canSelectSubtitle;
  final bool supportsPictureInPicture;
  final bool supportsMiniPlayer;
  final bool supportsFullscreen;
  final bool supportsCast;

  /// False when the engine reports position but not how much is buffered, so
  /// the scrubber can omit the buffered bar instead of drawing a wrong one.
  final bool reportsBufferedPosition;

  /// Whether the engine enumerates video/audio/text tracks at all.
  final bool reportsTrackList;

  /// Always false today: no DRM is implemented on any engine.
  final bool supportsDrm;

  /// Whether the engine can switch between fit and crop-to-fill without
  /// distorting the picture.
  final bool canChangeVideoFit;

  EngineCapabilities copyWith({
    bool? canPlayPause,
    bool? canSeek,
    bool? canSetSpeed,
    List<double>? speeds,
    bool? canSetVolume,
    bool? canMute,
    bool? canSelectQuality,
    bool? supportsAdaptiveBitrate,
    bool? canSelectAudioTrack,
    bool? canSelectSubtitle,
    bool? supportsPictureInPicture,
    bool? supportsMiniPlayer,
    bool? supportsFullscreen,
    bool? supportsCast,
    bool? reportsBufferedPosition,
    bool? reportsTrackList,
    bool? supportsDrm,
    bool? canChangeVideoFit,
  }) {
    return EngineCapabilities(
      canPlayPause: canPlayPause ?? this.canPlayPause,
      canSeek: canSeek ?? this.canSeek,
      canSetSpeed: canSetSpeed ?? this.canSetSpeed,
      speeds: speeds ?? this.speeds,
      canSetVolume: canSetVolume ?? this.canSetVolume,
      canMute: canMute ?? this.canMute,
      canSelectQuality: canSelectQuality ?? this.canSelectQuality,
      supportsAdaptiveBitrate:
          supportsAdaptiveBitrate ?? this.supportsAdaptiveBitrate,
      canSelectAudioTrack: canSelectAudioTrack ?? this.canSelectAudioTrack,
      canSelectSubtitle: canSelectSubtitle ?? this.canSelectSubtitle,
      supportsPictureInPicture:
          supportsPictureInPicture ?? this.supportsPictureInPicture,
      supportsMiniPlayer: supportsMiniPlayer ?? this.supportsMiniPlayer,
      supportsFullscreen: supportsFullscreen ?? this.supportsFullscreen,
      supportsCast: supportsCast ?? this.supportsCast,
      reportsBufferedPosition:
          reportsBufferedPosition ?? this.reportsBufferedPosition,
      reportsTrackList: reportsTrackList ?? this.reportsTrackList,
      supportsDrm: supportsDrm ?? this.supportsDrm,
      canChangeVideoFit: canChangeVideoFit ?? this.canChangeVideoFit,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EngineCapabilities &&
        other.canPlayPause == canPlayPause &&
        other.canSeek == canSeek &&
        other.canSetSpeed == canSetSpeed &&
        listEquals(other.speeds, speeds) &&
        other.canSetVolume == canSetVolume &&
        other.canMute == canMute &&
        other.canSelectQuality == canSelectQuality &&
        other.supportsAdaptiveBitrate == supportsAdaptiveBitrate &&
        other.canSelectAudioTrack == canSelectAudioTrack &&
        other.canSelectSubtitle == canSelectSubtitle &&
        other.supportsPictureInPicture == supportsPictureInPicture &&
        other.supportsMiniPlayer == supportsMiniPlayer &&
        other.supportsFullscreen == supportsFullscreen &&
        other.supportsCast == supportsCast &&
        other.reportsBufferedPosition == reportsBufferedPosition &&
        other.reportsTrackList == reportsTrackList &&
        other.supportsDrm == supportsDrm &&
        other.canChangeVideoFit == canChangeVideoFit;
  }

  @override
  int get hashCode => Object.hash(
        canPlayPause,
        canSeek,
        canSetSpeed,
        Object.hashAll(speeds),
        canSetVolume,
        canMute,
        canSelectQuality,
        supportsAdaptiveBitrate,
        canSelectAudioTrack,
        canSelectSubtitle,
        supportsPictureInPicture,
        supportsMiniPlayer,
        supportsFullscreen,
        supportsCast,
        reportsBufferedPosition,
        reportsTrackList,
        supportsDrm,
        canChangeVideoFit,
      );
}
