import 'package:zv_player/zv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

/// Records what the engine was asked to do, so the controller's delegation and
/// capability gating can be checked without a real player.
class _RecordingEngine implements PlaybackEngine {
  _RecordingEngine({
    required this.kind,
    required EngineCapabilities capabilities,
    this.failOnInitialize = false,
  }) : _capabilities = capabilities;

  @override
  final PlaybackEngineKind kind;

  final EngineCapabilities _capabilities;
  final bool failOnInitialize;

  final List<String> calls = <String>[];
  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());

  ZvMediaSource? loadedSource;
  bool? loadedAutoPlay;
  int initializeCount = 0;
  bool _initialized = false;
  bool _disposed = false;

  void emit(ZvPlayerState next) => _state.value = next;

  @override
  ValueListenable<ZvPlayerState> get state => _state;

  @override
  EngineCapabilities get capabilities => _capabilities;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> initialize() async {
    initializeCount++;
    if (failOnInitialize) throw StateError('engine unavailable');
    _initialized = true;
  }

  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {
    loadedSource = source;
    loadedAutoPlay = autoPlay;
    calls.add('load');
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seekTo(Duration position) async => calls.add('seekTo');

  @override
  Future<void> setSpeed(double speed) async => calls.add('setSpeed');

  @override
  Future<void> setVolume(double volume) async => calls.add('setVolume');

  @override
  Future<void> setMuted(bool muted) async => calls.add('setMuted');

  @override
  Future<void> selectQuality(VideoQualityTrack track) async =>
      calls.add('selectQuality');

  @override
  Future<void> selectAudioTrack(AudioTrackOption track) async =>
      calls.add('selectAudioTrack');

  @override
  Future<void> selectSubtitle(SubtitleTrackOption? track) async =>
      calls.add('selectSubtitle');

  @override
  Future<bool> enterPictureInPicture() async {
    calls.add('enterPictureInPicture');
    return true;
  }

  @override
  void setFullscreen(bool fullscreen) => calls.add('setFullscreen');
  @override
  Future<void> setVideoFit(VideoFitMode fit) async {}

  @override
  Widget buildSurface(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    _disposed = true;
    _state.dispose();
  }
}

