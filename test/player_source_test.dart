import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('embedded source classification (device-failure regression)', () {
    // The exact payload that reached Media3 on device and threw
    // UnrecognizedInputFormatException / ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED.
    const String youtubeWatchUrl =
        'https://www.youtube.com/watch?v=iITwUMIwI1k';

    test('API casing "YouTube" classifies as YouTube, not native', () {
      final ZvSourceType type = ZvMediaSource.detectType(
        youtubeWatchUrl,
        declaredType: 'YouTube',
      );
      expect(type, ZvSourceType.youtube);
      expect(type.isNativePlayable, isFalse);
      expect(type.isEmbedded, isTrue);
    });

    test('any casing of the declared type is accepted', () {
      for (final String declared in <String>[
        'YouTube',
        'youtube',
        'YOUTUBE',
        ' YouTube ',
        'Vimeo',
        'EMBEDDED',
      ]) {
        expect(
          ZvMediaSource.detectType('https://example.com/x',
                  declaredType: declared)
              .isNativePlayable,
          isFalse,
          reason: declared,
        );
      }
    });

    test('a YouTube URL is caught even when the backend mislabels it', () {
      // Defence in depth: bad metadata must not reach the native pipeline.
      expect(
        ZvMediaSource.detectType(youtubeWatchUrl, declaredType: 'url'),
        ZvSourceType.youtube,
      );
      expect(
        ZvMediaSource.detectType('https://youtu.be/abc123',
            declaredType: 'mp4'),
        ZvSourceType.youtube,
      );
      expect(
        ZvMediaSource.detectType('https://vimeo.com/12345', declaredType: ''),
        ZvSourceType.vimeo,
      );
    });

    test('an extensionless http URL is still treated as progressive', () {
      // Native extractors can sniff containers; only embeds are refused.
      expect(
        ZvMediaSource.detectType('https://cdn.example.com/stream/12345'),
        ZvSourceType.progressive,
      );
    });

    test('isNativePlayable is true only for the four native kinds', () {
      expect(ZvSourceType.progressive.isNativePlayable, isTrue);
      expect(ZvSourceType.hls.isNativePlayable, isTrue);
      expect(ZvSourceType.dash.isNativePlayable, isTrue);
      expect(ZvSourceType.local.isNativePlayable, isTrue);
      expect(ZvSourceType.youtube.isNativePlayable, isFalse);
      expect(ZvSourceType.vimeo.isNativePlayable, isFalse);
      expect(ZvSourceType.embedded.isNativePlayable, isFalse);
      expect(ZvSourceType.unknown.isNativePlayable, isFalse);
    });
  });

  group('ZvMediaSource.detectType', () {
    test('recognises HLS and DASH manifests by extension', () {
      expect(
        ZvMediaSource.detectType('https://cdn.example.com/a/master.m3u8'),
        ZvSourceType.hls,
      );
      expect(
        ZvMediaSource.detectType('https://cdn.example.com/a/manifest.mpd'),
        ZvSourceType.dash,
      );
    });

    test('ignores query strings and fragments when reading the extension', () {
      expect(
        ZvMediaSource.detectType(
          'https://cdn.example.com/master.m3u8?token=abc&exp=123#t=10',
        ),
        ZvSourceType.hls,
      );
    });

    test('recognises progressive containers', () {
      for (final String extension in <String>['mp4', 'mkv', 'webm', 'mov']) {
        expect(
          ZvMediaSource.detectType('https://cdn.example.com/video.$extension'),
          ZvSourceType.progressive,
          reason: 'failed for .$extension',
        );
      }
    });

    test('treats file paths and file URIs as local', () {
      expect(
        ZvMediaSource.detectType('/data/user/0/app/files/movie.mp4'),
        ZvSourceType.local,
      );
      expect(
        ZvMediaSource.detectType('file:///tmp/movie.mp4'),
        ZvSourceType.local,
      );
    });

    test('lets a declared backend type win over the URL', () {
      // The backend knows about manifests hidden behind redirects.
      expect(
        ZvMediaSource.detectType(
          'https://cdn.example.com/stream/12345',
          declaredType: 'hls',
        ),
        ZvSourceType.hls,
      );
      expect(
        ZvMediaSource.detectType('/local/path/file.mp4', declaredType: 'local'),
        ZvSourceType.local,
      );
    });

    test('treats an extensionless http URL as progressive for native sniffing',
        () {
      // Refusing these would block legitimate CDN URLs that carry no
      // extension; the native extractor decides, and an unplayable container
      // surfaces as a clean unsupported-format error.
      expect(
        ZvMediaSource.detectType('https://cdn.example.com/stream/12345'),
        ZvSourceType.progressive,
      );
    });

    test('returns unknown only for input that cannot be classified', () {
      expect(ZvMediaSource.detectType(''), ZvSourceType.unknown);
      expect(ZvMediaSource.detectType('   '), ZvSourceType.unknown);
      expect(ZvMediaSource.detectType('not a url'), ZvSourceType.unknown);
    });

    test('returns unknown for an empty URI rather than guessing', () {
      expect(ZvMediaSource.detectType(''), ZvSourceType.unknown);
    });
  });

  group('ZvMediaSource', () {
    test('isAdaptive is true only for manifest formats', () {
      expect(
        ZvMediaSource.detect(uri: 'https://x/a.m3u8').isAdaptive,
        isTrue,
      );
      expect(
        ZvMediaSource.detect(uri: 'https://x/a.mp4').isAdaptive,
        isFalse,
      );
    });

    test('hasManualVariants needs more than one URL to be a real choice', () {
      const ZvSourceVariant variant = ZvSourceVariant(
        id: '1',
        label: '720p',
        uri: 'https://x/720.mp4',
      );
      expect(
        ZvMediaSource.detect(
          uri: 'https://x/720.mp4',
          variants: <ZvSourceVariant>[variant],
        ).hasManualVariants,
        isFalse,
      );
      expect(
        ZvMediaSource.detect(
          uri: 'https://x/720.mp4',
          variants: <ZvSourceVariant>[
            variant,
            const ZvSourceVariant(
              id: '2',
              label: '1080p',
              uri: 'https://x/1080.mp4',
            ),
          ],
        ).hasManualVariants,
        isTrue,
      );
    });

    test('serialises DRM config for the bridge without implementing DRM', () {
      final ZvMediaSource source = ZvMediaSource.detect(
        uri: 'https://x/a.mpd',
        drm: const DrmConfig(
          scheme: DrmScheme.widevine,
          licenseUrl: 'https://licence.example.com',
        ),
      );
      final Map<String, dynamic> map = source.toMap();
      expect((map['drm'] as Map<String, dynamic>)['scheme'], 'widevine');
      expect(
        (map['drm'] as Map<String, dynamic>)['licenseUrl'],
        'https://licence.example.com',
      );
    });
  });
}
