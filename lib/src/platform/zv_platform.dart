import 'dart:async';

import 'package:flutter/services.dart';

import '../capabilities/device_capabilities.dart';
import '../source/zv_media_source.dart';
import '../state/zv_player_state.dart';

/// Commands the Flutter layer may send to a native player, and the event
/// stream it gets back.
///
/// One native player instance per [playerId]. The instance outlives any view:
/// views attach to it and detach from it, which is what lets the same playback
/// session move between the page, fullscreen, the mini player and PiP without
/// ever creating a second decoder.
abstract class ZvPlatform {
  /// Creates a native player and returns its id.
  Future<int> create();

  /// Events for one player, decoded from the native event channel.
  Stream<Map<String, dynamic>> events(int playerId);

  Future<void> load(int playerId, ZvMediaSource source, {bool autoPlay = true});

  Future<void> play(int playerId);

  Future<void> pause(int playerId);

  Future<void> seekTo(int playerId, Duration position);

  Future<void> setSpeed(int playerId, double speed);

  Future<void> setVolume(int playerId, double volume);

  Future<void> setMuted(int playerId, bool muted);

  /// [trackId] null restores automatic (adaptive) selection.
  Future<void> selectVideoTrack(int playerId, String? trackId);

  Future<void> selectAudioTrack(int playerId, String trackId);

  /// [trackId] null turns subtitles off.
  Future<void> selectSubtitleTrack(int playerId, String? trackId);

  /// Asks the platform to enter Picture-in-Picture. Returns false when the
  /// device or OS refuses, which the UI reports rather than faking an overlay.
  Future<bool> enterPictureInPicture(int playerId);

  /// Crop-to-fill or show the whole frame. Implemented by the platform's own
  /// scaler, so the picture is never stretched.
  Future<void> setVideoFit(int playerId, VideoFitMode fit);

  /// Blocks screenshots and screen recording for the current window where the
  /// platform supports it. Android applies FLAG_SECURE; iOS has no equivalent
  /// guarantee, so this is best-effort there.
  Future<void> setSecureSurface(int playerId, bool secure);

  Future<void> dispose(int playerId);

  /// What this device can actually decode and display.
  Future<DeviceCapabilities> capabilities();
}

/// Default implementation over method and event channels.
class MethodChannelZvPlatform implements ZvPlatform {
  MethodChannelZvPlatform();

  static const MethodChannel _global = MethodChannel('zv_player/global');

  final Map<int, MethodChannel> _players = <int, MethodChannel>{};
  final Map<int, Stream<Map<String, dynamic>>> _events =
      <int, Stream<Map<String, dynamic>>>{};

  MethodChannel _channelFor(int playerId) {
    return _players.putIfAbsent(
      playerId,
      () => MethodChannel('zv_player/player_$playerId'),
    );
  }

  @override
  Future<int> create() async {
    final int? id = await _global.invokeMethod<int>('create');
    if (id == null) {
      throw PlatformException(
        code: 'create_failed',
        message: 'Native player could not be created',
      );
    }
    return id;
  }

  @override
  Stream<Map<String, dynamic>> events(int playerId) {
    return _events.putIfAbsent(playerId, () {
      return EventChannel('zv_player/events_$playerId')
          .receiveBroadcastStream()
          .map<Map<String, dynamic>>((Object? event) {
        if (event is Map) {
          return event.map<String, dynamic>(
            (Object? key, Object? value) => MapEntry<String, dynamic>(
              '$key',
              value,
            ),
          );
        }
        return <String, dynamic>{'event': 'unknown'};
      }).asBroadcastStream();
    });
  }

  @override
  Future<void> load(
    int playerId,
    ZvMediaSource source, {
    bool autoPlay = true,
  }) {
    return _channelFor(playerId).invokeMethod<void>('load', <String, dynamic>{
      ...source.toMap(),
      'autoPlay': autoPlay,
    });
  }

  @override
  Future<void> play(int playerId) =>
      _channelFor(playerId).invokeMethod<void>('play');

  @override
  Future<void> pause(int playerId) =>
      _channelFor(playerId).invokeMethod<void>('pause');

  @override
  Future<void> seekTo(int playerId, Duration position) {
    return _channelFor(playerId).invokeMethod<void>('seekTo', <String, dynamic>{
      'positionMs': position.inMilliseconds,
    });
  }

  @override
  Future<void> setSpeed(int playerId, double speed) {
    return _channelFor(playerId)
        .invokeMethod<void>('setSpeed', <String, dynamic>{'speed': speed});
  }

