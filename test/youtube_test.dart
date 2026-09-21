import 'package:flutter_test/flutter_test.dart';
import 'package:zv_player/src/engine/youtube_page.dart';
import 'package:zv_player/zv_player.dart';

void main() {
  group('youTubeVideoId', () {
    test('recognises every common URL shape', () {
      const String id = 'iITwUMIwI1k';
      for (final String url in <String>[
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&t=1s',
        'https://m.youtube.com/watch?feature=share&v=$id',
        'https://music.youtube.com/watch?v=$id&list=RD$id',
        'https://youtu.be/$id',
        'https://youtu.be/$id?si=abc',
        'https://www.youtube.com/embed/$id',
        'https://www.youtube-nocookie.com/embed/$id?rel=0',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id',
        'www.youtube.com/watch?v=$id',
        '<iframe src="https://www.youtube.com/embed/$id"></iframe>',
        id,
      ]) {
        expect(youTubeVideoId(url), id, reason: url);
      }
    });

    test('the catalogue URLs resolve, playlist parameters and all', () {
      expect(
          youTubeVideoId('https://www.youtube.com/watch?v=0w62ddeVwGE'
              '&list=RD0w62ddeVwGE&start_radio=1'),
          '0w62ddeVwGE');
      expect(youTubeVideoId('https://www.youtube.com/watch?v=BKOVzHcjEIo&t=1s'),
          'BKOVzHcjEIo');
    });

    test('rejects anything that is not a YouTube video', () {
      for (final String url in <String>[
        '',
        'https://vimeo.com/12345',
        'https://cdn.example.com/movie.mp4',
        'https://www.youtube.com/',
        'https://www.youtube.com/watch?v=short',
        'https://www.youtube.com/channel/UC1234567890',
        'https://notyoutube.com/watch?v=iITwUMIwI1k',
      ]) {
        expect(youTubeVideoId(url), isNull, reason: url);
      }
    });
  });

  group('YouTube page', () {
    final String html = youTubePage('iITwUMIwI1k', autoplay: true, mute: false);

    test('hides YouTube\'s own controls', () {
      expect(html, contains('controls: 0'));
      expect(html, isNot(contains('controls: 1')));
    });

    // Regression: with a warm cache the API fired its ready callback before
    // the callback existed, so the player was never created.
    test('defines the ready callback before loading the API', () {
      final int callback = html.indexOf('function onYouTubeIframeAPIReady');
      final int api = html.indexOf('https://www.youtube.com/iframe_api');
      expect(callback, isNonNegative);
      expect(callback, lessThan(api));
    });

    test('unmuting never starts playback', () {
      final String unMute =
          html.substring(html.indexOf('function unMute'), html.length);
      expect(unMute.substring(0, unMute.indexOf('}')),
          isNot(contains('playVideo')));
    });
  });

  group('YouTubeEngine', () {
    final ZvMediaSource youtube = ZvMediaSource.detect(
        uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k',
        declaredType: 'YouTube');

    test('claims only what the IFrame API can do', () {
      final EngineCapabilities caps = YouTubeEngine().capabilities;
      expect(caps.canPlayPause, isTrue);
      expect(caps.canSeek, isTrue);
      expect(caps.canSetSpeed, isTrue);
      expect(caps.canSetVolume, isTrue);
      expect(caps.canMute, isTrue);
      expect(caps.reportsBufferedPosition, isTrue);
      expect(caps.canSelectQuality, isFalse);
      expect(caps.canSelectSubtitle, isFalse);
      expect(caps.canSelectAudioTrack, isFalse);
      expect(caps.supportsPictureInPicture, isFalse);
      expect(caps.supportsCast, isFalse);
      expect(caps.canChangeVideoFit, isFalse);
      expect(caps.supportsDrm, isFalse);
    });

    test('an invalid YouTube link is an error state, not a blank player',
        () async {
      final YouTubeEngine engine = YouTubeEngine();
      await engine.load(ZvMediaSource.detect(
          uri: 'https://www.youtube.com/channel/UC1', declaredType: 'YouTube'));
      expect(engine.state.value.status, PlayerStatus.error);
      expect(engine.state.value.error?.code, 'youtube_invalid_url');
      await engine.dispose();
    });

    test('page events drive the shared state model', () async {
      final YouTubeEngine engine = YouTubeEngine();
      await engine.load(youtube);
      expect(engine.state.value.status, PlayerStatus.loading);

      engine.debugHandleWebMessage(
          '{"event":"timeUpdate","currentTime":12.5,"duration":13369,'
          '"buffered":0.01,"volume":0.8,"muted":false,"rate":1}');
      expect(engine.state.value.status, PlayerStatus.ready);
      expect(engine.state.value.position, const Duration(milliseconds: 12500));
      expect(engine.state.value.duration, const Duration(seconds: 13369));
      expect(engine.state.value.bufferedPosition.inSeconds, 133);

      engine.debugHandleWebMessage('playing');
      expect(engine.state.value.status, PlayerStatus.playing);
      engine.debugHandleWebMessage('paused');
      expect(engine.state.value.status, PlayerStatus.paused);
      engine.debugHandleWebMessage('ended');
      expect(engine.state.value.status, PlayerStatus.completed);

      engine.debugHandleWebMessage('{"event":"error","code":150}');
      expect(engine.state.value.error?.code, 'youtube_150');
      await engine.dispose();
    });

    test('a seek survives the provider reporting its stale clock', () async {
      final YouTubeEngine engine = YouTubeEngine();
      await engine.load(youtube);
      await engine.seekTo(const Duration(seconds: 600));
      engine.debugHandleWebMessage(
          '{"event":"timeUpdate","currentTime":12,"duration":13369}');
      expect(engine.state.value.position, const Duration(seconds: 600));
      engine.debugHandleWebMessage(
          '{"event":"timeUpdate","currentTime":600.4,"duration":13369}');
      expect(engine.state.value.position.inSeconds, 600);
      await engine.dispose();
    });

    test('a malformed page message is ignored', () async {
      final YouTubeEngine engine = YouTubeEngine();
      await engine.load(youtube);
      engine.debugHandleWebMessage('{not json');
      engine.debugHandleWebMessage(null);
      expect(engine.state.value.hasError, isFalse);
      await engine.dispose();
    });

    test('the standard router sends YouTube here and media to native', () {
      final SourceRouter router = SourceRouter.standard();
      expect(router.hasYouTubeEngine, isTrue);
      expect(router.hasNativeEngine, isTrue);
      expect(router.select(youtube).kind, PlaybackEngineKind.embedded);
      final PlaybackEngine? engine = router.createEngine(youtube);
      expect(engine, isA<YouTubeEngine>());
      engine!.dispose();
      for (final String uri in <String>[
        'https://cdn.example.com/a.mp4',
        'https://cdn.example.com/master.m3u8',
        'https://cdn.example.com/manifest.mpd',
        '/data/user/0/app/files/a.mp4',
      ]) {
        expect(router.select(ZvMediaSource.detect(uri: uri)).kind,
            PlaybackEngineKind.native,
            reason: uri);
      }
      expect(router.select(ZvMediaSource.detect(uri: 'not a url')).kind,
          PlaybackEngineKind.unsupported);
    });
  });
}
