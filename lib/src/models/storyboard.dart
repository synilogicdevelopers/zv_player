import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// Where one preview frame lives inside a storyboard sheet.
@immutable
class StoryboardFrame {
  const StoryboardFrame({
    required this.url,
    required this.source,
    required this.index,
  });

  /// The sheet to draw from.
  final String url;

  /// The crop within that sheet, in sheet pixels.
  final Rect source;

  /// Which tile this is, counted from the start of the whole storyboard.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is StoryboardFrame &&
      other.url == url &&
      other.source == source &&
      other.index == index;

  @override
  int get hashCode => Object.hash(url, source, index);

  @override
  String toString() => 'StoryboardFrame($url @$index $source)';
}

/// Sprite-sheet preview frames for scrubbing, as an OTT packager produces them.
///
/// This is metadata the *content* carries; no engine derives it and nothing is
/// fetched to discover it. A source without it keeps the timestamp-only
/// preview, which is the honest behaviour for a provider that publishes no
/// storyboard - YouTube among them.
///
/// [urlTemplate] may address a single sheet, or several when the tiles do not
/// fit on one: `{index}` is replaced by the zero-based sheet number.
@immutable
class StoryboardMetadata {
  const StoryboardMetadata({
    required this.urlTemplate,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
    required this.columns,
    required this.rows,
    required this.interval,
    this.startTime = Duration.zero,
    this.duration,
    this.vttUrl,
  });

  /// Sheet address. Contains `{index}` when the storyboard spans sheets.
  final String urlTemplate;

  /// One tile's size in sheet pixels.
  final int thumbnailWidth;
  final int thumbnailHeight;

  /// Tile grid on a single sheet.
  final int columns;
  final int rows;

  /// How much play time one tile covers.
  final Duration interval;

  /// Play time the first tile corresponds to.
  final Duration startTime;

  /// Play time the storyboard covers, when the packager states it.
  final Duration? duration;

  /// WebVTT index, for packagers that publish one. Held for callers that
  /// prefer it; this class does not fetch it.
  final String? vttUrl;

  int get tilesPerSheet => columns * rows;

  /// Whether this describes a storyboard that can actually be drawn.
  bool get isValid =>
      urlTemplate.trim().isNotEmpty &&
      thumbnailWidth > 0 &&
      thumbnailHeight > 0 &&
      columns > 0 &&
      rows > 0 &&
      interval > Duration.zero;

  /// The frame covering [position], or null when this metadata cannot be
  /// honoured - an invalid descriptor, or a position outside what it covers.
  /// Callers fall back to the timestamp preview on null.
  StoryboardFrame? frameAt(Duration position) {
    if (!isValid) return null;
    final Duration offset = position - startTime;
    if (offset.isNegative) return null;
    final Duration? covered = duration;
    if (covered != null && covered > Duration.zero && offset >= covered) {
      return null;
    }
    final int index = offset.inMilliseconds ~/ interval.inMilliseconds;
    final int sheet = index ~/ tilesPerSheet;
    final int withinSheet = index % tilesPerSheet;
    final int column = withinSheet % columns;
    final int row = withinSheet ~/ columns;
    return StoryboardFrame(
      url: urlTemplate.replaceAll('{index}', '$sheet'),
      source: Rect.fromLTWH(
        (column * thumbnailWidth).toDouble(),
        (row * thumbnailHeight).toDouble(),
        thumbnailWidth.toDouble(),
        thumbnailHeight.toDouble(),
      ),
      index: index,
    );
  }

  /// Reads a backend descriptor, returning null unless it is usable.
  static StoryboardMetadata? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final String? url =
        (map['url'] as String?) ?? (map['urlTemplate'] as String?);
    if (url == null || url.trim().isEmpty) return null;
    final StoryboardMetadata metadata = StoryboardMetadata(
      urlTemplate: url.trim(),
      thumbnailWidth: _int(map['thumbnailWidth'] ?? map['width']) ?? 0,
      thumbnailHeight: _int(map['thumbnailHeight'] ?? map['height']) ?? 0,
      columns: _int(map['columns'] ?? map['cols']) ?? 0,
      rows: _int(map['rows']) ?? 0,
      interval: _duration(map['intervalMs'], map['interval']) ?? Duration.zero,
      startTime:
          _duration(map['startTimeMs'], map['startTime']) ?? Duration.zero,
      duration: _duration(map['durationMs'], map['duration']),
      vttUrl: (map['vttUrl'] as String?)?.trim(),
    );
    return metadata.isValid ? metadata : null;
  }

  static int? _int(Object? value) =>
      value is num ? value.round() : int.tryParse('$value');

  static Duration? _duration(Object? ms, Object? seconds) {
    if (ms is num) return Duration(milliseconds: ms.round());
    if (seconds is num) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is StoryboardMetadata &&
      other.urlTemplate == urlTemplate &&
      other.thumbnailWidth == thumbnailWidth &&
      other.thumbnailHeight == thumbnailHeight &&
      other.columns == columns &&
      other.rows == rows &&
      other.interval == interval &&
      other.startTime == startTime &&
      other.duration == duration &&
      other.vttUrl == vttUrl;

  @override
  int get hashCode => Object.hash(urlTemplate, thumbnailWidth, thumbnailHeight,
      columns, rows, interval, startTime, duration, vttUrl);
}
