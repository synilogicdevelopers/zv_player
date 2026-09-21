import 'package:flutter/foundation.dart';

/// Canonical QoE event names.
///
/// These are the hooks a future analytics backend subscribes to. Nothing here
/// sends anything anywhere by default - see [PlayerAnalyticsSink].
class PlayerEventName {
  const PlayerEventName._();

  static const String startup = 'startup';
  static const String play = 'play';
  static const String pause = 'pause';
  static const String seek = 'seek';
  static const String bufferStart = 'buffer_start';
  static const String bufferEnd = 'buffer_end';
  static const String qualityChange = 'quality_change';
  static const String subtitleChange = 'subtitle_change';
  static const String audioChange = 'audio_change';
  static const String speedChange = 'speed_change';
  static const String fullscreen = 'fullscreen';
  static const String pip = 'pip';
  static const String castStart = 'cast_start';
  static const String castEnd = 'cast_end';
  static const String error = 'error';
  static const String completed = 'completed';
  static const String progress = 'progress';

  static const List<String> all = <String>[
    startup,
    play,
    pause,
    seek,
    bufferStart,
    bufferEnd,
    qualityChange,
    subtitleChange,
    audioChange,
    speedChange,
    fullscreen,
    pip,
    castStart,
    castEnd,
    error,
    completed,
    progress,
  ];
}

/// One analytics-shaped observation about playback.
@immutable
class PlayerAnalyticsEvent {
  PlayerAnalyticsEvent({
    required this.name,
    this.contentId,
    this.properties = const <String, Object?>{},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String name;
  final String? contentId;
  final Map<String, Object?> properties;
  final DateTime timestamp;

  @override
  String toString() =>
      'PlayerAnalyticsEvent($name, content: $contentId, props: $properties)';
}

/// Receives player events. Implement this to forward to a QoE backend.
///
/// The default is [NoopAnalyticsSink]: the player never posts to a production
/// API on its own, so no fabricated traffic is generated before a real
/// analytics platform exists.
abstract class PlayerAnalyticsSink {
  void add(PlayerAnalyticsEvent event);
}

class NoopAnalyticsSink implements PlayerAnalyticsSink {
  const NoopAnalyticsSink();

  @override
  void add(PlayerAnalyticsEvent event) {}
}

/// Prints events in debug builds. Useful while wiring up a real sink.
class DebugLogAnalyticsSink implements PlayerAnalyticsSink {
  const DebugLogAnalyticsSink();

  @override
  void add(PlayerAnalyticsEvent event) {
    if (kDebugMode) {
      debugPrint('[zv_player] $event');
    }
  }
}

/// Fans one event out to several sinks.
class MultiAnalyticsSink implements PlayerAnalyticsSink {
  const MultiAnalyticsSink(this.sinks);

  final List<PlayerAnalyticsSink> sinks;

  @override
  void add(PlayerAnalyticsEvent event) {
    for (final PlayerAnalyticsSink sink in sinks) {
      sink.add(event);
    }
  }
}
