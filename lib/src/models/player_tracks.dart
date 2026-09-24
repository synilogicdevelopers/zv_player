import 'package:flutter/foundation.dart';

/// Canonical quality rungs, 240p to 4K.
///
/// Used only to *label* renditions that genuinely exist. Nothing here causes a
/// quality to be offered: a rung appears in the UI when the source or the
/// manifest actually contains it.
enum QualityRung {
  q240(240, '240p'),
  q360(360, '360p'),
  q480(480, '480p'),
  q720(720, '720p'),
  q1080(1080, '1080p'),
  q1440(1440, '1440p'),
  q2160(2160, '4K');

  const QualityRung(this.height, this.label);

  final int height;
  final String label;

  /// Nearest rung at or below [height], so an odd 576-line rendition is
  /// labelled 480p rather than invented as something it is not.
  static QualityRung? nearest(int? height) {
    if (height == null || height <= 0) return null;
    QualityRung? match;
    for (final QualityRung rung in QualityRung.values) {
      if (height >= rung.height) match = rung;
    }
    return match ?? QualityRung.q240;
  }

  /// Parses a backend label ("720p", "4K", "1080") into a rung when possible.
  static QualityRung? fromLabel(String? label) {
    if (label == null) return null;
    final String value = label.trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == '4k' || value == 'uhd' || value == '2160p') {
      return QualityRung.q2160;
    }
    if (value == '2k') return QualityRung.q1440;
    final RegExpMatch? match = RegExp(r'(\d{3,4})').firstMatch(value);
    if (match == null) return null;
    return nearest(int.tryParse(match.group(1)!));
  }
}

/// A selectable video rendition.
///
/// [isAuto] marks the single synthetic entry that hands selection back to the
/// native adaptive logic. It is only ever offered for HLS/DASH, because a set
/// of separate progressive URLs cannot adapt.
@immutable
class VideoQualityTrack {
  const VideoQualityTrack({
    required this.id,
    required this.label,
    this.width,
    this.height,
    this.bitrate,
    this.codec,
    this.frameRate,
    this.isAuto = false,
    this.isSelected = false,
    this.isVariant = false,
  });

  const VideoQualityTrack.auto({this.isSelected = true})
      : id = kAutoTrackId,
        label = 'Auto',
        width = null,
        height = null,
        bitrate = null,
        codec = null,
        frameRate = null,
        isAuto = true,
        isVariant = false;

  static const String kAutoTrackId = '__auto__';

  final String id;
  final String label;
  final int? width;
  final int? height;
  final int? bitrate;
  final String? codec;

  /// Frames per second when the media states it; null when it does not.
  final double? frameRate;
  final bool isAuto;
  final bool isSelected;

  /// True when selecting this means reloading a separate URL rather than
  /// switching representation inside one manifest.
  final bool isVariant;

  VideoQualityTrack copyWith({bool? isSelected}) => VideoQualityTrack(
        id: id,
        label: label,
        width: width,
        height: height,
        bitrate: bitrate,
        codec: codec,
        frameRate: frameRate,
        isAuto: isAuto,
        isSelected: isSelected ?? this.isSelected,
        isVariant: isVariant,
      );

  static VideoQualityTrack fromMap(Map<dynamic, dynamic> map) {
    final int? height = _asInt(map['height']);
    final String? rawLabel = map['label'] as String?;
    final String label = (rawLabel != null && rawLabel.isNotEmpty)
        ? rawLabel
        : (QualityRung.nearest(height)?.label ?? 'Track');
    return VideoQualityTrack(
      id: '${map['id']}',
      label: label,
      width: _asInt(map['width']),
      height: height,
      bitrate: _asInt(map['bitrate']),
      codec: map['codec'] as String?,
      frameRate: _asDouble(map['frameRate']),
      isSelected: map['isSelected'] == true,
    );
  }
}

/// One audio rendition. Populated from what the source actually contains - the
/// UI never synthesises languages.
@immutable
class AudioTrackOption {
  const AudioTrackOption({
    required this.id,
    required this.language,
    required this.label,
    this.codec,
    this.channels,
    this.bitrate,
    this.isSelected = false,
  });

  final String id;
  final String language;
  final String label;
  final String? codec;
  final int? channels;
  final int? bitrate;
  final bool isSelected;

  /// True for codecs in the Dolby family. Reported from the track's codec
  /// string only; it is never shown as decoration on content that lacks it.
  bool get isDolby {
    final String value = (codec ?? '').toLowerCase();
    return value.startsWith('ec-3') ||
        value.startsWith('ac-3') ||
        value.startsWith('ac-4') ||
        value.contains('dolby');
  }

  AudioTrackOption copyWith({bool? isSelected}) => AudioTrackOption(
        id: id,
        language: language,
        label: label,
        codec: codec,
        channels: channels,
        bitrate: bitrate,
        isSelected: isSelected ?? this.isSelected,
      );

  static AudioTrackOption fromMap(Map<dynamic, dynamic> map) {
    final String language = (map['language'] as String?) ?? '';
    final String? rawLabel = map['label'] as String?;
    return AudioTrackOption(
      id: '${map['id']}',
      language: language,
      label: (rawLabel != null && rawLabel.isNotEmpty)
          ? rawLabel
          : (language.isNotEmpty ? language : 'Audio'),
      codec: map['codec'] as String?,
      channels: _asInt(map['channels']),
      bitrate: _asInt(map['bitrate']),
      isSelected: map['isSelected'] == true,
    );
  }
}

