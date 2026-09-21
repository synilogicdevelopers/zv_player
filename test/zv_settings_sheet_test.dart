import 'package:zv_player/zv_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

/// The settings sheet is where "no fake controls" is easiest to get wrong, so
/// these tests pin what may and may not appear for each engine shape.
///
/// The sheet is a short root list of rows - icon, title, current value,
/// chevron - and choices live on a secondary panel. So the tests come in two
/// shapes: which *rows* exist for a given capability set, and what a row opens.
void main() {
  late ZvNativeController sink;

  setUp(() {
    sink = ZvNativeController(
      platform: FakePlayerPlatform(),
      progressStore: InMemoryProgressStore(),
      secureSurface: false,
    );
  });

  tearDown(() async {
    if (sink.playerId != null) await sink.dispose();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required EngineCapabilities capabilities,
    ZvPlayerState state = const ZvPlayerState(),
    ValueChanged<double>? onSetBrightness,
    double? brightness,
    ValueChanged<VideoFitMode>? onSetVideoFit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZvPlayerThemeScope(
            theme: ZvPlayerTheme.standard,
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => ZvSettingsSheet.show(
                  context,
                  sink,
                  state,
                  capabilities,
                  onSetBrightness: onSetBrightness,
                  brightness: brightness,
                  onSetVideoFit: onSetVideoFit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // Opened through the real modal route, so pop() behaves as it does in the
    // app rather than tearing down the only route in the test.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps a root row and settles on its secondary panel.
  Future<void> openPanel(WidgetTester tester, String row) async {
    await tester.ensureVisible(find.text(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
  }

  const EngineCapabilities embeddedYouTube = EngineCapabilities(
    canPlayPause: true,
    canSeek: true,
    canSetSpeed: true,
    speeds: <double>[0.25, 0.5, 1.0, 1.5, 2.0],
    canSetVolume: true,
    canMute: true,
  );

  const PlayerTracks fullTracks = PlayerTracks(
    video: <VideoQualityTrack>[
      VideoQualityTrack(id: '1', label: '720p', isSelected: true),
      VideoQualityTrack(id: '2', label: '1080p'),
    ],
    audio: <AudioTrackOption>[
      AudioTrackOption(id: 'a1', language: 'en', label: 'English'),
      AudioTrackOption(id: 'a2', language: 'hi', label: 'Hindi'),
    ],
    subtitles: <SubtitleTrackOption>[
      SubtitleTrackOption(id: 's1', language: 'en', label: 'English'),
    ],
  );

  group('never shows an empty row', () {
    testWidgets('an engine with nothing to configure says so', (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities(canPlayPause: true),
      );

      expect(find.text('No settings are available for this video'),
          findsOneWidget);
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Captions'), findsNothing);
      expect(find.text('Audio'), findsNothing);
      expect(find.text('Speed'), findsNothing);
    });

    testWidgets('quality is hidden when the engine cannot switch it',
        (tester) async {
      // Tracks exist, but this engine cannot select them.
      await pumpSheet(
        tester,
        capabilities: embeddedYouTube,
        state: const ZvPlayerState(
          tracks: PlayerTracks(
            video: <VideoQualityTrack>[
              VideoQualityTrack(id: '1', label: '720p'),
              VideoQualityTrack(id: '2', label: '1080p'),
            ],
          ),
        ),
      );

      expect(find.text('Quality'), findsNothing);
    });

    testWidgets(
        'quality is hidden when the engine can switch but has no tracks',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
      );

      expect(find.text('Quality'), findsNothing);
      expect(find.text('Captions'), findsNothing);
      // Speed needs no media, so it is still offered.
      expect(find.text('Speed'), findsOneWidget);
    });
  });

  group('capability-shaped rows', () {
    testWidgets('native media with real tracks shows every playback row',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
        state: const ZvPlayerState(tracks: fullTracks),
      );

      expect(find.text('PLAYBACK'), findsOneWidget);
      expect(find.text('Quality'), findsOneWidget);
      expect(find.text('Captions'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
    });

    testWidgets('each row shows its current value', (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
        state: const ZvPlayerState(tracks: fullTracks, speed: 1.5),
      );

      // Quality row reads the selected rendition, captions read Off, speed
      // reads the current rate - no row is a bare label.
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);
    });

    testWidgets('a YouTube-shaped engine offers only what it can do',
        (tester) async {
      await pumpSheet(tester, capabilities: embeddedYouTube);

      // Speed and volume are genuinely driveable through the IFrame API.
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      await openPanel(tester, 'Volume');
      expect(find.text('Mute'), findsOneWidget);
      // These are not, so they must not appear.
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Captions'), findsNothing);
      expect(find.text('Audio'), findsNothing);
    });

    testWidgets('an embed with no fit capability shows no Fit row',
        (tester) async {
      // onSetVideoFit is withheld exactly as the view withholds it for an
      // engine that cannot crop without distorting.
      await pumpSheet(tester, capabilities: embeddedYouTube);
      expect(find.text('Fit'), findsNothing);
    });

    testWidgets('a single supported speed is not a menu', (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities(
          canSetSpeed: true,
          speeds: <double>[1.0],
        ),
      );
      expect(find.text('Speed'), findsNothing);
    });
  });

  group('secondary selection panels', () {
    testWidgets('an embed offers only the rates its page accepts',
        (tester) async {
      await pumpSheet(tester, capabilities: embeddedYouTube);
      // Rates are not on the root list; they are one tap away.
      expect(find.text('0.25x'), findsNothing);

      await openPanel(tester, 'Speed');

      expect(find.text('Playback speed'), findsOneWidget);
      // YouTube's set includes 0.25x and excludes 0.75x.
      expect(find.text('0.25x'), findsOneWidget);
      expect(find.text('0.75x'), findsNothing);
    });

    testWidgets('native media offers the full ladder', (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
      );
      await openPanel(tester, 'Speed');

      expect(find.text('0.75x'), findsOneWidget);
      expect(find.text('0.25x'), findsNothing);
    });

    testWidgets('captions panel carries an Off entry above the tracks',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
        state: const ZvPlayerState(tracks: fullTracks),
      );
      await openPanel(tester, 'Captions');

      expect(find.text('Off'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('a panel returns to the root list', (tester) async {
      await pumpSheet(tester, capabilities: embeddedYouTube);
      await openPanel(tester, 'Speed');
      expect(find.text('More'), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('More'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
    });

    testWidgets('choosing a rate applies it and returns to the root',
        (tester) async {
      await pumpSheet(tester, capabilities: embeddedYouTube);
      await openPanel(tester, 'Speed');
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      // Back on the root list, with the row showing the new value.
      expect(find.text('More'), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);
    });

    testWidgets('audio panel marks a Dolby track only from its codec',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
        state: const ZvPlayerState(
          tracks: PlayerTracks(
            audio: <AudioTrackOption>[
              AudioTrackOption(
                id: 'a1',
                language: 'en',
                label: 'English',
                codec: 'ac-3',
              ),
              AudioTrackOption(id: 'a2', language: 'hi', label: 'Hindi'),
            ],
          ),
        ),
      );
      await openPanel(tester, 'Audio');

      expect(find.text('Dolby'), findsOneWidget);
    });
  });

  group('video and display', () {
    testWidgets('fit row appears only when the engine can crop',
        (tester) async {
      // Starting on Fill keeps the row's title and its value distinguishable:
      // title "Fit", value "Fill".
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
        state: const ZvPlayerState(videoFit: VideoFitMode.fill),
        onSetVideoFit: (_) {},
      );

      expect(find.text('VIDEO'), findsOneWidget);
      expect(find.text('Fit'), findsOneWidget);
      expect(find.text('Fill'), findsOneWidget);
    });

    testWidgets('fit panel offers Fit and Fill and reports the choice',
        (tester) async {
      VideoFitMode? chosen;
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities.nativeMedia(),
        onSetVideoFit: (VideoFitMode fit) => chosen = fit,
      );
      // The row's value is "Fit" too, so open by the row's leading title.
      await tester.tap(find.text('Fit').first);
      await tester.pumpAndSettle();

      expect(find.text('Fill'), findsOneWidget);
      await tester.tap(find.text('Fill'));
      await tester.pumpAndSettle();

      expect(chosen, VideoFitMode.fill);
    });

    testWidgets('brightness is hidden when the platform gave no value',
        (tester) async {
      await pumpSheet(tester, capabilities: embeddedYouTube);
      expect(find.text('Brightness'), findsNothing);
      expect(find.text('Brightness'), findsNothing);
    });

    testWidgets('brightness appears under Display once supplied',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: embeddedYouTube,
        onSetBrightness: (_) {},
        brightness: 0.5,
      );

      expect(find.text('Brightness'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.text('50%'), findsOneWidget);

      await openPanel(tester, 'Brightness');
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  group('audio', () {
    testWidgets('a muted player shows 0% regardless of stored volume',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: embeddedYouTube,
        state: const ZvPlayerState(isMuted: true, volume: 0.8),
      );

      expect(find.text('Muted'), findsOneWidget);
    });

    testWidgets('mute is a toggle that reflects state', (tester) async {
      await pumpSheet(
        tester,
        capabilities: embeddedYouTube,
        state: const ZvPlayerState(isMuted: true),
      );

      await openPanel(tester, 'Volume');
      expect(find.text('Mute'), findsOneWidget);
      final Switch toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isTrue);
    });

    testWidgets('volume percentage reflects state', (tester) async {
      await pumpSheet(
        tester,
        capabilities: embeddedYouTube,
        state: const ZvPlayerState(volume: 0.4),
      );
      expect(find.text('40%'), findsOneWidget);
    });

    testWidgets('an engine that cannot change volume shows no slider',
        (tester) async {
      await pumpSheet(
        tester,
        capabilities: const EngineCapabilities(canMute: true),
      );
      await openPanel(tester, 'Volume');
      expect(find.text('Mute'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });
  });
}
