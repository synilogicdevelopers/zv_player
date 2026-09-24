import 'package:flutter/foundation.dart';

/// What a marked stretch of a title is.
///
/// Only kinds the player can act on are listed; anything else a backend sends
/// is dropped rather than guessed at.
enum PlaybackMarkerKind {
  /// Opening titles. "Skip Intro".
  intro,

  /// "Previously on…". "Skip Recap".
  recap,

  /// Closing credits, where an OTT app usually offers the next episode.
  outro;

  static PlaybackMarkerKind? parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'intro':
      case 'opening':
        return PlaybackMarkerKind.intro;
      case 'recap':
      case 'previously':
        return PlaybackMarkerKind.recap;
      case 'outro':
      case 'credits':
      case 'ending':
        return PlaybackMarkerKind.outro;
      default:
        return null;
    }
  }
}

/// One marked stretch of the timeline, supplied by the catalogue.
///
/// The player never invents these. A title with no marker data simply has no
/// skip control - there is no default "intro is the first 90 seconds" rule
/// anywhere in this package.
@immutable
class PlaybackMarker {
  const PlaybackMarker({
    required this.kind,
    required this.start,
    required this.end,
    this.label,
  });

  final PlaybackMarkerKind kind;
  final Duration start;
  final Duration end;

  /// Shown on the control when the backend supplies its own wording;
  /// otherwise the app picks the copy, so this package ships no strings.
  final String? label;

  Duration get duration => end - start;

  /// A marker the player can honour: inside the timeline, and a real span.
  ///
  /// [contentDuration] is optional because a live or not-yet-measured source
  /// has none; the rest of the checks still apply.
  bool isValid({Duration? contentDuration}) {
    if (start.isNegative || end.isNegative) return false;
    if (end <= start) return false;
    if (contentDuration != null &&
        contentDuration > Duration.zero &&
        start >= contentDuration) {
      return false;
    }
    return true;
  }

  bool contains(Duration position) => position >= start && position < end;

  /// Parses one marker from a backend map, returning null for anything that
  /// is not a usable marker. Times are milliseconds or seconds:
  /// `startMs`/`endMs` win, `start`/`end` are read as seconds.
  static PlaybackMarker? fromMap(Map<dynamic, dynamic> map) {
    final PlaybackMarkerKind? kind = PlaybackMarkerKind.parse(
        map['type'] as String? ?? map['kind'] as String?);
    if (kind == null) return null;
    final Duration? start = _readDuration(map, 'startMs', 'start');
    final Duration? end = _readDuration(map, 'endMs', 'end');
    if (start == null || end == null) return null;
    final String? label = (map['label'] as String?)?.trim();
    final PlaybackMarker marker = PlaybackMarker(
      kind: kind,
      start: start,
      end: end,
      label: (label == null || label.isEmpty) ? null : label,
    );
    return marker.isValid() ? marker : null;
  }

  static Duration? _readDuration(
      Map<dynamic, dynamic> map, String msKey, String secondsKey) {
    final Object? ms = map[msKey];
    if (ms is num) return Duration(milliseconds: ms.round());
    final Object? seconds = map[secondsKey];
    if (seconds is num) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackMarker &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, start, end, label);

  @override
  String toString() => 'PlaybackMarker(${kind.name} $start-$end)';
}

/// The markers for one title, already filtered to the usable ones.
@immutable
class PlaybackMarkers {
  const PlaybackMarkers._(this.all);

  /// Empty is the normal case: most catalogues supply no markers at all.
  static const PlaybackMarkers none = PlaybackMarkers._(<PlaybackMarker>[]);

  final List<PlaybackMarker> all;

  bool get isEmpty => all.isEmpty;
  bool get isNotEmpty => all.isNotEmpty;

  /// Keeps only markers the player can honour, so nothing downstream has to
  /// re-check them before drawing a control.
  factory PlaybackMarkers.from(Iterable<PlaybackMarker> markers,
      {Duration? contentDuration}) {
    final List<PlaybackMarker> valid = markers
        .where(
            (PlaybackMarker m) => m.isValid(contentDuration: contentDuration))
        .toList()
      ..sort(
          (PlaybackMarker a, PlaybackMarker b) => a.start.compareTo(b.start));
    return valid.isEmpty ? none : PlaybackMarkers._(valid);
  }

  /// Parses a backend list, dropping every entry that is not a usable marker.
  factory PlaybackMarkers.fromList(Object? raw, {Duration? contentDuration}) {
    if (raw is! List) return none;
    final List<PlaybackMarker> parsed = <PlaybackMarker>[];
    for (final Object? entry in raw) {
      if (entry is Map) {
        final PlaybackMarker? marker = PlaybackMarker.fromMap(entry);
        if (marker != null) parsed.add(marker);
      }
    }
    return PlaybackMarkers.from(parsed, contentDuration: contentDuration);
  }

  /// The marker covering [position], if any - what a "Skip …" control binds to.
  PlaybackMarker? at(Duration position, {PlaybackMarkerKind? kind}) {
    for (final PlaybackMarker marker in all) {
      if (kind != null && marker.kind != kind) continue;
      if (marker.contains(position)) return marker;
    }
    return null;
  }

  PlaybackMarker? firstOf(PlaybackMarkerKind kind) {
    for (final PlaybackMarker marker in all) {
      if (marker.kind == kind) return marker;
    }
    return null;
  }
}
