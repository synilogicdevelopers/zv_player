import '../source/zv_media_source.dart';

/// State of a downloaded item, as the player cares about it.
enum OfflineItemState { none, queued, downloading, paused, completed, failed }

/// Resolves a content id to a source that plays without the network.
///
/// The app's existing download stack keeps working untouched; it implements
/// this interface to hand the player a local [ZvMediaSource]. Keeping it behind
/// an interface means the current file-encryption scheme can later be replaced
/// by adaptive downloads with persisted DRM licences without the player
/// changing at all.
///
/// Note: today's downloads are AES-encrypted at rest and decrypted to a
/// plaintext file for playback. That is *not* equivalent to DRM-secured
/// offline playback and must not be described as such.
abstract class OfflineSourceResolver {
  Future<OfflineItemState> stateFor(String contentId);

  /// Returns null when nothing playable is stored for [contentId].
  Future<ZvMediaSource?> resolve(String contentId);
}

/// Default: nothing is available offline.
class NoOfflineSourceResolver implements OfflineSourceResolver {
  const NoOfflineSourceResolver();

  @override
  Future<OfflineItemState> stateFor(String contentId) async =>
      OfflineItemState.none;

  @override
  Future<ZvMediaSource?> resolve(String contentId) async => null;
}
