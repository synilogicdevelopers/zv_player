import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QualityRung', () {
    test('maps heights to the nearest rung at or below', () {
      expect(QualityRung.nearest(1080), QualityRung.q1080);
      expect(QualityRung.nearest(2160), QualityRung.q2160);
      // An odd rendition is labelled by the rung below, not rounded up.
      expect(QualityRung.nearest(576), QualityRung.q480);
      expect(QualityRung.nearest(144), QualityRung.q240);
      expect(QualityRung.nearest(null), isNull);
      expect(QualityRung.nearest(0), isNull);
    });

    test('parses backend quality labels', () {
      expect(QualityRung.fromLabel('720p'), QualityRung.q720);
      expect(QualityRung.fromLabel('4K'), QualityRung.q2160);
      expect(QualityRung.fromLabel('2K'), QualityRung.q1440);
      expect(QualityRung.fromLabel('1080'), QualityRung.q1080);
      expect(QualityRung.fromLabel('default'), isNull);
      expect(QualityRung.fromLabel(null), isNull);
    });
  });

  group('track mapping from native payloads', () {
    test('labels a video track from its height when none is supplied', () {
      final VideoQualityTrack track = VideoQualityTrack.fromMap(
        <String, Object?>{'id': '0:1', 'height': 1080, 'width': 1920},
      );
      expect(track.label, '1080p');
      expect(track.id, '0:1');
    });

    test('keeps the native label when one is supplied', () {
      final VideoQualityTrack track = VideoQualityTrack.fromMap(
        <String, Object?>{'id': '0:0', 'label': '4K', 'height': 2160},
      );
      expect(track.label, '4K');
    });

    test('detects Dolby audio from the codec string only', () {
      final AudioTrackOption dolby = AudioTrackOption.fromMap(
        <String, Object?>{'id': '1:0', 'language': 'en', 'codec': 'ec-3'},
      );
      final AudioTrackOption aac = AudioTrackOption.fromMap(
        <String, Object?>{'id': '1:1', 'language': 'hi', 'codec': 'mp4a.40.2'},
      );
      expect(dolby.isDolby, isTrue);
      expect(aac.isDolby, isFalse);
    });

    test('falls back to the language when a track has no label', () {
      final AudioTrackOption track = AudioTrackOption.fromMap(
        <String, Object?>{'id': '1:0', 'language': 'hi'},
      );
      expect(track.label, 'hi');
    });
  });

  group('PlayerTracks', () {
    test('reports a choice only when more than one option exists', () {
      const PlayerTracks single = PlayerTracks(
        video: <VideoQualityTrack>[
          VideoQualityTrack(id: '1', label: '720p'),
        ],
      );
      expect(single.hasQualityChoice, isFalse);

      const PlayerTracks multiple = PlayerTracks(
        video: <VideoQualityTrack>[
          VideoQualityTrack(id: '1', label: '720p'),
          VideoQualityTrack(id: '2', label: '1080p'),
        ],
      );
      expect(multiple.hasQualityChoice, isTrue);
    });

    test('has no subtitles when the source carries none', () {
      const PlayerTracks tracks = PlayerTracks();
      expect(tracks.hasSubtitles, isFalse);
      expect(tracks.selectedSubtitle, isNull);
    });
  });
}
