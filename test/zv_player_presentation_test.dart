import 'package:zv_player/zv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal engine: the player's presentation must not depend on what plays.
class _StubEngine implements PlaybackEngine {
  _StubEngine({this.failOnInitialize = false, this.surface});

  final bool failOnInitialize;

  /// Lets a test supply a surface that notices when it is torn down and
  /// rebuilt, which is how platform-view recreation is detected.
  final Widget? surface;
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
  Future<void> initialize() async {
    if (failOnInitialize) throw StateError('engine unavailable');
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
  Widget buildSurface(BuildContext context) =>
      surface ?? const SizedBox.expand();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _state.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> chromeCalls;

  setUp(() {
    // A fresh isolate owns nothing; keep tests independent of each other.
    AppOrientationBaseline.debugResetOwners();
    chromeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform,
            (MethodCall call) async {
      chromeCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<List<String>> orientationRequests() => chromeCalls
      .where(
          (MethodCall c) => c.method == 'SystemChrome.setPreferredOrientations')
      .map((MethodCall c) => (c.arguments as List<dynamic>).cast<String>())
      .toList();

  const List<String> landscape = <String>[
    'DeviceOrientation.landscapeLeft',
    'DeviceOrientation.landscapeRight',
  ];
  const List<String> portrait = <String>['DeviceOrientation.portraitUp'];

  ZvPlayerController controllerWith(_StubEngine engine) {
    return ZvPlayerController(
      router: SourceRouter(youTubeEngineBuilder: () => engine),
      logger: (_, __) {},
    );
  }

  Future<ZvPlayerController> pumpPlayer(
    WidgetTester tester, {
    bool autoEnterFullscreen = true,
    _StubEngine? engine,
  }) async {
    final ZvPlayerController controller =
        controllerWith(engine ?? _StubEngine());
    await controller.open(
      ZvMediaSource.detect(
        uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k',
        declaredType: 'YouTube',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZvPlayer(
            controller: controller,
            autoEnterFullscreen: autoEnterFullscreen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
      'a YouTube source gets the full ZV Player chrome over its surface',
      (tester) async {
    _SurfaceProbe.builds = 0;
    final ZvPlayerController controller =
        controllerWith(_StubEngine(surface: const _SurfaceProbe()));
    await controller.open(ZvMediaSource.detect(
        uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k',
        declaredType: 'YouTube'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ZvPlayer(
                controller: controller, title: 'Dhurandar', onBack: () {}))));
    await tester.pumpAndSettle();

    // One surface, and ZV Player's own controls stacked over it.
    expect(find.byType(_SurfaceProbe), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    final Rect surface = tester.getRect(find.byType(_SurfaceProbe));
    expect(
        surface.contains(tester.getCenter(find.byTooltip('Settings'))), isTrue);
    expect(_SurfaceProbe.builds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });

  group('opens in landscape theater', () {
    testWidgets('entering the player requests landscape only', (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);

      expect(orientationRequests(), isNotEmpty);
      expect(orientationRequests().first, landscape);
      expect(controller.value.isFullscreen, isTrue);
      expect(controller.value.isFullscreen, isTrue);

      await controller.dispose();
    });

    testWidgets('immersive system UI is requested on entry', (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);

      final Iterable<MethodCall> uiModes = chromeCalls.where(
        (MethodCall c) => c.method == 'SystemChrome.setEnabledSystemUIMode',
      );
      expect(uiModes, isNotEmpty);
      expect('${uiModes.first.arguments}', contains('immersiveSticky'));

      await controller.dispose();
    });

    testWidgets('a rebuild does not re-issue orientation calls',
        (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);
      final int before = orientationRequests().length;

      // Force several rebuilds the way playback progress would.
      for (int i = 0; i < 3; i++) {
        controller.value = controller.value.copyWith(
            position: Duration(seconds: i),
            duration: const Duration(minutes: 5));
        await tester.pump();
      }

      expect(orientationRequests().length, before);
      await controller.dispose();
    });

    testWidgets('autoEnterFullscreen false leaves orientation untouched',
        (tester) async {
      final ZvPlayerController controller =
          await pumpPlayer(tester, autoEnterFullscreen: false);

      expect(orientationRequests(), isEmpty);
      expect(controller.value.isFullscreen, isFalse);

      await controller.dispose();
    });
  });

  group('restoration never unlocks the app', () {
    testWidgets('leaving the player restores portrait only', (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(orientationRequests().last, portrait);
      await controller.dispose();
    });

    testWidgets('no restoration ever requests the full orientation set',
        (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // The old bug: restoring with DeviceOrientation.values left the whole
      // app rotatable. Every request must be one of the two explicit sets.
      for (final List<String> request in orientationRequests()) {
        expect(request.length, lessThanOrEqualTo(2));
        expect(
          request,
          anyOf(equals(landscape), equals(portrait)),
        );
        expect(request, isNot(contains('DeviceOrientation.portraitDown')));
      }
      await controller.dispose();
    });

    testWidgets('an engine that fails to start still restores portrait',
        (tester) async {
      final ZvPlayerController controller = await pumpPlayer(
        tester,
        engine: _StubEngine(failOnInitialize: true),
      );
      expect(controller.value.hasError, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(orientationRequests().last, portrait);
      await controller.dispose();
    });

    testWidgets('immediate Back before playback is ready restores portrait',
        (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);

      // Disposed straight after entry, as a fast Back would.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(orientationRequests().last, portrait);
      await controller.dispose();
    });
  });

  // A presentation change must never re-parent the engine's surface. On
  // Android the embed is a hybrid-composition platform view: if the widget at
  // that slot changes type, Flutter unmounts the subtree and the WebView -
  // with the provider's player object inside it - is destroyed and rebuilt.
  // Entering fullscreen on route entry did exactly that, killing playback
  // milliseconds after it started.
  group('the video surface survives presentation changes', () {
    testWidgets('entering fullscreen does not rebuild the surface',
        (tester) async {
      _SurfaceProbe.builds = 0;
      final _StubEngine engine = _StubEngine(surface: const _SurfaceProbe());
      final ZvPlayerController controller = await pumpPlayer(
        tester,
        engine: engine,
      );
      await tester.pumpAndSettle();

      expect(_SurfaceProbe.builds, 1);
      expect(controller.value.isFullscreen, isTrue);

      await controller.dispose();
    });

    testWidgets('normal and fullscreen keep one surface', (tester) async {
      _SurfaceProbe.builds = 0;
      final _StubEngine engine = _StubEngine(surface: const _SurfaceProbe());
      final ZvPlayerController controller = await pumpPlayer(
        tester,
        autoEnterFullscreen: false,
        engine: engine,
      );
      await tester.pumpAndSettle();
      expect(_SurfaceProbe.builds, 1);

      controller.setFullscreen(true);
      await tester.pumpAndSettle();

      // One creation for the whole session, whatever the presentation did.
      expect(_SurfaceProbe.builds, 1);

      await controller.dispose();
    });
  });

  group('back behaviour and idempotency', () {
    testWidgets('Back collapses fullscreen before it pops the route',
        (tester) async {
      final ZvPlayerController controller = controllerWith(_StubEngine());
      await controller.open(
        ZvMediaSource.detect(
            uri: 'https://youtu.be/abc', declaredType: 'YouTube'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZvPlayer(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.value.isFullscreen, isTrue);

      // First Back: collapses presentation, route stays.
      final bool popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(popped, isTrue, reason: 'the route handled the pop itself');
      expect(controller.value.isFullscreen, isFalse);
      expect(orientationRequests().last, portrait);
      expect(find.byType(ZvPlayer), findsOneWidget,
          reason: 'the player is still on screen after the first Back');

      await controller.dispose();
    });

    testWidgets('repeated enter/exit ends on the app baseline', (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);

      for (int i = 0; i < 3; i++) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(controller.value.isFullscreen, isFalse);

        await tester.tap(find.byIcon(Icons.fullscreen_rounded));
        await tester.pumpAndSettle();
        expect(controller.value.isFullscreen, isTrue);
      }

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(orientationRequests().last, portrait);
      await controller.dispose();
    });

    /// One player route replacing another - "play next", or any rebuild that
    /// re-keys the view. Flutter builds the incoming element before unmounting
    /// the outgoing one, so the dying player's teardown runs *after* the live
    /// player has already asked for landscape. Restoring unconditionally there
    /// dropped a fullscreen video back into portrait.
    testWidgets('a player replacing another keeps landscape through hand-over',
        (tester) async {
      final ZvPlayerController first = await pumpPlayer(tester);
      expect(orientationRequests().last, landscape);
      expect(AppOrientationBaseline.isOwnedByPlayer, isTrue);

      chromeCalls.clear();

      // The replacement route is built while the outgoing one is still alive.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZvPlayer(key: UniqueKey(), controller: first),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(orientationRequests().last, landscape,
          reason: 'the outgoing player must not restore over a live one');
      expect(AppOrientationBaseline.isOwnedByPlayer, isTrue);
      expect(await AppOrientationBaseline.restoreIfUnowned(), isFalse,
          reason: 'the incoming player owns landscape legitimately');

      // ...and the survivor still hands the app back when it finally goes.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
      expect(orientationRequests().last, portrait);
      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse);

      await first.dispose();
      // Let the release land here rather than in the next test's call list.
      await tester.pump();
    });

    testWidgets('once the player route is gone the app is back on portrait',
        (tester) async {
      final ZvPlayerController controller = await pumpPlayer(tester);
      expect(orientationRequests().last, landscape);

      // The route is removed, which is what a Back out of the player does.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      expect(orientationRequests().last, portrait);
      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse,
          reason: 'a removed route must not keep owning landscape');
      // Nothing is left for the start-up heal to undo.
      chromeCalls.clear();
      expect(await AppOrientationBaseline.restoreIfUnowned(), isTrue);
      expect(orientationRequests().last, portrait);

      await controller.dispose();
      // Drain this test's own teardown so a late restore cannot be recorded
      // against the next test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pump();
    });
  });
}

/// Counts how many times it is *created*, not rebuilt. A platform view being
/// re-parented shows up here as a second initState.
class _SurfaceProbe extends StatefulWidget {
  const _SurfaceProbe();

  static int builds = 0;

  @override
  State<_SurfaceProbe> createState() => _SurfaceProbeState();
}

class _SurfaceProbeState extends State<_SurfaceProbe> {
  @override
  void initState() {
    super.initState();
    _SurfaceProbe.builds++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
