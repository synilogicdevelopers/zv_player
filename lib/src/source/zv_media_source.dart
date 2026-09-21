import 'package:flutter/foundation.dart';

/// How the media is delivered.
///
/// Classification happens once, up front, and decides **which engine plays the
/// source at all** - not merely which native factory to use. Anything that is
/// not [isNativePlayable] must never reach Media3 or AVPlayer: handing a
/// YouTube watch page to a native media pipeline produces an
/// `UnrecognizedInputFormatException`, not a video.
enum ZvSourceType {
  /// A single self-contained file served over HTTP (mp4, mkv, webm ...).
  progressive,

  /// HLS manifest (.m3u8). Native player performs adaptive selection.
  hls,

  /// MPEG-DASH manifest (.mpd). Native player performs adaptive selection.
  dash,

  /// A file already on the device.
  local,

  /// A YouTube watch/share URL. Playable only through YouTube's own embed.
  youtube,

  /// A Vimeo URL. Playable only through Vimeo's embed.
  vimeo,

  /// Any other page/iframe that must run inside a web view.
  embedded,

  /// Genuinely unclassifiable (empty or malformed). Never sent to native.
  unknown;

  /// Whether the native media pipeline can play this.
  ///
  /// The embed types and [unknown] are deliberately excluded: the player
  /// refuses them with a clear error instead of failing deep inside a decoder.
  bool get isNativePlayable =>
      this == ZvSourceType.progressive ||
      this == ZvSourceType.hls ||
      this == ZvSourceType.dash ||
      this == ZvSourceType.local;

  /// Whether this source belongs to a web-view based player.
  bool get isEmbedded =>
      this == ZvSourceType.youtube ||
      this == ZvSourceType.vimeo ||
      this == ZvSourceType.embedded;

  /// Human-readable platform name, for error messages.
  String get displayName {
    switch (this) {
      case ZvSourceType.youtube:
        return 'YouTube';
      case ZvSourceType.vimeo:
        return 'Vimeo';
      case ZvSourceType.embedded:
        return 'an embedded player';
      default:
        return 'this source';
    }
  }
}

/// DRM schemes the bridge is shaped to carry.
///
/// Nothing here is implemented today. It exists so a licence server can be
/// added later without changing the source model, the bridge, or the UI.
enum DrmScheme { none, widevine, fairplay, playready, clearKey }

/// Future DRM configuration carried by a [ZvMediaSource].
///
/// DRM is not implemented yet: passing a non-null config does not protect
/// content - the native layer reports an unsupported-DRM error instead of
/// pretending the stream is secured.
@immutable
class DrmConfig {
  const DrmConfig({
    required this.scheme,
    this.licenseUrl,
    this.certificateUrl,
    this.headers = const <String, String>{},
    this.token,
    this.allowOfflinePersistence = false,
    this.securityPolicy,
  });

  final DrmScheme scheme;

  /// Licence acquisition endpoint (Widevine proxy / FairPlay KSM).
  final String? licenseUrl;

  /// FairPlay application certificate. Unused by Widevine.
  final String? certificateUrl;

  /// Extra headers for licence requests (auth, entitlement).
  final Map<String, String> headers;

  /// Entitlement token, when the licence server expects one out of band.
  final String? token;

  /// Whether a persistable licence should be requested (offline playback).
  final bool allowOfflinePersistence;

  /// Opaque policy identifier, e.g. an HDCP or output-protection level.
  final String? securityPolicy;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'scheme': scheme.name,
        'licenseUrl': licenseUrl,
        'certificateUrl': certificateUrl,
        'headers': headers,
        'token': token,
        'allowOfflinePersistence': allowOfflinePersistence,
        'securityPolicy': securityPolicy,
      };
}

/// A subtitle file that lives outside the manifest.
///
/// The current backend serves side-loaded subtitle files, so these are passed
/// to the native player as extra text tracks and appear in the same track list
/// as any in-manifest subtitles.
@immutable
class ExternalSubtitle {
  const ExternalSubtitle({
    required this.uri,
    required this.language,
    required this.label,
    this.format = 'auto',
    this.isDefault = false,
  });

  final String uri;

  /// BCP-47 where the backend provides it; may be a plain name like "English".
  final String language;
  final String label;

