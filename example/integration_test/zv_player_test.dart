// On-device acceptance for ZV Player. Run from example/:
//   flutter test integration_test/zv_player_test.dart -d <device>
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zv_player/src/widgets/zv_error_view.dart';
import 'package:zv_player/src/widgets/zv_progress_bar.dart';
import 'package:zv_player/zv_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> until(
    WidgetTester tester,
    bool Function() condition,
    String description,
  ) async {
    for (int i = 0; i < 160 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(condition(), isTrue, reason: description);
  }

  Future<ZvPlayerController> open(WidgetTester tester, String uri) async {
    final ZvPlayerController controller = ZvPlayerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ZvPlayer(controller: controller, title: uri, onBack: () {}),
        ),
      ),
    );
    await controller.open(ZvMediaSource.detect(uri: uri));
    await tester.pump();
    return controller;
  }

  Future<void> close(WidgetTester tester, ZvPlayerController c) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await c.dispose();
  }

  /// Plays, pauses, seeks and resumes through ZV Player's own controller,
  /// with ZV Player's chrome on screen.
  Future<void> playsInZvPlayer(
    WidgetTester tester,
    String uri, {
    required PlaybackEngineKind engine,
  }) async {
    final ZvPlayerController c = await open(tester, uri);
    expect(c.engineKind, engine);
    await until(
      tester,
      () => c.value.position > const Duration(seconds: 2),
      'playback advances',
    );
    // ZV Player's chrome is the UI: progress bar and transport are ours.
    expect(find.byType(ZvProgressBar), findsOneWidget);
    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    await c.pause();
    await until(tester, () => c.value.status == PlayerStatus.paused, 'pause');
    await c.seekTo(const Duration(seconds: 20));
    await until(
      tester,
      () =>
          (c.value.position - const Duration(seconds: 20)).abs() <
          const Duration(seconds: 3),
      'seek lands at 20s',
    );
    await c.play();
    await until(
      tester,
      () => c.value.position > const Duration(seconds: 21),
      'resumes after seek',
    );
    debugPrint(
      'ZV_ACCEPTANCE $uri engine=${engine.name} '
      'position=${c.value.position.inMilliseconds} PASS',
    );
    await close(tester, c);
  }

  testWidgets('YouTube plays inside ZV Player', (tester) async {
    await playsInZvPlayer(
      tester,
      'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
      engine: PlaybackEngineKind.embedded,
    );
  });

  testWidgets('MP4 plays natively', (tester) async {
    await playsInZvPlayer(
      tester,
      'https://media.w3.org/2010/05/sintel/trailer.mp4',
      engine: PlaybackEngineKind.native,
    );
  });

  testWidgets('HLS plays natively and seeks', (tester) async {
    await playsInZvPlayer(
      tester,
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      engine: PlaybackEngineKind.native,
    );
  });

  testWidgets('DASH routes to the native engine', (tester) async {
    const String dash =
        'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd';
    if (Platform.isAndroid) {
      await playsInZvPlayer(tester, dash, engine: PlaybackEngineKind.native);
      return;
    }
    // AVPlayer has no DASH support: routed natively, reported as an error.
    final ZvPlayerController c = await open(tester, dash);
    expect(c.engineKind, PlaybackEngineKind.native);
    await until(tester, () => c.value.hasError, 'iOS reports DASH unsupported');
    debugPrint('ZV_ACCEPTANCE dash iOS error=${c.value.error?.code} PASS');
    await close(tester, c);
  });

  testWidgets('an invalid URL shows the ZV error state', (tester) async {
    final ZvPlayerController c = await open(tester, 'not a video');
    await tester.pump(const Duration(seconds: 1));
    expect(c.engine, isNull);
    expect(c.value.error?.code, 'unsupported_source');
    expect(find.byType(ZvErrorView), findsOneWidget);
    debugPrint('ZV_ACCEPTANCE invalid url -> error state PASS');
    await close(tester, c);
  });
}