  @override
  Future<void> setVolume(int playerId, double volume) {
    return _channelFor(playerId)
        .invokeMethod<void>('setVolume', <String, dynamic>{'volume': volume});
  }

  @override
  Future<void> setMuted(int playerId, bool muted) {
    return _channelFor(playerId)
        .invokeMethod<void>('setMuted', <String, dynamic>{'muted': muted});
  }

  @override
  Future<void> selectVideoTrack(int playerId, String? trackId) {
    return _channelFor(playerId).invokeMethod<void>(
      'selectVideoTrack',
      <String, dynamic>{'trackId': trackId},
    );
  }

  @override
  Future<void> selectAudioTrack(int playerId, String trackId) {
    return _channelFor(playerId).invokeMethod<void>(
      'selectAudioTrack',
      <String, dynamic>{'trackId': trackId},
    );
  }

  @override
  Future<void> selectSubtitleTrack(int playerId, String? trackId) {
    return _channelFor(playerId).invokeMethod<void>(
      'selectSubtitleTrack',
      <String, dynamic>{'trackId': trackId},
    );
  }

  @override
  Future<bool> enterPictureInPicture(int playerId) async {
    final bool? entered =
        await _channelFor(playerId).invokeMethod<bool>('enterPictureInPicture');
    return entered ?? false;
  }

  @override
  Future<void> setVideoFit(int playerId, VideoFitMode fit) {
    return _channelFor(playerId).invokeMethod<void>(
      'setVideoFit',
      <String, dynamic>{'fit': fit.name},
    );
  }

  @override
  Future<void> setSecureSurface(int playerId, bool secure) {
    return _channelFor(playerId).invokeMethod<void>(
      'setSecureSurface',
      <String, dynamic>{'secure': secure},
    );
  }

  @override
  Future<void> dispose(int playerId) async {
    await _global.invokeMethod<void>('dispose', <String, dynamic>{
      'playerId': playerId,
    });
    _players.remove(playerId);
    _events.remove(playerId);
  }

  @override
  Future<DeviceCapabilities> capabilities() async {
    final Map<Object?, Object?>? raw =
        await _global.invokeMethod<Map<Object?, Object?>>('capabilities');
    if (raw == null) return const DeviceCapabilities();
    return DeviceCapabilities.fromMap(raw);
  }
}

/// Turns a native error code into something a viewer can read and something a
/// log can use. Raw platform detail never reaches the screen.
PlayerErrorInfo mapNativeError({
  required String? code,
  required String? message,
  String? detail,
}) {
  final String normalised = (code ?? '').toLowerCase();

  if (normalised.contains('drm')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.drm,
      message: 'This title is protected and cannot be played on this device.',
      code: code,
      technicalDetail: detail ?? message,
    );
  }
  if (normalised.contains('unsupported') || normalised.contains('format')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.unsupportedFormat,
      message: 'This video format is not supported on your device.',
      code: code,
      technicalDetail: detail ?? message,
    );
  }
  // Matches Media3's ERROR_CODE_DECODING_* as well as plain "decoder".
  if (normalised.contains('decod')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.decoder,
      message: 'Your device could not decode this video.',
      code: code,
      technicalDetail: detail ?? message,
    );
  }
  if (normalised.contains('timeout') || normalised.contains('buffer')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.bufferingTimeout,
      message: 'The video is taking too long to load. Check your connection.',
      code: code,
      technicalDetail: detail ?? message,
      isRecoverable: true,
    );
  }
  if (normalised.contains('network') ||
      normalised.contains('io') ||
      normalised.contains('connect') ||
      normalised.contains('http')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.network,
      message: 'Connection lost. Check your network and try again.',
      code: code,
      technicalDetail: detail ?? message,
      isRecoverable: true,
    );
  }
  if (normalised.contains('source') || normalised.contains('404')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.sourceUnavailable,
      message: 'This video is currently unavailable.',
      code: code,
      technicalDetail: detail ?? message,
    );
  }
  if (normalised.contains('audio')) {
    return PlayerErrorInfo(
      type: PlayerErrorType.audio,
      message: 'There was an audio problem during playback.',
      code: code,
      technicalDetail: detail ?? message,
      isRecoverable: true,
    );
  }

  return PlayerErrorInfo(
    type: PlayerErrorType.unknown,
    message: 'Something went wrong while playing this video.',
    code: code,
    technicalDetail: detail ?? message,
    isRecoverable: true,
  );
}
