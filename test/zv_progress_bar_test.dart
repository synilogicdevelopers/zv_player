import 'package:zv_player/zv_player.dart';
import 'package:zv_player/src/widgets/zv_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scrubber is where the device screenshot went wrong, so these tests pin
/// the geometry: the track spans the whole duration regardless of position.
void main() {
  const double barWidth = 400;

  late List<Duration> previews;
  late List<Duration> commits;

  setUp(() {
    previews = <Duration>[];
    commits = <Duration>[];
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required Duration position,
    required Duration duration,
    Duration buffered = Duration.zero,
    bool enabled = true,
    bool showBuffered = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZvPlayerThemeScope(
            theme: ZvPlayerTheme.standard,
            child: Center(
              child: SizedBox(
                width: barWidth,
                child: ZvProgressBar(
                  position: position,
                  duration: duration,
                  buffered: buffered,
                  enabled: enabled,
                  showBuffered: showBuffered,
                  onSeekPreview: previews.add,
                  onSeekCommit: commits.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Widths of the three bands, widest first (remaining is always the widest).
  List<double> trackWidths(WidgetTester tester) {
    return tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((FractionallySizedBox box) => (box.widthFactor ?? 0) * barWidth)
        .toList();
  }

  group('the track always spans the whole duration', () {
    testWidgets('at 0%', (tester) async {
      await pumpBar(
        tester,
        position: Duration.zero,
        duration: const Duration(minutes: 100),
      );

      // The background band is full width even with nothing played.
      expect(trackWidths(tester).first, barWidth);
    });

    testWidgets('at 25%', (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 25),
        duration: const Duration(minutes: 100),
      );

      final List<double> widths = trackWidths(tester);
      expect(widths.first, barWidth, reason: 'remaining track is full width');
      expect(widths.last, closeTo(barWidth * 0.25, 0.5));
    });

    testWidgets('at 50%', (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 100),
      );

      final List<double> widths = trackWidths(tester);
      expect(widths.first, barWidth);
      expect(widths.last, closeTo(barWidth * 0.5, 0.5));
    });

    testWidgets('a long film part-watched still shows the full track',
        (tester) async {
      // The screenshot case: 2h08m into a 3h50m film.
      await pumpBar(
        tester,
        position: const Duration(hours: 2, minutes: 8),
        duration: const Duration(hours: 3, minutes: 50),
      );

      final List<double> widths = trackWidths(tester);
      expect(widths.first, barWidth,
          reason: 'the bar must not end where playback has reached');
      expect(widths.last, closeTo(barWidth * (128 / 230), 1.0));
    });

    testWidgets('an unknown duration renders an empty full-width track',
        (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 5),
        duration: Duration.zero,
      );

      final List<double> widths = trackWidths(tester);
      expect(widths.first, barWidth);
      expect(widths.last, 0, reason: 'no fraction can be computed');
    });
  });

  group('clamping', () {
    testWidgets('a position past the duration does not overflow',
        (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 200),
        duration: const Duration(minutes: 100),
      );
      expect(trackWidths(tester).last, closeTo(barWidth, 0.5));
    });

    testWidgets('buffered never renders behind the playhead', (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 100),
        buffered: const Duration(minutes: 10),
      );

      final List<double> widths = trackWidths(tester);
      // remaining, buffered, played
      expect(widths[1], greaterThanOrEqualTo(widths[2] - 0.5));
    });

    testWidgets('buffered beyond the duration is clamped', (tester) async {
      await pumpBar(
        tester,
        position: Duration.zero,
        duration: const Duration(minutes: 100),
        buffered: const Duration(minutes: 500),
      );
      expect(trackWidths(tester)[1], closeTo(barWidth, 0.5));
    });

    testWidgets('the buffered band is omitted when unsupported',
        (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 100),
        buffered: const Duration(minutes: 50),
        showBuffered: false,
      );
      // Only remaining and played remain.
      expect(trackWidths(tester).length, 2);
    });
  });

  group('scrubbing', () {
    testWidgets('a tap seeks to that point on the full track', (tester) async {
      await pumpBar(
        tester,
        position: Duration.zero,
        duration: const Duration(minutes: 100),
      );

      final Offset topLeft = tester.getTopLeft(find.byType(ZvProgressBar));
      final Offset centre = tester.getCenter(find.byType(ZvProgressBar));
      await tester.tapAt(Offset(topLeft.dx + barWidth * 0.75, centre.dy));
      await tester.pump();

      expect(commits.single.inMinutes, closeTo(75, 1));
    });

    testWidgets('touching the bar does not move playback', (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 25),
        duration: const Duration(minutes: 100),
      );

      // Press far from the thumb; an absolute-seek bar would jump here.
      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byType(ZvProgressBar)));
      await tester.pump();

      expect(previews, isEmpty);
      expect(commits, isEmpty);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('a drag moves playback in proportion to the full track',
        (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 25),
        duration: const Duration(minutes: 100),
      );

      // 10% of a 400px track on a 100 minute film is ten minutes, measured
      // from the playhead (25%) rather than from wherever the finger landed.
      await tester.drag(
        find.byType(ZvProgressBar),
        const Offset(barWidth * 0.1, 0),
      );
      await tester.pump();

      expect(previews, isNotEmpty);
      expect(commits.last.inMinutes, closeTo(35, 2));
    });

    testWidgets('dragging left moves playback back proportionally',
        (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 100),
      );

      await tester.drag(
        find.byType(ZvProgressBar),
        const Offset(-barWidth * 0.25, 0),
      );
      await tester.pump();

      expect(commits.last.inMinutes, closeTo(25, 2));
    });

    testWidgets('a drag past the start is clamped to zero', (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 100),
      );

      await tester.drag(
          find.byType(ZvProgressBar), const Offset(-barWidth * 2, 0));
      await tester.pump();

      expect(commits.last, Duration.zero);
    });

    testWidgets('a drag past the end is clamped to the duration',
        (tester) async {
      await pumpBar(
        tester,
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 100),
      );

      await tester.drag(
          find.byType(ZvProgressBar), const Offset(barWidth * 2, 0));
      await tester.pump();

      expect(commits.last, const Duration(minutes: 100));
    });

    testWidgets('a disabled bar ignores taps and drags', (tester) async {
      await pumpBar(
        tester,
        position: Duration.zero,
        duration: const Duration(minutes: 100),
        enabled: false,
      );

      await tester.tapAt(tester.getCenter(find.byType(ZvProgressBar)));
      await tester.pump();

      expect(commits, isEmpty);
      expect(previews, isEmpty);
    });
  });
}
