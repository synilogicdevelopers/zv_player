import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

void main() {
  late FakePlayerPlatform platform;
  late NativeMediaEngine engine;

  ZvMediaSource mp4(
          {List<ZvSourceVariant> variants = const <ZvSourceVariant>[]}) =>
      ZvMediaSource.detect(
        uri: 'https://cdn.example.com/movie.mp4',
        contentId: 'c1',
        variants: variants,
      );

  setUp(() {
    platform = FakePlayerPlatform();
    engine = NativeMediaEngine(
      controller: ZvNativeController(
        platform: platform,
        progressStore: InMemoryProgressStore(),
        secureSurface: false,
      ),
    );
  });

  tearDown(() async {
    if (!engine.isDisposed) await engine.dispose();
  });

  group('lifecycle', () {
    test('nothing is acquired on construction', () {
      expect(engine.isInitialized, isFalse);
      expect(platform.createdPlayers, 0);
    });

    test('initialize creates exactly one native player and is repeatable',
        () async {
      await engine.initialize();
      await engine.initialize();

      expect(engine.isInitialized, isTrue);
      expect(platform.createdPlayers, 1);
    });

    test('load initialises when the caller has not', () async {
      await engine.load(mp4());

      expect(engine.isInitialized, isTrue);
      expect(platform.loadedSources.length, 1);
    });

    test('dispose is idempotent and releases the player', () async {
      await engine.initialize();
      await engine.dispose();
      await engine.dispose();

      expect(engine.isDisposed, isTrue);
      expect(platform.disposed, isTrue);
    });

    test('commands after dispose are ignored rather than throwing', () async {
      await engine.load(mp4());
      await engine.dispose();
      final int callsBefore = platform.calls.length;

      await engine.play();
      await engine.pause();
      await engine.seekTo(const Duration(seconds: 5));
      await engine.setSpeed(1.5);
      expect(await engine.enterPictureInPicture(), isFalse);

      expect(platform.calls.length, callsBefore);
    });

    test('commands before initialize are ignored', () async {
      await engine.play();
      expect(platform.calls, isNot(contains('play')));
    });
  });

  group('capabilities', () {
    test('an adaptive source reports full native capability', () {
      final EngineCapabilities caps = NativeMediaEngine.capabilitiesFor(
        ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8'),
      );
      expect(caps.canSelectQuality, isTrue);
      expect(caps.canSelectAudioTrack, isTrue);
      expect(caps.canSelectSubtitle, isTrue);
      expect(caps.canSetSpeed, isTrue);
      expect(caps.supportsPictureInPicture, isTrue);
      expect(caps.reportsBufferedPosition, isTrue);
      // No DRM exists on any engine yet.
      expect(caps.supportsDrm, isFalse);
    });

    test('a single-URL progressive source cannot offer quality switching', () {
      final EngineCapabilities caps = NativeMediaEngine.capabilitiesFor(mp4());
      expect(caps.canSelectQuality, isFalse);
      expect(caps.canSeek, isTrue);
    });

    test('multiple per-quality URLs do allow quality switching', () {
      final EngineCapabilities caps = NativeMediaEngine.capabilitiesFor(
        mp4(variants: const <ZvSourceVariant>[
          ZvSourceVariant(id: '1', label: '720p', uri: 'https://x/720.mp4'),
          ZvSourceVariant(id: '2', label: '1080p', uri: 'https://x/1080.mp4'),
        ]),
      );
      expect(caps.canSelectQuality, isTrue);
    });

    test('capabilities follow the loaded source', () async {
      await engine.load(mp4());
      expect(engine.capabilities.canSelectQuality, isFalse);

      await engine.load(
        ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8'),
      );
      expect(engine.capabilities.canSelectQuality, isTrue);
    });

    test('a track selection the engine cannot make is ignored', () async {
      await engine.load(mp4()); // canSelectQuality == false
      await engine.selectQuality(
        const VideoQualityTrack(id: '0:0', label: '1080p'),
      );

      expect(platform.calls, isNot(contains('selectVideoTrack')));
    });
  });

  group('delegation', () {
    test('transport commands reach the platform', () async {
      await engine.load(mp4());
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'ready'});
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 0,
        'durationMs': 60000,
      });
      await pumpEventQueue();

      await engine.play();
      await engine.pause();
      await engine.seekTo(const Duration(seconds: 10));
      await engine.setSpeed(1.5);

      expect(platform.calls, contains('play'));
      expect(platform.calls, contains('pause'));
      expect(platform.lastSeek, const Duration(seconds: 10));
      expect(platform.lastSpeed, 1.5);
    });

    test('state is the shared player state', () async {
      await engine.load(mp4());
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'playing'});
      await pumpEventQueue();

      expect(engine.state.value.isPlaying, isTrue);
      expect(engine.kind, PlaybackEngineKind.native);
    });
  });
}
