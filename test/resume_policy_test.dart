import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ResumePolicy policy = ResumePolicy();
  const Duration duration = Duration(minutes: 100);

  group('ResumePolicy.shouldSave', () {
    test('ignores positions too small to be real progress', () {
      expect(policy.shouldSave(const Duration(seconds: 3), duration), isFalse);
      expect(policy.shouldSave(const Duration(seconds: 9), duration), isFalse);
    });

    test('saves ordinary mid-playback positions', () {
      expect(policy.shouldSave(const Duration(minutes: 30), duration), isTrue);
    });

    test('does not save once the item is effectively finished', () {
      // Past the 95% threshold: resuming here would be pointless.
      expect(policy.shouldSave(const Duration(minutes: 96), duration), isFalse);
    });

    test('does not save when the duration is unknown', () {
      expect(
        policy.shouldSave(const Duration(minutes: 5), Duration.zero),
        isFalse,
      );
    });
  });

  group('ResumePolicy.isComplete', () {
    test('treats the last few seconds as complete', () {
      expect(
          policy.isComplete(const Duration(minutes: 99, seconds: 50), duration),
          isTrue);
    });

    test('mid-playback is not complete', () {
      expect(policy.isComplete(const Duration(minutes: 50), duration), isFalse);
    });

    test('an unknown duration is never complete', () {
      expect(policy.isComplete(const Duration(minutes: 50), Duration.zero),
          isFalse);
    });
  });

  group('ResumePolicy.shouldResumeFrom', () {
    test('resumes from a meaningful position', () {
      expect(
        policy.shouldResumeFrom(const Duration(minutes: 20), duration),
        isTrue,
      );
    });

    test('does not resume from a trivial position', () {
      expect(
        policy.shouldResumeFrom(const Duration(seconds: 4), duration),
        isFalse,
      );
    });

    test('does not resume a finished item', () {
      expect(
        policy.shouldResumeFrom(
            const Duration(minutes: 99, seconds: 55), duration),
        isFalse,
      );
    });
  });

  group('InMemoryProgressStore', () {
    test('stores, returns and clears progress', () async {
      final InMemoryProgressStore store = InMemoryProgressStore();
      expect(await store.load('abc'), isNull);

      await store.save(
        const PlaybackProgress(
          contentId: 'abc',
          position: Duration(minutes: 12),
          duration: duration,
        ),
      );
      final PlaybackProgress? loaded = await store.load('abc');
      expect(loaded?.position, const Duration(minutes: 12));
      expect(loaded?.fraction, closeTo(0.12, 0.001));

      await store.clear('abc');
      expect(await store.load('abc'), isNull);
    });
  });
}
