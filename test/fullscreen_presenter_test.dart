import 'package:zv_player/src/ui/fullscreen_presenter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> chromeCalls;

  setUp(() {
    // Ownership is a global static, as it must be to survive between routes and
    // die with the isolate. Each test therefore starts as a fresh isolate does.
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

  List<String> orientationsFrom(MethodCall call) =>
      (call.arguments as List<dynamic>).cast<String>();

  MethodCall? lastCallTo(String method) {
    for (final MethodCall call in chromeCalls.reversed) {
      if (call.method == method) return call;
    }
    return null;
  }

  test('enter requests landscape and hides system chrome', () async {
    final FullscreenPresenter presenter = FullscreenPresenter();
    expect(await presenter.enter(), isTrue);
    expect(presenter.isActive, isTrue);

    expect(
      orientationsFrom(lastCallTo('SystemChrome.setPreferredOrientations')!),
      <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ],
    );
    expect(lastCallTo('SystemChrome.setEnabledSystemUIMode'), isNotNull);
  });

  test('exit restores the app baseline, not every orientation', () async {
    // The regression this guards: restoring `DeviceOrientation.values` does not
    // put the app back as it was - it unlocks rotation for the whole app, so
    // unrelated screens started rotating after the player had been opened.
    final FullscreenPresenter presenter = FullscreenPresenter();
    await presenter.enter();
    expect(await presenter.exit(), isTrue);

    final List<String> restored =
        orientationsFrom(lastCallTo('SystemChrome.setPreferredOrientations')!);
    expect(restored, <String>['DeviceOrientation.portraitUp']);
    expect(restored.length, 1);
    expect(restored, isNot(contains('DeviceOrientation.landscapeLeft')));
    expect(presenter.isActive, isFalse);
  });

  test('honours a custom baseline', () async {
    final FullscreenPresenter presenter = FullscreenPresenter(
      baseOrientations: const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    );
    await presenter.enter();
    await presenter.exit();

    expect(
      orientationsFrom(lastCallTo('SystemChrome.setPreferredOrientations')!),
      <String>[
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ],
    );
  });

  test('enter and exit are idempotent', () async {
    final FullscreenPresenter presenter = FullscreenPresenter();

    expect(await presenter.enter(), isTrue);
    expect(await presenter.enter(), isFalse, reason: 'already fullscreen');
    expect(await presenter.exit(), isTrue);
    expect(await presenter.exit(), isFalse, reason: 'already windowed');
    expect(presenter.isActive, isFalse);
  });

  test('repeated enter/exit cycles leave the app on its baseline', () async {
    final FullscreenPresenter presenter = FullscreenPresenter();
    for (int i = 0; i < 3; i++) {
      await presenter.enter();
      await presenter.exit();
    }

    expect(presenter.isActive, isFalse);
    expect(
      orientationsFrom(lastCallTo('SystemChrome.setPreferredOrientations')!),
      <String>['DeviceOrientation.portraitUp'],
    );
  });

  test('restoreSynchronously puts the baseline back from a dispose path',
      () async {
    final FullscreenPresenter presenter = FullscreenPresenter();
    await presenter.enter();

    presenter.restoreSynchronously();
    await Future<void>.delayed(Duration.zero);

    expect(presenter.isActive, isFalse);
    expect(
      orientationsFrom(lastCallTo('SystemChrome.setPreferredOrientations')!),
      <String>['DeviceOrientation.portraitUp'],
    );
  });

  test('restoreSynchronously does nothing when not fullscreen', () async {
    final FullscreenPresenter presenter = FullscreenPresenter();
    chromeCalls.clear();

    presenter.restoreSynchronously();
    await Future<void>.delayed(Duration.zero);

    expect(chromeCalls, isEmpty);
  });
}
