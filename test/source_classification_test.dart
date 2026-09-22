import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/zv_player.dart';

/// Regression coverage for routing a URL to the right engine.
///
/// The field bug: a trailer stored as an opaque `google.com/goto` redirect
/// fell through to the "any https URL is progressive" rule and reached Media3,
/// which failed with `UnrecognizedInputFormatException`.
void main() {
  ZvSourceType typeOf(String uri, {String? declared}) =>
      ZvMediaSource.detect(uri: uri, declaredType: declared).type;

  final SourceRouter router = SourceRouter.standard();
  PlaybackEngineKind engineFor(String uri, {String? declared}) => router
      .select(ZvMediaSource.detect(uri: uri, declaredType: declared))
      .kind;

  group('YouTube is recognised before any native detection', () {
    for (final String url in <String>[
      'https://youtube.com/watch?v=iITwUMIwI1k',
      'https://www.youtube.com/watch?v=iITwUMIwI1k',
      // The catalogue's real form, with YouTube's `pp` tracking parameter.
      'https://www.youtube.com/watch?v=opNGmvyFdRo&pp=ygUQYm9sbHl3b29kIG1vdmllcw%3D%3D',
      'https://m.youtube.com/watch?v=iITwUMIwI1k',
      'https://youtu.be/iITwUMIwI1k',
      'https://www.youtube.com/embed/iITwUMIwI1k',
      'https://www.youtube-nocookie.com/embed/iITwUMIwI1k',
      'www.youtube.com/watch?v=iITwUMIwI1k',
      '<iframe src="https://www.youtube.com/embed/iITwUMIwI1k"></iframe>',
    ]) {
      test(url, () {
        expect(typeOf(url, declared: 'URL'), ZvSourceType.youtube);
        expect(engineFor(url, declared: 'URL'), PlaybackEngineKind.embedded);
      });
    }

    test('a YouTube URL mislabelled as native media still goes to YouTube', () {
      for (final String declared in <String>['hls', 'dash', 'local', 'file']) {
        expect(
            typeOf('https://www.youtube.com/watch?v=iITwUMIwI1k',
                declared: declared),
            ZvSourceType.youtube,
            reason: 'declared $declared');
      }
    });

    test('the YouTube engine receives a URL it can read', () {
      final ZvMediaSource source = ZvMediaSource.detect(
          uri:
              '<iframe src="https://www.youtube.com/embed/iITwUMIwI1k"></iframe>');
      expect(youTubeVideoId(source.uri), 'iITwUMIwI1k');
    });
  });

  group('native routes are unchanged', () {
    test('MP4', () {
      expect(typeOf('https://cdn.example.com/movie.mp4', declared: 'URL'),
          ZvSourceType.progressive);
      expect(engineFor('https://cdn.example.com/movie.mp4'),
          PlaybackEngineKind.native);
    });
    test('HLS', () {
      expect(typeOf('https://cdn.example.com/master.m3u8?token=1'),
          ZvSourceType.hls);
      expect(engineFor('https://cdn.example.com/master.m3u8'),
          PlaybackEngineKind.native);
    });
    test('DASH', () {
      expect(typeOf('https://cdn.example.com/manifest.mpd'), ZvSourceType.dash);
      expect(engineFor('https://cdn.example.com/manifest.mpd'),
          PlaybackEngineKind.native);
    });
    test('local file', () {
      expect(typeOf('/data/user/0/app/files/a.mp4'), ZvSourceType.local);
    });
  });

  group('invalid and non-media URLs never reach a native pipeline', () {
    test('garbage is unsupported', () {
      expect(typeOf('not a video'), ZvSourceType.unknown);
      expect(engineFor('not a video'), PlaybackEngineKind.unsupported);
      expect(typeOf(''), ZvSourceType.unknown);
    });

    test('an opaque google.com/goto redirect is unsupported, not native', () {
      const String goto =
          'https://www.google.com/goto?url=CAESYwHrOzAVkmQ9mKzIFmaApUAIJPiQF8LqRO8_Rsf9CIq';
      expect(typeOf(goto, declared: 'URL'), ZvSourceType.unknown);
      expect(engineFor(goto, declared: 'URL'), PlaybackEngineKind.unsupported);
      expect(router.createEngine(ZvMediaSource.detect(uri: goto)), isNull);
    });

    test('a readable Google redirect is unwrapped locally', () {
      final ZvMediaSource yt = ZvMediaSource.detect(
          uri: 'https://www.google.com/url?q=https%3A%2F%2Fwww.youtube.com%2F'
              'watch%3Fv%3DiITwUMIwI1k&sa=D',
          declaredType: 'URL');
      expect(yt.type, ZvSourceType.youtube);
      expect(yt.uri, 'https://www.youtube.com/watch?v=iITwUMIwI1k');

      final ZvMediaSource mp4 = ZvMediaSource.detect(
          uri:
              'https://www.google.co.in/url?url=https://cdn.example.com/a.mp4');
      expect(mp4.type, ZvSourceType.progressive);
      expect(mp4.uri, 'https://cdn.example.com/a.mp4');
    });

    test('a look-alike host is not YouTube', () {
      expect(typeOf('https://notyoutube.com/watch?v=iITwUMIwI1k'),
          isNot(ZvSourceType.youtube));
    });
  });
}
