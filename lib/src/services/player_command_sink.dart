import '../models/player_tracks.dart';

/// Everything the player chrome can ask of a playback session.
///
/// Exists so one set of controls can drive either the native controller or the
/// universal controller. The controls take a sink and a capability set; they
/// never hold a concrete controller and never branch on engine.
abstract class PlayerCommandSink {
  Future<void> play();

  Future<void> pause();

  Future<void> togglePlayPause();

  Future<void> seekTo(Duration position);

  Future<void> seekBy(Duration delta);

  /// Moves the scrubber while dragging, without committing a seek.
  void previewSeek(Duration position);

  Future<void> setSpeed(double speed);

  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  Future<void> toggleMute();

  Future<void> selectQuality(VideoQualityTrack track);

  Future<void> selectAudioTrack(AudioTrackOption track);

  /// Null turns subtitles off.
  Future<void> selectSubtitle(SubtitleTrackOption? track);

  /// Re-attempts playback after an error.
  Future<void> retry();
}
