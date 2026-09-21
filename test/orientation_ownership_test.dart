import 'dart:io';

import 'package:zv_player/zv_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Orientation ownership: the app owns portrait, the player borrows landscape
/// and must always give it back.
///
/// A literal Android hot restart cannot be produced in a unit test - it is a
/// native-side event. What *is* testable is the semantics that made the device
/// bug possible: orientation lives outside Dart, so the release path must not
/// depend on a widget's `dispose()` having run. These tests therefore simulate
/// a restart as "the Dart state is gone, start-up runs again" and assert the
/// baseline is re-established.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> chromeCalls;

  setUp(() {
    // Statics survive between tests but not a hot restart; start each test as a
    // freshly started isolate would.
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

  List<String> uiModes() => chromeCalls
      .where(
          (MethodCall c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
      .map((MethodCall c) => '${c.arguments}')
      .toList();

  const List<String> landscape = <String>[
    'DeviceOrientation.landscapeLeft',
    'DeviceOrientation.landscapeRight',
  ];
  const List<String> portrait = <String>['DeviceOrientation.portraitUp'];

  group('app baseline', () {
    test('is portrait only, and never the full orientation set', () {
      expect(AppOrientationBaseline.orientations, <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      expect(
        AppOrientationBaseline.orientations.length,
        lessThan(DeviceOrientation.values.length),
      );
    });

    test('restore requests portrait and normal system UI', () async {
      await AppOrientationBaseline.restore();

      expect(orientationRequests().single, portrait);
      expect(uiModes().single, contains('edgeToEdge'));
    });

    test('restore is safe to call repeatedly', () async {
      await AppOrientationBaseline.restore();
      await AppOrientationBaseline.restore();

      for (final List<String> request in orientationRequests()) {
        expect(request, portrait);
      }
    });

    test('the presenter defaults to the same baseline', () async {
      final FullscreenPresenter presenter = FullscreenPresenter();
      expect(presenter.baseOrientations, AppOrientationBaseline.orientations);

      await presenter.enter();
      await presenter.exit();
      expect(orientationRequests().last, portrait);
    });
  });

  group('hot restart semantics', () {
    test('start-up clears landscape left behind by a previous run', () async {
      // A player was mid-fullscreen when the isolate died.
      final FullscreenPresenter beforeRestart = FullscreenPresenter();
      await beforeRestart.enter();
      expect(orientationRequests().last, landscape);

      // Hot restart: Dart state is discarded without dispose() running, so no
      // exit() ever happens. Only start-up can put this right.
      chromeCalls.clear();
      await AppOrientationBaseline.restore();

      expect(orientationRequests().last, portrait,
          reason: 'the app must not inherit the old landscape request');
    });

    test('a restarted isolate starts with no presenter believing it is active',
        () async {
      final FullscreenPresenter beforeRestart = FullscreenPresenter();
      await beforeRestart.enter();
      expect(beforeRestart.isActive, isTrue);

      // The restart also destroys the ownership count, exactly as it destroys
      // the presenter that was holding landscape. Without this the old claim
      // would linger and the new presentation would look like a hand-over.
      AppOrientationBaseline.debugResetOwners();

      // The replacement instance after restart holds no stale state.
      final FullscreenPresenter afterRestart = FullscreenPresenter();
      expect(afterRestart.isActive, isFalse);
      // ...so it can acquire landscape again cleanly if a player is rebuilt.
      expect(await afterRestart.enter(), isTrue);
      expect(orientationRequests().last, landscape);

      await afterRestart.exit();
      expect(orientationRequests().last, portrait);
    });

    test('a player rebuilt after restart may reacquire landscape, then release',
        () async {
      await AppOrientationBaseline.restore();
      final FullscreenPresenter presenter = FullscreenPresenter();

      await presenter.enter();
      expect(orientationRequests().last, landscape);

      await presenter.exit();
      expect(orientationRequests().last, portrait);
    });

    test('restart after the player was already closed stays portrait',
        () async {
      final FullscreenPresenter presenter = FullscreenPresenter();
      await presenter.enter();
      await presenter.exit();

      chromeCalls.clear();
      await AppOrientationBaseline.restore();

      expect(orientationRequests().last, portrait);
    });

    test('restart before any player is opened stays portrait', () async {
      await AppOrientationBaseline.restore();

      expect(orientationRequests().single, portrait);
      expect(orientationRequests().any((List<String> r) => r == landscape),
          isFalse);
    });
  });

  group('no request ever unlocks the app', () {
    test('every orientation request is one of the two explicit sets', () async {
      await AppOrientationBaseline.restore();
      final FullscreenPresenter presenter = FullscreenPresenter();

      for (int i = 0; i < 3; i++) {
        await presenter.enter();
        await presenter.exit();
      }
      presenter.restoreSynchronously();
      await Future<void>.delayed(Duration.zero);

      for (final List<String> request in orientationRequests()) {
        expect(request, anyOf(equals(portrait), equals(landscape)));
        expect(request.length, lessThanOrEqualTo(2));
      }
      expect(orientationRequests().last, portrait,
          reason: 'repeated cycles must end on the app baseline');
    });

    test('system UI never stays immersive after release', () async {
      final FullscreenPresenter presenter = FullscreenPresenter();
      await presenter.enter();
      await presenter.exit();

      expect(uiModes().last, contains('edgeToEdge'));
    });
  });

  group('dismissal while entry is still in flight', () {
    test('a player popped mid-entry still gives landscape back', () async {
      final FullscreenPresenter presenter = FullscreenPresenter();

      // The route is popped after landscape has been asked for but before the
      // platform has finished applying it. This used to release nothing: the
      // Activity stayed landscape with no widget left alive to restore it.
      final Future<bool> entering = presenter.enter();
      presenter.restoreSynchronously();
      expect(await entering, isFalse,
          reason: 'an abandoned entry must not report success');

      await Future<void>.delayed(Duration.zero);
      expect(orientationRequests().last, portrait);
      expect(presenter.isActive, isFalse);
      expect(presenter.ownsOrientation, isFalse);
      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse);
    });

    test('exit() during an in-flight entry releases too', () async {
      final FullscreenPresenter presenter = FullscreenPresenter();

      final Future<bool> entering = presenter.enter();
      expect(await presenter.exit(), isTrue);
      await entering;

      await Future<void>.delayed(Duration.zero);
      expect(orientationRequests().last, portrait);
      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse);
    });

    test('system UI does not stay immersive after an abandoned entry',
        () async {
      final FullscreenPresenter presenter = FullscreenPresenter();
      final Future<bool> entering = presenter.enter();
      presenter.restoreSynchronously();
      await entering;
      await Future<void>.delayed(Duration.zero);

      expect(uiModes().last, contains('edgeToEdge'));
    });
  });

  group('ownership registry', () {
    test('a live player owns orientation and start-up defers to it', () async {
      final FullscreenPresenter presenter = FullscreenPresenter();
      await presenter.enter();
      expect(AppOrientationBaseline.isOwnedByPlayer, isTrue);

      chromeCalls.clear();
      expect(await AppOrientationBaseline.restoreIfUnowned(), isFalse,
          reason: 'healing must never fight a player that is on screen');
      expect(orientationRequests(), isEmpty);

      await presenter.exit();
      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse);
    });

    test('with nobody owning it, the heal restores portrait', () async {
      chromeCalls.clear();
      expect(await AppOrientationBaseline.restoreIfUnowned(), isTrue);
      expect(orientationRequests().last, portrait);
    });

    test('a hot restart leaves nothing owning landscape, so the heal runs',
        () async {
      // Before the restart: a player is in fullscreen.
      final FullscreenPresenter before = FullscreenPresenter();
      await before.enter();
      expect(orientationRequests().last, landscape);

      // The restart: Dart state - including the ownership count - is gone,
      // while the Activity is still landscape. dispose() never ran.
      AppOrientationBaseline.debugResetOwners();
      chromeCalls.clear();

      expect(await AppOrientationBaseline.restoreIfUnowned(), isTrue);
      expect(orientationRequests().last, portrait);
    });

    test('release cannot go negative and orphan a live player', () async {
      AppOrientationBaseline.release();
      AppOrientationBaseline.release();
      final FullscreenPresenter presenter = FullscreenPresenter();
      await presenter.enter();

      expect(AppOrientationBaseline.isOwnedByPlayer, isTrue);
      expect(await AppOrientationBaseline.restoreIfUnowned(), isFalse);
    });

    test('two presentations in sequence each release their own claim',
        () async {
      final FullscreenPresenter first = FullscreenPresenter();
      await first.enter();
      await first.exit();
      final FullscreenPresenter second = FullscreenPresenter();
      await second.enter();
      expect(AppOrientationBaseline.isOwnedByPlayer, isTrue);
      second.restoreSynchronously();

      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(orientationRequests().last, portrait);
    });

    test('repeated release from several exit paths stays idempotent', () async {
      final FullscreenPresenter presenter = FullscreenPresenter();
      await presenter.enter();

      await presenter.exit();
      expect(await presenter.exit(), isFalse);
      presenter.restoreSynchronously();
      presenter.restoreSynchronously();

      expect(AppOrientationBaseline.isOwnedByPlayer, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(orientationRequests().last, portrait);
    });
  });

  group('Android and iOS behave identically', () {
    // Orientation is a platform-side preference on both targets: Flutter turns
    // `setPreferredOrientations` into `Activity.setRequestedOrientation` on
    // Android and into `supportedInterfaceOrientations` on iOS. Both outlive
    // the Dart isolate, so both leaked landscape after a hot restart and both
    // are healed by the same start-up call. That is only true while this layer
    // stays free of platform branches - which is what these tests pin down.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final TargetPlatform platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      final String name = platform == TargetPlatform.iOS ? 'iOS' : 'Android';

      test('$name: start-up clears landscape left by a dead isolate', () async {
        debugDefaultTargetPlatformOverride = platform;

        final FullscreenPresenter presenter = FullscreenPresenter();
        await presenter.enter();
        expect(orientationRequests().last, landscape);

        // Hot restart: statics and widgets are gone, the platform is not.
        AppOrientationBaseline.debugResetOwners();
        chromeCalls.clear();
        await AppOrientationBaseline.restore();

        expect(orientationRequests().last, portrait);
        expect(uiModes().last, contains('edgeToEdge'));
      });

      test('$name: a live player still wins over the heal', () async {
        debugDefaultTargetPlatformOverride = platform;

        final FullscreenPresenter presenter = FullscreenPresenter();
        await presenter.enter();

        chromeCalls.clear();
        expect(await AppOrientationBaseline.restoreIfUnowned(), isFalse);
        expect(orientationRequests(), isEmpty);

        await presenter.exit();
        expect(orientationRequests().last, portrait);
      });

      test('$name: enter then exit issues one identical call sequence',
          () async {
        debugDefaultTargetPlatformOverride = platform;

        final FullscreenPresenter presenter = FullscreenPresenter();
        await presenter.enter();
        await presenter.exit();

        expect(
          chromeCalls.map((MethodCall c) => c.method).toList(),
          <String>[
            'SystemChrome.setPreferredOrientations',
            'SystemChrome.setEnabledSystemUIMode',
            'SystemChrome.setEnabledSystemUIMode',
            'SystemChrome.setPreferredOrientations',
          ],
          reason: 'neither platform may need extra or reordered calls',
        );
      });
    }

    test('the orientation layer carries no platform branch', () {
      final File source = File('lib/src/ui/fullscreen_presenter.dart');
      expect(source.existsSync(), isTrue, reason: 'run from the package root');
      final String code = source.readAsStringSync();

      for (final String branch in <String>[
        'Platform.isAndroid',
        'Platform.isIOS',
        'defaultTargetPlatform',
        'dart:io',
      ]) {
        expect(code, isNot(contains(branch)),
            reason: 'orientation ownership must stay a single shared '
                'implementation; a branch here is how the platforms drift');
      }
    });
  });
}
