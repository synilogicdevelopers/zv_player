import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

/// Volume, mute, brightness, fit and mode are *presentation*. None of them may
/// start or stop playback. A device test found unmute silently resuming a
/// paused video, so these invariants are pinned here.
void main() {
  late FakePlayerPlatform platform;
  late ZvNativeController controller;

  ZvMediaSource source() => ZvMediaSource.detect(
        uri: 'https://cdn.example.com/movie.mp4',
        contentId: 'c1',
      );

  setUp(() async {
    platform = FakePlayerPlatform();
    controller = ZvNativeController(
      platform: platform,
      progressStore: InMemoryProgressStore(),
      secureSurface: false,
    );
    await controller.load(source());
  });

  tearDown(() async {
    if (controller.playerId != null) await controller.dispose();
  });

  Future<void> setPlaying(bool playing) async {
    platform.emit(<String, dynamic>{
      'event': 'status',
      'status': playing ? 'playing' : 'paused',
    });
    await pumpEventQueue();
  }

  group('mute and volume never change playback state', () {
    test('paused + unmute stays paused', () async {
      await setPlaying(false);
      expect(controller.value.isPlaying, isFalse);

      await controller.setMuted(false);
      await pumpEventQueue();

      expect(controller.value.status, PlayerStatus.paused);
      expect(platform.calls, isNot(contains('play')));
    });

    test('paused + mute stays paused', () async {
      await setPlaying(false);
      await controller.setMuted(true);
      await pumpEventQueue();

      expect(controller.value.status, PlayerStatus.paused);
      expect(platform.calls, isNot(contains('play')));
    });

    test('playing + unmute stays playing', () async {
      await setPlaying(true);
      await controller.setMuted(false);
      await pumpEventQueue();

      expect(controller.value.status, PlayerStatus.playing);
      expect(platform.calls, isNot(contains('pause')));
    });

    test('playing + mute stays playing', () async {
      await setPlaying(true);
      await controller.setMuted(true);
      await pumpEventQueue();

      expect(controller.value.status, PlayerStatus.playing);
      expect(platform.calls, isNot(contains('pause')));
    });

    test('a volume change while paused does not resume', () async {
      await setPlaying(false);
      await controller.setVolume(0.7);
      await pumpEventQueue();

      expect(controller.value.status, PlayerStatus.paused);
      expect(controller.value.volume, 0.7);
      expect(platform.calls, isNot(contains('play')));
    });

    test('toggling mute repeatedly never issues a transport command', () async {
      await setPlaying(false);
      for (int i = 0; i < 4; i++) {
        await controller.toggleMute();
        await pumpEventQueue();
      }

      expect(controller.value.status, PlayerStatus.paused);
      expect(platform.calls, isNot(contains('play')));
      expect(platform.calls, isNot(contains('pause')));
    });
  });

  group('video fit is presentation only', () {
    test('changing fit does not touch playback', () async {
      await setPlaying(false);

      await controller.setVideoFit(VideoFitMode.fill);
      await pumpEventQueue();

      expect(controller.value.videoFit, VideoFitMode.fill);
      expect(controller.value.status, PlayerStatus.paused);
      expect(platform.calls, isNot(contains('play')));
    });

    test('fit survives as state and can be switched back', () async {
      await controller.setVideoFit(VideoFitMode.fill);
      expect(controller.value.videoFit, VideoFitMode.fill);

      await controller.setVideoFit(VideoFitMode.fit);
      expect(controller.value.videoFit, VideoFitMode.fit);
    });

    test('fit defaults to showing the whole frame', () {
      expect(const ZvPlayerState().videoFit, VideoFitMode.fit);
    });
  });

  group('presentation mode is independent of playback and fit', () {
    test('entering fullscreen does not change playback or fit', () async {
      await setPlaying(true);
      await controller.setVideoFit(VideoFitMode.fill);

      controller.setFullscreen(true);

      expect(controller.value.isFullscreen, isTrue);
      expect(controller.value.status, PlayerStatus.playing);
      expect(controller.value.videoFit, VideoFitMode.fill,
          reason: 'presentation must not reset the picture scaling');
    });
  });
}
