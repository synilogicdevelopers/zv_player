/// The 11-character YouTube video id in [input], or null when [input] is not a
/// recognisable YouTube video reference.
///
/// Accepts `watch?v=` (with the id anywhere in the query), `youtu.be/`,
/// `/embed/`, `/shorts/`, `/live/` and `/v/` URLs on youtube.com,
/// m.youtube.com, music.youtube.com and youtube-nocookie.com, an `<iframe>`
/// snippet, or a bare id. Playlist and timestamp parameters are ignored.
String? youTubeVideoId(String input) {
  String raw = input.trim();
  if (raw.isEmpty) return null;

  // An embed snippet: take its src.
  if (raw.startsWith('<iframe')) {
    final RegExpMatch? src = RegExp('src=[\'"]([^\'"]+)[\'"]').firstMatch(raw);
    if (src == null) return null;
    raw = src.group(1)!;
  }

  final RegExp id = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (id.hasMatch(raw)) return raw;

  final Uri? uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (uri == null) return null;
  final String host = uri.host.toLowerCase();

  String? candidate;
  if (host == 'youtu.be') {
    candidate = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com')) {
    final List<String> segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'watch') {
      candidate = uri.queryParameters['v'];
    } else if (segments.length >= 2 &&
        const <String>{'embed', 'shorts', 'live', 'v'}
            .contains(segments.first)) {
      candidate = segments[1];
    }
  }
  if (candidate == null || !id.hasMatch(candidate)) return null;
  return candidate;
}