  /// 'vtt', 'srt', 'ttml' or 'auto' to let the native layer infer it.
  final String format;
  final bool isDefault;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uri': uri,
        'language': language,
        'label': label,
        'format': format,
        'isDefault': isDefault,
      };
}

/// One manually configured rendition of the same content.
///
/// This is what today's backend actually provides: separate URLs per quality.
/// It is **not** adaptive bitrate - switching variants reloads the source at
/// the same position. Real ABR arrives with HLS/DASH, where the native player
/// selects between representations inside one manifest.
@immutable
class ZvSourceVariant {
  const ZvSourceVariant({
    required this.id,
    required this.label,
    required this.uri,
    this.height,
    this.type = ZvSourceType.unknown,
  });

  final String id;

  /// Label exactly as the backend supplies it ("720p", "4K", "default").
  final String label;
  final String uri;

  /// Vertical resolution when known; drives ordering and the quality ladder.
  final int? height;
  final ZvSourceType type;

  ZvSourceType get resolvedType =>
      type == ZvSourceType.unknown ? ZvMediaSource.detectType(uri) : type;
}

/// Everything the player needs to open one piece of content.
///
/// Deliberately free of today's API shape: callers map their own models into
/// this, so a backend change never reaches the player or its UI.
@immutable
class ZvMediaSource {
  const ZvMediaSource({
    required this.uri,
    required this.type,
    this.title = '',
    this.subtitleText = '',
    this.contentId,
    this.episodeId,
    this.headers = const <String, String>{},
    this.duration,
    this.startPosition,
    this.drm,
    this.preferredAudioLanguage,
    this.preferredSubtitleLanguage,
    this.variants = const <ZvSourceVariant>[],
    this.externalSubtitles = const <ExternalSubtitle>[],
    this.posterUrl,
    this.isLive = false,
    this.metadata = const <String, dynamic>{},
  });

