import 'package:flutter/foundation.dart';

/// A saved playback position.
@immutable
class PlaybackProgress {
  const PlaybackProgress({
    required this.contentId,
    required this.position,
    required this.duration,
  });

  final String contentId;
  final Duration position;
  final Duration duration;

  double get fraction {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Where resume positions live.
///
/// The app already has watch-progress APIs and a Hive store; implement this to
/// bridge to them. The player never invents endpoints of its own - if nothing
/// is supplied it falls back to [InMemoryProgressStore], which is per-session.
abstract class PlaybackProgressStore {
  Future<PlaybackProgress?> load(String contentId);

  Future<void> save(PlaybackProgress progress);

  Future<void> clear(String contentId);
}

/// Session-scoped fallback. Enough to make resume work inside one run of the
/// app, and honest about not persisting anything.
class InMemoryProgressStore implements PlaybackProgressStore {
  final Map<String, PlaybackProgress> _entries = <String, PlaybackProgress>{};

  @override
  Future<PlaybackProgress?> load(String contentId) async => _entries[contentId];

  @override
  Future<void> save(PlaybackProgress progress) async {
    _entries[progress.contentId] = progress;
  }

  @override
  Future<void> clear(String contentId) async {
    _entries.remove(contentId);
  }
}

/// Rules for what is worth remembering.
///
/// Kept separate from the controller so they can be unit-tested directly and
/// tuned without touching playback code.
class ResumePolicy {
  const ResumePolicy({
    this.minimumPosition = const Duration(seconds: 10),
    this.completionThreshold = 0.95,
    this.minimumRemaining = const Duration(seconds: 15),
    this.saveInterval = const Duration(seconds: 5),
  });

  /// Below this, a position is noise rather than progress.
  final Duration minimumPosition;

  /// At or beyond this fraction the item counts as finished.
  final double completionThreshold;

  /// Too close to the end to be a useful resume point.
  final Duration minimumRemaining;

  /// How often progress is written while playing.
  final Duration saveInterval;

  bool shouldSave(Duration position, Duration duration) {
    if (position < minimumPosition) return false;
    if (duration <= Duration.zero) return false;
    if (duration - position < minimumRemaining) return false;
    return position.inMilliseconds / duration.inMilliseconds <
        completionThreshold;
  }

  bool isComplete(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    if (duration - position < minimumRemaining) return true;
    return position.inMilliseconds / duration.inMilliseconds >=
        completionThreshold;
  }

  /// A stored position is only restored when it still means something.
  bool shouldResumeFrom(Duration position, Duration duration) {
    if (position < minimumPosition) return false;
    if (duration <= Duration.zero) return true;
    return !isComplete(position, duration);
  }
}