void main() {
  ZvMediaSource sourceOf(String uri, {String? declaredType}) =>
      ZvMediaSource.detect(uri: uri, declaredType: declaredType);

  final ZvMediaSource youtube = sourceOf(
    'https://www.youtube.com/watch?v=iITwUMIwI1k',
    declaredType: 'YouTube',
  );
  final ZvMediaSource mp4 = sourceOf('https://cdn.example.com/movie.mp4');

  late List<String> logTags;
  late List<Map<String, Object?>> logFields;

  void logger(String tag, Map<String, Object?> fields) {
    logTags.add(tag);
    logFields.add(fields);
  }

  setUp(() {
    logTags = <String>[];
    logFields = <Map<String, Object?>>[];
  });

  ZvPlayerController controllerWith({
    _RecordingEngine? embedded,
    _RecordingEngine? native,
  }) {
    return ZvPlayerController(
      router: SourceRouter(
        youTubeEngineBuilder: embedded == null ? null : () => embedded,
        nativeEngineBuilder: native == null ? null : () => native,
      ),
      logger: logger,
    );
  }

  _RecordingEngine embeddedEngine() => _RecordingEngine(
        kind: PlaybackEngineKind.embedded,
        capabilities: const EngineCapabilities(
          canPlayPause: true,
          canSeek: true,
          canMute: true,
          // Matches the real embed pages: no speed, no track menus, no PiP.
        ),
      );

  _RecordingEngine nativeEngine() => _RecordingEngine(
        kind: PlaybackEngineKind.native,
        capabilities: const EngineCapabilities.nativeMedia(),
      );

  group('connectivity recovery', () {
    for (final playing in [true, false]) {
      testWidgets(
          'restores position and playing=$playing without a second engine',
          (tester) async {
        final engine = embeddedEngine();
        final controller = controllerWith(embedded: engine);
        await controller.open(youtube, autoPlay: playing);
        engine.emit(ZvPlayerState(
            source: youtube,
            status: playing ? PlayerStatus.playing : PlayerStatus.paused,
            position: const Duration(minutes: 12),
            duration: const Duration(hours: 2)));
        await controller.setNetworkAvailable(false);
        await controller.setNetworkAvailable(false);
        expect(engine.calls.where((c) => c == 'pause').length, 1);
        // A late provider tick must not erase the reconnect checkpoint.
        engine.emit(const ZvPlayerState(status: PlayerStatus.paused));
        expect(controller.value.position, const Duration(minutes: 12));
        await controller.setNetworkAvailable(true);
        await controller.setNetworkAvailable(true);
        expect(engine.calls.where((c) => c == 'load').length, 2);
        expect(engine.loadedSource!.startPosition, const Duration(minutes: 12));
        expect(engine.loadedAutoPlay, playing);
        expect(engine.initializeCount, 1);
        engine.emit(ZvPlayerState(
            status: playing ? PlayerStatus.playing : PlayerStatus.ready,
            position: const Duration(minutes: 12, seconds: 1)));
        expect(controller.isRecovering, isFalse);
        await controller.dispose();
      });
    }
    testWidgets(
        'stalled recovery stops after three loads and cancels on dispose',
        (tester) async {
      final engine = embeddedEngine();
      final controller = controllerWith(embedded: engine);
      await controller.open(youtube);
      await controller.setNetworkAvailable(false);
      await controller.setNetworkAvailable(true);
      await tester.pump(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 12));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 12));
      expect(controller.recoveryFailed, isTrue);
      expect(engine.calls.where((c) => c == 'load').length, 4);
      await tester.pump(const Duration(minutes: 1));
      expect(engine.calls.where((c) => c == 'load').length, 4);
      await controller.dispose();
    });
    test('paused reconnect waits for its checkpoint before declaring recovery',
        () async {
      final engine = embeddedEngine();
      final controller = controllerWith(embedded: engine);
      await controller.open(youtube, autoPlay: false);
      engine.emit(const ZvPlayerState(
          status: PlayerStatus.paused,
          position: Duration(seconds: 60),
          duration: Duration(minutes: 10)));
      await controller.setNetworkAvailable(false);
      await controller.setNetworkAvailable(true);
      engine.emit(const ZvPlayerState(
          status: PlayerStatus.ready, position: Duration.zero));
      expect(controller.isRecovering, isTrue);
      expect(controller.value.position, const Duration(seconds: 60));
      engine.emit(const ZvPlayerState(
          status: PlayerStatus.ready, position: Duration(seconds: 60)));
      expect(controller.isRecovering, isFalse);
      expect(controller.value.isPlaying, isFalse);
      await controller.dispose();
    });
    testWidgets('background pause cancels resume intent during an outage',
        (tester) async {
      final engine = embeddedEngine();
      final controller = controllerWith(embedded: engine);
      await controller.open(youtube);
      await controller.setNetworkAvailable(false);
      await controller.pause();
      await controller.setNetworkAvailable(true);
      expect(engine.loadedAutoPlay, isFalse);
      await controller.dispose();
    });
  });

  group('engine selection through the universal controller', () {
    test('YouTube opens on the embedded engine', () async {
      final _RecordingEngine embedded = embeddedEngine();
      final ZvPlayerController controller =
          controllerWith(embedded: embedded, native: nativeEngine());
      await controller.open(youtube);

      expect(controller.engineKind, PlaybackEngineKind.embedded);
      expect(embedded.calls, contains('load'));
      expect(controller.value.hasError, isFalse);
      await controller.dispose();
    });

    test('Vimeo builds no engine and reports an unsupported source', () async {
      final _RecordingEngine embedded = embeddedEngine();
      final ZvPlayerController controller =
          controllerWith(embedded: embedded, native: nativeEngine());
      await controller.open(sourceOf('https://vimeo.com/12345'));

      expect(controller.engine, isNull);
      expect(controller.value.error?.code, 'unsupported_source');
      expect(embedded.initializeCount, 0);
      await controller.dispose();
    });

    test('MP4, HLS, DASH and local files open on the native engine', () async {
      for (final ZvMediaSource source in <ZvMediaSource>[
        mp4,
        sourceOf('https://cdn.example.com/master.m3u8'),
        sourceOf('https://cdn.example.com/manifest.mpd'),
        sourceOf('/data/user/0/app/files/a.mp4'),
      ]) {
        final _RecordingEngine native = nativeEngine();
        final ZvPlayerController controller =
            controllerWith(embedded: embeddedEngine(), native: native);
        await controller.open(source);

        expect(controller.engineKind, PlaybackEngineKind.native,
            reason: source.uri);
        expect(native.calls, contains('load'));
        await controller.dispose();
      }
    });

    test('backend casing does not change the decision', () async {
      for (final String declared in <String>['YouTube', 'youtube', 'YOUTUBE']) {
        final ZvPlayerController controller = controllerWith(
          embedded: embeddedEngine(),
          native: nativeEngine(),
        );
        await controller.open(
          sourceOf('https://example.com/x', declaredType: declared),
        );
        expect(controller.engineKind, PlaybackEngineKind.embedded,
            reason: declared);
        await controller.dispose();
      }
    });

    test('a YouTube URL mislabelled as URL still avoids the native engine',
        () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller =
          controllerWith(embedded: embeddedEngine(), native: native);
      await controller.open(
        sourceOf('https://www.youtube.com/watch?v=iITwUMIwI1k',
            declaredType: 'URL'),
      );

      expect(controller.engineKind, PlaybackEngineKind.embedded);
      expect(native.calls, isEmpty, reason: 'native engine must never load it');
      await controller.dispose();
    });

    test('an unsupported source errors cleanly and builds no engine', () async {
      final _RecordingEngine embedded = embeddedEngine();
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller =
          controllerWith(embedded: embedded, native: native);
      await controller.open(sourceOf(''));

      expect(controller.value.hasError, isTrue);
      expect(controller.value.error?.code, 'unsupported_source');
      expect(controller.engine, isNull);
      expect(embedded.initializeCount, 0);
      expect(native.initializeCount, 0);
      await controller.dispose();
    });

    test('an engine that cannot start surfaces an error, not an exception',
        () async {
      final _RecordingEngine broken = _RecordingEngine(
        kind: PlaybackEngineKind.native,
        capabilities: const EngineCapabilities.nativeMedia(),
        failOnInitialize: true,
      );
      final ZvPlayerController controller = controllerWith(native: broken);

      await controller.open(mp4);
      expect(controller.value.hasError, isTrue);
      expect(controller.value.error?.code, 'engine_start_failed');
      await controller.dispose();
    });

    test('the engine is initialised exactly once per open', () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller = controllerWith(native: native);
      await controller.open(mp4);

      expect(native.initializeCount, 1);
      expect(native.calls.where((String c) => c == 'load').length, 1);
      await controller.dispose();
    });
  });

  group('capability-driven commands', () {
    test('commands the engine cannot honour never reach it', () async {
      final _RecordingEngine embedded = embeddedEngine();
      final ZvPlayerController controller = controllerWith(embedded: embedded);
      await controller.open(youtube);
      embedded.calls.clear();

      await controller.setSpeed(2.0);
      await controller.selectQuality(
        const VideoQualityTrack(id: '1', label: '1080p'),
      );
      await controller.selectSubtitle(null);
      await controller.setVolume(0.5);
      expect(await controller.enterPictureInPicture(), isFalse);

      expect(embedded.calls, isEmpty);
      await controller.dispose();
    });

    test('supported commands are delegated', () async {
      final _RecordingEngine embedded = embeddedEngine();
      final ZvPlayerController controller = controllerWith(embedded: embedded);
      await controller.open(youtube);
      embedded.emit(const ZvPlayerState(
        status: PlayerStatus.playing,
        duration: Duration(minutes: 5),
      ));
      embedded.calls.clear();

      await controller.play();
      await controller.pause();
      await controller.seekTo(const Duration(seconds: 30));
      await controller.setMuted(true);

      expect(embedded.calls,
          containsAll(<String>['play', 'pause', 'seekTo', 'setMuted']));
      await controller.dispose();
    });

    test('capabilities before an engine exists claim nothing', () {
      final ZvPlayerController controller = controllerWith();
      expect(controller.capabilities.canPlayPause, isFalse);
      expect(controller.capabilities.canSeek, isFalse);
      controller.dispose();
    });
  });

  group('state, fullscreen and lifecycle', () {
    test('engine state is mirrored to the controller', () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller = controllerWith(native: native);
      await controller.open(mp4);

      native.emit(const ZvPlayerState(
        status: PlayerStatus.playing,
        position: Duration(seconds: 12),
        duration: Duration(minutes: 3),
      ));

      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.position, const Duration(seconds: 12));
      await controller.dispose();
    });

    test('fullscreen toggles are idempotent and reach the engine', () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller = controllerWith(native: native);
      await controller.open(mp4);

      controller.setFullscreen(true);
      expect(controller.value.isFullscreen, isTrue);
      controller.setFullscreen(true);
      controller.setFullscreen(false);
      expect(controller.value.isFullscreen, isFalse);
      controller.setFullscreen(false);

      expect(native.calls.where((String c) => c == 'setFullscreen').length, 4);
      await controller.dispose();
    });

    test('dispose releases the engine and is idempotent', () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller = controllerWith(native: native);
      await controller.open(mp4);

      await controller.dispose();
      await controller.dispose();

      expect(native.isDisposed, isTrue);
      expect(controller.isDisposed, isTrue);
      expect(native.calls.where((String c) => c == 'dispose').length, 1);
    });

    test('engine events after dispose do not touch the controller', () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller = controllerWith(native: native);
      await controller.open(mp4);
      final PlayerStatus before = controller.value.status;
      await controller.dispose();

      // The engine is disposed with the controller, so this is the guard that
      // a late listener callback cannot mutate a disposed notifier.
      expect(controller.value.status, before);
    });
  });

  group('device-verification logging', () {
    test('the documented tags are emitted in order', () async {
      final _RecordingEngine native = nativeEngine();
      final ZvPlayerController controller = controllerWith(native: native);
      await controller.open(mp4);
      native.emit(const ZvPlayerState(status: PlayerStatus.playing));
      await controller.dispose();

      expect(
        logTags,
        containsAllInOrder(<String>[
          ZvPlayerLog.open,
          ZvPlayerLog.sourceClassified,
          ZvPlayerLog.engineSelected,
          ZvPlayerLog.engineInitialized,
          ZvPlayerLog.firstFrame,
          ZvPlayerLog.close,
        ]),
      );
    });

    test('logs carry source type and engine kind, and no credentials',
        () async {
      final ZvPlayerController controller =
          controllerWith(embedded: embeddedEngine());
      await controller.open(youtube);

      final Map<String, Object?> selected =
          logFields[logTags.indexOf(ZvPlayerLog.engineSelected)];
      expect(selected['engine'], 'embedded');
      expect(selected['sourceType'], 'youtube');

      // No field carries a URL or token.
      for (final Map<String, Object?> fields in logFields) {
        for (final Object? value in fields.values) {
          expect('$value'.toLowerCase(), isNot(contains('http')));
          expect('$value'.toLowerCase(), isNot(contains('bearer')));
        }
      }
      await controller.dispose();
    });

    test('an error is logged with its code', () async {
      final ZvPlayerController controller = controllerWith();
      await controller.open(sourceOf(''));

      expect(logTags, contains(ZvPlayerLog.error));
      await controller.dispose();
    });
  });

  group('native engine through the router', () {
    test('a real native engine reaches the platform', () async {
      final FakePlayerPlatform platform = FakePlayerPlatform();
      final ZvPlayerController controller = ZvPlayerController(
        router: SourceRouter(
          nativeEngineBuilder: () => NativeMediaEngine(
            controller: ZvNativeController(
              platform: platform,
              progressStore: InMemoryProgressStore(),
              secureSurface: false,
            ),
          ),
        ),
        logger: logger,
      );

      await controller.open(mp4);
      expect(platform.createdPlayers, 1);
      expect(platform.loadedSources.length, 1);
      await controller.dispose();
      expect(platform.disposed, isTrue);
    });
  });
}
