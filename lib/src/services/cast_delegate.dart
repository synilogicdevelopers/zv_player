import 'package:flutter/foundation.dart';

/// Connection state of an external playback target.
enum CastConnectionState { unavailable, idle, connecting, connected, error }

/// A discoverable playback target: a Chromecast today, potentially AirPlay or
/// a DIAL/Smart TV endpoint later.
@immutable
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    this.modelName,
    this.isConnected = false,
  });

  final String id;
  final String name;
  final String? modelName;
  final bool isConnected;
}

/// A live casting session.
@immutable
class CastSession {
  const CastSession({
    required this.device,
    required this.state,
    this.position = Duration.zero,
    this.isPlaying = false,
  });

  final CastDevice device;
  final CastConnectionState state;
  final Duration position;
  final bool isPlaying;
}

/// The player's view of casting.
///
/// Deliberately protocol-agnostic: the app keeps its existing
/// `flutter_chrome_cast` integration and adapts it to this interface, so the
/// player UI never imports a Chromecast type and another protocol can be added
/// without touching the player.
abstract class CastDelegate {
  Stream<CastSession?> get sessionStream;

  CastSession? get currentSession;

  Future<List<CastDevice>> availableDevices();

  Future<void> connect(CastDevice device);

  Future<void> disconnect();

  /// Hands the current media to the connected receiver.
  Future<void> loadMedia({
    required String uri,
    required String title,
    Duration startPosition = Duration.zero,
    String? posterUrl,
  });
}

/// Default: casting is simply unavailable, and the UI hides its affordances.
class NoCastDelegate implements CastDelegate {
  const NoCastDelegate();

  @override
  Stream<CastSession?> get sessionStream => const Stream<CastSession?>.empty();

  @override
  CastSession? get currentSession => null;

  @override
  Future<List<CastDevice>> availableDevices() async => const <CastDevice>[];

  @override
  Future<void> connect(CastDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> loadMedia({
    required String uri,
    required String title,
    Duration startPosition = Duration.zero,
    String? posterUrl,
  }) async {}
}
