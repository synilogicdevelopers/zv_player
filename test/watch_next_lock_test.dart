import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/src/widgets/zv_player_controls.dart';
import 'package:zv_player/zv_player.dart';

import 'fake_player_platform.dart';

/// Minimal engine: lock mode and the secondary row must not depend on what
/// happens to be playing.
class _StubEngine implements PlaybackEngine {
  final ValueNotifier<ZvPlayerState> _state =
      ValueNotifier<ZvPlayerState>(const ZvPlayerState());
  bool _initialized = false;
  bool _disposed = false;

  @override
  PlaybackEngineKind get kind => PlaybackEngineKind.embedded;
  @override
  ValueListenable<ZvPlayerState> get state => _state;
  @override
  EngineCapabilities get capabilities =>
      EngineCapabilities(canPlayPause: true, canSeek: true);
  @override
  bool get isInitialized => _initialized;
  @override
  bool get isDisposed => _disposed;
  @override
  Future<void> initialize() async => _initialized = true;
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
  Widget buildSurface(BuildContext context) => const SizedBox.expand();
  @override
  Future<void> dispose() async {
    _disposed = true;
    _state.dispose();
  }
}

void main() {
  group('Watch Next in the secondary row', () {
    late FakePlayerPlatform platform;
    late ZvNativeController controller;

    setUp(() async {
      platform = FakePlayerPlatform();
      controller = ZvNativeController(
        platform: platform,
        progressStore: InMemoryProgressStore(),
        secureSurface: false,
      );
      await controller.initialise();
    });

    tearDown(() async {
      if (controller.playerId != null) await controller.dispose();
    });

    Future<void> pumpControls(
      WidgetTester tester, {
      VoidCallback? onWatchNext,
      String watchNextLabel = 'Watch Next',
      VoidCallback? onLock,
    }) async {
      const ZvPlayerState state = ZvPlayerState(status: PlayerStatus.playing);
      controller.value = state;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZvPlayerThemeScope(
            theme: ZvPlayerTheme.standard,
            child: ZvPlayerControls(
              sink: controller,
              capabilities: const EngineCapabilities.nativeMedia(),
              state: state,
              visible: true,
              onInteraction: () {},
              onWatchNext: onWatchNext,
              watchNextLabel: watchNextLabel,
              onLock: onLock ?? () {},
              onToggleFullscreen: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('leads the row, ahead of Lock', (WidgetTester tester) async {
      await pumpControls(tester, onWatchNext: () {});

      expect(find.text('Watch Next'), findsOneWidget);
      expect(find.text('Lock'), findsOneWidget);
      // Same row, so the one that comes first sits further left.
      expect(tester.getTopLeft(find.text('Watch Next')).dx,
          lessThan(tester.getTopLeft(find.text('Lock')).dx),
          reason: 'Watch Next must be positioned before Lock');
    });

    testWidgets('is absent when the host offers none', (tester) async {
      await pumpControls(tester);

      expect(find.text('Watch Next'), findsNothing,
          reason: 'No handler, no control - as with every other chip');
      expect(find.text('Lock'), findsOneWidget,
          reason: 'The rest of the row is untouched');
    });

    testWidgets('carries the host wording', (WidgetTester tester) async {
      await pumpControls(tester,
          onWatchNext: () {}, watchNextLabel: 'More like this');

      expect(find.text('More like this'), findsOneWidget);
      expect(find.text('Watch Next'), findsNothing,
          reason: 'A film has no next episode to promise');
      expect(tester.getTopLeft(find.text('More like this')).dx,
          lessThan(tester.getTopLeft(find.text('Lock')).dx),
          reason: 'Position does not depend on the wording');
    });

    testWidgets('reports the tap to the host', (WidgetTester tester) async {
      int taps = 0;
      await pumpControls(tester, onWatchNext: () => taps++);

      await tester.tap(find.text('Watch Next'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('lock mode', () {
    ZvPlayerController controllerWith(_StubEngine engine) => ZvPlayerController(
          router: SourceRouter(youTubeEngineBuilder: () => engine),
          logger: (_, __) {},
        );

    /// The player as a host uses it: a Watch Next handler supplied, and the
    /// host listening for lock so it can manage anything it draws itself.
    Future<List<bool>> pumpPlayer(WidgetTester tester,
        {required ZvPlayerController controller}) async {
      final List<bool> lockEvents = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZvPlayer(
            controller: controller,
            autoEnterFullscreen: false,
            onWatchNext: () {},
            onLockChanged: lockEvents.add,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return lockEvents;
    }

    testWidgets('locking hides Watch Next and tells the host',
        (WidgetTester tester) async {
      final ZvPlayerController controller = controllerWith(_StubEngine());
      await controller.open(ZvMediaSource.detect(
          uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k',
          declaredType: 'YouTube'));
      final List<bool> lockEvents =
          await pumpPlayer(tester, controller: controller);

      // Unlocked: Watch Next is there to be used.
      expect(find.text('Watch Next'), findsOneWidget);
      expect(lockEvents, isEmpty, reason: 'Nothing has happened yet');

      await tester.tap(find.byTooltip('Lock player'));
      await tester.pumpAndSettle();

      expect(lockEvents, <bool>[true], reason: 'The host must hear the lock');
      expect(find.text('Watch Next'), findsNothing,
          reason: 'Locked: Watch Next must not be visible or tappable');
      expect(find.byTooltip('Unlock player'), findsOneWidget);

      await tester.tap(find.byTooltip('Unlock player'));
      await tester.pumpAndSettle();

      expect(lockEvents, <bool>[true, false],
          reason: 'And hear the unlock, so it can restore its own overlay');
      expect(find.text('Watch Next'), findsOneWidget,
          reason: 'Unlocking restores Watch Next');
      expect(find.text('Lock'), findsOneWidget,
          reason: 'The rest of the chrome comes back too');
      await controller.dispose();
    });

    testWidgets('a host that ignores lock still locks normally',
        (WidgetTester tester) async {
      final ZvPlayerController controller = controllerWith(_StubEngine());
      await controller.open(ZvMediaSource.detect(
          uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k',
          declaredType: 'YouTube'));
      // No onWatchNext, no onLockChanged: exactly a pre-0.1.5 consumer.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZvPlayer(controller: controller, autoEnterFullscreen: false),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Watch Next'), findsNothing);
      await tester.tap(find.byTooltip('Lock player'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unlock player'), findsOneWidget,
          reason: 'Lock behaviour is unchanged for existing consumers');
      await tester.tap(find.byTooltip('Unlock player'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Lock player'), findsOneWidget);
      await controller.dispose();
    });
  });
}
