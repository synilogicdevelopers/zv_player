import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_platform.dart';

void main() {
  late FakePlayerPlatform platform;
  late InMemoryProgressStore store;
  late RecordingAnalyticsSink analytics;
  late ZvNativeController controller;

  ZvMediaSource progressiveSource(
      {List<ZvSourceVariant> variants = const <ZvSourceVariant>[]}) {
    return ZvMediaSource.detect(
      uri: 'https://cdn.example.com/movie-720.mp4',
      contentId: 'content-1',
      title: 'Test Movie',
      variants: variants,
    );
  }

  setUp(() {
    platform = FakePlayerPlatform();
    store = InMemoryProgressStore();
    analytics = RecordingAnalyticsSink();
    controller = ZvNativeController(
      platform: platform,
      progressStore: store,
      analytics: analytics,
      secureSurface: false,
    );
  });

  tearDown(() async {
    if (controller.playerId != null) await controller.dispose();
  });

  group('lifecycle', () {
    test('creates exactly one native player', () async {
      await controller.initialise();
      await controller.initialise(); // Second call must be a no-op.
      expect(platform.createdPlayers, 1);
      expect(controller.playerId, 1);
    });

    test('concurrent initialise calls share one native player', () async {
      // Two callers racing must not produce two decoders.
      await Future.wait<void>(<Future<void>>[
        controller.initialise(),
        controller.initialise(),
        controller.initialise(),
      ]);
      expect(platform.createdPlayers, 1);
    });

    test('load initialises the player when it has not been created yet',
        () async {
      await controller.load(progressiveSource());
      expect(platform.createdPlayers, 1);
      expect(platform.loadedSources.length, 1);
    });

    test('releases the native player on dispose', () async {
      await controller.initialise();
      await controller.dispose();
      expect(platform.disposed, isTrue);
      expect(controller.playerId, isNull);
    });

    test('a failed native creation surfaces an error instead of throwing',
        () async {
      final FailingCreatePlatform failing = FailingCreatePlatform();
      final ZvNativeController broken = ZvNativeController(
        platform: failing,
        progressStore: InMemoryProgressStore(),
        secureSurface: false,
      );
      addTearDown(broken.dispose);

      // Must not throw into the calling screen.
      await broken.initialise();

      expect(broken.value.hasError, isTrue);
      expect(broken.value.error?.type, PlayerErrorType.lifecycle);
      expect(broken.value.error?.code, 'player_create_failed');
      expect(broken.value.error!.message, isNot(contains('Exception')));
    });

    test('persists progress on dispose instead of losing the last interval',
        () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 420000,
        'durationMs': 900000,
      });
      await pumpEventQueue();

      await controller.dispose();
      expect((await store.load('content-1'))?.position,
          const Duration(minutes: 7));
    });

    test('ignores native events that arrive after disposal', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      final PlayerStatus statusBefore = controller.value.status;
      await controller.dispose();

      // Must not throw "used after dispose" or mutate state.
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'playing'});
      await pumpEventQueue();
      expect(controller.value.status, statusBefore);
    });
  });

  group('state transitions', () {
    test('follows native status events', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      expect(controller.value.status, PlayerStatus.loading);

      platform.emit(<String, dynamic>{'event': 'status', 'status': 'ready'});
      await pumpEventQueue();
      expect(controller.value.status, PlayerStatus.ready);

      platform.emit(<String, dynamic>{'event': 'status', 'status': 'playing'});
      await pumpEventQueue();
      expect(controller.value.isPlaying, isTrue);

      platform
          .emit(<String, dynamic>{'event': 'status', 'status': 'buffering'});
      await pumpEventQueue();
      expect(controller.value.isBuffering, isTrue);
      // Controls must stay usable through a stall.
      expect(controller.value.isInitialised, isTrue);
    });

    test('updates position, duration and buffered from native', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 30000,
        'durationMs': 600000,
        'bufferedMs': 90000,
      });
      await pumpEventQueue();

      expect(controller.value.position, const Duration(seconds: 30));
      expect(controller.value.duration, const Duration(minutes: 10));
      expect(controller.value.bufferedPosition, const Duration(seconds: 90));
      expect(controller.value.progress, closeTo(0.05, 0.001));
    });

    test('a drag preview is not overwritten by native position events',
        () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'ready'});
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 1000,
        'durationMs': 600000,
      });
      await pumpEventQueue();

      controller.previewSeek(const Duration(minutes: 5));
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 2000,
        'durationMs': 600000,
      });
      await pumpEventQueue();

      expect(controller.value.position, const Duration(minutes: 5));
    });
  });

  group('tracks', () {
    test('offers Auto only when the manifest has several renditions', () async {
      await controller.initialise();
      await controller.load(
        ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8'),
      );
      platform.emit(<String, dynamic>{
        'event': 'tracks',
        'video': <Map<String, Object?>>[
          <String, Object?>{'id': '0:0', 'height': 1080, 'isSelected': false},
          <String, Object?>{'id': '0:1', 'height': 720, 'isSelected': false},
        ],
        'audio': <Map<String, Object?>>[],
        'text': <Map<String, Object?>>[],
      });
      await pumpEventQueue();

      expect(controller.value.tracks.video.first.isAuto, isTrue);
      expect(controller.value.tracks.video.length, 3);
    });

    test('does not offer Auto for a single rendition', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'tracks',
        'video': <Map<String, Object?>>[
          <String, Object?>{'id': '0:0', 'height': 720, 'isSelected': true},
        ],
        'audio': <Map<String, Object?>>[],
        'text': <Map<String, Object?>>[],
      });
      await pumpEventQueue();

      expect(
        controller.value.tracks.video.any((VideoQualityTrack t) => t.isAuto),
        isFalse,
      );
      expect(controller.value.tracks.hasQualityChoice, isFalse);
    });

    test('exposes no subtitle or audio options when the media has none',
        () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'tracks',
        'video': <Map<String, Object?>>[],
        'audio': <Map<String, Object?>>[],
        'text': <Map<String, Object?>>[],
      });
      await pumpEventQueue();

      expect(controller.value.tracks.hasSubtitles, isFalse);
      expect(controller.value.tracks.hasAudioChoice, isFalse);
    });

    test('per-URL variants become the quality list without a native override',
        () async {
      await controller.initialise();
      final ZvMediaSource source = progressiveSource(
        variants: const <ZvSourceVariant>[
          ZvSourceVariant(
            id: 'v720',
            label: '720p',
            uri: 'https://cdn.example.com/movie-720.mp4',
            height: 720,
          ),
          ZvSourceVariant(
            id: 'v1080',
            label: '1080p',
            uri: 'https://cdn.example.com/movie-1080.mp4',
            height: 1080,
          ),
        ],
      );
      await controller.load(source);

      // Highest first, and the one matching the current URI is selected.
      expect(controller.value.tracks.video.first.label, '1080p');
      expect(controller.value.tracks.video.length, 2);
      expect(
        controller.value.tracks.video
            .firstWhere((VideoQualityTrack t) => t.id == 'v720')
            .isSelected,
        isTrue,
      );
      expect(
          controller.value.tracks.video
              .every((VideoQualityTrack t) => t.isVariant),
          isTrue);
    });

    test('switching a variant reloads that URL at the same position', () async {
      await controller.initialise();
      await controller.load(
        progressiveSource(
          variants: const <ZvSourceVariant>[
            ZvSourceVariant(
              id: 'v720',
              label: '720p',
              uri: 'https://cdn.example.com/movie-720.mp4',
              height: 720,
            ),
            ZvSourceVariant(
              id: 'v1080',
              label: '1080p',
              uri: 'https://cdn.example.com/movie-1080.mp4',
              height: 1080,
            ),
          ],
        ),
      );
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 120000,
        'durationMs': 600000,
      });
      await pumpEventQueue();

      await controller.selectQuality(
        controller.value.tracks.video
            .firstWhere((VideoQualityTrack t) => t.id == 'v1080'),
      );

      expect(platform.loadedSources.last.uri,
          'https://cdn.example.com/movie-1080.mp4');
      expect(platform.loadedSources.last.startPosition,
          const Duration(minutes: 2));
      // No native track override: there is only one rendition in the file.
      expect(platform.lastVideoTrackId, isNull);
      expect(analytics.names, contains(PlayerEventName.qualityChange));
    });

    test('selecting Auto clears the native override', () async {
      await controller.initialise();
      await controller.load(
        ZvMediaSource.detect(uri: 'https://cdn.example.com/master.m3u8'),
      );
      platform.emit(<String, dynamic>{
        'event': 'tracks',
        'video': <Map<String, Object?>>[
          <String, Object?>{'id': '0:0', 'height': 1080},
          <String, Object?>{'id': '0:1', 'height': 720},
        ],
        'audio': <Map<String, Object?>>[],
        'text': <Map<String, Object?>>[],
      });
      await pumpEventQueue();

      await controller.selectQuality(controller.value.tracks.video[1]);
      expect(platform.lastVideoTrackId, '0:0');

      await controller.selectQuality(controller.value.tracks.video.first);
      expect(platform.lastVideoTrackId, isNull);
    });

    test('turning subtitles off passes null to the platform', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      await controller.selectSubtitle(null);
      expect(platform.calls, contains('selectSubtitleTrack'));
      expect(platform.lastSubtitleTrackId, isNull);
    });
  });

  group('resume', () {
    test('restores a stored position when it is still meaningful', () async {
      await store.save(
        const PlaybackProgress(
          contentId: 'content-1',
          position: Duration(minutes: 8),
          duration: Duration(minutes: 100),
        ),
      );
      await controller.initialise();
      await controller.load(progressiveSource());

      expect(platform.loadedSources.single.startPosition,
          const Duration(minutes: 8));
    });

    test('ignores a stored position from a finished item', () async {
      await store.save(
        const PlaybackProgress(
          contentId: 'content-1',
          position: Duration(minutes: 99, seconds: 58),
          duration: Duration(minutes: 100),
        ),
      );
      await controller.initialise();
      await controller.load(progressiveSource());

      expect(platform.loadedSources.single.startPosition, Duration.zero);
    });

    test('does not save a position too small to matter', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 4000,
        'durationMs': 600000,
      });
      await pumpEventQueue();

      await controller.flushProgress();
      expect(await store.load('content-1'), isNull);
    });

    test('saves a real mid-playback position', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 300000,
        'durationMs': 600000,
      });
      await pumpEventQueue();

      await controller.flushProgress();
      expect((await store.load('content-1'))?.position,
          const Duration(minutes: 5));
    });

    test('clears stored progress when playback completes', () async {
      await store.save(
        const PlaybackProgress(
          contentId: 'content-1',
          position: Duration(minutes: 30),
          duration: Duration(minutes: 100),
        ),
      );
      await controller.initialise();
      await controller.load(progressiveSource(), useStoredResume: false);

      platform.emit(<String, dynamic>{'event': 'completed'});
      await pumpEventQueue();

      expect(controller.value.status, PlayerStatus.completed);
      expect(await store.load('content-1'), isNull);
    });
  });

  group('source routing', () {
    test('a YouTube source is refused before it reaches the platform',
        () async {
      await controller.initialise();
      await controller.load(
        ZvMediaSource.detect(
          uri: 'https://www.youtube.com/watch?v=iITwUMIwI1k',
          declaredType: 'YouTube',
          contentId: 'yt-1',
        ),
      );

      // The critical assertion: native load was never called.
      expect(platform.loadedSources, isEmpty);
      expect(platform.calls, isNot(contains('load')));
      expect(controller.value.hasError, isTrue);
      expect(controller.value.error?.type, PlayerErrorType.unsupportedFormat);
      expect(controller.value.error?.code, 'source_not_native');
      // The viewer is told which platform, not given a decoder exception.
      expect(controller.value.error!.message, contains('YouTube'));
      expect(controller.value.error!.message, isNot(contains('Exception')));
    });

    test('Vimeo and generic embeds are refused too', () async {
      await controller.initialise();
      for (final String declared in <String>['Vimeo', 'Embedded']) {
        await controller.load(
          ZvMediaSource.detect(
            uri: 'https://example.com/embed/1',
            declaredType: declared,
          ),
        );
        expect(controller.value.hasError, isTrue, reason: declared);
      }
      expect(platform.loadedSources, isEmpty);
    });

    test('native sources still load normally', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      expect(platform.loadedSources.length, 1);
      expect(controller.value.hasError, isFalse);
    });
  });

  group('errors', () {
    test('surfaces a non-recoverable error without retrying', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      final int loadsBefore = platform.loadedSources.length;

      platform.emit(<String, dynamic>{
        'event': 'error',
        'code': 'ERROR_CODE_DECODING_FAILED',
        'message': 'decoder init failed',
        'recoverable': false,
      });
      await pumpEventQueue();

      expect(controller.value.hasError, isTrue);
      expect(controller.value.error?.type, PlayerErrorType.decoder);
      expect(platform.loadedSources.length, loadsBefore);
    });

    test('never shows raw native detail as the viewer-facing message',
        () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'error',
        'code': 'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED',
        'message': 'MediaDrmCallbackException: stack trace here',
        'recoverable': false,
      });
      await pumpEventQueue();

      expect(controller.value.error!.message, isNot(contains('Exception')));
      expect(controller.value.error!.technicalDetail, isNotNull);
    });

    // Uses testWidgets for its fake clock: the retry schedule is timer-driven.
    testWidgets('automatic retries stop at maxRetries',
        (WidgetTester tester) async {
      final FakePlayerPlatform local = FakePlayerPlatform();
      final ZvNativeController retrying = ZvNativeController(
        platform: local,
        progressStore: InMemoryProgressStore(),
        maxRetries: 2,
        secureSurface: false,
      );
      addTearDown(retrying.dispose);

      await retrying.initialise();
      await retrying.load(
        ZvMediaSource.detect(
            uri: 'https://cdn.example.com/a.mp4', contentId: 'c1'),
      );
      expect(local.loadedSources.length, 1);

      Future<void> failOnce() async {
        local.emit(<String, dynamic>{
          'event': 'error',
          'code': 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
          'recoverable': true,
        });
        await tester.pump();
        // Longer than the widest backoff so the scheduled retry fires.
        await tester.pump(const Duration(seconds: 10));
      }

      await failOnce();
      expect(local.loadedSources.length, 2, reason: 'first retry');

      await failOnce();
      expect(local.loadedSources.length, 3, reason: 'second retry');

      // Third failure exhausts the budget: surface it, do not reload again.
      await failOnce();
      expect(local.loadedSources.length, 3, reason: 'no third retry');
      expect(retrying.value.hasError, isTrue);
      expect(retrying.value.error?.type, PlayerErrorType.network);
    });

    test('retry reloads from the current position', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 60000,
        'durationMs': 600000,
      });
      await pumpEventQueue();
      platform.emit(<String, dynamic>{
        'event': 'error',
        'code': 'ERROR_CODE_DECODING_FAILED',
        'recoverable': false,
      });
      await pumpEventQueue();

      await controller.retry();
      expect(platform.loadedSources.last.startPosition,
          const Duration(minutes: 1));
    });
  });

  group('transport', () {
    test('seek is clamped to the media duration', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'ready'});
      platform.emit(<String, dynamic>{
        'event': 'position',
        'positionMs': 0,
        'durationMs': 60000,
      });
      await pumpEventQueue();

      await controller.seekTo(const Duration(minutes: 5));
      expect(platform.lastSeek, const Duration(seconds: 60));

      await controller.seekTo(const Duration(seconds: -30));
      expect(platform.lastSeek, Duration.zero);
    });

    test('a live stream cannot be seeked', () async {
      await controller.initialise();
      await controller.load(
        ZvMediaSource.detect(
            uri: 'https://cdn.example.com/live.m3u8', isLive: true),
      );
      expect(controller.value.canSeek, isFalse);

      await controller.seekTo(const Duration(seconds: 30));
      expect(platform.calls, isNot(contains('seekTo')));
    });

    test('a refused seek still ends the drag so the scrubber unfreezes',
        () async {
      await controller.initialise();
      await controller.load(
        ZvMediaSource.detect(
            uri: 'https://cdn.example.com/live.m3u8', isLive: true),
      );
      controller.value = controller.value.copyWith(isSeeking: true);

      await controller.seekTo(const Duration(seconds: 30));
      expect(controller.value.isSeeking, isFalse);
    });

    test('speed changes reach the platform and the state', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      await controller.setSpeed(1.5);

      expect(platform.lastSpeed, 1.5);
      expect(controller.value.speed, 1.5);
      expect(analytics.names, contains(PlayerEventName.speedChange));
    });

    test('PiP is refused once the device reports no support', () async {
      platform.capabilitiesResult =
          const DeviceCapabilities(supportsPip: false, probed: true);
      await controller.initialise();
      // Capabilities are probed after load, not during the transition, so the
      // answer is only known once playback has started.
      await controller.load(progressiveSource());
      await pumpEventQueue();

      expect(await controller.enterPictureInPicture(), isFalse);
      expect(platform.calls, isNot(contains('enterPictureInPicture')));
    });
  });

  group('analytics', () {
    test('emits startup and play without sending anything anywhere', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'playing'});
      await pumpEventQueue();

      expect(analytics.names, contains(PlayerEventName.startup));
      expect(analytics.names, contains(PlayerEventName.play));
      expect(
        analytics.events
            .firstWhere(
                (PlayerAnalyticsEvent e) => e.name == PlayerEventName.startup)
            .properties['startupTimeMs'],
        isA<int>(),
      );
    });

    test('brackets a stall with buffer_start and buffer_end', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      platform
          .emit(<String, dynamic>{'event': 'status', 'status': 'buffering'});
      await pumpEventQueue();
      platform.emit(<String, dynamic>{'event': 'status', 'status': 'playing'});
      await pumpEventQueue();

      expect(
          analytics.names,
          containsAllInOrder(<String>[
            PlayerEventName.bufferStart,
            PlayerEventName.bufferEnd,
          ]));
    });
  });

  group('up next', () {
    test('has no next episode unless the caller supplies one', () async {
      await controller.initialise();
      await controller.load(progressiveSource());
      expect(controller.value.hasNextEpisode, isFalse);

      await controller.playNext(); // Must be a no-op, not a crash.
      expect(platform.loadedSources.length, 1);
    });

    test('plays the supplied next item', () async {
      await controller.initialise();
      await controller.load(
        progressiveSource(),
        upNext: UpNextItem(
          title: 'Episode 2',
          source: ZvMediaSource.detect(
            uri: 'https://cdn.example.com/ep2.mp4',
            contentId: 'content-2',
          ),
        ),
      );
      expect(controller.value.hasNextEpisode, isTrue);

      await controller.playNext();
      expect(platform.loadedSources.last.contentId, 'content-2');
    });
  });
}
