import 'package:flutter/foundation.dart';

import '../models/playback_markers.dart';
import '../models/storyboard.dart';

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
    this.storyboard,
    this.markers = PlaybackMarkers.none,
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
    StoryboardMetadata? storyboard,
    PlaybackMarkers markers = PlaybackMarkers.none,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final String playable = normalizeUri(uri);
    return ZvMediaSource(
      uri: playable,
      type: detectType(playable, declaredType: declaredType),
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
      storyboard: storyboard,
      markers: markers,
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

  /// Sprite-sheet scrub previews the packager published for this title, when
  /// it published any. Null keeps the timestamp-only preview.
  final StoryboardMetadata? storyboard;

  /// Intro / recap / outro spans supplied by the catalogue. Empty by default:
  /// the player never guesses where an intro is.
  final PlaybackMarkers markers;
  final Map<String, dynamic> metadata;

  /// Whether scrubbing can show real frames rather than only a timestamp.
  bool get hasStoryboard => storyboard?.isValid == true;

  bool get isAdaptive => type == ZvSourceType.hls || type == ZvSourceType.dash;

  /// True when quality must be switched by reloading a different URL, which is
  /// the case for every progressive source the current backend serves.
  bool get hasManualVariants => variants.length > 1;

  /// The address to play, recovered locally from common wrappers:
  ///
  /// - an `<iframe ... src="...">` embed snippet yields its `src`;
  /// - a Google redirect (`google.<tld>/url?q=` or `?url=`) whose destination
  ///   is a readable http(s) URL yields that destination.
  ///
  /// Nothing is fetched. An opaque redirect (Google's `goto?url=` token) is
  /// returned unchanged, and [detectType] reports it as unknown.
  static String normalizeUri(String uri) {
    String raw = uri.trim();
    if (raw.startsWith('<iframe')) {
      final RegExpMatch? src =
          RegExp('src=[\'"]([^\'"]+)[\'"]').firstMatch(raw);
      if (src != null) raw = src.group(1)!.trim();
    }
    for (int hop = 0; hop < 3; hop++) {
      final Uri? parsed = _parseLoose(raw);
      if (parsed == null || !_isGoogleRedirect(parsed)) break;
      final String? target =
          parsed.queryParameters['q'] ?? parsed.queryParameters['url'];
      if (target == null) break;
      final String t = target.trim();
      final String tl = t.toLowerCase();
      if (!tl.startsWith('http://') && !tl.startsWith('https://')) break;
      raw = t;
    }
    return raw;
  }

  static Uri? _parseLoose(String raw) {
    if (raw.isEmpty) return null;
    final String withScheme = raw.contains('://') ? raw : 'https://$raw';
    final Uri? uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  static bool _hostIs(String host, String domain) {
    final String h = host.toLowerCase();
    return h == domain || h.endsWith('.$domain');
  }

  static bool _isYouTubeHost(String host) =>
      _hostIs(host, 'youtube.com') ||
      _hostIs(host, 'youtu.be') ||
      _hostIs(host, 'youtube-nocookie.com');

  static bool _isVimeoHost(String host) => _hostIs(host, 'vimeo.com');

  /// `google.<tld>` (optionally `www.`) on a redirect path.
  static bool _isGoogleRedirect(Uri uri) {
    final bool google = RegExp(r'^(www\.)?google\.[a-z]{2,3}(\.[a-z]{2})?$')
        .hasMatch(uri.host.toLowerCase());
    return google && (uri.path == '/url' || uri.path == '/goto');
  }

  /// Classifies a source from the backend's declared type and the URI itself.
  ///
  /// Order matters, and it is not "extension first":
  ///
  /// 0. The URI is normalised locally with [normalizeUri] (iframe `src`, a
  ///    readable Google redirect destination). Nothing is fetched.
  /// 1. A YouTube or Vimeo host wins over any declared type: a watch page can
  ///    never be handed to Media3/AVPlayer, even if mislabelled `hls`.
  /// 2. The declared type is matched case-insensitively (the API sends
  ///    `YouTube`, the app's constant is `youtube`).
  /// 3. An opaque search-engine redirect (`google.com/goto`) is unknown - a
  ///    web page, not media - rather than guessed to be a file.
  /// 4. Only then are manifest and container extensions considered.
  static ZvSourceType detectType(String uri, {String? declaredType}) {
    final String raw = normalizeUri(uri);
    final String declared = (declaredType ?? '').trim().toLowerCase();

    // 1. A YouTube or Vimeo address is a web page whatever the backend
    // declared, and must never reach a native media pipeline.
    final Uri? parsed = _parseLoose(raw);
    if (parsed != null && _isYouTubeHost(parsed.host)) {
      return ZvSourceType.youtube;
    }
    if (parsed != null && _isVimeoHost(parsed.host)) {
      return ZvSourceType.vimeo;
    }

    // 2. Declared type, case-insensitive.
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

    // 3. A search-engine redirect whose destination could not be read
    // locally (an opaque `google.com/goto` token) is a web page, not media.
    // It is not followed: that would mean loading and parsing the page.
    if (parsed != null && _isGoogleRedirect(parsed)) {
      return ZvSourceType.unknown;
    }
    final String lower = raw.toLowerCase();

    final bool looksLocal = raw.startsWith('file://') ||
        raw.startsWith('/') ||
        (!raw.contains('://') && raw.contains('.'));

    // 4. Extensions, ignoring query and fragment.
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
      storyboard: storyboard,
      markers: markers,
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