  /// Builds a source, inferring [type] from the URI unless [declaredType]
  /// resolves to something known.
  factory ZvMediaSource.detect({
    required String uri,
    String? declaredType,
    String title = '',
    String subtitleText = '',
    String? contentId,
    String? episodeId,
    Map<String, String> headers = const <String, String>{},
    Duration? duration,
    Duration? startPosition,
    DrmConfig? drm,
    String? preferredAudioLanguage,
    String? preferredSubtitleLanguage,
    List<ZvSourceVariant> variants = const <ZvSourceVariant>[],
    List<ExternalSubtitle> externalSubtitles = const <ExternalSubtitle>[],
    String? posterUrl,
    bool isLive = false,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    return ZvMediaSource(
      uri: uri,
      type: detectType(uri, declaredType: declaredType),
      title: title,
      subtitleText: subtitleText,
      contentId: contentId,
      episodeId: episodeId,
      headers: headers,
      duration: duration,
      startPosition: startPosition,
      drm: drm,
      preferredAudioLanguage: preferredAudioLanguage,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      variants: variants,
      externalSubtitles: externalSubtitles,
      posterUrl: posterUrl,
      isLive: isLive,
      metadata: metadata,
    );
  }

  final String uri;
  final ZvSourceType type;
  final String title;

  /// Secondary line under the title (episode name, channel name).
  final String subtitleText;

  /// Stable id used for resume bookkeeping. No resume happens without it.
  final String? contentId;
  final String? episodeId;
  final Map<String, String> headers;
  final Duration? duration;
  final Duration? startPosition;
  final DrmConfig? drm;
  final String? preferredAudioLanguage;
  final String? preferredSubtitleLanguage;
  final List<ZvSourceVariant> variants;
  final List<ExternalSubtitle> externalSubtitles;
  final String? posterUrl;
  final bool isLive;
  final Map<String, dynamic> metadata;

  bool get isAdaptive => type == ZvSourceType.hls || type == ZvSourceType.dash;

  /// True when quality must be switched by reloading a different URL, which is
  /// the case for every progressive source the current backend serves.
  bool get hasManualVariants => variants.length > 1;

  /// Classifies a source from the backend's declared type and the URI itself.
  ///
  /// Order matters, and it is not "extension first":
  ///
  /// 1. A declared embed type wins - the backend knows `YouTube` means YouTube.
  ///    Matching is case-insensitive, because the API sends `YouTube` while the
  ///    app's own constant is `youtube`; comparing those directly is how a
  ///    watch URL previously reached Media3 and failed to parse.
  /// 2. The URL host is then checked regardless of what was declared, so a
  ///    mislabelled or unlabelled YouTube/Vimeo link still cannot reach the
  ///    native pipeline.
  /// 3. Only then are manifest and container extensions considered.
  static ZvSourceType detectType(String uri, {String? declaredType}) {
    final String raw = uri.trim();
    final String declared = (declaredType ?? '').trim().toLowerCase();

    // 1. Declared type, case-insensitive.
    switch (declared) {
      case 'youtube':
      case 'you_tube':
      case 'yt':
        return ZvSourceType.youtube;
      case 'vimeo':
        return ZvSourceType.vimeo;
      case 'embedded':
      case 'embed':
      case 'iframe':
      case 'web':
      case 'webview':
        return ZvSourceType.embedded;
      case 'hls':
      case 'm3u8':
      case 'application/x-mpegurl':
        return ZvSourceType.hls;
      case 'dash':
      case 'mpd':
        return ZvSourceType.dash;
      case 'file':
      case 'local':
      case 'offline':
      case 'download':
        return ZvSourceType.local;
    }

    if (raw.isEmpty) return ZvSourceType.unknown;

    // 2. Host check, whatever the backend claimed.
    final String lower = raw.toLowerCase();
    if (lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube-nocookie.com')) {
      return ZvSourceType.youtube;
    }
    if (lower.contains('vimeo.com')) return ZvSourceType.vimeo;

    final bool looksLocal = raw.startsWith('file://') ||
        raw.startsWith('/') ||
        (!raw.contains('://') && raw.contains('.'));

    // 3. Extensions, ignoring query and fragment.
    String path = lower;
    final int queryIndex = path.indexOf('?');
    if (queryIndex >= 0) path = path.substring(0, queryIndex);
    final int hashIndex = path.indexOf('#');
    if (hashIndex >= 0) path = path.substring(0, hashIndex);

    if (path.endsWith('.m3u8')) return ZvSourceType.hls;
    if (path.endsWith('.mpd')) return ZvSourceType.dash;

    if (looksLocal) return ZvSourceType.local;

    const List<String> progressiveExtensions = <String>[
      '.mp4',
      '.m4v',
      '.mkv',
      '.webm',
      '.mov',
      '.ts',
      '.avi',
      '.3gp',
      '.flv',
    ];
    for (final String extension in progressiveExtensions) {
      if (path.endsWith(extension)) return ZvSourceType.progressive;
    }

    // An http(s) URL that is not an embed and not a manifest: treat as
    // progressive and let the native extractor sniff the container. If it
    // cannot, the player surfaces a clean unsupported-format error.
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return ZvSourceType.progressive;
    }

    return ZvSourceType.unknown;
  }

  ZvMediaSource copyWith({
    String? uri,
    ZvSourceType? type,
    Duration? startPosition,
    String? preferredAudioLanguage,
    String? preferredSubtitleLanguage,
  }) {
    return ZvMediaSource(
      uri: uri ?? this.uri,
      type: type ?? this.type,
      title: title,
      subtitleText: subtitleText,
      contentId: contentId,
      episodeId: episodeId,
      headers: headers,
      duration: duration,
      startPosition: startPosition ?? this.startPosition,
      drm: drm,
      preferredAudioLanguage:
          preferredAudioLanguage ?? this.preferredAudioLanguage,
      preferredSubtitleLanguage:
          preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      variants: variants,
      externalSubtitles: externalSubtitles,
      posterUrl: posterUrl,
      isLive: isLive,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uri': uri,
        'type': type.name,
        'title': title,
        'headers': headers,
        'startPositionMs': startPosition?.inMilliseconds ?? 0,
        'drm': drm?.toMap(),
        'preferredAudioLanguage': preferredAudioLanguage,
        'preferredSubtitleLanguage': preferredSubtitleLanguage,
        'externalSubtitles':
            externalSubtitles.map((ExternalSubtitle s) => s.toMap()).toList(),
        'isLive': isLive,
      };
}
