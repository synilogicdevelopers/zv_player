import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/zv_player.dart';

/// The field bug: a Content Details page autoplays its trailer, the viewer
/// taps through to Sign In, and the trailer keeps playing - audibly - behind
/// it. Pushing a page does not dispose the page underneath, so nothing ever
/// told the engine to stop.
///
/// An engine that records what it was asked to do, and can hold its
/// initialisation open so a test can navigate mid-open.
class _Engine implements PlaybackEngine {
  _Engine({this.hold, this.pip = false});

  final Completer<void>? hold;
  final bool pip;
  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());

  int pauseCalls = 0;
  bool _disposed = false;

  /// Starts playing the way a real engine does once it has loaded.
  void reportPlaying() {
    if (_disposed) return;
    _state.value = _state.value.copyWith(
        status: PlayerStatus.playing, isPip: pip, volume: 1, isMuted: false);
  }

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.native;
  @override
  ValueListenable<ZvPlayerState> get state => _state;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities.nativeMedia();
  @override
  bool get isInitialized => true;
  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> initialize() async {
    if (hold != null) await hold!.future;
  }

  @override
  Future<void> load(ZvMediaSource source, {bool autoPlay = true}) async {
    if (_disposed || !autoPlay) return;
    reportPlaying();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    pauseCalls++;
    _state.value = _state.value.copyWith(status: PlayerStatus.paused);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _state.dispose();
  }

  @override
  Future<void> play() async => reportPlaying();
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
  late _Engine engine;

  ZvPlayerController controllerWith({Completer<void>? hold, bool pip = false}) {
    return ZvPlayerController(
      router: SourceRouter(nativeEngineBuilder: () {
        engine = _Engine(hold: hold, pip: pip);
        return engine;
      }),
      logger: (_, __) {},
    );
  }

  final ZvMediaSource trailer =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/trailer.mp4');

  /// A details page holding an inline player, with a button that pushes a
  /// Sign In page over it - exactly the app's navigation.
  Future<NavigatorState> pumpDetailsPage(
    WidgetTester tester,
    ZvPlayerController controller, {
    bool pauseWhenRouteObscured = true,
  }) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: ZvPlayer(
          controller: controller,
          autoEnterFullscreen: false,
          pauseWhenRouteObscured: pauseWhenRouteObscured,
        ),
      ),
    ));
    await tester.pump();
    return navigator.currentState!;
  }

  Future<void> pushSignIn(WidgetTester tester, NavigatorState navigator) async {
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Sign In')))));
    // One frame is all the viewer needs to have "left": the push has begun.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('leaving the page for Sign In stops the trailer and its audio',
      (WidgetTester tester) async {
    final ZvPlayerController controller = controllerWith();
    final NavigatorState navigator = await pumpDetailsPage(tester, controller);
    await controller.open(trailer);
    await tester.pump();
    expect(controller.value.isPlaying, isTrue, reason: 'trailer autoplays');

    await pushSignIn(tester, navigator);

    expect(controller.value.isPlaying, isFalse,
        reason: 'playback must stop when the page is covered');
    expect(engine.pauseCalls, greaterThan(0),
        reason: 'the engine itself must be paused, not just the UI');
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse,
        reason: 'and must stay stopped once the push settles');
    await controller.dispose();
  });

  testWidgets('an engine still loading when the page is left never starts',
      (WidgetTester tester) async {
    final Completer<void> hold = Completer<void>();
    final ZvPlayerController controller = controllerWith(hold: hold);
    final NavigatorState navigator = await pumpDetailsPage(tester, controller);
    final Future<void> opening = controller.open(trailer);
    await tester.pump();

    await pushSignIn(tester, navigator);
    // The engine only finishes initialising now, after the viewer has gone.
    hold.complete();
    await opening;
    await tester.pumpAndSettle();

    expect(controller.value.isPlaying, isFalse,
        reason: 'a late open must not resurrect playback behind Sign In');
    await controller.dispose();
  });

  testWidgets('coming back leaves the player paused, not silently resumed',
      (WidgetTester tester) async {
    final ZvPlayerController controller = controllerWith();
    final NavigatorState navigator = await pumpDetailsPage(tester, controller);
    await controller.open(trailer);
    await tester.pump();

    await pushSignIn(tester, navigator);
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(controller.value.isPlaying, isFalse);
    expect(find.byType(ZvPlayer), findsOneWidget,
        reason: 'the player is still there, ready to be played again');
    await controller.dispose();
  });

  testWidgets('the player\'s own settings sheet does not stop playback',
      (WidgetTester tester) async {
    final ZvPlayerController controller = controllerWith();
    await pumpDetailsPage(tester, controller);
    await controller.open(trailer);
    await tester.pump();

    // Opened the way a viewer opens it, from the player's own controls.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(ZvSettingsSheet), findsOneWidget);

    expect(controller.value.isPlaying, isTrue,
        reason: 'changing quality is not leaving the video');

    Navigator.of(tester.element(find.byType(ZvSettingsSheet))).pop();
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isTrue);
    await controller.dispose();
  });

  testWidgets('a player in Picture in Picture keeps playing when covered',
      (WidgetTester tester) async {
    final ZvPlayerController controller = controllerWith(pip: true);
    final NavigatorState navigator = await pumpDetailsPage(tester, controller);
    await controller.open(trailer);
    await tester.pump();
    expect(controller.value.isPip, isTrue);

    await pushSignIn(tester, navigator);
    await tester.pumpAndSettle();

    expect(controller.value.isPlaying, isTrue,
        reason: 'a floating window is meant to outlive its page');
    await controller.dispose();
  });

  testWidgets('disposing the page releases the engine', (tester) async {
    final ZvPlayerController controller = controllerWith();
    await pumpDetailsPage(tester, controller);
    await controller.open(trailer);
    await tester.pump();
    final _Engine opened = engine;

    // The route is gone for good, as on a back navigation.
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();

    expect(opened.isDisposed, isTrue, reason: 'no engine may survive the page');
    expect(controller.engine, isNull);
  });

  group('release()', () {
    test('stops playback, drops the engine, and leaves the controller usable',
        () async {
      final ZvPlayerController controller = controllerWith();
      await controller.open(trailer);
      final _Engine first = engine;
      expect(controller.value.isPlaying, isTrue);

      await controller.release();

      expect(first.isDisposed, isTrue);
      expect(controller.engine, isNull);
      expect(controller.isDisposed, isFalse);
      expect(controller.value.isPlaying, isFalse);
      expect(controller.value.position, Duration.zero);

      // Reusable: a fresh source gets a fresh engine.
      await controller.open(trailer);
      expect(controller.engine, isNotNull);
      expect(identical(controller.engine, first), isFalse);
      await controller.dispose();
    });

    test('is safe to call twice, and after dispose', () async {
      final ZvPlayerController controller = controllerWith();
      await controller.open(trailer);
      await controller.release();
      await controller.release();
      await controller.dispose();
      await controller.release();
      expect(controller.engine, isNull);
    });
  });
}
