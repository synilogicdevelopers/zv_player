import 'package:zv_player/zv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

/// Minimal stand-in for an engine that lives outside this package.
class _FakeEmbeddedEngine implements PlaybackEngine {
  static int built = 0;
  static int initialised = 0;

  _FakeEmbeddedEngine() {
    built++;
  }

  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());
  bool _initialized = false;
  bool _disposed = false;

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.embedded;

  @override
  ValueListenable<ZvPlayerState> get state => _state;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
        canSeek: true,
        canMute: true,
      );

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> initialize() async {
    initialised++;
    _initialized = true;
  }

  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {}

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

  @override
  Future<void> dispose() async {
    _disposed = true;
    _state.dispose();
  }
}

void main() {
  ZvMediaSource sourceOf(String uri, {String? declaredType}) =>
      ZvMediaSource.detect(uri: uri, declaredType: declaredType);

  late SourceRouter router;

  setUp(() {
    _FakeEmbeddedEngine.built = 0;
    _FakeEmbeddedEngine.initialised = 0;
    router = SourceRouter(
      nativeEngineBuilder: () => NativeMediaEngine(
          controller: ZvNativeController(
        platform: FakePlayerPlatform(),
        secureSurface: false,
      )),
      youTubeEngineBuilder: _FakeEmbeddedEngine.new,
    );
  });

  group('routing by source', () {
    test('YouTube goes to the YouTube engine', () {
      for (final ZvMediaSource source in <ZvMediaSource>[
        sourceOf('https://www.youtube.com/watch?v=iITwUMIwI1k',
            declaredType: 'YouTube'),
        sourceOf('https://youtu.be/abc123'),
        sourceOf('https://cdn.example.com/x', declaredType: 'youtube'),
      ]) {
        expect(router.select(source).kind, PlaybackEngineKind.embedded);
      }
    });

    test('Vimeo and generic iframes are unsupported, with a reason', () {
      for (final ZvMediaSource source in <ZvMediaSource>[
        sourceOf('https://vimeo.com/12345'),
        sourceOf('https://x.example/v', declaredType: 'Vimeo'),
        sourceOf('https://example.com/embed/1', declaredType: 'embedded'),
      ]) {
        final EngineSelection selection = router.select(source);
        expect(selection.kind, PlaybackEngineKind.unsupported);
        expect(selection.reason, contains('not supported'));
        expect(router.createEngine(source), isNull);
      }
    });

    test('MP4 goes to the native engine', () {
      expect(
        router.select(sourceOf('https://cdn.example.com/movie.mp4')).kind,
        PlaybackEngineKind.native,
      );
    });

    test('HLS goes to the native engine', () {
      expect(
        router.select(sourceOf('https://cdn.example.com/master.m3u8')).kind,
        PlaybackEngineKind.native,
      );
      expect(
        router
            .select(sourceOf('https://cdn.example.com/s', declaredType: 'HLS'))
            .kind,
        PlaybackEngineKind.native,
      );
    });

    test('DASH goes to the native engine', () {
      expect(
        router.select(sourceOf('https://cdn.example.com/manifest.mpd')).kind,
        PlaybackEngineKind.native,
      );
    });

    test('a local file goes to the native engine', () {
      expect(
        router.select(sourceOf('/data/user/0/app/files/movie.mp4')).kind,
        PlaybackEngineKind.native,
      );
      expect(
        router.select(sourceOf('file:///tmp/a.mp4')).kind,
        PlaybackEngineKind.native,
      );
    });

    test('an unclassifiable source is rejected cleanly', () {
      final EngineSelection selection = router.select(sourceOf(''));
      expect(selection.kind, PlaybackEngineKind.unsupported);
      expect(selection.isPlayable, isFalse);
      expect(selection.reason, isNotEmpty);
      expect(router.createEngine(sourceOf('')), isNull);
    });

    test('every selection explains itself', () {
      expect(
        router.select(sourceOf('https://youtu.be/a')).reason,
        contains('YouTube'),
      );
      expect(
        router.select(sourceOf('https://x/a.m3u8')).reason,
        contains('hls'),
      );
    });
  });

  group('engine construction', () {
    test('selecting does not build or initialise any engine', () {
      router.select(sourceOf('https://youtu.be/abc'));
      router.selectForType(ZvSourceType.hls);

      expect(_FakeEmbeddedEngine.built, 0);
      expect(_FakeEmbeddedEngine.initialised, 0);
    });

    test('createEngine builds the right engine, still uninitialised', () async {
      final PlaybackEngine? embedded =
          router.createEngine(sourceOf('https://youtu.be/abc'));
      expect(embedded, isA<_FakeEmbeddedEngine>());
      expect(embedded!.isInitialized, isFalse,
          reason: 'routing must complete before resources are acquired');
      expect(_FakeEmbeddedEngine.initialised, 0);

      final PlaybackEngine? native =
          router.createEngine(sourceOf('https://cdn.example.com/a.mp4'));
      expect(native, isA<NativeMediaEngine>());
      expect(native!.isInitialized, isFalse);

      await embedded.dispose();
      await native.dispose();
    });

    test('an unregistered engine yields null rather than a wrong engine', () {
      const SourceRouter nativeOnly = SourceRouter();
      expect(nativeOnly.hasYouTubeEngine, isFalse);
      expect(nativeOnly.hasNativeEngine, isFalse);
      expect(nativeOnly.createEngine(sourceOf('https://youtu.be/a')), isNull);
      // The decision is still correct even with nothing registered.
      expect(
        nativeOnly.select(sourceOf('https://youtu.be/a')).kind,
        PlaybackEngineKind.embedded,
      );
    });
  });
}
