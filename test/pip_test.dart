import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/zv_player.dart';

import 'fake_player_platform.dart';

/// Picture in Picture is decided by the engine behind the source, never by the
/// player UI. A native pipeline can hand a real system window; the YouTube
/// IFrame embed cannot, and must not pretend otherwise.
class _Engine implements PlaybackEngine {
  _Engine({
    required this.kind,
    required this.capabilities,
    this.pipGranted = true,
  });

  @override
  final PlaybackEngineKind kind;
  @override
  final EngineCapabilities capabilities;

  /// What the platform answers: a device can refuse PiP outright.
  final bool pipGranted;

  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());

  int pipRequests = 0;
  bool _disposed = false;

  /// The platform's PiP callback coming back up through the engine.
  void reportPipMode(bool inPip) {
    if (_disposed) return;
    _state.value = _state.value.copyWith(isPip: inPip);
  }

  @override
  ValueListenable<ZvPlayerState> get state => _state;
  @override
  bool get isInitialized => true;
  @override
  bool get isDisposed => _disposed;

  @override
  Future<bool> enterPictureInPicture() async {
    pipRequests++;
    if (!pipGranted || _disposed) return false;
    reportPipMode(true);
    return true;
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {
    if (_disposed || !autoPlay) return;
    _state.value = _state.value.copyWith(
        status: PlayerStatus.playing,
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 5));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _state.dispose();
  }

  @override
  Future<void> play() async =>
      _state.value = _state.value.copyWith(status: PlayerStatus.playing);
  @override
  Future<void> pause() async =>
      _state.value = _state.value.copyWith(status: PlayerStatus.paused);
  @override
  Future<void> seekTo(Duration position) async =>
      _state.value = _state.value.copyWith(position: position);
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
  void setFullscreen(bool fullscreen) {}
  @override
  Future<void> setVideoFit(VideoFitMode fit) async {}
  @override
  Widget buildSurface(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late _Engine engine;

  ZvPlayerController nativeController({bool pipGranted = true}) =>
      ZvPlayerController(
        router: SourceRouter(nativeEngineBuilder: () {
          engine = _Engine(
              kind: PlaybackEngineKind.native,
              capabilities: const EngineCapabilities.nativeMedia(),
              pipGranted: pipGranted);
          return engine;
        }),
        logger: (_, __) {},
      );

  final ZvMediaSource mp4 =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/movie.mp4');
  final ZvMediaSource hls =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8');
  final ZvMediaSource youTube =
      ZvMediaSource.detect(uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k');

  group('capability is decided by the engine, per source', () {
    test('native media reports Picture in Picture', () {
      const EngineCapabilities native = EngineCapabilities.nativeMedia();
      expect(native.supportsPictureInPicture, isTrue);
    });

    test('the YouTube IFrame embed does not', () {
      // Real platform PiP would mean handing the system a media stream, which
      // for YouTube could only come from extracting or scraping it. The engine
      // reports the honest answer instead.
      expect(YouTubeEngine.kCapabilities.supportsPictureInPicture, isFalse);
    });

    test('an unsupported source claims nothing', () {
      final ZvPlayerController controller = nativeController();
      expect(controller.capabilities.supportsPictureInPicture, isFalse,
          reason: 'no engine yet, so no claim');
      controller.dispose();
    });

    for (final ZvMediaSource source in <ZvMediaSource>[mp4, hls]) {
      test('${source.type.name} routes to an engine that offers PiP', () async {
        final ZvPlayerController controller = nativeController();
        await controller.open(source);
        expect(controller.capabilities.supportsPictureInPicture, isTrue);
        await controller.dispose();
      });
    }

    test('YouTube routes to the embedded engine, which offers no PiP', () {
      final SourceRouter router = SourceRouter.standard();
      expect(router.select(youTube).kind, PlaybackEngineKind.embedded);
      expect(YouTubeEngine.kCapabilities.supportsPictureInPicture, isFalse);
    });
  });

  group('entering and leaving', () {
    test('a granted request puts the player in PiP and keeps it playing',
        () async {
      final ZvPlayerController controller = nativeController();
      await controller.open(mp4);
      expect(controller.value.isPlaying, isTrue);

      expect(await controller.enterPictureInPicture(), isTrue);

      expect(controller.value.isPip, isTrue);
      expect(controller.value.isPlaying, isTrue,
          reason: 'PiP continues playback; it does not pause it');
      expect(controller.value.position, const Duration(seconds: 30),
          reason: 'position is preserved across the transition');
      await controller.dispose();
    });

    test('leaving PiP restores the player with its position and state',
        () async {
      final ZvPlayerController controller = nativeController();
      await controller.open(mp4);
      await controller.enterPictureInPicture();
      await controller.seekTo(const Duration(minutes: 2));

      // The platform reports the window closing.
      engine.reportPipMode(false);
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.isPip, isFalse);
      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.position, const Duration(minutes: 2),
          reason: 'position survives the PiP round trip');
      await controller.dispose();
    });

    test('a device that refuses PiP reports false and stays inline', () async {
      final ZvPlayerController controller = nativeController(pipGranted: false);
      await controller.open(mp4);

      expect(await controller.enterPictureInPicture(), isFalse);
      expect(controller.value.isPip, isFalse);
      expect(controller.value.isPlaying, isTrue,
          reason: 'a refused request must not disturb playback');
      await controller.dispose();
    });

    test('a controller without PiP capability never reaches the engine',
        () async {
      final ZvPlayerController controller = ZvPlayerController(
        router: SourceRouter(nativeEngineBuilder: () {
          engine = _Engine(
              kind: PlaybackEngineKind.native,
              capabilities: const EngineCapabilities(canPlayPause: true));
          return engine;
        }),
        logger: (_, __) {},
      );
      await controller.open(mp4);

      expect(await controller.enterPictureInPicture(), isFalse);
      expect(engine.pipRequests, 0,
          reason: 'the request is gated before it becomes a platform call');
      await controller.dispose();
    });

    test('disposing while in PiP releases the engine', () async {
      final ZvPlayerController controller = nativeController();
      await controller.open(mp4);
      await controller.enterPictureInPicture();
      final _Engine inPip = engine;

      await controller.dispose();

      expect(inPip.isDisposed, isTrue,
          reason: 'a PiP window must not outlive the player that owns it');
    });

    test('release() ends a PiP session too', () async {
      final ZvPlayerController controller = nativeController();
      await controller.open(mp4);
      await controller.enterPictureInPicture();
      final _Engine inPip = engine;

      await controller.release();

      expect(inPip.isDisposed, isTrue);
      expect(controller.value.isPip, isFalse);
      await controller.dispose();
    });
  });

  group('the button follows the capability', () {
    Future<void> pumpPlayer(
        WidgetTester tester, ZvPlayerController controller) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZvPlayer(controller: controller, autoEnterFullscreen: false),
        ),
      ));
      await tester.pump();
    }

    testWidgets('native media shows Picture in picture', (tester) async {
      final ZvPlayerController controller = nativeController();
      await controller.open(mp4);
      await pumpPlayer(tester, controller);

      expect(find.byTooltip('Picture in picture'), findsOneWidget);

      await tester.tap(find.byTooltip('Picture in picture'));
      await tester.pump();
      expect(engine.pipRequests, 1);
      await controller.dispose();
    });

    testWidgets('an engine without PiP shows no button at all', (tester) async {
      final ZvPlayerController controller = ZvPlayerController(
        router: SourceRouter(nativeEngineBuilder: () {
          engine = _Engine(
              kind: PlaybackEngineKind.native,
              capabilities: const EngineCapabilities(
                  canPlayPause: true, canSeek: true, supportsFullscreen: true));
          return engine;
        }),
        logger: (_, __) {},
      );
      await controller.open(mp4);
      await pumpPlayer(tester, controller);

      expect(find.byTooltip('Picture in picture'), findsNothing,
          reason: 'no broken PiP button for an engine that cannot do it');
      await controller.dispose();
    });
  });

  group('the device has the last word', () {
    late FakePlayerPlatform platform;

    NativeMediaEngine engineWith({required bool devicePip}) {
      platform = FakePlayerPlatform()
        ..capabilitiesResult =
            DeviceCapabilities(supportsPip: devicePip, probed: true);
      return NativeMediaEngine(
        controller: ZvNativeController(
          platform: platform,
          progressStore: InMemoryProgressStore(),
          secureSurface: false,
        ),
      );
    }

    final ZvMediaSource source =
        ZvMediaSource.detect(uri: 'https://cdn.example.com/movie.mp4');

    test('hardware without the PiP feature makes the engine report false',
        () async {
      final NativeMediaEngine engine = engineWith(devicePip: false);
      await engine.initialize();
      await engine.load(source);
      // The probe is fired once playback is under way, not during the
      // transition; let it land.
      await Future<void>.delayed(Duration.zero);

      expect(engine.capabilities.supportsPictureInPicture, isFalse,
          reason: 'no button may be offered for a device that cannot do PiP');
      expect(await engine.enterPictureInPicture(), isFalse);
      expect(platform.calls.contains('enterPictureInPicture'), isFalse,
          reason: 'and the platform is never asked');
      await engine.dispose();
    });

    test('hardware with the feature keeps PiP available', () async {
      final NativeMediaEngine engine = engineWith(devicePip: true);
      await engine.initialize();
      await engine.load(source);
      await Future<void>.delayed(Duration.zero);

      expect(engine.capabilities.supportsPictureInPicture, isTrue);
      await engine.enterPictureInPicture();
      expect(platform.calls.contains('enterPictureInPicture'), isTrue);
      await engine.dispose();
    });
  });
}
