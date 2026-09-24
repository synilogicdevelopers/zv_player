import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/zv_player.dart';

/// The P2.1 foundation: what the player can *represent*, and - just as
/// important - what it refuses to claim when the data is not there.
void main() {
  group('capabilities stay honest per engine', () {
    test('YouTube advertises only what the IFrame API actually does', () {
      const EngineCapabilities yt = YouTubeEngine.kCapabilities;
      // The official API drives playback, seeking, rate, volume and mute.
      expect(yt.canPlayPause, isTrue);
      expect(yt.canSeek, isTrue);
      expect(yt.canSetSpeed, isTrue);
      // It exposes no track enumeration, no rendition picking, no PiP.
      expect(yt.canSelectQuality, isFalse);
      expect(yt.canSelectAudioTrack, isFalse);
      expect(yt.canSelectSubtitle, isFalse);
      expect(yt.reportsTrackList, isFalse);
      expect(yt.supportsPictureInPicture, isFalse);
      // And it does not adapt on our behalf in a way we can drive.
      expect(yt.supportsAdaptiveBitrate, isFalse);
    });

    test('a native engine may adapt and select', () {
      const EngineCapabilities native = EngineCapabilities.nativeMedia();
      expect(native.supportsAdaptiveBitrate, isTrue);
      expect(native.canSelectQuality, isTrue);
      expect(native.canSelectAudioTrack, isTrue);
      expect(native.canSelectSubtitle, isTrue);
      expect(native.reportsTrackList, isTrue);
    });

    test('a YouTube source is never adaptive to us', () {
      final ZvMediaSource yt = ZvMediaSource.detect(
          uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k');
      expect(yt.isAdaptive, isFalse);
      expect(yt.hasStoryboard, isFalse,
          reason: 'no storyboard is derived for YouTube');
      expect(yt.markers.isEmpty, isTrue);
    });
  });

  group('track data carries what the media really declares', () {
    test('multiple video renditions, including frame rate', () {
      final PlayerTracks tracks = PlayerTracks(
        video: <VideoQualityTrack>[
          VideoQualityTrack.fromMap(<String, Object?>{
            'id': '0:0',
            'label': '1080p',
            'width': 1920,
            'height': 1080,
            'bitrate': 6000000,
            'codec': 'avc1.640028',
            'frameRate': 50.0,
            'isSelected': true,
          }),
          VideoQualityTrack.fromMap(<String, Object?>{
            'id': '0:1',
            'label': '720p',
            'width': 1280,
            'height': 720,
            'bitrate': 3000000,
          }),
        ],
      );
      expect(tracks.video, hasLength(2));
      expect(tracks.hasQualityChoice, isTrue);
      expect(tracks.video.first.frameRate, 50.0);
      expect(tracks.video.first.height, 1080);
      expect(tracks.video.last.frameRate, isNull,
          reason: 'absent frame rate stays absent, never a default');
    });

    test('multiple audio tracks', () {
      final PlayerTracks tracks = PlayerTracks(
        audio: <AudioTrackOption>[
          AudioTrackOption.fromMap(<String, Object?>{
            'id': '1:0',
            'language': 'hi',
            'label': 'Hindi',
            'channels': 6,
            'isSelected': true
          }),
          AudioTrackOption.fromMap(<String, Object?>{
            'id': '1:1',
            'language': 'en',
            'label': 'English'
          }),
        ],
      );
      expect(tracks.audio, hasLength(2));
      expect(tracks.hasAudioChoice, isTrue);
      expect(tracks.audio.first.language, 'hi');
      expect(tracks.audio.first.channels, 6);
    });

    test('multiple subtitle tracks, with forced and default flags', () {
      final PlayerTracks tracks = PlayerTracks(
        subtitles: <SubtitleTrackOption>[
          SubtitleTrackOption.fromMap(<String, Object?>{
            'id': '2:0',
            'language': 'en',
            'label': 'English',
            'isDefault': true,
          }),
          SubtitleTrackOption.fromMap(<String, Object?>{
            'id': '2:1',
            'language': 'en',
            'label': 'English (forced)',
            'isForced': true,
          }),
        ],
      );
      expect(tracks.subtitles, hasLength(2));
      expect(tracks.hasSubtitles, isTrue);
      expect(tracks.subtitles.first.isDefault, isTrue);
      expect(tracks.subtitles.first.isForced, isFalse);
      expect(tracks.subtitles.last.isForced, isTrue);
    });

    test('no data means no choice - nothing is synthesised', () {
      const PlayerTracks empty = PlayerTracks();
      expect(empty.hasQualityChoice, isFalse,
          reason: 'no quality control without renditions');
      expect(empty.hasAudioChoice, isFalse,
          reason: 'no audio control without audio tracks');
      expect(empty.hasSubtitles, isFalse,
          reason: 'no subtitle control without subtitle tracks');
      expect(empty.video, isEmpty);
      expect(empty.audio, isEmpty);
      expect(empty.subtitles, isEmpty);
    });

    test('a single rendition is not a choice', () {
      final PlayerTracks one = PlayerTracks(
        video: <VideoQualityTrack>[
          VideoQualityTrack.fromMap(
              <String, Object?>{'id': '0:0', 'label': '720p', 'height': 720})
        ],
      );
      expect(one.video, hasLength(1));
      expect(one.hasQualityChoice, isFalse,
          reason: 'one rendition gives the viewer nothing to pick');
    });
  });

  group('skip markers appear only with real marker data', () {
    test('no markers means no skip control', () {
      final ZvMediaSource source =
          ZvMediaSource.detect(uri: 'https://cdn.example.com/movie.mp4');
      expect(source.markers.isEmpty, isTrue);
      expect(source.markers.at(const Duration(seconds: 30)), isNull);
      expect(source.markers.firstOf(PlaybackMarkerKind.intro), isNull);
    });

    test('a supplied intro is honoured for its span only', () {
      final PlaybackMarkers markers =
          PlaybackMarkers.fromList(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'intro',
          'startMs': 12000,
          'endMs': 75000,
          'label': 'Skip Intro'
        },
      ]);
      expect(markers.isNotEmpty, isTrue);
      final PlaybackMarker intro = markers.firstOf(PlaybackMarkerKind.intro)!;
      expect(intro.label, 'Skip Intro');
      expect(intro.duration, const Duration(seconds: 63));
      expect(markers.at(const Duration(seconds: 5)), isNull);
      expect(markers.at(const Duration(seconds: 40)), intro);
      expect(markers.at(const Duration(seconds: 80)), isNull,
          reason: 'past the intro there is nothing to skip');
    });

    test('recap and outro are represented too, in timeline order', () {
      final PlaybackMarkers markers =
          PlaybackMarkers.fromList(<Map<String, Object?>>[
        <String, Object?>{'type': 'credits', 'start': 3000, 'end': 3300},
        <String, Object?>{'type': 'previously', 'start': 0, 'end': 45},
      ]);
      expect(
          markers.all.map((PlaybackMarker m) => m.kind), <PlaybackMarkerKind>[
        PlaybackMarkerKind.recap,
        PlaybackMarkerKind.outro
      ]);
    });

    test('invalid markers are dropped rather than half-honoured', () {
      final PlaybackMarkers markers = PlaybackMarkers.fromList(<Object>[
        <String, Object?>{'type': 'intro', 'startMs': 90000, 'endMs': 30000},
        <String, Object?>{'type': 'intro', 'startMs': -5000, 'endMs': 10000},
        <String, Object?>{'type': 'intro', 'startMs': 10000, 'endMs': 10000},
        <String, Object?>{'type': 'sponsor', 'startMs': 0, 'endMs': 5000},
        <String, Object?>{'type': 'intro'},
        'not a marker',
      ]);
      expect(markers.isEmpty, isTrue,
          reason: 'reversed, negative, empty, unknown and malformed all drop');
    });

    test('a marker beyond the end of the content is rejected', () {
      final PlaybackMarkers markers = PlaybackMarkers.from(
        <PlaybackMarker>[
          const PlaybackMarker(
              kind: PlaybackMarkerKind.intro,
              start: Duration(minutes: 40),
              end: Duration(minutes: 41)),
        ],
        contentDuration: const Duration(minutes: 20),
      );
      expect(markers.isEmpty, isTrue);
    });

    test('non-list and null marker payloads are safe', () {
      expect(PlaybackMarkers.fromList(null).isEmpty, isTrue);
      expect(PlaybackMarkers.fromList(<String, Object?>{}).isEmpty, isTrue);
    });
  });

  group('storyboard maps a timestamp to a sprite crop', () {
    const StoryboardMetadata sheet = StoryboardMetadata(
      urlTemplate: 'https://cdn.example.com/sb/{index}.jpg',
      thumbnailWidth: 160,
      thumbnailHeight: 90,
      columns: 5,
      rows: 5,
      interval: Duration(seconds: 10),
    );

    test('first tile', () {
      final StoryboardFrame frame = sheet.frameAt(const Duration(seconds: 3))!;
      expect(frame.index, 0);
      expect(frame.url, 'https://cdn.example.com/sb/0.jpg');
      expect(frame.source, const Rect.fromLTWH(0, 0, 160, 90));
    });

    test('a tile further along the same row and the next row', () {
      expect(sheet.frameAt(const Duration(seconds: 25))!.source,
          const Rect.fromLTWH(320, 0, 160, 90));
      expect(sheet.frameAt(const Duration(seconds: 55))!.source,
          const Rect.fromLTWH(0, 90, 160, 90));
    });

    test('rolls onto the next sheet once the grid is full', () {
      // 25 tiles per sheet x 10s = 250s on sheet 0.
      final StoryboardFrame frame =
          sheet.frameAt(const Duration(seconds: 250))!;
      expect(frame.index, 25);
      expect(frame.url, 'https://cdn.example.com/sb/1.jpg');
      expect(frame.source, const Rect.fromLTWH(0, 0, 160, 90));
    });

    test('outside the covered range there is no frame', () {
      const StoryboardMetadata bounded = StoryboardMetadata(
        urlTemplate: 'https://cdn.example.com/sb.jpg',
        thumbnailWidth: 160,
        thumbnailHeight: 90,
        columns: 2,
        rows: 2,
        interval: Duration(seconds: 10),
        startTime: Duration(seconds: 30),
        duration: Duration(seconds: 40),
      );
      expect(bounded.frameAt(const Duration(seconds: 10)), isNull);
      expect(bounded.frameAt(const Duration(seconds: 200)), isNull);
      expect(bounded.frameAt(const Duration(seconds: 35)), isNotNull);
    });

    test('an unusable descriptor yields nothing, so the caller falls back', () {
      const StoryboardMetadata broken = StoryboardMetadata(
        urlTemplate: '',
        thumbnailWidth: 0,
        thumbnailHeight: 0,
        columns: 0,
        rows: 0,
        interval: Duration.zero,
      );
      expect(broken.isValid, isFalse);
      expect(broken.frameAt(Duration.zero), isNull);
      expect(StoryboardMetadata.fromMap(null), isNull);
      expect(
          StoryboardMetadata.fromMap(<String, Object?>{'url': 'x.jpg'}), isNull,
          reason: 'a url alone cannot be cropped');
    });

    test('a source without storyboard metadata keeps timestamp-only preview',
        () {
      final ZvMediaSource plain =
          ZvMediaSource.detect(uri: 'https://cdn.example.com/movie.mp4');
      expect(plain.storyboard, isNull);
      expect(plain.hasStoryboard, isFalse);
    });

    test('a native source can carry a real storyboard', () {
      final ZvMediaSource withBoard = ZvMediaSource.detect(
        uri: 'https://cdn.example.com/master.m3u8',
        storyboard: StoryboardMetadata.fromMap(<String, Object?>{
          'url': 'https://cdn.example.com/sb/{index}.jpg',
          'thumbnailWidth': 160,
          'thumbnailHeight': 90,
          'columns': 5,
          'rows': 5,
          'intervalMs': 10000,
        }),
      );
      expect(withBoard.hasStoryboard, isTrue);
      expect(
          withBoard.storyboard!.frameAt(const Duration(seconds: 12))!.index, 1);
    });
  });

  group('existing behaviour is untouched', () {
    test('source classification is unchanged', () {
      expect(
          ZvMediaSource.detect(uri: 'https://www.youtube.com/watch?v=abc123')
              .type,
          ZvSourceType.youtube);
      expect(
          ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8').type,
          ZvSourceType.hls);
      expect(
          ZvMediaSource.detect(uri: 'https://cdn.example.com/manifest.mpd')
              .type,
          ZvSourceType.dash);
      expect(
          ZvMediaSource.detect(
                  uri: 'https://www.google.com/goto?url=CAESYwHrOzAV')
              .type,
          ZvSourceType.unknown);
    });

    test('resume metadata still carries through copyWith', () {
      final ZvMediaSource source = ZvMediaSource.detect(
        uri: 'https://cdn.example.com/movie.mp4',
        contentId: 'c1',
        startPosition: const Duration(minutes: 3),
        storyboard: const StoryboardMetadata(
          urlTemplate: 'https://cdn.example.com/sb.jpg',
          thumbnailWidth: 160,
          thumbnailHeight: 90,
          columns: 2,
          rows: 2,
          interval: Duration(seconds: 5),
        ),
      );
      final ZvMediaSource resumed =
          source.copyWith(startPosition: const Duration(minutes: 7));
      expect(resumed.contentId, 'c1');
      expect(resumed.startPosition, const Duration(minutes: 7));
      expect(resumed.hasStoryboard, isTrue,
          reason: 'storyboard survives a resume copy');
    });

    test('playback state still reports the basics', () {
      const ZvPlayerState state = ZvPlayerState(
        status: PlayerStatus.playing,
        position: Duration(minutes: 5),
        duration: Duration(hours: 2),
        bufferedPosition: Duration(minutes: 8),
        isLive: false,
      );
      expect(state.isPlaying, isTrue);
      expect(state.hasError, isFalse);
      expect(state.bufferedPosition, const Duration(minutes: 8));
      expect(const ZvPlayerState(status: PlayerStatus.completed).status,
          PlayerStatus.completed);
    });
  });
}