/// One subtitle/caption rendition, whether in-manifest or side-loaded.
@immutable
class SubtitleTrackOption {
  const SubtitleTrackOption({
    required this.id,
    required this.language,
    required this.label,
    this.format,
    this.isExternal = false,
    this.isForced = false,
    this.isDefault = false,
    this.isSelected = false,
  });

  static const String kOffTrackId = '__off__';

  final String id;
  final String language;
  final String label;
  final String? format;
  final bool isExternal;

  /// Forced narrative subtitles - the ones a player shows even with subtitles
  /// off, for foreign-language dialogue. Only true when the media says so.
  final bool isForced;

  /// The track the media marks as its default.
  final bool isDefault;
  final bool isSelected;

  SubtitleTrackOption copyWith({bool? isSelected}) => SubtitleTrackOption(
        id: id,
        language: language,
        label: label,
        format: format,
        isExternal: isExternal,
        isForced: isForced,
        isDefault: isDefault,
        isSelected: isSelected ?? this.isSelected,
      );

  static SubtitleTrackOption fromMap(Map<dynamic, dynamic> map) {
    final String language = (map['language'] as String?) ?? '';
    final String? rawLabel = map['label'] as String?;
    return SubtitleTrackOption(
      id: '${map['id']}',
      language: language,
      label: (rawLabel != null && rawLabel.isNotEmpty)
          ? rawLabel
          : (language.isNotEmpty ? language : 'Subtitle'),
      format: map['format'] as String?,
      isExternal: map['isExternal'] == true,
      isForced: map['isForced'] == true,
      isDefault: map['isDefault'] == true,
      isSelected: map['isSelected'] == true,
    );
  }
}

/// Everything selectable for the loaded source.
@immutable
class PlayerTracks {
  const PlayerTracks({
    this.video = const <VideoQualityTrack>[],
    this.audio = const <AudioTrackOption>[],
    this.subtitles = const <SubtitleTrackOption>[],
  });

  final List<VideoQualityTrack> video;
  final List<AudioTrackOption> audio;
  final List<SubtitleTrackOption> subtitles;

  /// Quality is worth showing only when there is a real choice.
  /// The label to show for [track] within this set.
  ///
  /// Renditions can share a resolution - two 1080p variants at different
  /// bitrates are ordinary in an HLS ladder - and repeating the same word
  /// gives the viewer nothing to choose between. Only real metadata
  /// disambiguates: bitrate first, then frame rate. When the media offers
  /// nothing to tell them apart the label is left alone rather than decorated
  /// with an invented number.
  String videoLabelFor(VideoQualityTrack track) {
    final bool duplicated =
        video.where((VideoQualityTrack t) => t.label == track.label).length > 1;
    if (!duplicated) return track.label;
    final int? bitrate = track.bitrate;
    if (bitrate != null && bitrate > 0) {
      // Mbps reads better, but neighbouring rungs can round to the same
      // figure (8.03 and 8.00 both read "8.0"). When that happens, exact kbps
      // keeps every entry distinguishable without inventing anything.
      final String mbps =
          '${track.label} · ${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
      final bool rounds = video
              .where((VideoQualityTrack t) =>
                  t.bitrate != null &&
                  t.bitrate! > 0 &&
                  '${t.label} · ${(t.bitrate! / 1000000).toStringAsFixed(1)} Mbps' ==
                      mbps)
              .length >
          1;
      if (bitrate >= 1000000 && !rounds) return mbps;
      return '${track.label} · ${(bitrate / 1000).round()} kbps';
    }
    final double? fps = track.frameRate;
    if (fps != null && fps > 0) return '${track.label} · ${fps.round()} fps';
    return track.label;
  }

  /// "Forced" / "Default" only where the media itself says so.
  static String? subtitleNoteFor(SubtitleTrackOption track) {
    if (track.isForced) return 'Forced';
    if (track.isDefault) return 'Default';
    return null;
  }

  bool get hasQualityChoice => video.length > 1;
  bool get hasAudioChoice => audio.length > 1;
  bool get hasSubtitles => subtitles.isNotEmpty;

  VideoQualityTrack? get selectedVideo =>
      _firstSelected<VideoQualityTrack>(video, (t) => t.isSelected);
  AudioTrackOption? get selectedAudio =>
      _firstSelected<AudioTrackOption>(audio, (t) => t.isSelected);
  SubtitleTrackOption? get selectedSubtitle =>
      _firstSelected<SubtitleTrackOption>(subtitles, (t) => t.isSelected);

  static T? _firstSelected<T>(List<T> items, bool Function(T) test) {
    for (final T item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  PlayerTracks copyWith({
    List<VideoQualityTrack>? video,
    List<AudioTrackOption>? audio,
    List<SubtitleTrackOption>? subtitles,
  }) {
    return PlayerTracks(
      video: video ?? this.video,
      audio: audio ?? this.audio,
      subtitles: subtitles ?? this.subtitles,
    );
  }
}

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
