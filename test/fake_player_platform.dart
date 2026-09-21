import 'dart:async';

import 'package:zv_player/zv_player.dart';

/// In-memory stand-in for the native player.
///
/// Records the commands the controller issues and lets a test push the events a
/// real Media3/AVPlayer instance would emit, so controller logic is testable
/// without a device.
class FakePlayerPlatform implements ZvPlatform {
  final List<String> calls = <String>[];
  final List<ZvMediaSource> loadedSources = <ZvMediaSource>[];
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  int createdPlayers = 0;
  bool disposed = false;
  String? lastVideoTrackId;
  String? lastAudioTrackId;
  String? lastSubtitleTrackId;
  double? lastSpeed;
  double? lastVolume;
  Duration? lastSeek;
  bool pipResult = true;
  DeviceCapabilities capabilitiesResult =
      const DeviceCapabilities(supportsPip: true, probed: true);

  /// Mirrors a real platform: once the player is gone, nothing more arrives.
  void emit(Map<String, dynamic> event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  @override
  Future<int> create() async {
    createdPlayers++;
    calls.add('create');
    return createdPlayers;
  }

  @override
  Stream<Map<String, dynamic>> events(int playerId) => _events.stream;

  @override
  Future<void> load(int playerId, ZvMediaSource source,
      {bool autoPlay = true}) async {
    calls.add('load');
    loadedSources.add(source);
  }

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo');
    lastSeek = position;
  }

  @override
  Future<void> setSpeed(int playerId, double speed) async {
    calls.add('setSpeed');
    lastSpeed = speed;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('setVolume');
    lastVolume = volume;
  }

  @override
  Future<void> setMuted(int playerId, bool muted) async =>
      calls.add('setMuted');

  @override
  Future<void> selectVideoTrack(int playerId, String? trackId) async {
    calls.add('selectVideoTrack');
    lastVideoTrackId = trackId;
  }

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async {
    calls.add('selectAudioTrack');
    lastAudioTrackId = trackId;
  }

  @override
  Future<void> selectSubtitleTrack(int playerId, String? trackId) async {
    calls.add('selectSubtitleTrack');
    lastSubtitleTrackId = trackId;
  }

  @override
  Future<bool> enterPictureInPicture(int playerId) async {
    calls.add('enterPictureInPicture');
    return pipResult;
  }

  VideoFitMode? lastVideoFit;

  @override
  Future<void> setVideoFit(int playerId, VideoFitMode fit) async {
    calls.add('setVideoFit');
    lastVideoFit = fit;
  }

  @override
  Future<void> setSecureSurface(int playerId, bool secure) async =>
      calls.add('setSecureSurface');

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    disposed = true;
    await _events.close();
  }

  @override
  Future<DeviceCapabilities> capabilities() async {
    calls.add('capabilities');
    return capabilitiesResult;
  }
}

/// A platform whose player creation always fails, as a device with no free
/// decoder or a missing plugin registration would behave.
class FailingCreatePlatform extends FakePlayerPlatform {
  @override
  Future<int> create() async {
    throw StateError('native player unavailable');
  }
}

/// Records what a real analytics backend would receive.
class RecordingAnalyticsSink implements PlayerAnalyticsSink {
  final List<PlayerAnalyticsEvent> events = <PlayerAnalyticsEvent>[];

  List<String> get names =>
      events.map((PlayerAnalyticsEvent e) => e.name).toList();

  @override
  void add(PlayerAnalyticsEvent event) => events.add(event);
}
