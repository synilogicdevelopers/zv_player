import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/zv_player.dart';

import 'fake_player_platform.dart';

/// What the settings surface offers for a source, and what it refuses to offer.
///
/// The rule throughout: a control exists only when the engine can perform the
/// operation *and* the media actually contains a choice.
void main() {
  VideoQualityTrack video(String id, String label,
          {int? height, int? bitrate, double? fps, bool selected = false}) =>
      VideoQualityTrack(
          id: id,
          label: label,
          height: height,
          bitrate: bitrate,
          frameRate: fps,
          isSelected: selected);

  AudioTrackOption audio(String id, String language, String label,
          {bool selected = false}) =>
      AudioTrackOption(
          id: id, language: language, label: label, isSelected: selected);

  SubtitleTrackOption subtitle(String id, String language, String label,
          {bool forced = false,
          bool isDefault = false,
          bool selected = false}) =>
      SubtitleTrackOption(
          id: id,
          language: language,
          label: label,
          isForced: forced,
          isDefault: isDefault,
          isSelected: selected);

  /// Records what actually reached the engine.
  late List<String> commands;

  /// Opens the real settings sheet for a given state + capabilities.
  Future<void> openSheet(
    WidgetTester tester, {
    required PlayerTracks tracks,
    required EngineCapabilities capabilities,
    ZvMediaSource? source,
  }) async {
    commands = <String>[];
    final ZvPlayerController controller = ZvPlayerController(
      router:
          SourceRouter(nativeEngineBuilder: () => throw StateError('unused')),
      logger: (_, __) {},
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (BuildContext context) {
          return ZvSettingsSheet(
            sink: _RecordingSink(commands, controller),
            capabilities: capabilities,
            state: ZvPlayerState(
              status: PlayerStatus.playing,
              source: source,
              position: const Duration(minutes: 4),
              duration: const Duration(hours: 1),
              tracks: tracks,
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final ZvMediaSource hls =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8');
  final ZvMediaSource mp4 =
      ZvMediaSource.detect(uri: 'https://cdn.example.com/movie.mp4');

  const EngineCapabilities native = EngineCapabilities.nativeMedia();
  const EngineCapabilities youTube = YouTubeEngine.kCapabilities;

  PlayerTracks ladder() => PlayerTracks(
        video: <VideoQualityTrack>[
          const VideoQualityTrack.auto(),
          video('0:0', '1080p', height: 1080, bitrate: 8000000, fps: 60),
          video('0:1', '720p', height: 720, bitrate: 3000000),
          video('0:2', '480p', height: 480, bitrate: 1200000),
        ],
        audio: <AudioTrackOption>[
          audio('1:0', 'en', 'English', selected: true),
          audio('1:1', 'hi', 'Hindi'),
        ],
        subtitles: <SubtitleTrackOption>[
          subtitle('2:0', 'en', 'English', isDefault: true),
          subtitle('2:1', 'en', 'English (forced)', forced: true),
        ],
      );

  group('quality', () {
    testWidgets('multiple real renditions offer a quality control',
        (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(), capabilities: native, source: hls);
      expect(find.text('Quality'), findsOneWidget);
    });

    testWidgets('a single rendition offers none', (WidgetTester tester) async {
      await openSheet(
        tester,
        tracks: PlayerTracks(
            video: <VideoQualityTrack>[video('0:0', '720p', height: 720)]),
        capabilities: native,
        source: mp4,
      );
      expect(find.text('Quality'), findsNothing);
    });

    testWidgets('YouTube offers none at all', (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(),
          capabilities: youTube,
          source: ZvMediaSource.detect(
              uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k'));
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Audio'), findsNothing);
      expect(find.text('Captions'), findsNothing);
    });

    testWidgets('Auto is offered for adaptive media and reaches the engine',
        (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(), capabilities: native, source: hls);
      await tester.tap(find.text('Quality'));
      await tester.pumpAndSettle();
      expect(find.text('Auto'), findsWidgets);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);

      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(commands, <String>['selectQuality:0:1'],
          reason: 'the real track id, not a label, reaches the engine');
    });

    testWidgets('the current rendition is the one marked',
        (WidgetTester tester) async {
      final PlayerTracks tracks = PlayerTracks(video: <VideoQualityTrack>[
        video('0:0', '1080p', height: 1080, selected: true),
        video('0:1', '720p', height: 720),
      ]);
      await openSheet(tester,
          tracks: tracks, capabilities: native, source: hls);
      await tester.tap(find.text('Quality'));
      await tester.pumpAndSettle();
      // The sheet marks the current option with its emphasised text style.
      final Iterable<Text> labels = tester.widgetList<Text>(find.byType(Text));
      final Iterable<Text> emphasised = labels.where((Text t) =>
          t.style?.fontWeight == FontWeight.w600 &&
          (t.data == '1080p' || t.data == '720p'));
      expect(emphasised, hasLength(1),
          reason: 'exactly one rendition reads as current');
    });

    testWidgets('same-resolution renditions are told apart by real metadata',
        (WidgetTester tester) async {
      final PlayerTracks tracks = PlayerTracks(video: <VideoQualityTrack>[
        video('0:0', '1080p', height: 1080, bitrate: 8000000),
        video('0:1', '1080p', height: 1080, bitrate: 4500000),
      ]);
      await openSheet(tester,
          tracks: tracks, capabilities: native, source: hls);
      await tester.tap(find.text('Quality'));
      await tester.pumpAndSettle();
      expect(find.text('1080p · 8.0 Mbps'), findsOneWidget);
      expect(find.text('1080p · 4.5 Mbps'), findsOneWidget);

      // Selecting one must not mark the other.
      await tester.tap(find.text('1080p · 4.5 Mbps'));
      await tester.pumpAndSettle();
      expect(commands, <String>['selectQuality:0:1']);
    });

    test('renditions that round to the same Mbps stay distinguishable', () {
      final PlayerTracks tracks = PlayerTracks(video: <VideoQualityTrack>[
        video('0:0', '1080p', height: 1080, bitrate: 8031601),
        video('0:1', '1080p', height: 1080, bitrate: 8001098),
      ]);
      final String a = tracks.videoLabelFor(tracks.video[0]);
      final String b = tracks.videoLabelFor(tracks.video[1]);
      expect(a, isNot(b), reason: 'two entries must never read identically');
      expect(a, '1080p · 8032 kbps');
      expect(b, '1080p · 8001 kbps');
    });

    test('labels come from the media, never from a fixed ladder', () {
      final PlayerTracks tracks = PlayerTracks(video: <VideoQualityTrack>[
        video('0:0', '1080p', height: 1080, bitrate: 8000000),
        video('0:1', '1080p', height: 1080),
      ]);
      // Nothing distinguishes the second one, so it is left alone rather than
      // given an invented number.
      expect(tracks.videoLabelFor(tracks.video[1]), '1080p');
      expect(
          PlayerTracks(video: <VideoQualityTrack>[video('0:0', '4K')])
              .videoLabelFor(video('0:0', '4K')),
          '4K');
    });
  });

  group('audio', () {
    testWidgets('multiple audio tracks offer a control that selects a real one',
        (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(), capabilities: native, source: hls);
      expect(find.text('Audio'), findsOneWidget);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsWidgets);
      expect(find.text('Hindi'), findsOneWidget);

      await tester.tap(find.text('Hindi'));
      await tester.pumpAndSettle();
      expect(commands, <String>['selectAudioTrack:1:1']);
    });

    testWidgets('a single audio track offers none',
        (WidgetTester tester) async {
      await openSheet(
        tester,
        tracks: PlayerTracks(
            audio: <AudioTrackOption>[audio('1:0', 'en', 'English')]),
        capabilities: native,
        source: mp4,
      );
      expect(find.text('Audio'), findsNothing);
    });

    testWidgets('no audio metadata offers none', (WidgetTester tester) async {
      await openSheet(tester,
          tracks: const PlayerTracks(), capabilities: native, source: mp4);
      expect(find.text('Audio'), findsNothing);
    });

    test('a track without language still gets a usable label', () {
      final AudioTrackOption parsed = AudioTrackOption.fromMap(
          <String, Object?>{'id': '1:0', 'language': '', 'label': ''});
      expect(parsed.label, isNotEmpty);
      expect(parsed.language, isEmpty,
          reason: 'an absent language is left absent, never guessed');
    });
  });

  group('subtitles', () {
    testWidgets('tracks plus Off, selecting one reaches the engine',
        (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(), capabilities: native, source: hls);
      expect(find.text('Captions'), findsOneWidget);
      await tester.tap(find.text('Captions'));
      await tester.pumpAndSettle();
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      await tester.tap(find.text('English (forced)'));
      await tester.pumpAndSettle();
      expect(commands, <String>['selectSubtitle:2:1']);
    });

    testWidgets('Off turns subtitles off', (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(), capabilities: native, source: hls);
      await tester.tap(find.text('Captions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(commands, <String>['selectSubtitle:off']);
    });

    testWidgets('forced and default are shown only where the media says so',
        (WidgetTester tester) async {
      await openSheet(tester,
          tracks: ladder(), capabilities: native, source: hls);
      await tester.tap(find.text('Captions'));
      await tester.pumpAndSettle();
      expect(find.text('Forced'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
    });

    test('exactly one track is the default, and only where declared', () {
      // What the platforms now send: Android from SELECTION_FLAG_DEFAULT, iOS
      // from the selection group's own defaultOption. Neither marks a track
      // default merely because it is programme content.
      final List<SubtitleTrackOption> parsed = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'text:0',
          'language': 'en',
          'label': 'English',
          'isDefault': true,
        },
        <String, Object?>{
          'id': 'text:1',
          'language': 'it',
          'label': 'Italian',
          'isDefault': false,
        },
        <String, Object?>{
          'id': 'text:2',
          'language': 'en',
          'label': 'English (forced)',
          'isForced': true,
        },
      ].map(SubtitleTrackOption.fromMap).toList();

      expect(parsed.where((SubtitleTrackOption t) => t.isDefault), hasLength(1),
          reason: 'a group designates one default, not every track');
      expect(parsed[0].isDefault, isTrue);
      expect(parsed[1].isDefault, isFalse,
          reason: 'a non-default track must never read as default');
      expect(parsed[2].isDefault, isFalse);
      // The correction must not disturb forced.
      expect(parsed[2].isForced, isTrue);
      expect(parsed[0].isForced, isFalse);
      // And the badges follow suit.
      expect(PlayerTracks.subtitleNoteFor(parsed[0]), 'Default');
      expect(PlayerTracks.subtitleNoteFor(parsed[1]), isNull);
      expect(PlayerTracks.subtitleNoteFor(parsed[2]), 'Forced');
    });

    test('a group with no default leaves every track unmarked', () {
      // AVFoundation's defaultOption is nullable, and HLS need not declare
      // DEFAULT=YES; nothing is invented in that case.
      final List<SubtitleTrackOption> parsed = <Map<String, Object?>>[
        <String, Object?>{'id': 'text:0', 'language': 'en', 'label': 'English'},
        <String, Object?>{'id': 'text:1', 'language': 'it', 'label': 'Italian'},
      ].map(SubtitleTrackOption.fromMap).toList();
      expect(parsed.any((SubtitleTrackOption t) => t.isDefault), isFalse);
      expect(parsed.any((SubtitleTrackOption t) => t.isForced), isFalse);
    });

    test('a plain track carries no badge', () {
      expect(PlayerTracks.subtitleNoteFor(subtitle('2:9', 'fr', 'French')),
          isNull);
    });

    testWidgets('no subtitles offers no control', (WidgetTester tester) async {
      await openSheet(tester,
          tracks: const PlayerTracks(), capabilities: native, source: mp4);
      expect(find.text('Captions'), findsNothing);
    });
  });

  group('regression: nothing else moved', () {
    testWidgets('speed is still offered and unchanged',
        (WidgetTester tester) async {
      await openSheet(tester,
          tracks: const PlayerTracks(), capabilities: native, source: mp4);
      expect(find.text('Speed'), findsOneWidget);
    });

    testWidgets('an MP4 with one of everything shows no track selectors',
        (WidgetTester tester) async {
      await openSheet(
        tester,
        tracks: PlayerTracks(
          video: <VideoQualityTrack>[video('0:0', '1080p', height: 1080)],
          audio: <AudioTrackOption>[audio('1:0', 'en', 'English')],
        ),
        capabilities: native,
        source: mp4,
      );
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Audio'), findsNothing);
      expect(find.text('Captions'), findsNothing);
      expect(find.text('Speed'), findsOneWidget);
    });

    test('selection does not touch position or engine lifecycle', () async {
      final FakePlayerPlatform platform = FakePlayerPlatform();
      final NativeMediaEngine engine = NativeMediaEngine(
        controller: ZvNativeController(
          platform: platform,
          progressStore: InMemoryProgressStore(),
          secureSurface: false,
        ),
      );
      await engine.initialize();
      await engine.load(
          ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8'));
      final int playersBefore = platform.createdPlayers;

      await engine.selectQuality(video('0:1', '720p', height: 720));
      await engine.selectAudioTrack(audio('1:1', 'hi', 'Hindi'));
      await engine.selectSubtitle(subtitle('2:0', 'en', 'English'));

      expect(platform.createdPlayers, playersBefore,
          reason: 'no new engine is built to change a track');
      expect(platform.calls.where((String c) => c == 'load'), hasLength(1),
          reason: 'the media is not reloaded, so the position survives');
      await engine.dispose();
    });
  });
}

/// Passes commands through while recording which track id was asked for.
class _RecordingSink implements PlayerCommandSink {
  _RecordingSink(this.log, this._inner);

  final List<String> log;
  final ZvPlayerController _inner;

  @override
  Future<void> selectQuality(VideoQualityTrack track) async =>
      log.add('selectQuality:${track.id}');

  @override
  Future<void> selectAudioTrack(AudioTrackOption track) async =>
      log.add('selectAudioTrack:${track.id}');

  @override
  Future<void> selectSubtitle(SubtitleTrackOption? track) async =>
      log.add('selectSubtitle:${track?.id ?? 'off'}');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(_inner.noSuchMethod, <Object?>[invocation]);
}
