import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/zv_player.dart';

/// An engine that records its lifecycle, optionally holding initialisation
/// open so a test can act while an open is in flight.
class _Engine implements PlaybackEngine {
  _Engine(this.id, {this.hold});

  final int id;
  final Completer<void>? hold;
  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());

  ZvMediaSource? loaded;
  bool _initialized = false;
  bool _disposed = false;

  void emit(ZvPlayerState next) {
    if (!_disposed) _state.value = next;
  }

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.native;
  @override
  ValueListenable<ZvPlayerState> get state => _state;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities.nativeMedia();
  @override
  bool get isInitialized => _initialized;
  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> initialize() async {
    if (hold != null) await hold!.future;
    _initialized = true;
  }

  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {
    if (_disposed) return;
    loaded = source;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _state.dispose();
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> selectQuality(VideoQualityTrack track) async {}
  @override
  Future<void> selectAudioTrack(AudioTrackOption track) async {}
  @override
  Future<void> selectSubtitle(SubtitleTrackOption? track) async {}
  @override
  Future<bool> enterPictureInPicture() async => false;
  @override
  void setFullscreen(bool fullscreen) {}
  @override
  Future<void> setVideoFit(VideoFitMode fit) async {}
  @override
  Widget buildSurface(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late List<_Engine> built;
  final List<Completer<void>?> holds = <Completer<void>?>[];

  ZvPlayerController controller() {
    built = <_Engine>[];
    holds.clear();
    return ZvPlayerController(
      router: SourceRouter(nativeEngineBuilder: () {
        final _Engine e = _Engine(built.length,
            hold: holds.length > built.length ? holds[built.length] : null);
        built.add(e);
        return e;
      }),
      logger: (_, __) {},
    );
  }

  final ZvMediaSource a =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/a.mp4');
  final ZvMediaSource b =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/b.m3u8');

  test('opening B releases A; only B remains active', () async {
    final ZvPlayerController c = controller();
    await c.open(a);
    final _Engine engineA = built.single;
    expect(engineA.loaded, a);

    await c.open(b);
    expect(built, hasLength(2));
    expect(engineA.isDisposed, isTrue, reason: 'A must be released');
    expect(identical(c.engine, built[1]), isTrue);
    expect(built[1].isDisposed, isFalse);
    expect(built[1].loaded, b);
    await c.dispose();
  });

  test('state is fresh for the new source; presentation carries over',
      () async {
    final ZvPlayerController c = controller();
    await c.open(a);
    built.single.emit(const ZvPlayerState(
        status: PlayerStatus.playing,
        position: Duration(minutes: 40),
        duration: Duration(hours: 2)));
    c.setFullscreen(true);
    expect(c.value.position, const Duration(minutes: 40));

    await c.open(b);
    expect(c.value.position, Duration.zero);
    expect(c.value.status, isNot(PlayerStatus.playing));
    expect(c.value.isFullscreen, isTrue);
    await c.dispose();
  });

  test('a released engine can no longer write state', () async {
    final ZvPlayerController c = controller();
    await c.open(a);
    final _Engine engineA = built.single;
    await c.open(b);
    // Even if A emitted during teardown, it is detached from the controller.
    expect(engineA.isDisposed, isTrue);
    built[1].emit(const ZvPlayerState(
        status: PlayerStatus.playing, position: Duration(seconds: 3)));
    expect(c.value.position, const Duration(seconds: 3));
    await c.dispose();
  });

  test('open -> dispose releases the engine', () async {
    final ZvPlayerController c = controller();
    await c.open(a);
    await c.dispose();
    expect(built.single.isDisposed, isTrue);
    expect(c.engine, isNull);
    // Opening after dispose is a no-op: no new engine.
    await c.open(b);
    expect(built, hasLength(1));
  });

  test('open -> close -> open: each session owns exactly one engine', () async {
    final ZvPlayerController first = controller();
    await first.open(a);
    await first.dispose();
    final _Engine firstEngine = built.single;

    final ZvPlayerController second = controller();
    await second.open(b);
    expect(firstEngine.isDisposed, isTrue);
    expect(built.single.isDisposed, isFalse);
    expect(built.single.loaded, b);
    await second.dispose();
  });

  test('rapid opens while A is still initialising leave only the last',
      () async {
    final ZvPlayerController c = controller();
    final Completer<void> holdA = Completer<void>();
    holds.addAll(<Completer<void>?>[holdA, null]);

    final Future<void> openA = c.open(a);
    await Future<void>.delayed(Duration.zero);
    expect(built, hasLength(1), reason: 'A is created and initialising');

    await c.open(b);
    expect(built[0].isDisposed, isTrue, reason: 'A released mid-start');
    expect(identical(c.engine, built[1]), isTrue);

    holdA.complete();
    await openA;
    expect(built[0].loaded, isNull, reason: 'superseded A never loads');
    expect(identical(c.engine, built[1]), isTrue);
    expect(built[1].loaded, b);
    expect(c.value.hasError, isFalse);
    await c.dispose();
  });

  test('dispose during initialisation is safe', () async {
    final ZvPlayerController c = controller();
    final Completer<void> hold = Completer<void>();
    holds.add(hold);

    final Future<void> opening = c.open(a);
    await Future<void>.delayed(Duration.zero);
    await c.dispose();
    hold.complete();
    await opening;
    expect(built.single.isDisposed, isTrue);
    expect(built.single.loaded, isNull);
  });
}
