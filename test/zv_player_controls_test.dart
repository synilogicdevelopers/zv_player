import 'package:zv_player/zv_player.dart';
import 'package:zv_player/src/widgets/zv_progress_bar.dart';
import 'package:zv_player/src/widgets/zv_player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

void main() {
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
    required ZvPlayerState state,
    bool visible = true,
    VoidCallback? onToggleFullscreen,
    VoidCallback? onCast,
    // Defaults to full native capability, matching what this screen had
    // before controls became capability-driven.
    EngineCapabilities capabilities = const EngineCapabilities.nativeMedia(),
  }) async {
    controller.value = state;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZvPlayerThemeScope(
            theme: ZvPlayerTheme.standard,
            child: ZvPlayerControls(
              sink: controller,
              capabilities: capabilities,
              state: state,
              visible: visible,
              onInteraction: () {},
              title: 'Test Title',
              subtitleText: 'Episode 1',
              onToggleFullscreen: onToggleFullscreen ?? () {},
              onCast: onCast,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const ZvPlayerState playingState = ZvPlayerState(
    status: PlayerStatus.playing,
    position: Duration(minutes: 2),
    duration: Duration(minutes: 10),
  );

  testWidgets('a short inline stage keeps the essentials without overflow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 200,
                  child: ZvPlayerControls(
                      sink: controller,
                      capabilities: const EngineCapabilities.nativeMedia(),
                      state: playingState,
                      visible: true,
                      title: 'Dhurandar',
                      onInteraction: () {},
                      onLock: () {},
                      onSetBrightness: (_) {},
                      brightness: 0.5,
                      onToggleFullscreen: () {}),
                )))));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
    // The side slider and the secondary row need a real stage.
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('Lock player'), findsNothing);
  });

  testWidgets('time digit changes and drag emphasis never resize the timeline',
      (tester) async {
    final state = playingState.copyWith(
        position: const Duration(seconds: 22),
        duration: const Duration(hours: 3, minutes: 42, seconds: 49));
    await pumpControls(tester, state: state);
    final width = tester.getSize(find.byType(ZvProgressBar)).width;
    await pumpControls(tester,
        state: state.copyWith(
            position: const Duration(hours: 2, minutes: 8), isSeeking: true));
    expect(tester.getSize(find.byType(ZvProgressBar)).width, width);
  });

  group('transport controls', () {
    testWidgets('shows the title and a pause glyph while playing',
        (tester) async {
      await pumpControls(tester, state: playingState);

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('shows a play glyph while paused', (tester) async {
      await pumpControls(
        tester,
        state: playingState.copyWith(status: PlayerStatus.paused),
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('shows a replay glyph once playback completes', (tester) async {
      await pumpControls(
        tester,
        state: playingState.copyWith(status: PlayerStatus.completed),
      );
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
    });

    testWidgets('tapping pause reaches the platform', (tester) async {
      await pumpControls(tester, state: playingState);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();

      expect(platform.calls, contains('pause'));
    });

    testWidgets('double-arrow seek buttons issue a seek', (tester) async {
      await pumpControls(tester, state: playingState);
      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.pump();

      expect(platform.lastSeek, const Duration(minutes: 2, seconds: 10));
    });

    testWidgets('seek buttons are disabled for a live stream', (tester) async {
      await pumpControls(
        tester,
        state: playingState.copyWith(isLive: true),
      );

      final IconButton forward = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.forward_10_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(forward.onPressed, isNull);
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('a buffering stall shows a spinner but keeps the bar usable',
        (tester) async {
      await pumpControls(
        tester,
        state: playingState.copyWith(status: PlayerStatus.buffering),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Seek remains available during the stall.
      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.pump();
      expect(platform.calls, contains('seekTo'));
    });

    testWidgets('hidden controls do not receive taps', (tester) async {
      await pumpControls(tester, state: playingState, visible: false);
      await tester.tap(find.byIcon(Icons.pause_rounded), warnIfMissed: false);
      await tester.pump();

      expect(platform.calls, isNot(contains('pause')));
    });

    testWidgets('the back-10 button seeks back by ten seconds', (tester) async {
      await pumpControls(tester, state: playingState);
      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      await tester.pump();

      expect(platform.lastSeek, const Duration(minutes: 1, seconds: 50));
    });

    testWidgets('the timeline row is position only, plus fullscreen',
        (tester) async {
      await pumpControls(tester, state: playingState);

      // Volume lives in Settings; nothing on the chrome can unmute (and so
      // nothing here can accidentally start playback).
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(find.byIcon(Icons.volume_off_rounded), findsNothing);
      expect(find.text('1x'), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });

    testWidgets('exactly one play/pause control is rendered', (tester) async {
      await pumpControls(tester, state: playingState);
      expect(find.bySemanticsLabel('Pause'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('secondary row offers only what is real', (tester) async {
      await pumpControls(tester, state: playingState);
      // Native speed is real; no tracks means no audio & subtitles entry, and
      // no host episode list means no Episodes / Next.
      expect(find.text('Speed (1x)'), findsOneWidget);
      expect(find.text('Audio & Subtitles'), findsNothing);
      expect(find.byTooltip('Captions'), findsNothing);
      expect(find.text('Episodes'), findsNothing);
      expect(find.text('Next'), findsNothing);

      await pumpControls(
        tester,
        state: playingState.copyWith(
          tracks: const PlayerTracks(
            subtitles: <SubtitleTrackOption>[
              SubtitleTrackOption(id: 't1', language: 'en', label: 'English'),
            ],
          ),
        ),
      );
      expect(find.text('Audio & Subtitles'), findsOneWidget);
      expect(find.byTooltip('Captions'), findsOneWidget);
    });

    testWidgets('speed entry opens straight onto the speed panel',
        (tester) async {
      await pumpControls(tester, state: playingState);
      await tester.tap(find.text('Speed (1x)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();
      expect(platform.lastSpeed, 1.5);
    });

    testWidgets('cast is hidden unless the host supplies a handler',
        (tester) async {
      await pumpControls(tester, state: playingState);
      expect(find.byIcon(Icons.cast_rounded), findsNothing);
    });

    testWidgets('cast appears when the host supplies a handler',
        (tester) async {
      int casts = 0;
      await pumpControls(
        tester,
        state: playingState,
        onCast: () => casts++,
      );

      expect(find.byIcon(Icons.cast_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.cast_rounded));
      await tester.pump();
      expect(casts, 1);
    });

    testWidgets('elapsed and total time are rendered', (tester) async {
      await pumpControls(tester, state: playingState);
      // Elapsed on the left, the whole running time on the right - the bar
      // between them spans the entire duration.
      expect(find.text('2:00'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
    });
  });

  group('settings sheet', () {
    Future<void> openSettings(WidgetTester tester, ZvPlayerState state) async {
      await pumpControls(tester, state: state);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    /// The sheet's root is a list of rows; choices live one tap deeper.
    Future<void> openPanel(WidgetTester tester, String row) async {
      await tester.ensureVisible(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
    }

    testWidgets('offers no quality section when the source has one rendition',
        (tester) async {
      await openSettings(
        tester,
        playingState.copyWith(
          tracks: const PlayerTracks(
            video: <VideoQualityTrack>[
              VideoQualityTrack(id: '1', label: '720p', isSelected: true),
            ],
          ),
        ),
      );

      expect(find.text('Quality'), findsNothing);
      expect(find.text('Speed'), findsOneWidget);
    });

    testWidgets('offers a quality section when renditions really exist',
        (tester) async {
      await openSettings(
        tester,
        playingState.copyWith(
          tracks: const PlayerTracks(
            video: <VideoQualityTrack>[
              VideoQualityTrack(id: '1', label: '1080p', isVariant: true),
              VideoQualityTrack(
                id: '2',
                label: '720p',
                isSelected: true,
                isVariant: true,
              ),
            ],
          ),
        ),
      );

      // The row exists on the root and carries the current rendition.
      expect(find.text('Quality'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);

      await openPanel(tester, 'Quality');
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      // Non-adaptive sources say so instead of implying ABR.
      expect(
        find.text('Switching reloads the video at this position'),
        findsOneWidget,
      );
    });

    testWidgets('hides subtitle and audio sections when the media has none',
        (tester) async {
      await openSettings(tester, playingState);

      expect(find.text('Captions'), findsNothing);
      expect(find.text('Audio'), findsNothing);
    });

    testWidgets('shows subtitles with an Off entry when tracks exist',
        (tester) async {
      await openSettings(
        tester,
        playingState.copyWith(
          tracks: const PlayerTracks(
            subtitles: <SubtitleTrackOption>[
              SubtitleTrackOption(id: 't1', language: 'en', label: 'English'),
            ],
          ),
        ),
      );

      // The root row reads "Captions  Off"; the tracks are on its panel.
      expect(find.text('Captions'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('English'), findsNothing);

      await openPanel(tester, 'Captions');
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('marks a Dolby audio track only from its codec',
        (tester) async {
      await openSettings(
        tester,
        playingState.copyWith(
          tracks: const PlayerTracks(
            audio: <AudioTrackOption>[
              AudioTrackOption(
                id: 'a1',
                language: 'en',
                label: 'English',
                codec: 'ec-3',
              ),
              AudioTrackOption(
                id: 'a2',
                language: 'hi',
                label: 'Hindi',
                codec: 'mp4a.40.2',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Audio'), findsOneWidget);

      await openPanel(tester, 'Audio');
      expect(find.text('Dolby'), findsOneWidget);
    });

    testWidgets('choosing a speed applies it', (tester) async {
      await openSettings(tester, playingState);
      await openPanel(tester, 'Speed');
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      expect(platform.lastSpeed, 1.5);
    });
  });
}
